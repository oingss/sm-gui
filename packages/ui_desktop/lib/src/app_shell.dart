/// 应用主壳 — 对齐 Go 版 React 版 App.jsx：
/// 标题栏（节点列表 / 运行日志 / ⚙设置 Tab + 内核状态灯）→
/// ConfigBar（仅节点页）→ 内容区 → BottomBar。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_kit/ui_kit.dart';

import 'modals/import_modal.dart';
import 'modals/subscription_modal.dart';
import 'providers.dart';
import 'widgets/bottom_bar.dart';
import 'widgets/config_bar.dart';
import 'widgets/log_panel.dart';
import 'widgets/node_list.dart';
import 'settings_panel.dart';

/// 主窗口内容（不含 MaterialApp，由 apps/desktop 提供）。
class SmDesktopApp extends ConsumerStatefulWidget {
  const SmDesktopApp({super.key});

  @override
  ConsumerState<SmDesktopApp> createState() => _SmDesktopAppState();
}

class _SmDesktopAppState extends ConsumerState<SmDesktopApp> {
  String _tab = 'nodes'; // nodes | log | settings

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
      width: 540,
      builder: (_) => const SubscriptionModal(),
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
            ),
          // ── 主内容 ──
          Expanded(
            child: switch (_tab) {
              'log' => const LogPanel(),
              'settings' => const SettingsPanel(),
              _ => const NodeList(),
            },
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
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: SmPalette.bgPanel,
        border: Border(bottom: BorderSide(color: SmPalette.border)),
      ),
      child: Row(
        children: [
          // Tab 胶囊组
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: SmPalette.bgInput,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _TabButton(
                  label: '节点列表',
                  active: tab == 'nodes',
                  onTap: () => onTab('nodes'),
                ),
                _TabButton(
                  label: '运行日志',
                  active: tab == 'log',
                  badge: running,
                  onTap: () => onTab('log'),
                ),
                _TabButton(
                  label: '⚙ 设置',
                  active: tab == 'settings',
                  onTap: () => onTab('settings'),
                ),
              ],
            ),
          ),
          const Spacer(),
          // 状态胶囊
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: SmPalette.bgInput,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: running ? SmPalette.green : SmPalette.textFaint,
                    boxShadow: running
                        ? [
                            BoxShadow(
                              color: SmPalette.green.withValues(alpha: 0.35),
                              blurRadius: 4,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  running ? '运行中 #$pid' : '未运行',
                  style: const TextStyle(
                    color: SmPalette.textMid,
                    fontSize: 11,
                    fontFamily: 'Consolas',
                  ),
                ),
              ],
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
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: active ? SmPalette.bgPanel : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: active ? SmPalette.accent : SmPalette.textMid,
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (badge) ...[
              const SizedBox(width: 5),
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
