import 'package:flutter/material.dart';
import 'package:flutter_application/l10n/app_localizations.dart';
import 'tabs/general_tab.dart';
import 'tabs/providers_tab.dart';
import 'tabs/agents_tab.dart';
import 'tabs/capabilities_tab.dart';
import 'tabs/data_tab.dart';
import 'tabs/about_tab.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedIndex = 0;

  final List<Widget> _tabs = const [
    GeneralTab(),
    ProvidersTab(),
    AgentsTab(),
    CapabilitiesTab(),
    DataTab(),
    AboutTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 640;
    final l10n = AppLocalizations.of(context)!;

    if (isWide) {
      return DefaultTabController(
        length: _tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(l10n.settingsTitle),
            elevation: 0,
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(icon: const Icon(Icons.tune_outlined), text: l10n.tabGeneral),
                Tab(icon: const Icon(Icons.cloud_outlined), text: l10n.tabProviders),
                Tab(icon: const Icon(Icons.smart_toy_outlined), text: l10n.tabAgents),
                Tab(icon: const Icon(Icons.auto_awesome_outlined), text: l10n.tabCapabilities),
                Tab(icon: const Icon(Icons.storage_outlined), text: l10n.tabData),
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
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.tune_outlined), selectedIcon: const Icon(Icons.tune), label: l10n.tabGeneral),
          NavigationDestination(icon: const Icon(Icons.cloud_outlined), selectedIcon: const Icon(Icons.cloud), label: l10n.tabProviders),
          NavigationDestination(icon: const Icon(Icons.smart_toy_outlined), selectedIcon: const Icon(Icons.smart_toy), label: l10n.tabAgents),
          NavigationDestination(icon: const Icon(Icons.auto_awesome_outlined), selectedIcon: const Icon(Icons.auto_awesome), label: l10n.tabCapabilities),
          NavigationDestination(icon: const Icon(Icons.storage_outlined), selectedIcon: const Icon(Icons.storage), label: l10n.tabData),
          NavigationDestination(icon: const Icon(Icons.info_outline), selectedIcon: const Icon(Icons.info), label: l10n.tabAbout),
        ],
      ),
    );
  }
}
