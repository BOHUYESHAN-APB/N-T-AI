import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../widgets/license_viewer.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  static const List<Map<String, String>> _referencedProjects = [
    {
      'name': 'N.E.K.O. (Next-gen Emotive Kernel for Operators)',
      'license': 'MIT',
      'url': 'https://github.com/BOHUYESHAN-APB/N.E.K.O.',
    },
    {
      'name': 'dlp3d.ai',
      'license': 'MIT',
      'url': 'https://github.com/dlp3d/dlp3d.ai',
    },
    {
      'name': 'Excalidraw',
      'license': 'MIT',
      'url': 'https://github.com/excalidraw/excalidraw',
    },
    {
      'name': 'live2d-py',
      'license': 'MIT',
      'url': 'https://github.com/EasyLive2D/live2d-py',
    },
    {
      'name': 'DeepResearchAgent',
      'license': 'MIT',
      'url': 'https://github.com/SkyworkAI/DeepResearchAgent',
    },
    {
      'name': 'free-OKC (OK Computer Virtual Machine)',
      'license': 'MIT',
      'url': 'https://github.com/kexinoh/free-OKC',
    },
    {
      'name': 'OpenManus',
      'license': 'MIT',
      'url': 'https://github.com/FoundationAgents/OpenManus',
    },
    {
      'name': 'Skywork-Super-Agents',
      'license': 'The Unlicense',
      'url': 'https://github.com/Skywork-ai/Skywork-Super-Agents',
    },
    {
      'name': 'FFmpeg',
      'license': 'LGPLv2.1+',
      'url': 'https://ffmpeg.org/',
    },
    {
      'name': 'FFmpeg-Builds (BtbN)',
      'license': 'GPL/LGPL (FFmpeg)',
      'url': 'https://github.com/BtbN/FFmpeg-Builds',
    },
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {}
  }

  void _showProjectInfoDialog({
    required String name,
    required String license,
    required String url,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: SelectableText('许可证：$license\n仓库：$url'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')), 
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('N-T-AI'),
            subtitle: Text(_version.isEmpty ? '版本信息加载中…' : '版本：$_version'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.book_outlined),
            title: Text('开源许可（依赖包）'),
            subtitle: Text('查看本应用及依赖包的开源许可（来自 Dart/Flutter LicenseRegistry）'),
          ),
          ListTile(
            title: const Text('查看依赖包许可证'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(context: context, applicationName: 'N-T-AI'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: const Text('问题反馈'),
            subtitle: const Text('提交 Bug 或建议 (GitHub Issues)'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () {
              // Use url_launcher if available, or just show a dialog with the link
              showDialog(context: context, builder: (ctx) => AlertDialog(
                title: const Text('问题反馈'),
                content: const SelectableText('请访问 GitHub Issues 页面提交反馈：\n\nhttps://github.com/BOHUYESHAN-APB/N-T-AI/issues'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
              ));
            },
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.text_snippet_outlined),
            title: Text('字体与第三方文本授权'),
            subtitle: Text('本应用内置的字体与第三方文本说明/许可'),
          ),
          ListTile(
            title: const Text('FZG · SIL Open Font License 1.1'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LicenseViewer(title: 'FZG · OFL 1.1', assetPath: 'assets/licenses/FZG-OFL-1.1.txt'))),
          ),
          ListTile(
            title: const Text('FZG · OFL 中文（参考译文）'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LicenseViewer(title: 'FZG · OFL 中文参考', assetPath: 'assets/licenses/FZG-OFL-zh.md'))),
          ),
          ListTile(
            title: const Text('MiSans 字体许可（摘录）'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LicenseViewer(title: 'MiSans License', assetPath: 'assets/licenses/MiSans-LICENSE.txt'))),
          ),
          ListTile(
            title: const Text('nfdcs 字体许可（作者声明）'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LicenseViewer(title: 'nfdcs License', assetPath: 'assets/licenses/nfdcs-LICENSE.txt'))),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.code_outlined),
            title: Text('参考开源项目'),
            subtitle: Text('本应用参考/使用的开源项目与许可证信息'),
          ),
          for (final p in _referencedProjects)
            ListTile(
              title: Text('${p['name']} · ${p['license']}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showProjectInfoDialog(
                name: p['name'] ?? '',
                license: p['license'] ?? '',
                url: p['url'] ?? '',
              ),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('特别致谢', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '本软件界面使用了以下优秀字体，特此致谢：\n\n'
              '• MiSans (小米公司)\n'
              '• FZG (方正字迹-盖体)\n'
              '• nfdcs (南方大草书)\n\n'
              '以上字体均遵循其各自的开源许可或授权声明。',
              style: TextStyle(color: Colors.grey, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
