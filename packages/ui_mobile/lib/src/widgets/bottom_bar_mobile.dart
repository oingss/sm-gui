/// 移动端底部状态栏 — 与桌面端 widgets/bottom_bar.dart 视觉完全一致的
/// 开关块样式（图标 + 标签 + 开关 + 描述行），但桌面端的三个开关
/// （TUN 模式 / 系统代理 / 启动核心）在移动端合并为一个「启动 VPN」开关——
/// 移动端恒为 Android VPN 模式，TUN 由系统 VpnService 建立，无系统代理概念。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../providers.dart';
import '../vpn_engine.dart';

class BottomBarMobile extends ConsumerWidget {
  const BottomBarMobile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(smAppProvider);
    final settings = ref.watch(settingsProvider);
    final phase = ref.watch(enginePhaseProvider).valueOrNull ?? phaseStopped;
    final coreName = settings.core == coreMihomo ? 'mihomo' : 'sing-box';
    final running = phase == phaseStarted;
    final busy = phase == phaseStarting || phase == phaseStopping;

    final desc = switch (phase) {
      phaseStarted => '$coreName 运行中，VPN 已连接',
      phaseStarting => '正在连接…',
      phaseStopping => '正在断开…',
      _ => '点击启动 VPN（$coreName）',
    };

    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: SmPalette.bgPanel,
        border: Border(top: BorderSide(color: SmPalette.border)),
      ),
      child: SafeArea(
        top: false,
        child: _ToggleBlock(
          label: '启动 VPN',
          icon: '▶',
          enabled: running,
          busy: busy,
          activeColor: SmPalette.green,
          desc: desc,
          onToggle: (on) => _toggleVpn(context, ref, app, on),
        ),
      ),
    );
  }

  Future<void> _toggleVpn(
      BuildContext context, WidgetRef ref, SmApp app, bool on) async {
    final coreName = app.settings.core == coreMihomo ? 'mihomo' : 'sing-box';
    await runAction(
      context,
      () => on ? app.startCore() : app.stopCore(),
      successMsg: on ? '$coreName 已启动' : '$coreName 已停止',
      failurePrefix: on ? '启动失败' : '停止失败',
    );
  }
}

/// 开关块（与桌面 BottomBar._ToggleBlock 视觉完全一致）。
class _ToggleBlock extends StatelessWidget {
  final String label;
  final String icon;
  final bool enabled;
  final bool busy;
  final Color activeColor;
  final String desc;
  final ValueChanged<bool> onToggle;

  const _ToggleBlock({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.activeColor,
    required this.desc,
    required this.onToggle,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? activeColor : SmPalette.textMid;
    return InkWell(
      onTap: busy ? null : () => onToggle(!enabled),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: enabled
              ? activeColor.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(icon,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: fg, fontSize: 16, fontFamily: 'Consolas')),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: fg, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: enabled
                          ? Color.lerp(activeColor, SmPalette.textDim, 0.3)
                          : SmPalette.textDim,
                      fontSize: 11,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              _MiniSwitch(on: enabled, activeColor: activeColor),
          ],
        ),
      ),
    );
  }
}

/// 开关外观（与桌面 BottomBar._MiniSwitch 完全一致，40×22 胶囊 + 滑块，
/// 略放大以适配触控）。
class _MiniSwitch extends StatelessWidget {
  final bool on;
  final Color activeColor;

  const _MiniSwitch({required this.on, required this.activeColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 22,
      decoration: BoxDecoration(
        color: on ? activeColor : SmPalette.bgHover,
        borderRadius: BorderRadius.circular(11),
        boxShadow: on
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.18),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 16,
          height: 16,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? Colors.white : SmPalette.textDim,
            boxShadow: const [
              BoxShadow(
                  color: Colors.black26, offset: Offset(0, 1), blurRadius: 2),
            ],
          ),
        ),
      ),
    );
  }
}
