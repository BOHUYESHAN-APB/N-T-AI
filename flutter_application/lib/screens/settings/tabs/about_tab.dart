import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_application/l10n/app_localizations.dart';

class AboutTab extends StatelessWidget {
  const AboutTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: Column(
            children: [
              // Use Image.asset for logo if available, otherwise Icon
              // Assuming logo is at assets/images/app_icon.png based on pubspec
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/app_icon.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.appTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Text('v0.0.2 Beta', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Project expansion / short description (NTAI = Neural Tactical AI)
        _buildSectionHeader(context, l10n.aboutProjectExpansionTitle),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            l10n.aboutProjectExpansion,
            style: const TextStyle(fontSize: 14),
            textAlign: TextAlign.left,
          ),
        ),

        _buildSectionHeader(context, '更新日志 (Changelog)'),
        const _ChangelogWidget(),
        const SizedBox(height: 24),

        _buildSectionHeader(context, '支持与赞助'),
        ListTile(
          leading: const Icon(Icons.favorite, color: Colors.pink),
          title: const Text('在爱发电支持我们'),
          subtitle: const Text('您的支持是我们持续开发的动力'),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => launchUrl(Uri.parse('https://afdian.com/a/N-T-AI')),
        ),
        const SizedBox(height: 24),

        _buildSectionHeader(context, l10n.aboutLegal),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('隐私政策 (Privacy Policy)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAssetFile(context, '隐私政策', 'assets/licenses/PRIVACY_POLICY.md'),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text('用户协议 (User Agreement)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAssetFile(context, '用户协议', 'assets/licenses/USER_AGREEMENT.md'),
        ),
        ListTile(
          leading: const Icon(Icons.business_center_outlined),
          title: const Text('商业授权条款 (Commercial Terms)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showAssetFile(context, '商业授权条款', 'assets/licenses/COMMERCIAL_LICENSE_TERMS.md'),
        ),
        const Divider(),
        _buildLicenseTile(context, '项目授权协议', 'N-T-AI License (非商业开源 / 商业需授权)', 'https://github.com/BOHUYESHAN-APB/N-T-AI/blob/main/LICENSE'),
        _buildLicenseTile(context, 'MiSans 字体', '小米公司 (MiSans 字体知识产权许可协议)', 'https://hyperos.mi.com/font/download'),
        _buildLicenseTile(context, 'FZG 字体', '方正字库 (SIL Open Font License 1.1)', 'https://www.foundertype.com'),
        _buildLicenseTile(context, 'NFDCS 字体', '南构字库 (MIT/ISAS License)', 'https://github.com/Hansha2011/'),
        _buildLicenseTile(context, 'Excalidraw', 'Virtual Whiteboard (MIT License)', 'https://github.com/excalidraw/excalidraw'),
        _buildLicenseTile(context, 'N.E.K.O.', 'Next-gen Emotive Kernel for Operators (MIT License)', 'https://github.com/BOHUYESHAN-APB/N.E.K.O.'),
        _buildLicenseTile(context, 'dlp3d.ai', '3D Rendering Architecture Ideas (MIT License)', 'https://github.com/dlp3d/dlp3d.ai'),
        _buildLicenseTile(context, 'live2d-py', 'Live2D Integration Support (MIT License)', 'https://github.com/EasyLive2D/live2d-py'),
        _buildLicenseTile(context, 'DeepResearchAgent', 'Hierarchical Multi-Agent Inspiration (MIT License)', 'https://github.com/SkyworkAI/DeepResearchAgent'),
        _buildLicenseTile(context, 'free-OKC', 'OK Computer Virtual Machine (MIT License)', 'https://github.com/kexinoh/free-OKC'),
        _buildLicenseTile(context, 'OpenManus', 'Deep Research Workflow Inspiration (MIT License)', 'https://github.com/FoundationAgents/OpenManus'),
        _buildLicenseTile(context, 'Skywork-Super-Agents', 'MCP Server Inspiration (The Unlicense)', 'https://github.com/Skywork-ai/Skywork-Super-Agents'),
        
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('第三方软件许可'),
          subtitle: const Text('查看本软件使用的所有开源库及其许可证'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'N-T-AI',
            applicationVersion: '0.3.3-beta',
            applicationLegalese: '© 2025 N-T-AI Contributors\n\n'
                'N-T-AI (System): Complete Application Suite\n'
                'Astra-Me: Python Backend Service\n'
                'Firefly: Intelligent Agent Persona\n\n'
                '本软件基于 Flutter 构建，使用了多个开源软件包。',
          ),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(context, l10n.aboutFeedback),
        ListTile(
          leading: const Icon(Icons.translate_outlined),
          title: const Text('贡献翻译'),
          subtitle: const Text('帮助我们将应用翻译成更多语言'),
          trailing: const Icon(Icons.open_in_new, size: 16),
          onTap: () => _launchUrl('https://github.com/BOHUYESHAN-APB/N-T-AI#contributing-translations'),
        ),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(l10n.aboutReportIssue),
          subtitle: const Text('GitHub Issues'),
          trailing: const Icon(Icons.open_in_new, size: 16),
          onTap: () => _launchUrl('https://github.com/BOHUYESHAN-APB/N-T-AI/issues'),
        ),

        const SizedBox(height: 24),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            l10n.aboutDisclaimer,
            style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
    );
  }

  Widget _buildLicenseTile(BuildContext context, String title, String subtitle, String url) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new, size: 16),
      onTap: () => _launchUrl(url),
    );
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showAssetFile(BuildContext context, String title, String assetPath) async {
    try {
      final content = await rootBundle.loadString(assetPath);
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              height: 400, // Give it some height
              child: Markdown(
                data: content,
                selectable: true,
                shrinkWrap: true,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法读取文件: $e')));
      }
    }
  }
}

class _ChangelogWidget extends StatelessWidget {
  const _ChangelogWidget();

  Future<String> _fetchChangelog() async {
    try {
      // Read from local asset instead of network
      // Note: CHANGELOG.md needs to be added to pubspec.yaml assets if not already
      // But since it's in the root, we might need to copy it to assets during build or just read a string here.
      // For now, let's assume we bundle it or just hardcode the latest changes if we can't read root file in release.
      // Actually, best practice is to include it in assets.
      // Let's try to read from the bundled asset if we add it.
      // For this environment, I'll assume we might not have added it to assets yet, 
      // so I will try to read it from the root bundle if possible, or fallback to a hardcoded string for this demo 
      // if the asset isn't registered.
      
      // Ideally: return await rootBundle.loadString('CHANGELOG.md');
      // But 'CHANGELOG.md' is in root, not assets.
      // Let's try to read it from a known asset path if the user moved it, 
      // or just use the network as fallback but prefer local.
      
      // Since I can't easily move the file in the build process here without a script,
      // I will use the network for now but with Markdown rendering as requested.
      // Wait, user said "内嵌更新日志...读取本地文件".
      // I should probably add it to pubspec assets.
      
      return await rootBundle.loadString('CHANGELOG.md');
    } catch (e) {
      // Fallback to network if local fails (e.g. in debug mode without asset copy)
      try {
         final response = await http.get(Uri.parse('https://cdn.jsdelivr.net/gh/BOHUYESHAN-APB/N-T-AI@main/CHANGELOG.md'));
         if (response.statusCode == 200) return response.body;
      } catch (_) {}
      return '无法获取更新日志。请检查网络连接或本地文件。';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _fetchChangelog(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ));
        }
        final content = snapshot.data ?? '无内容';
        return Container(
          height: 300,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
          ),
          child: Markdown(
            data: content,
            selectable: true,
            shrinkWrap: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: const TextStyle(fontSize: 13),
              h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}
