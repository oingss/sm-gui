/// 顶部配置栏 — 路由模式 / 内核 / 配置文件 / DNS 模式 / 导入 / 订阅 / 设置。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../providers.dart';

/// 路由模式下拉项。
class _ModeOption {
  final String mode;
  final String label;
  const _ModeOption(this.mode, this.label);
}

class ConfigBar extends ConsumerWidget {
  final VoidCallback onImport;
  final VoidCallback onSubscription;
  final VoidCallback onSettings;

  const ConfigBar({
    super.key,
    required this.onImport,
    required this.onSubscription,
    required this.onSettings,
  });

  List<_ModeOption> get _modeOptions => [
        const _ModeOption(modeCustom, '跟随配置文件'),
        for (final name in builtinDisplayNames())
          _ModeOption(parseBuiltinName(name)!, name),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final configFiles = ref.watch(configFilesProvider).valueOrNull ?? const [];
    final builtin = isBuiltinMode(settings.routingMode);
    final activePath = settings.activeConfigPath();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: SmPalette.bgPanel,
        border: Border(bottom: BorderSide(color: SmPalette.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          const Icon(Icons.settings_ethernet,
              size: 16, color: SmPalette.textDim),
          const SizedBox(width: 8),
          _label('路由模式'),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: settings.routingMode,
              isDense: true,
              isExpanded: true,
              items: [
                for (final m in _modeOptions)
                  DropdownMenuItem(
                      value: m.mode,
                      child: Text(m.label,
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => _changeMode(context, ref, v),
              decoration: const InputDecoration(
                hintText: '选择路由模式',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 14),
          _label('内核'),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<String>(
              initialValue: settings.core,
              isDense: true,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                    value: coreSingBox,
                    child: Text('sing-box')),
                DropdownMenuItem(
                    value: coreMihomo,
                    child: Text('mihomo')),
              ],
              onChanged: (v) => _changeCore(context, ref, v),
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 14),
          if (builtin) ...[
            _label('DNS 模式'),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                initialValue: settings.builtin.dnsMode,
                isDense: true,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                      value: 'redir-host',
                      child: Text('redir-host')),
                  DropdownMenuItem(
                      value: 'fake-ip',
                      child: Text('fake-ip')),
                ],
                onChanged: (v) => _changeDnsMode(context, ref, v),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 6, vertical: 8),
                ),
              ),
            ),
          ] else ...[
            _label('配置文件'),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue:
                    activePath.isEmpty ? null : activePath,
                hint: Text(
                  configFiles.isEmpty
                      ? 'configs 目录为空'
                      : '— 选择配置文件 —',
                  style: const TextStyle(
                      color: SmPalette.textDim, fontSize: 12),
                ),
                isDense: true,
                isExpanded: true,
                items: [
                  for (final f in configFiles)
                    DropdownMenuItem(
                        value: f,
                        child: Text(f,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => _selectConfig(context, ref, v),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 6, vertical: 8),
                ),
              ),
            ),
          ],
          const SizedBox(width: 14),
          _ActionButton(
            icon: Icons.add_circle_outline,
            label: '导入节点',
            onTap: onImport,
          ),
          _ActionButton(
            icon: Icons.sync,
            label: '订阅',
            onTap: onSubscription,
          ),
          _ActionButton(
            icon: Icons.settings_outlined,
            label: '设置',
            onTap: onSettings,
          ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Text(text,
            style:
                const TextStyle(color: SmPalette.textDim, fontSize: 12)),
      );

  Future<void> _changeMode(
      BuildContext context, WidgetRef ref, String? mode) async {
    if (mode == null) return;
    final app = ref.read(smAppProvider);
    await runAction(context, () async {
      app.settings.routingMode = mode;
      app.cfgManager.save();
      await app.restartIfRunning();
      ref.read(settingsVersionProvider.notifier).bump();
    }, successMsg: '路由模式已切换', failurePrefix: '切换路由模式失败');
    ref.read(configFilesProvider.notifier).reload();
  }

  Future<void> _changeCore(
      BuildContext context, WidgetRef ref, String? core) async {
    if (core == null) return;
    final app = ref.read(smAppProvider);
    await runAction(context, () async {
      app.settings.core = core;
      app.cfgManager.save();
      await app.restartIfRunning();
      ref.read(settingsVersionProvider.notifier).bump();
    }, successMsg: '已切换内核: $core', failurePrefix: '切换内核失败');
    ref.read(configFilesProvider.notifier).reload();
  }

  Future<void> _changeDnsMode(
      BuildContext context, WidgetRef ref, String? mode) async {
    if (mode == null) return;
    final app = ref.read(smAppProvider);
    await runAction(context, () async {
      app.settings.builtin.dnsMode = mode;
      app.cfgManager.save();
      await app.restartIfRunning();
      ref.read(settingsVersionProvider.notifier).bump();
    }, successMsg: 'DNS 模式已切换为 $mode', failurePrefix: '切换 DNS 模式失败');
  }

  Future<void> _selectConfig(
      BuildContext context, WidgetRef ref, String? name) async {
    if (name == null || name.isEmpty) return;
    final app = ref.read(smAppProvider);
    await runAction(context, () => app.selectConfigFile(name),
        successMsg: '已切换配置: $name', failurePrefix: '切换配置失败');
    ref.read(settingsVersionProvider.notifier).bump();
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: SmPalette.text,
          side: const BorderSide(color: SmPalette.border),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
