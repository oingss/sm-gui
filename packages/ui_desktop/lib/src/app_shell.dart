/// 应用主壳 — 对齐原 React 版 App.jsx：
/// 标题栏（节点列表/运行日志 Tab + 内核状态灯）→ ConfigBar → 内容区 → BottomBar。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_kit/ui_kit.dart';

import 'modals/import_modal.dart';
import 'modals/settings_modal.dart';
import 'modals/subscription_modal.dart';
import 'providers.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/config_bar.dart';
import 'widgets/log_panel.dart';
import 'widgets/node_list.dart';

/// 主窗口内容（不含 MaterialApp，由 apps/desktop 提供）。
class SmDesktopApp extends ConsumerStatefulWidget {
  const SmDesktopApp({super.key});

  @override
  ConsumerState<SmDesktopApp> createState() => _SmDesktopAppState();
}

class _SmDesktopAppState extends ConsumerState<SmDesktopApp> {
  String _tab = 'nodes'; // nodes | log

  void _openImport() {
    AppModal.show<void>(
      context,
      title: '导入节点',
      width: 560,
      builder: (_) => const ImportModal(),
    );
  }

  void _openSubscription() {
    AppModal.show<void>(
      context,
      title: '订阅管理',
      width: 560,
      builder: (_) => const SubscriptionModal(),
    );
  }

  void _openSettings() {
    AppModal.show<void>(
      context,
      title: '设置',
      width: 620,
      builder: (_) => const SettingsModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status =
        ref.watch(coreStatusProvider).valueOrNull ?? const ProcessStatus();
    final running = status.running;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 标题栏 ──
          _TitleBar(
            tab: _tab,
            onTab: (t) => setState(() => _tab = t),
            running: running,
            pid: status.pid,
          ),
          // ── 配置栏（仅节点列表页）──
          if (_tab == 'nodes')
            ConfigBar(
              onImport: _openImport,
              onSubscription: _openSubscription,
              onSettings: _openSettings,
            ),
          // ── 主内容 ──
          Expanded(
            child: _tab == 'nodes' ? const NodeList() : const LogPanel(),
          ),
          // ── 底部栏 ──
          const BottomBar(),
        ],
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  final String tab;
  final ValueChanged<String> onTab;
  final bool running;
  final int pid;

  const _TitleBar({
    required this.tab,
    required this.onTab,
    required this.running,
    required this.pid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: SmPalette.bgPanel,
        border: Border(bottom: BorderSide(color: SmPalette.border)),
      ),
      child: Row(
        children: [
          _TabButton(
            label: '节点列表',
            active: tab == 'nodes',
            onTap: () => onTab('nodes'),
          ),
          const SizedBox(width: 6),
          _TabButton(
            label: '运行日志',
            active: tab == 'log',
            badge: running,
            onTap: () => onTab('log'),
          ),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: running ? SmPalette.green : SmPalette.textDim,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            running ? '运行中 #$pid' : '未运行',
            style: TextStyle(
              color: running ? SmPalette.green : SmPalette.textDim,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final bool badge;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.active,
    this.badge = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? SmPalette.accent.withValues(alpha: 0.18) : null,
          borderRadius: BorderRadius.circular(6),
          border: active
              ? Border.all(color: SmPalette.accent.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? SmPalette.text : SmPalette.textDim,
                fontSize: 13,
              ),
            ),
            if (badge) ...[
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: SmPalette.green,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
