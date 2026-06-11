// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:webview_guardian_example/src/app_controller.dart';
import 'package:webview_guardian_example/src/browser_tab.dart';
import 'package:webview_guardian_example/src/logs_tab.dart';
import 'package:webview_guardian_example/src/settings_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      SettingsTab(controller: widget.controller),
      LogsTab(controller: widget.controller),
      BrowserTab(controller: widget.controller),
    ];

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final isWide = MediaQuery.sizeOf(context).width >= 840;

        return Scaffold(
          appBar: AppBar(
            title: const Text('WebView Guardian'),
            actions: [
              _ReadinessChip(controller: widget.controller),
              const SizedBox(width: 12),
            ],
          ),
          body: isWide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectTab,
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.shield_outlined),
                          selectedIcon: Icon(Icons.shield),
                          label: Text('Blocker'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.receipt_long_outlined),
                          selectedIcon: Icon(Icons.receipt_long),
                          label: Text('Logs'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.public_outlined),
                          selectedIcon: Icon(Icons.public),
                          label: Text('Browser'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _TabStack(selectedIndex: _selectedIndex, tabs: tabs),
                    ),
                  ],
                )
              : _TabStack(selectedIndex: _selectedIndex, tabs: tabs),
          bottomNavigationBar: isWide
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectTab,
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.shield_outlined), label: 'Blocker'),
                    NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Logs'),
                    NavigationDestination(icon: Icon(Icons.public_outlined), label: 'Browser'),
                  ],
                ),
        );
      },
    );
  }

  void _selectTab(int index) {
    setState(() => _selectedIndex = index);
  }
}

class _TabStack extends StatelessWidget {
  const _TabStack({required this.selectedIndex, required this.tabs});

  final int selectedIndex;
  final List<Widget> tabs;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(index: selectedIndex, children: tabs);
  }
}

class _ReadinessChip extends StatelessWidget {
  const _ReadinessChip({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = controller.isReady;
    final isLoading = controller.isInitializing || controller.isUpdatingSubscriptions;

    return Chip(
      avatar: isLoading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isReady ? Icons.check_circle : Icons.sync_problem,
              size: 18,
              color: isReady ? colorScheme.primary : colorScheme.error,
            ),
      label: Text(isReady ? 'Ready' : 'Loading'),
    );
  }
}
