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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
