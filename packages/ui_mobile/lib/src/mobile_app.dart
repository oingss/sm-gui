/// 移动端主壳 — BottomNavigationBar 四页（首页/节点/日志/设置），
/// IndexedStack 保活各页状态；深色 Material 3 主题由 ui_kit 提供。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import 'pages/home_page.dart';
import 'pages/logs_page.dart';
import 'pages/nodes_page.dart';
import 'pages/settings_page.dart';
import 'providers.dart';

/// 移动端主界面内容（不含 MaterialApp，由 apps/mobile 提供）。
class SmMobileApp extends ConsumerWidget {
  const SmMobileApp({super.key});

  static const _pages = [
    HomePage(),
    NodesPage(),
    LogsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabIndexProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: index,
        selectedItemColor: SmPalette.accent,
        unselectedItemColor: SmPalette.textDim,
        backgroundColor: SmPalette.bgPanel,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: (i) => ref.read(tabIndexProvider.notifier).state = i,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.power_settings_new), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.dns_outlined), label: '节点'),
          BottomNavigationBarItem(icon: Icon(Icons.terminal_outlined), label: '日志'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}
