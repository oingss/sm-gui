/// 底部状态栏 — 启动/停止核心（状态灯）、系统代理、TUN、mixed 端口、当前应用节点。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../providers.dart';

class BottomBar extends ConsumerWidget {
  const BottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(smAppProvider);
    final settings = ref.watch(settingsProvider);
    final status =
        ref.watch(coreStatusProvider).valueOrNull ?? const ProcessStatus();
    final sysProxy = ref.watch(sysProxyProvider).valueOrNull ?? false;
    final tun = ref.watch(tunEnabledProvider);
    final appliedNode = ref.watch(appliedNodeProvider);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: SmPalette.bgPanel,
        border: Border(top: BorderSide(color: SmPalette.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          // 启动/停止核心
          InkWell(
            onTap: () => _toggleCore(context, ref, app, !status.running),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: status.running
                          ? SmPalette.green
                          : SmPalette.textDim,
                      boxShadow: status.running
                          ? [
                              BoxShadow(
                                color: SmPalette.green.withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    status.running
                        ? '${settings.core} 运行中'
                        : '启动 ${settings.core}',
                    style: const TextStyle(
                        color: SmPalette.text, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const _VDivider(),
          _SwitchItem(
            label: '系统代理',
            value: sysProxy,
            activeColor: SmPalette.accent,
            desc: sysProxy
                ? '127.0.0.1:${settings.proxyPort}'
                : '点击设置系统代理',
            onChanged: (v) => _toggleProxy(context, ref, app, v),
          ),
          const _VDivider(),
          _SwitchItem(
            label: 'TUN 模式',
            value: tun,
            activeColor: SmPalette.green,
            desc: tun ? '虚拟网卡已启用' : '点击启用 TUN',
            onChanged: (v) => _toggleTun(context, ref, app, v),
          ),
          const _VDivider(),
          Text(
            'mixed 端口: ${settings.proxyPort}',
            style: const TextStyle(color: SmPalette.textDim, fontSize: 12),
          ),
          const SizedBox(width: 16),
          Text(
            '当前节点: ${appliedNode == null ? '未应用' : appliedNode.name}',
            style: const TextStyle(color: SmPalette.textDim, fontSize: 12),
          ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleCore(
      BuildContext context, WidgetRef ref, SmApp app, bool on) async {
    await runAction(
      context,
      () => on ? app.startCore() : app.stopCore(),
      successMsg: on ? '${app.settings.core} 已启动' : '${app.settings.core} 已停止',
      failurePrefix: on ? '启动失败' : '停止失败',
    );
  }

  Future<void> _toggleProxy(
      BuildContext context, WidgetRef ref, SmApp app, bool on) async {
    await runAction(
      context,
      () => on ? app.enableSystemProxy() : app.disableSystemProxy(),
      successMsg: on ? '已启用系统代理' : '已关闭系统代理',
      failurePrefix: '系统代理操作失败',
    );
    ref.read(sysProxyProvider.notifier).reload();
  }

  Future<void> _toggleTun(
      BuildContext context, WidgetRef ref, SmApp app, bool on) async {
    await runAction(
      context,
      () => on ? app.enableTun() : app.disableTun(),
      successMsg: on ? '已启用 TUN 模式' : '已关闭 TUN 模式',
      failurePrefix: 'TUN 操作失败',
    );
    ref.read(settingsVersionProvider.notifier).bump();
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: SmPalette.border,
    );
  }
}

class _SwitchItem extends StatelessWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final String desc;
  final ValueChanged<bool> onChanged;

  const _SwitchItem({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.desc,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              height: 20,
              width: 36,
              child: Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: value,
                  activeThumbColor: activeColor,
                  onChanged: onChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: SmPalette.text, fontSize: 12)),
                Text(desc,
                    style: TextStyle(
                        color: value ? activeColor : SmPalette.textDim,
                        fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
