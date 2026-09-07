/// 订阅管理弹层（BottomSheet）— 移植 ui_desktop/subscription_modal：
/// 已有订阅（订阅分组）列表：编辑 / 更新；新增订阅：名称 / URL / 自动更新 / 间隔。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../providers.dart';
import 'group_edit_sheet.dart';

/// 弹出订阅管理 BottomSheet。
Future<void> showSubscriptionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SmPalette.bgPanel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const SubscriptionSheet(),
  );
}

class SubscriptionSheet extends ConsumerStatefulWidget {
  const SubscriptionSheet({super.key});

  @override
  ConsumerState<SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends ConsumerState<SubscriptionSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  bool _autoUpdate = false;
  final _interval = TextEditingController(text: '24');
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_loading || _url.text.trim().isEmpty) return;
    final app = ref.read(smAppProvider);
    setState(() => _loading = true);
    final ok = await runAction(context, () async {
      await app.addSubscription(
        name: _name.text.trim().isEmpty ? '订阅' : _name.text.trim(),
        url: _url.text.trim(),
        autoUpdate: _autoUpdate,
        updateIntervalHours: int.tryParse(_interval.text) ?? 10,
      );
      if (mounted) {
        AppToast.show(context, '订阅已添加', ToastType.success);
      }
    }, failurePrefix: '添加订阅失败');
    if (ok && mounted) Navigator.of(context).pop();
    if (mounted) setState(() => _loading = false);
    await ref.read(groupsProvider.notifier).reload();
    await ref.read(nodesProvider.notifier).reload();
  }

  Future<void> _refresh(Group g) async {
    final app = ref.read(smAppProvider);
    final ok = await runAction(context, () async {
      final count = await app.refreshGroupSubscription(g.id);
      if (mounted) {
        AppToast.show(context, '订阅「${g.name}」更新成功，共 $count 个节点',
            ToastType.success);
      }
    }, failurePrefix: '订阅更新失败');
    if (ok) {
      await ref.read(nodesProvider.notifier).reload();
      await ref.read(groupsProvider.notifier).reload();
      if (mounted) setState(() {}); // 刷新组头更新时间
    }
  }

  Future<void> _edit(Group g) {
    return showGroupEditSheet(context, group: g);
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).valueOrNull ?? const [];
    final subs = groups.where((g) => g.subUrl.isNotEmpty).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '订阅管理',
                style: TextStyle(
                    color: SmPalette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              if (subs.isNotEmpty) ...[
                const Text('已添加的订阅',
                    style:
                        TextStyle(color: SmPalette.textDim, fontSize: 12)),
                const SizedBox(height: 6),
                for (final g in subs)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: SmPalette.bgInput,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: SmPalette.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(g.name,
                                  style: const TextStyle(
                                      color: SmPalette.text, fontSize: 13)),
                              Text(g.subUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: SmPalette.textDim,
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('更新于 ${formatLastUpdate(g.lastUpdate)}',
                            style: const TextStyle(
                                color: SmPalette.textDim, fontSize: 11)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '更新订阅',
                          icon: const Icon(Icons.refresh,
                              size: 18, color: SmPalette.accent),
                          onPressed: () => _refresh(g),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: '编辑',
                          icon: const Icon(Icons.edit_outlined,
                              size: 18, color: SmPalette.textDim),
                          onPressed: () => _edit(g),
                        ),
                      ],
                    ),
                  ),
                const Divider(color: SmPalette.border),
              ],
              const Text('添加新订阅',
                  style: TextStyle(color: SmPalette.textDim, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: _name,
                decoration:
                    const InputDecoration(hintText: '订阅名称（留空则命名为「订阅」）'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _url,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'https://your-subscription-url...'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _autoUpdate,
                    onChanged: (v) => setState(() => _autoUpdate = v ?? false),
                  ),
                  const Text('自动更新',
                      style: TextStyle(color: SmPalette.text, fontSize: 13)),
                  const SizedBox(width: 16),
                  const Text('间隔（小时）',
                      style:
                          TextStyle(color: SmPalette.textDim, fontSize: 12)),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: _interval,
                      enabled: _autoUpdate,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ModalButton(
                    label: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  ModalButton(
                    label: _loading ? '拉取中…' : '添加订阅',
                    primary: true,
                    onPressed:
                        _url.text.trim().isEmpty || _loading ? null : _add,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
