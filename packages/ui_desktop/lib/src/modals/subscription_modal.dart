/// 订阅管理弹窗 — 已有订阅（订阅分组）列表：编辑 / 更新；新增订阅：
/// 名称 / URL / 自动更新 / 间隔。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import 'group_edit_modal.dart';
import '../providers.dart';

class SubscriptionModal extends ConsumerStatefulWidget {
  const SubscriptionModal({super.key});

  @override
  ConsumerState<SubscriptionModal> createState() => _SubscriptionModalState();
}

class _SubscriptionModalState extends ConsumerState<SubscriptionModal> {
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
    }
  }

  Future<void> _edit(Group g) {
    return AppModal.show<void>(
      context,
      title: '编辑订阅 — ${g.name}',
      width: 460,
      builder: (_) => GroupEditModal(group: g),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).valueOrNull ?? const [];
    final subs = groups.where((g) => g.subUrl.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subs.isNotEmpty) ...[
          const Text('已添加的订阅',
              style: TextStyle(color: SmPalette.textDim, fontSize: 12)),
          const SizedBox(height: 6),
          for (final g in subs)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                                color: SmPalette.text, fontSize: 12)),
                        Text(g.subUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: SmPalette.textDim, fontSize: 11)),
                      ],
                    ),
                  ),
                  Text('更新于 ${formatLastUpdate(g.lastUpdate)}',
                      style: const TextStyle(
                          color: SmPalette.textDim, fontSize: 11)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '更新订阅',
                    icon: const Icon(Icons.refresh,
                        size: 16, color: SmPalette.accent),
                    onPressed: () => _refresh(g),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined,
                        size: 16, color: SmPalette.textDim),
                    onPressed: () => _edit(g),
                  ),
                ],
              ),
            ),
          const Divider(color: SmPalette.border),
        ],
        const Text('添加新订阅',
            style: TextStyle(color: SmPalette.textDim, fontSize: 12)),
        const ModalFieldLabel('订阅名称'),
        TextField(
          controller: _name,
          decoration: const InputDecoration(hintText: '留空则命名为「订阅」'),
        ),
        const ModalFieldLabel('订阅链接'),
        TextField(
          controller: _url,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'https://your-subscription-url...'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: Checkbox(
                value: _autoUpdate,
                onChanged: (v) => setState(() => _autoUpdate = v ?? false),
              ),
            ),
            const SizedBox(width: 6),
            const Text('自动更新',
                style: TextStyle(color: SmPalette.text, fontSize: 12)),
            const SizedBox(width: 16),
            const Text('间隔（小时）',
                style: TextStyle(color: SmPalette.textDim, fontSize: 12)),
            const SizedBox(width: 6),
            SizedBox(
              width: 70,
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
              onPressed: _url.text.trim().isEmpty || _loading ? null : _add,
            ),
          ],
        ),
      ],
    );
  }
}
