"""
Browser Service
Provides a lightweight browser sandbox using Playwright for visiting web pages.
Supports JavaScript rendering and handling of dynamic content.
"""

import asyncio
from typing import Optional
from playwright.async_api import async_playwright, Browser, Page
from app.core.logger import logger

class BrowserService:
    def __init__(self):
        self._browser: Optional[Browser] = None
        self._playwright = None
        self._lock = asyncio.Lock()

    async def _ensure_browser(self):
        if self._browser:
            return

        async with self._lock:
            if self._browser:
                return
            
            try:
                self._playwright = await async_playwright().start()
                # Try to use installed browsers to avoid downloading if possible
                # But 'chromium' is standard.
                # If on Windows, we might try 'msedge' channel if we want to use system browser,
                # but 'chromium' is safer for headless consistency.
                self._browser = await self._playwright.chromium.launch(
                    headless=True,
                    args=['--no-sandbox', '--disable-setuid-sandbox']
                )
                logger.info("BrowserService: Browser launched.")
            except Exception as e:
                logger.error(f"BrowserService: Failed to launch browser: {e}")
                # Fallback or re-raise
                raise e

    async def fetch_page(self, url: str, wait_for_selector: str = None) -> str:
        """
        Visits a URL and returns the page content (HTML).
        """
        try:
            await self._ensure_browser()
            if not self._browser:
                return ""

            page = await self._browser.new_page(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            )
            
            try:
                logger.info(f"BrowserService: Visiting {url}")
                await page.goto(url, timeout=30000, wait_until="domcontentloaded")
                
                if wait_for_selector:
                    try:
                        await page.wait_for_selector(wait_for_selector, timeout=5000)
                    except:
                        pass # Ignore if selector not found, just return what we have

                # Scroll to bottom to trigger lazy loading
                await page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
                await asyncio.sleep(1) 
                
                content = await page.content()
                return content
            finally:
                await page.close()
                
        except Exception as e:
            logger.error(f"BrowserService: Error fetching {url}: {e}")
            return f"Error: {str(e)}"

    async def close(self):
        if self._browser:
            await self._browser.close()
            self._browser = None
        if self._playwright:
            await self._playwright.stop()
            self._playwright = None

browser_service = BrowserService()
