/// 首页 — 连接状态大卡片（状态灯 + 大圆形连接按钮 + 当前节点 + 运行时长）
/// 与快速入口（订阅刷新、跳转日志页）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart' show coreMihomo;
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../modals/subscription_sheet.dart';
import '../providers.dart';
import '../vpn_engine.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Timer? _uptimeTimer;
  DateTime? _connectedAt;
  Duration _uptime = Duration.zero;

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    super.dispose();
  }

  /// 阶段 → （状态文案, 状态灯颜色）。
  (String, Color) _phaseView(String phase) => switch (phase) {
        phaseStarted => ('已连接', SmPalette.green),
        phaseStarting => ('连接中…', SmPalette.yellow),
        phaseStopping => ('断开中…', SmPalette.yellow),
        _ => ('未连接', SmPalette.textDim),
      };

  void _syncUptime(String phase) {
    if (phase == phaseStarted) {
      _connectedAt ??= DateTime.now();
      _uptimeTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() =>
            _uptime = DateTime.now().difference(_connectedAt ?? DateTime.now()));
      });
    } else {
      if (phase == phaseStopped) _connectedAt = null;
      _uptimeTimer?.cancel();
      _uptimeTimer = null;
      if (phase == phaseStopped) _uptime = Duration.zero;
    }
  }

  // ─── 动作 ──────────────────────────────────────────────────────────────────

  Future<void> _toggle() async {
    final app = ref.read(smAppProvider);
    final phase = ref.read(enginePhaseProvider).valueOrNull ?? phaseStopped;
    final connecting = phase == phaseStarting || phase == phaseStarted;
    await runAction(
      context,
      connecting ? app.stopCore : app.startCore,
      failurePrefix: connecting ? '断开失败' : '连接失败',
    );
    if (mounted) setState(() {}); // 立即刷新按钮状态
  }

  Future<void> _refreshAllSubs() async {
    final app = ref.read(smAppProvider);
    final subs = app.allGroups().where((g) => g.subUrl.isNotEmpty).toList();
    if (subs.isEmpty) {
      if (mounted) {
        AppToast.show(context, '暂无订阅，可在「订阅管理」中添加', ToastType.info);
      }
      return;
    }
    var okCount = 0;
    var failCount = 0;
    for (final g in subs) {
      try {
        await app.refreshGroupSubscription(g.id);
        okCount++;
      } catch (_) {
        failCount++;
      }
    }
    if (!mounted) return;
    await ref.read(nodesProvider.notifier).reload();
    await ref.read(groupsProvider.notifier).reload();
    AppToast.show(
      context,
      failCount == 0
          ? '已刷新 $okCount 个订阅'
          : '已刷新 $okCount 个订阅，$failCount 个失败',
      failCount == 0 ? ToastType.success : ToastType.warning,
    );
  }

  // ─── 构建 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final phase =
        ref.watch(enginePhaseProvider).valueOrNull ?? phaseStopped;
    final (statusText, statusColor) = _phaseView(phase);
    final connecting =
        phase == phaseStarting || phase == phaseStarted || phase == phaseStopping;
    final applied = ref.watch(appliedNodeProvider);
    final core = ref.watch(settingsProvider).core;
    final coreName = core == coreMihomo ? 'mihomo' : 'sing-box';
    _syncUptime(phase);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SM GUI'),
        backgroundColor: SmPalette.bgPanel,
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 连接状态大卡片 ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: SmPalette.bgPanel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SmPalette.border),
            ),
            child: Column(
              children: [
                // 状态灯 + 文案
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: phase == phaseStarted
                            ? [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(statusText,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 24),
                // 大圆形连接按钮
                SizedBox(
                  width: 132,
                  height: 132,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 132,
                        height: 132,
                        child: CircularProgressIndicator(
                          value: connecting ? null : 1,
                          strokeWidth: 3,
                          color: statusColor.withValues(alpha: 0.5),
                          backgroundColor: SmPalette.border,
                        ),
                      ),
                      InkWell(
                        onTap: _toggle,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: phase == phaseStarted
                                ? SmPalette.green.withValues(alpha: 0.15)
                                : SmPalette.bgInput,
                            border: Border.all(
                                color: phase == phaseStarted
                                    ? SmPalette.green
                                    : SmPalette.accent,
                                width: 2),
                          ),
                          child: Icon(
                            phase == phaseStarted
                                ? Icons.stop_rounded
                                : Icons.power_settings_new,
                            size: 48,
                            color: phase == phaseStarted
                                ? SmPalette.green
                                : SmPalette.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  phase == phaseStarted ? '点击断开' : '点击连接',
                  style: const TextStyle(
                      color: SmPalette.textDim, fontSize: 12),
                ),
                const SizedBox(height: 20),
                // 当前节点
                Text(
                  applied == null ? '当前节点：未应用' : '当前节点：${applied.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: SmPalette.text, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  '内核：$coreName',
                  style: const TextStyle(
                      color: SmPalette.textDim, fontSize: 12),
                ),
                Text(
                  '运行时长 ${formatUptime(_uptime)}',
                  style: const TextStyle(
                      color: SmPalette.textDim, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── 快速入口 ──
          const Text('快速入口',
              style: TextStyle(
                  color: SmPalette.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _QuickCard(
                  icon: Icons.refresh,
                  label: '订阅刷新',
                  color: SmPalette.accent,
                  onTap: _refreshAllSubs,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickCard(
                  icon: Icons.terminal_outlined,
                  label: '查看日志',
                  color: SmPalette.cyan,
                  onTap: () => ref.read(tabIndexProvider.notifier).state = 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _QuickCard(
            icon: Icons.rss_feed_outlined,
            label: '订阅管理',
            color: SmPalette.orange,
            onTap: () => showSubscriptionSheet(context),
          ),
        ],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: SmPalette.bgPanel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SmPalette.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(label,
                style:
                    const TextStyle(color: SmPalette.text, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
