import 'package:flutter/material.dart';
import 'package:speedguard/features/settings/settings.dart';
import 'package:speedguard/features/speedometer/speedscreen.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [SpeedPage(), SettingsPage()];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        animationDuration: Duration(milliseconds: 300),

        height: 65,
        backgroundColor: Colors.black.withOpacity(0.9),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        indicatorColor: Colors.deepPurpleAccent.withOpacity(0.3),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed_outlined, color: Colors.white70),
            selectedIcon: Icon(Icons.speed, color: Colors.deepPurpleAccent),
            label: 'Speedometer',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: Colors.white70),
            selectedIcon: Icon(Icons.settings, color: Colors.deepPurpleAccent),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
