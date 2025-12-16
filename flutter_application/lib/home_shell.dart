import 'package:flutter/material.dart';
import 'screens/firefly_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/memory_manager_screen.dart';
import 'screens/tarot_screen.dart';
import 'screens/deep_research/deep_research_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({Key? key}) : super(key: key);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static final List<Widget> _pages = <Widget>[
    const FireflyScreen(),
    const MemoryManagerScreen(heroTag: 'memory_fab_home'),
    const DeepResearchScreen(), // Deep Research
    NotesScreen(),
    const TarotScreen(),
    SettingsScreen(),
  ];


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        
        // Use IndexedStack to preserve state of all pages
        final content = IndexedStack(
          index: _selectedIndex,
          children: _pages,
        );

        // final titles = const ['流萤', '记忆', '笔记', '塔罗', '系统'];
        
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex < 5 ? _selectedIndex : null,
                  onDestinationSelected: _onItemTapped,
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -1.0, // Align to top
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24.0),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.chat_bubble_outlined),
                      selectedIcon: Icon(Icons.chat_bubble),
                      label: Text('Firefly'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.psychology_outlined),
                      selectedIcon: Icon(Icons.psychology),
                      label: Text('记忆'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.science_outlined),
                      selectedIcon: Icon(Icons.science),
                      label: Text('研究'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.edit_note_outlined),
                      selectedIcon: Icon(Icons.edit_note),
                      label: Text('笔记'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.style_outlined),
                      selectedIcon: Icon(Icons.style),
                      label: Text('塔罗'),
                    ),
                    // System is handled by trailing button to separate it
                  ],
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                _selectedIndex == 5 ? Icons.settings : Icons.settings_outlined,
                                color: _selectedIndex == 5 ? Theme.of(context).colorScheme.primary : null,
                              ),
                              tooltip: '系统设置',
                              onPressed: () => _onItemTapped(5),
                            ),
                            const SizedBox(height: 8),
                            const Text('系统', style: TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: content,
                  ),
                ),
              ],
            ),
          );
        } else {
          return Scaffold(
            body: content,
            bottomNavigationBar: NavigationBar(
              onDestinationSelected: _onItemTapped,
              selectedIndex: _selectedIndex,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outlined),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Firefly',
                ),
                NavigationDestination(
                  icon: Icon(Icons.psychology_outlined),
                  selectedIcon: Icon(Icons.psychology),
                  label: '记忆',
                ),
                NavigationDestination(
                  icon: Icon(Icons.science_outlined),
                  selectedIcon: Icon(Icons.science),
                  label: '研究',
                ),
                NavigationDestination(
                  icon: Icon(Icons.edit_note_outlined),
                  selectedIcon: Icon(Icons.edit_note),
                  label: '笔记',
                ),
                NavigationDestination(
                  icon: Icon(Icons.style_outlined),
                  selectedIcon: Icon(Icons.style),
                  label: '塔罗',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: '系统',
                ),
              ],
            ),
          );
        }
      },
    );
  }
}
