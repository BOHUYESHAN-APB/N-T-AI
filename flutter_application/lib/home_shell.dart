import 'package:flutter/material.dart';
import 'screens/chats_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/social_screen.dart';
import 'screens/system_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({Key? key}) : super(key: key);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static final List<Widget> _pages = <Widget>[
    ChatsScreen(),
    NotesScreen(),
    SocialScreen(),
    SystemScreen(),
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
        final navItems = const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outlined), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.note_outlined), selectedIcon: Icon(Icons.note), label: 'Notes'),
          NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: 'Social'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'System'),
        ];

        final content = _pages[_selectedIndex];

        final titles = const ['Chats', 'Notes', 'Social', 'System'];
        return Scaffold(
          appBar: AppBar(title: Text('N-T-AI · ${titles[_selectedIndex]}')),
          body: isWide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _onItemTapped,
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(icon: Icon(Icons.chat_bubble_outlined), selectedIcon: Icon(Icons.chat_bubble), label: Text('Chats')),
                        NavigationRailDestination(icon: Icon(Icons.note_outlined), selectedIcon: Icon(Icons.note), label: Text('Notes')),
                        NavigationRailDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public), label: Text('Social')),
                        NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('System')),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: content),
                  ],
                )
              : content,
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onItemTapped,
                  destinations: navItems,
                ),
        );
      },
    );
  }
}
