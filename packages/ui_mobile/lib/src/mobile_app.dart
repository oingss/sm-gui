/// 移动端主壳 — 与桌面端 app_shell.dart 结构完全一致：
/// 标题栏（节点列表 / 运行日志 / ⚙设置 Tab + 内核状态灯）→
/// ConfigBar（仅节点页）→ 内容区 → BottomBar（单一「启动 VPN」开关）。
/// 首页大圆形连接按钮已并入节点页顶部（HomePage 作为节点页的头部卡片），
/// 与桌面端「无独立首页 Tab、状态常驻标题栏/底部栏」的信息架构保持一致。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import 'pages/home_page.dart';
import 'pages/logs_page.dart';
import 'pages/nodes_page.dart';
import 'pages/settings_page.dart';
import 'providers.dart';
import 'widgets/bottom_bar_mobile.dart';
import 'widgets/config_bar_mobile.dart';
import 'widgets/title_bar.dart';

/// 移动端主界面内容（不含 MaterialApp，由 apps/mobile 提供）。
class SmMobileApp extends ConsumerStatefulWidget {
  const SmMobileApp({super.key});

  @override
  ConsumerState<SmMobileApp> createState() => _SmMobileAppState();
}

class _SmMobileAppState extends ConsumerState<SmMobileApp> {
  String _tab = 'nodes'; // nodes | log | settings

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 标题栏（与桌面完全一致的 Tab 胶囊 + 状态胶囊）──
          MobileTitleBar(
            tab: _tab,
            onTab: (t) => setState(() => _tab = t),
          ),
          // ── 配置栏（仅节点列表页，字段对齐桌面 ConfigBar）──
          if (_tab == 'nodes') const ConfigBarMobile(),
          // ── 主内容 ──
          Expanded(
            child: switch (_tab) {
              'log' => const LogsPage(),
              'settings' => const SettingsPage(),
              _ => const _NodesTab(),
            },
          ),
          // ── 底部栏（桌面三开关合并为一个「启动 VPN」）──
          const BottomBarMobile(),
        ],
      ),
    );
  }
}

/// 节点 Tab：顶部保留连接状态卡片（原首页大圆按钮/当前节点/线路信息），
/// 下接分组页签 + 节点列表——桌面端没有独立「首页」概念，状态信息常驻
/// 标题栏/底部栏，这里把连接状态卡片折叠进节点页顶部，信息架构对齐桌面。
class _NodesTab extends StatelessWidget {
  const _NodesTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ConnectionStatusCard(),
        const Divider(height: 1, color: SmPalette.border),
        const Expanded(child: NodesPage()),
      ],
    );
  }
}
