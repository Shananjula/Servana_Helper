// lib/screens/home_screen.dart — Helper app only (no poster code)
// Bottom-nav tabs (state-preserving via IndexedStack):
//  1) Dashboard  -> HelperDashboardScreen
//  2) Find Work  -> HelperBrowseTasksScreen
//  3) Activity   -> ActivityScreen (your existing, role-aware tracker)
//  4) Chats      -> ChatListScreen
//  5) Profile    -> SettingsScreen (or your Profile screen)
//
// Notes
// - Optional initialIndex lets you deep-link to a specific tab (0..4).
// - Re-add your AppBar actions (wallet/notifications) where indicated.
// - If your class/file names differ, just tweak the imports below.

import 'package:flutter/material.dart';

// ---- Helper-only screens (adjust names if yours differ) ----
import 'helper_dashboard_screen.dart';            // 1) Dashboard
import 'helper_browse_tasks_screen.dart';         // 2) Find Work (Helper-specific)
import 'activity_screen.dart';                    // 3) Activity (existing screen)
import 'chat_list_screen.dart';                   // 4) Chats
import 'settings_screen.dart';                    // 5) Profile / Settings

class HomeScreen extends StatefulWidget {
  /// Open a specific tab: 0=Dashboard, 1=Find Work, 2=Activity, 3=Chats, 4=Profile
  final int? initialIndex;
  const HomeScreen({super.key, this.initialIndex});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 0=Dashboard, 1=Find Work, 2=Activity, 3=Chats, 4=Profile
  int _index = 0;

  static const List<String> _titles = <String>[
    'Dashboard',
    'Find Work',
    'Activity',
    'Chats',
    'Profile',
  ];

  // Keep const where possible so Flutter can optimize rebuilds.
  late final List<Widget> _tabs = const <Widget>[
    HelperDashboardScreen(),       // 0
    HelperBrowseTasksScreen(),     // 1
    ActivityScreen(),              // 2 (uses your existing activity logic)
    ChatListScreen(),              // 3
    SettingsScreen(),              // 4
  ];

  @override
  void initState() {
    super.initState();
    final i = widget.initialIndex ?? 0;
    _index = (i < 0 || i > 4) ? 0 : i;
  }

  // Friendlier back behavior: if not on Dashboard, go to Dashboard first.
  Future<bool> _handleBack() async {
    if (_index != 0) {
      setState(() => _index = 0);
      return false; // don't pop app
    }
    return true; // allow normal back
  }

  void _onSelectTab(int i) {
    if (i == _index) return;
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final allow = await _handleBack();
        if (allow && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold
        (
        appBar: AppBar(
          title: Text(_titles[_index]),
          // Restore your existing AppBar actions here if you had them:
          // actions: [
          //   IconButton(
          //     icon: const Icon(Icons.account_balance_wallet_outlined),
          //     onPressed: () => Navigator.pushNamed(context, '/wallet'),
          //   ),
          //   IconButton(
          //     icon: const Icon(Icons.notifications_none),
          //     onPressed: () => Navigator.pushNamed(context, '/notifications'),
          //   ),
          // ],
        ),
        body: IndexedStack(index: _index, children: _tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onSelectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Find Work',
            ),
            NavigationDestination(
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
