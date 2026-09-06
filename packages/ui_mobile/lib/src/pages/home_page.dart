/// 连接状态卡片 — 状态灯 + 大圆形连接按钮 + 当前节点 + 内核/线路 + 运行时长。
/// 嵌入节点页顶部（对齐桌面端「无独立首页 Tab，状态常驻标题栏/底部栏」的
/// 信息架构：桌面端状态灯在标题栏、启动开关在底部栏，移动端把同样的信息
/// 折叠进一张卡片，放在节点页顶部，紧邻底部的「启动 VPN」开关）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart'
    show coreMihomo, isBuiltinMode, builtinDisplayName, modeCustom;
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../providers.dart';
import '../vpn_engine.dart';

class ConnectionStatusCard extends ConsumerStatefulWidget {
  const ConnectionStatusCard({super.key});

  @override
  ConsumerState<ConnectionStatusCard> createState() =>
      _ConnectionStatusCardState();
}

class _ConnectionStatusCardState extends ConsumerState<ConnectionStatusCard> {
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

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(enginePhaseProvider).valueOrNull ?? phaseStopped;
    final (statusText, statusColor) = _phaseView(phase);
    final connecting =
        phase == phaseStarting || phase == phaseStarted || phase == phaseStopping;
    final applied = ref.watch(appliedNodeProvider);
    final settings = ref.watch(settingsProvider);
    final core = settings.core;
    final coreName = core == coreMihomo ? 'mihomo' : 'sing-box';
    final routingLabel = isBuiltinMode(settings.routingMode)
        ? (builtinDisplayName(settings.routingMode) ?? settings.routingMode)
        : (settings.routingMode == modeCustom
            ? (settings.activeConfigPath().isEmpty
                ? '自定义（未选择配置文件）'
                : settings.activeConfigPath())
            : settings.routingMode);
    _syncUptime(phase);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: SmPalette.bgPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SmPalette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 大圆形连接按钮（左）
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
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
                    width: 68,
                    height: 68,
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
                      size: 30,
                      color:
                          phase == phaseStarted ? SmPalette.green : SmPalette.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 状态文案（右）
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: phase == phaseStarted
                            ? [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.5),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(statusText,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  applied == null ? '当前节点：未应用' : '当前节点：${applied.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: SmPalette.text, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '内核：$coreName · 线路：$routingLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: SmPalette.textDim, fontSize: 11),
                ),
                if (phase == phaseStarted) ...[
                  const SizedBox(height: 2),
                  Text(
                    '运行时长 ${formatUptime(_uptime)}',
                    style: const TextStyle(color: SmPalette.textDim, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
