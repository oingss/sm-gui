/// 标题栏 — 与桌面端 apps_shell.dart 的 _TitleBar 完全一致的结构：
/// Tab 胶囊组（节点列表 / 运行日志 / ⚙ 设置）+ 右侧内核运行状态胶囊。
/// 移动端仅将高度与内边距放大以适配触控，颜色/形状/文案与桌面端相同。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_kit/ui_kit.dart';

import '../providers.dart';

class MobileTitleBar extends ConsumerWidget {
  final String tab;
  final ValueChanged<String> onTab;

  const MobileTitleBar({super.key, required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status =
        ref.watch(coreStatusProvider).valueOrNull ?? const ProcessStatus();
    final running = status.running;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: SmPalette.bgPanel,
        border: Border(bottom: BorderSide(color: SmPalette.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Tab 胶囊组（横向可滚动，防止小屏挤压换行）
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
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
              ),
            ),
            const SizedBox(width: 8),
            // 状态胶囊
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: SmPalette.bgInput,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(width: 6),
                  Text(
                    running ? '运行中' : '未运行',
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                fontSize: 13,
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
