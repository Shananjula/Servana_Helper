// lib/helperhomeshell.dart
//
// HelperHomeShell (Phase 1, UPDATED)
// ----------------------------------
// 5-tab shell for the Helper app using an IndexedStack.
// Adds: `initialIndex` so deep screens can jump back to a specific tab.
//
// Tabs:
//   0 • Dashboard              -> HelperDashboardScreen
//   1 • Browse (category)      -> HelperBrowseTasksScreen
//   2 • My Jobs                -> HelperActiveTaskScreen
//   3 • Chats                  -> ChatListScreen
//   4 • Settings               -> SettingsScreen

import 'package:flutter/material.dart';
import 'package:servana/screens/helper_dashboard_screen.dart';
import 'package:servana/screens/helper_browse_tasks_screen.dart';
import 'package:servana/screens/helper_active_task_screen.dart';
import 'package:servana/screens/chat_list_screen.dart';
import 'package:servana/screens/settings_screen.dart';

class HelperHomeShell extends StatefulWidget {
  const HelperHomeShell({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  State<HelperHomeShell> createState() => _HelperHomeShellState();
}

class _HelperHomeShellState extends State<HelperHomeShell> {
  late int _index;
  final _items = const <_NavItem>[
    _NavItem(icon: Icons.home_rounded, label: 'Home'),
    _NavItem(icon: Icons.search_rounded, label: 'Browse'),
    _NavItem(icon: Icons.check_circle_rounded, label: 'My jobs'),
    _NavItem(icon: Icons.chat_bubble_rounded, label: 'Chats'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _items.length - 1);
  }

  void _setIndex(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HelperDashboardScreen(),
          HelperBrowseTasksScreen(),
          HelperActiveTaskScreen(),
          ChatListScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _setIndex,
        destinations: _items
            .map((e) => NavigationDestination(icon: Icon(e.icon), label: e.label))
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
