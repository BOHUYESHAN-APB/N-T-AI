from ddgs import DDGS
import json
import httpx
from bs4 import BeautifulSoup
from urllib.parse import urljoin
import asyncio
from app.core.logger import logger
from app.services.browser_service import browser_service

class SearchService:
    def __init__(self):
        # Suppress DDGS warning if possible or just init
        self.ddgs = DDGS()

    def _filter_results(self, results: list, query: str) -> list:
        # Simple keyword matching to filter out irrelevant results
        keywords = [k for k in query.split() if len(k) > 1]
        if not keywords: return results
        
        filtered = []
        for r in results:
            text = (r['title'] + " " + r['body']).lower()
            if any(k.lower() in text for k in keywords):
                filtered.append(r)
            else:
                # Relaxed: If we have very few results, keep them even if they don't match perfectly
                # But for now, let's just log it.
                logger.debug(f"Filtered out irrelevant result: {r['title']}")
        
        # If filtering removed everything, return original results (better than nothing)
        if not filtered and results:
            logger.warning("Filter removed all results, returning originals as fallback.")
            return results
            
        return filtered

    async def search_structured(self, query: str, max_results: int = 3, region: str = "zh-CN") -> dict:
        try:
            logger.info(f"Searching for: {query} (Region: {region})")
            loop = asyncio.get_event_loop()
            search_limit = max(10, max_results * 2)
            
            def do_search():
                results_text = []
                results_images = []
                try:
                    # 1. Text Search
                    res = self.ddgs.text(query, region=region, max_results=search_limit)
                    if res:
                        results_text = list(res)
                    
                    # 2. Image Search
                    res_img = self.ddgs.images(query, region=region, max_results=5)
                    if res_img:
                        results_images = list(res_img)
                        
                except Exception as inner_e:
                    logger.error(f"DDGS internal error: {inner_e}")
                
                return results_text, results_images

            results, raw_images = await loop.run_in_executor(None, do_search)
            
            logger.info(f"DDGS returned {len(results)} text results and {len(raw_images)} raw images")
            
            # Validate DDGS Images
            images = []
            if raw_images:
                logger.info(f"Validating {len(raw_images)} DDGS images...")
                # Extract URLs from DDGS result objects
                img_urls = [img if isinstance(img, str) else img.get('image') for img in raw_images]
                img_urls = [u for u in img_urls if u] # Filter None
                
                images = await self._validate_urls(img_urls)
                logger.info(f"DDGS valid images: {len(images)}")

            # Fallback to Bing if DDGS fails
            if not results:
                logger.warning("DDGS returned no results, switching to Bing fallback search...")
                results = await self.search_bing(query, max_results, region=region)
                results = self._filter_results(results, query)
                logger.info(f"Bing returned {len(results)} results")

            # Fallback to Baidu if Bing fails
            if not results and region == "zh-CN":
                logger.warning("Bing returned no results, switching to Baidu fallback search...")
                results = await self.search_baidu(query, max_results)
                # Baidu results are usually relevant, no strict filter needed
                logger.info(f"Baidu returned {len(results)} results")

            # Fallback for Images (if DDGS yielded no valid images)
            if not images:
                logger.warning("DDGS returned no valid images, trying Bing Images...")
                images = await self.search_images_bing(query, max_results=5, region=region)
                
            if not images and region == "zh-CN":
                logger.warning("Bing returned no valid images, trying Baidu Images...")
                images = await self.search_images_baidu(query, max_results=5)

            if not results:
                return {"results": [], "images": [], "formatted": "No search results found."}
            
            formatted_results = []
            trimmed_results = []
            for r in results[:max_results]:
                item = {
                    "title": r.get("title", ""),
                    "href": r.get("href", ""),
                    "body": r.get("body", ""),
                }
                trimmed_results.append(item)
                formatted_results.append(f"- [{item['title']}]({item['href']}): {item['body']}")
            
            if images:
                formatted_results.append("\n**Related Images:**")
                for img_url in images:
                    formatted_results.append(f"[IMAGE: {img_url}]")

            final_output = "\n".join(formatted_results)
            return {"results": trimmed_results, "images": images, "formatted": final_output}
        except Exception as e:
            logger.error(f"Search failed: {e}")
            return {"results": [], "images": [], "formatted": f"Search failed: {str(e)}"}

    async def search(self, query: str, max_results: int = 3, region: str = "zh-CN") -> str:
        payload = await self.search_structured(query=query, max_results=max_results, region=region)
        return payload.get("formatted") or "No search results found."

    async def search_baidu(self, query: str, max_results: int = 3) -> list:
        """Fallback search using Baidu scraping."""
        try:
            url = "https://www.baidu.com/s"
            params = {'wd': query}
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            }
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(url, params=params, headers=headers)
                if resp.status_code != 200:
                    return []
                html = resp.text
            
            soup = BeautifulSoup(html, 'html.parser')
            results = []
            # Baidu results in <div class="result c-container"> or similar
            # We look for h3 > a
            for item in soup.find_all('div', class_=lambda x: x and 'result' in x):
                h3 = item.find('h3')
                if not h3: continue
                link = h3.find('a')
                if not link: continue
                
                href = link.get('href')
                title = link.get_text()
                
                # Baidu snippet
                snippet_div = item.find('div', class_='c-abstract')
                snippet = snippet_div.get_text() if snippet_div else "No description"
                
                results.append({'title': title, 'href': href, 'body': snippet})
                if len(results) >= max_results:
                    break
            return results
        except Exception as e:
            logger.error(f"Baidu search failed: {e}")
            return []

    async def search_images_baidu(self, query: str, max_results: int = 5) -> list:
        try:
            url = "https://image.baidu.com/search/acjson"
            params = {
                "tn": "resultjson_com",
                "ipn": "rj",
                "word": query,
                "queryWord": query,
                "pn": 0,
                "rn": max_results * 2,
                "ie": "utf-8",
                "oe": "utf-8",
                "cl": 2,
                "lm": -1,
            }
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/plain, */*; q=0.01',
                'Referer': 'https://image.baidu.com/',
            }
            
            async with httpx.AsyncClient(timeout=10.0) as client:
                resp = await client.get(url, params=params, headers=headers)
                if resp.status_code != 200:
                    return []
                
                try:
                    data = resp.json()
                except Exception:
                    try:
                        import json
                        data = json.loads(resp.text)
                    except:
                        return []

                images = []
                if 'data' in data and isinstance(data['data'], list):
                    for item in data['data']:
                        if not item: continue
                        img_url = item.get('thumbURL') or item.get('middleURL') or item.get('hoverURL')
                        if img_url and img_url.startswith('http'):
                            images.append(img_url)
                        if len(images) >= max_results:
                            break
                
                return await self._validate_urls(images, referer='https://image.baidu.com/')

        except Exception as e:
            logger.error(f"Baidu Image Search failed: {e}")
            return []

    async def search_images_bing(self, query: str, max_results: int = 5, region: str = "zh-CN") -> list:
        try:
            url = "https://www.bing.com/images/search"
            params = {'q': query, 'first': 1}
            
            # Apply region settings
            if region == 'wt-wt' or region == 'us-en':
                params['setmkt'] = 'en-US'
                params['setlang'] = 'en-US'
            elif region == 'zh-CN':
                params['setmkt'] = 'zh-CN'
                params['setlang'] = 'zh-CN'

            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
            }
            
            async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
                resp = await client.get(url, params=params, headers=headers)
                if resp.status_code != 200:
                    return []
                html = resp.text
            
            soup = BeautifulSoup(html, 'html.parser')
            images = []
            import json
            
            for a in soup.find_all('a', class_='iusc'):
                m_attr = a.get('m')
                if not m_attr: continue
                try:
                    m_json = json.loads(m_attr)
                    murl = m_json.get('murl')
                    if murl and murl.startswith('http'):
                        images.append(murl)
                except:
                    continue
                if len(images) >= max_results:
                    break
            
            return await self._validate_urls(images, referer='https://www.bing.com/')
        except Exception as e:
            logger.error(f"Bing Image Search failed: {e}")
            return []

    async def search_bing(self, query: str, max_results: int = 3, region: str = "zh-CN") -> list:
        try:
            logger.info(f"Fallback searching Bing for: {query} (Region: {region})")
            accept_lang = 'zh-CN,zh;q=0.9,en;q=0.8'
            if region == 'wt-wt' or region == 'us-en':
                accept_lang = 'en-US,en;q=0.9'
                
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
                'Accept-Language': accept_lang,
            }
            url = "https://www.bing.com/search"
            params = {'q': query}
            if region == 'wt-wt':
                params['setmkt'] = 'en-US'
                params['setlang'] = 'en-US'
            elif region == 'zh-CN':
                params['setmkt'] = 'zh-CN'
                params['setlang'] = 'zh-CN'
            
            async with httpx.AsyncClient(timeout=10.0, follow_redirects=True) as client:
                resp = await client.get(url, params=params, headers=headers)
                if resp.status_code != 200:
                    return []
                html = resp.text
            
            soup = BeautifulSoup(html, 'html.parser')
            results = []
            for item in soup.find_all('li', class_='b_algo'):
                h2 = item.find('h2')
                if not h2: continue
                link = h2.find('a')
                if not link: continue
                
                href = link.get('href')
                title = link.get_text()
                
                snippet_div = item.find('div', class_='b_caption')
                snippet = snippet_div.get_text() if snippet_div else "No description"
                
                results.append({'title': title, 'href': href, 'body': snippet})
                if len(results) >= max_results:
                    break
            
            return results
        except Exception as e:
            logger.error(f"Bing search failed: {e}")
            return []

    async def get_search_context(self, query: str, region: str = "zh-CN") -> str:
        if query.startswith("http://") or query.startswith("https://"):
            logger.info(f"Detected URL in query, visiting page: {query}")
            return await self.visit_page(query)
        return await self.search(query, region=region)

    async def visit_page(self, url: str) -> str:
        try:
            logger.info(f"Visiting page: {url}")
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7',
            }
            
            async with httpx.AsyncClient(follow_redirects=True, timeout=20.0, verify=False) as client:
                response = await client.get(url, headers=headers)
                response.raise_for_status()
                html_content = response.text
            
            loop = asyncio.get_event_loop()
            output = await loop.run_in_executor(None, self._parse_html, url, html_content)
            output = await self._validate_images_in_output(output, referer=url)
            return output

        except httpx.TimeoutException:
            logger.error(f"Timeout visiting page {url}, trying BrowserService...")
            return await browser_service.fetch_page(url)
        except Exception as e:
            logger.error(f"Error visiting page {url}: {str(e)}, trying BrowserService...")
            # Fallback to BrowserService if simple request fails (e.g. 403 or JS required)
            return await browser_service.fetch_page(url)

    async def _validate_images_in_output(self, text: str, referer: str = None) -> str:
        import re
        # Match [IMAGE: url] but be careful with potential trailing chars if not clean
        image_pattern = re.compile(r'\[IMAGE:\s*(.*?)\]')
        matches = image_pattern.findall(text)
        
        if not matches:
            return text
        
        # Deduplicate matches
        matches = list(set(matches))
        
        logger.info(f"Validating {len(matches)} images...")
        valid_images = []
        async with httpx.AsyncClient(timeout=5.0, verify=False) as client:
            tasks = []
            for img_url in matches:
                tasks.append(self._check_image(client, img_url, referer=referer))
            
            results = await asyncio.gather(*tasks)
            
            valid_count = 0
            for img_url, is_valid in zip(matches, results):
                if is_valid:
                    valid_images.append(img_url)
                    valid_count += 1
                else:
                    logger.warning(f"✗ Removing inaccessible image: {img_url}")

        new_text = text
        for img_url, is_valid in zip(matches, results):
            if not is_valid:
                new_text = new_text.replace(f"[IMAGE: {img_url}]\n", "")
                new_text = new_text.replace(f"[IMAGE: {img_url}]", "")
        
        logger.info(f"Validation complete: {valid_count}/{len(matches)} images passed")
        return new_text

    async def _check_image(self, client, url: str, referer: str = None) -> bool:
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                'Referer': referer if referer else 'https://www.google.com/',
                'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
                'Sec-Fetch-Dest': 'image',
                'Sec-Fetch-Mode': 'no-cors',
                'Sec-Fetch-Site': 'cross-site'
            }

            async def _do_request(req_headers):
                try:
                    resp = await client.head(url, headers=req_headers)
                    if resp.status_code == 200:
                        return True, resp.status_code
                    if resp.status_code == 403:
                        return False, 403
                except Exception:
                    pass

                try:
                    async with client.stream('GET', url, headers=req_headers) as response:
                        if response.status_code == 200:
                            return True, 200
                        return False, response.status_code
                except Exception:
                    return False, 0

            success, status = await _do_request(headers)
            if success:
                return True
            
            if status == 403:
                no_ref_headers = headers.copy()
                no_ref_headers.pop('Referer', None)
                success, status = await _do_request(no_ref_headers)
                if success:
                    return True

            if status == 403:
                logger.warning(f"Image 403 Forbidden (even after retry): {url}")
            
            return False

        except Exception as e:
            logger.warning(f"Image probe failed for {url}: {e}")
            return False

    async def _validate_urls(self, urls: list, referer: str = None) -> list:
        """Helper to validate a list of URLs concurrently."""
        if not urls: return []
        
        valid_images = []
        logger.info(f"Validating {len(urls)} images...")
        async with httpx.AsyncClient(timeout=5.0, verify=False) as client:
            tasks = [self._check_image(client, img, referer=referer) for img in urls]
            results = await asyncio.gather(*tasks)
            for img, (is_valid, status) in zip(urls, results):
                if is_valid:
                    valid_images.append(img)
                else:
                    logger.debug(f"Image validation failed for {img} (Status: {status})")
        return valid_images

    def _parse_html(self, url: str, html: str) -> str:
        try:
            soup = BeautifulSoup(html, 'html.parser')
            for tag in soup(['script', 'style', 'nav', 'footer', 'iframe', 'noscript', 'svg']):
                tag.decompose()

            main_content = soup.find('main') or soup.find('article') or soup.find('div', class_='content') or soup.body
            if not main_content:
                return f"Could not extract content from {url}"

            text = main_content.get_text(separator='\n', strip=True)
            text = text[:5000] + "..." if len(text) > 5000 else text

            images = []
            logger.info(f"Found {len(main_content.find_all('img'))} images in {url}")
            for img in main_content.find_all('img'):
                src = img.get('src')
                data_src = img.get('data-src') or img.get('data-original') or img.get('data-url') or img.get('data-actualsrc')
                if data_src: src = data_src
                if not src: continue
                
                src = urljoin(url, src)
                src_lower = src.lower()
                if not (src_lower.startswith('http') or src_lower.startswith('data:')): continue
                if any(src_lower.endswith(ext) for ext in ['.svg', '.gif', '.ico']): continue
                if any(x in src_lower for x in ['icon', 'logo', 'avatar', 'ad', 'banner', 'tracker', 'pixel']): continue
                if 'mi-img.com' in src_lower: continue

                width = img.get('width')
                height = img.get('height')
                if width and height:
                    try:
                        w, h = int(width), int(height)
                        if w < 100 or h < 100: continue
                    except: pass
                
                if src not in images:
                    images.append(src)
                if len(images) >= 10: break
            
            logger.info(f"Extracted {len(images)} valid images from {url}")
            
            output = f"Page Title: {soup.title.string if soup.title else 'No Title'}\nURL: {url}\n\nContent:\n{text}\n\nRelevant Images:\n"
            if images:
                for img_url in images:
                    output += f"[IMAGE: {img_url}]\n"
            else:
                output += "No relevant images found.\n"
                
            return output
        except Exception as e:
            return f"Error parsing HTML from {url}: {str(e)}"

