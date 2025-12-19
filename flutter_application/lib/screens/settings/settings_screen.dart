import 'package:flutter/material.dart';
import 'package:flutter_application/l10n/app_localizations.dart';
import 'tabs/general_tab.dart';
import 'tabs/providers_tab.dart';
import 'tabs/default_capabilities_tab.dart';
import 'tabs/deep_research_tab.dart';
import 'tabs/plugins_tab.dart';
import 'tabs/about_tab.dart';

class SettingsScreen extends StatefulWidget {
  final int initialIndex;

  const SettingsScreen({Key? key, this.initialIndex = 0}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _selectedIndex;

  final List<Widget> _tabs = const [
    GeneralTab(),
    DefaultCapabilitiesTab(),
    DeepResearchTab(),
    PluginsTab(),
    ProvidersTab(),
    AboutTab(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(0, _tabs.length - 1).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 640;
    final l10n = AppLocalizations.of(context)!;
    final initialIndex = widget.initialIndex.clamp(0, _tabs.length - 1).toInt();

    if (isWide) {
      return DefaultTabController(
        length: _tabs.length,
        initialIndex: initialIndex,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.settingsTitle),
            elevation: 0,
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: const Icon(Icons.tune_outlined), text: l10n.tabGeneral),
                const Tab(icon: Icon(Icons.auto_awesome_outlined), text: '默认能力 (Default)'),
                const Tab(icon: Icon(Icons.science_outlined), text: '深度研究 (Deep Research)'),
                const Tab(icon: Icon(Icons.extension_outlined), text: '插件 (Plugins)'),
                Tab(icon: const Icon(Icons.cloud_outlined), text: l10n.tabProviders),
                Tab(icon: const Icon(Icons.info_outline), text: l10n.tabAbout),
              ],
            ),
          ),
          body: TabBarView(
            children: _tabs,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        elevation: 0,
      ),
      body: _tabs[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.tune_outlined),
            label: l10n.tabGeneral,
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            label: '能力',
          ),
          const NavigationDestination(
            icon: Icon(Icons.science_outlined),
            label: '研究',
          ),
          const NavigationDestination(
            icon: Icon(Icons.extension_outlined),
            label: '插件',
          ),
          NavigationDestination(
            icon: const Icon(Icons.cloud_outlined),
            label: l10n.tabProviders,
          ),
          NavigationDestination(
            icon: const Icon(Icons.info_outline),
            label: l10n.tabAbout,
          ),
        ],
      ),
    );
  }
}
