import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'agent_tool.dart';

class WebSearchTool extends AgentTool {
  @override
  String get name => 'web_search';

  @override
  String get description => 'Search the internet for information. Use this when you need up-to-date facts or data not in your training set.';

  @override
  String get usage => 'query: string (The search keywords)';

  @override
  Future<String> execute(String args) async {
    final query = args.trim();
    if (query.isEmpty) return 'Error: Empty search query';

    try {
      // Use Bing as it is more accessible globally (including CN)
      final uri = Uri.parse('https://www.bing.com/search').replace(queryParameters: {'q': query});
      
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      });

      if (response.statusCode != 200) {
        return 'Error: Search failed with status ${response.statusCode}';
      }

      final document = parser.parse(response.body);
      // Bing results selector
      final results = document.querySelectorAll('li.b_algo');
      
      if (results.isEmpty) {
        // Fallback check for other structures or "no results"
        return 'No results found for "$query" (Source: Bing)';
      }

      final buffer = StringBuffer();
      buffer.writeln('Search Results for "$query" (Source: Bing):\n');

      int count = 0;
      final visitedPages = <String>[];
      
      for (final result in results) {
        if (count >= 5) break; // Limit to top 5
        
        final titleEl = result.querySelector('h2');
        final linkEl = result.querySelector('h2 a');
        final snippetEl = result.querySelector('.b_caption p') ?? result.querySelector('.b_snippet');

        if (titleEl != null && linkEl != null) {
          final title = titleEl.text.trim();
          final url = linkEl.attributes['href'] ?? '';
          final snippet = snippetEl?.text.trim() ?? '';

          if (url.isNotEmpty && !url.startsWith('#')) {
            buffer.writeln('${count + 1}. $title');
            buffer.writeln('   URL: $url');
            buffer.writeln('   Snippet: $snippet');
            buffer.writeln('');
            
            // Removed auto-visit to reduce token usage and improve logic flow.
            // The LLM should decide to use 'visit_page' based on the snippet.
            
            count++;
          }
        }
      }
      
      if (visitedPages.isNotEmpty) {
        buffer.writeln('\n=== Detailed Content & Images from Top Results ===');
        for (final page in visitedPages) {
          buffer.writeln(page);
        }
      }

      return buffer.toString();
    } catch (e) {
      return 'Error searching web: $e';
    }
  }
}

class WebPageReaderTool extends AgentTool {
  @override
  String get name => 'visit_page';

  @override
  String get description => 'Visit a specific URL and read its content. Use this to get detailed information from a search result.';

  @override
  String get usage => 'url: string (The full URL to visit)';

  @override
  Future<String> execute(String args) async {
    final urlStr = args.trim();
    if (urlStr.isEmpty) return 'Error: Empty URL';

    try {
      final uri = Uri.parse(urlStr);
      final response = await http.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      });

      if (response.statusCode != 200) {
        return 'Error: Failed to load page (Status ${response.statusCode})';
      }

      final document = parser.parse(response.body);
      
      // Remove scripts and styles but keep nav/footer if they are small, as they might contain contact info or links
      // Actually, for "deep access", we usually want the main article.
      document.querySelectorAll('script, style, noscript, iframe, svg').forEach((e) => e.remove());

      final title = document.querySelector('title')?.text.trim() ?? 'No Title';
      
      // Try to find the main content container
      var mainContent = document.querySelector('main') ?? document.querySelector('article') ?? document.querySelector('#content') ?? document.body;
      
      // If main content is too short, fallback to body
      if ((mainContent?.text.length ?? 0) < 200) {
        mainContent = document.body;
      }

      String bodyText = mainContent?.text ?? '';
      
      // Replace multiple newlines with a single newline
      bodyText = bodyText.replaceAll(RegExp(r'\n\s*\n'), '\n');
      // Replace multiple spaces/tabs with a single space
      bodyText = bodyText.replaceAll(RegExp(r'[ \t]+'), ' ');
      
      final cleanBody = bodyText.trim();
      
      // Extract Images from Main Content
      final images = <String>[];
      final imgTags = mainContent?.querySelectorAll('img') ?? [];
      
      for (final img in imgTags) {
        if (images.length >= 10) break; // Increased limit
        
        var src = img.attributes['src'];
        if (src == null || src.isEmpty) continue;
        
        // Resolve relative URLs
        if (!src.startsWith('http')) {
          try {
            src = uri.resolve(src).toString();
          } catch (_) {
            continue;
          }
        }
        
        // Filter by keywords
        final lowerSrc = src.toLowerCase();
        // Relaxed keywords: removed 'logo' as sometimes logos are relevant in news, kept others
        if (lowerSrc.contains('icon') || lowerSrc.contains('avatar') || lowerSrc.contains('ad') || lowerSrc.contains('banner') || lowerSrc.contains('tracker')) {
          continue;
        }
        
        // Filter by dimensions (if attributes exist)
        final wStr = img.attributes['width'];
        final hStr = img.attributes['height'];
        if (wStr != null && hStr != null) {
          try {
            final w = int.parse(wStr.replaceAll(RegExp(r'[^0-9]'), ''));
            final h = int.parse(hStr.replaceAll(RegExp(r'[^0-9]'), ''));
            // Relaxed size constraint to 100x100
            if (w < 100 || h < 100) continue;
          } catch (_) {}
        }
        
        // Basic extension check to avoid svg or weird formats if needed, but generally trust img tag
        if (lowerSrc.endsWith('.svg') || lowerSrc.endsWith('.gif')) {
             // Optional: skip SVGs or small GIFs if they are likely icons
             // For now, we keep them unless they are tiny
        }

        if (!images.contains(src)) {
          images.add(src);
        }
      }

      // Increased limit for deeper content
      final truncatedBody = cleanBody.length > 10000 ? cleanBody.substring(0, 10000) + '...[Truncated]' : cleanBody;

      final buffer = StringBuffer();
      buffer.writeln('Page Title: $title');
      buffer.writeln('URL: $urlStr');
      buffer.writeln('\nContent:\n$truncatedBody');
      
      if (images.isNotEmpty) {
        buffer.writeln('\nRelevant Images:');
        for (final img in images) {
          buffer.writeln('[IMAGE: $img]');
        }
      } else {
        buffer.writeln('\nNo relevant images found.');
      }

      return buffer.toString();
    } catch (e) {
      return 'Error visiting page: $e';
    }
  }
}
