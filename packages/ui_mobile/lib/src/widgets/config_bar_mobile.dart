/// 移动端配置栏 — 与桌面端 widgets/config_bar.dart 字段完全一致：
/// 配置文件下拉（真实文件 + 内置路由分组）+ 刷新/打开目录 +
/// 导入节点 / 订阅 / 清空 + 节点计数。桌面端挤在一行，移动端拆成两行避免溢出。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../modals/import_sheet.dart';
import '../modals/subscription_sheet.dart';
import '../providers.dart';

class ConfigBarMobile extends ConsumerWidget {
  const ConfigBarMobile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final configFiles =
        ref.watch(configFilesProvider).valueOrNull ?? const <String>[];
    final nodes = ref.watch(nodesProvider).valueOrNull ?? const [];
    final core = settings.core;
    final isMihomo = core == coreMihomo;
    final extHint = isMihomo ? 'yaml' : 'json';

    final activePath = settings.activeConfigPath();
    final activeBuiltin =
        isBuiltinMode(settings.routingMode) ? settings.routingMode : '';
    final builtinItems = builtinDisplayNames();
    final realFiles =
        configFiles.where((f) => parseBuiltinName(f) == null).toList();

    final selectedName = activeBuiltin.isNotEmpty
        ? (builtinDisplayName(activeBuiltin) ?? '')
        : activePath;
    final value = configFiles.contains(selectedName) ? selectedName : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: SmPalette.bgPanel,
        border: Border(bottom: BorderSide(color: SmPalette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 配置文件区域 ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: SmPalette.bgInput,
              border: Border.all(color: SmPalette.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_ethernet,
                    size: 14, color: SmPalette.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: value.isEmpty ? null : value,
                    isDense: true,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down,
                        size: 18, color: SmPalette.textDim),
                    decoration: const InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isCollapsed: true,
                    ),
                    hint: Text(
                      configFiles.isEmpty
                          ? 'configs 目录为空，请放入 $extHint 配置…'
                          : (value.isEmpty ? '— 选择 $core 配置文件 —' : value),
                      style: TextStyle(
                        color: value.isEmpty
                            ? SmPalette.textDim
                            : SmPalette.text,
                        fontSize: 12,
                        fontFamily: 'Consolas',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: [
                      for (final f in realFiles)
                        DropdownMenuItem(
                          value: f,
                          child: Text(f,
                              style: const TextStyle(
                                  color: SmPalette.text,
                                  fontSize: 12,
                                  fontFamily: 'Consolas'),
                              overflow: TextOverflow.ellipsis),
                        ),
                      for (final b in builtinItems)
                        DropdownMenuItem(
                          value: b,
                          child: Text(b,
                              style: const TextStyle(
                                  color: SmPalette.textMid, fontSize: 12),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => _selectConfig(context, ref, v),
                  ),
                ),
                _MiniBtn(
                  icon: Icons.refresh,
                  tooltip: '重新扫描 configs 目录',
                  onTap: () => ref.read(configFilesProvider.notifier).reload(),
                ),
                _MiniBtn(
                  icon: Icons.home_outlined,
                  tooltip: '打开 configs 目录',
                  onTap: () async {
                    final app = ref.read(smAppProvider);
                    try {
                      await app.openConfigsDir();
                    } catch (_) {/* ignore */}
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ── 动作按钮 + 节点计数 ──
          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  label: '导入',
                  icon: Icons.add_circle_outline,
                  onTap: () => showImportSheet(context),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionBtn(
                  label: '订阅',
                  icon: Icons.sync,
                  onTap: () => showSubscriptionSheet(context),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionBtn(
                  label: '清空',
                  icon: Icons.do_not_disturb_on_outlined,
                  danger: true,
                  onTap: () => _clearNodes(context, ref),
                ),
              ),
              const SizedBox(width: 8),
              Text('${nodes.length} 个',
                  style: const TextStyle(
                      color: SmPalette.textDim,
                      fontSize: 11,
                      fontFamily: 'Consolas')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _selectConfig(
      BuildContext context, WidgetRef ref, String? name) async {
    if (name == null || name.isEmpty) return;
    final app = ref.read(smAppProvider);
    await runAction(context, () => app.selectConfigFile(name),
        successMsg: '已切换配置: $name', failurePrefix: '切换配置失败');
    ref.read(settingsVersionProvider.notifier).bump();
    ref.read(configFilesProvider.notifier).reload();
  }

  Future<void> _clearNodes(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDialog(context, '确认清空所有节点？');
    if (!confirmed || !context.mounted) return;
    final app = ref.read(smAppProvider);
    await runAction(context, () async => app.clearAllNodes(),
        successMsg: '已清空所有节点', failurePrefix: '清空失败');
    await ref.read(nodesProvider.notifier).reload();
  }
}

/// 下拉旁的小圆钮（刷新 / 打开目录）。
class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniBtn(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 30,
          margin: const EdgeInsets.only(left: 2),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: SmPalette.textDim),
        ),
      ),
    );
  }
}

/// 动作按钮（导入 / 订阅 / 清空）——移动端等宽三分栏，替代桌面端的横排按钮组。
class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool danger;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? SmPalette.red : SmPalette.text;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: const BorderSide(color: SmPalette.border),
        backgroundColor: SmPalette.bgInput,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }
}
