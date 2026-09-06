/// 分组新建/编辑弹窗 — 新建仅名称；编辑含名称 + 订阅链接 + 自动更新设置。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../providers.dart';

class GroupEditModal extends ConsumerStatefulWidget {
  /// null = 新建；非 null = 编辑。
  final Group? group;

  /// 新建时的插入位置分组 ID。
  final String? afterID;

  const GroupEditModal({super.key, this.group, this.afterID});

  @override
  ConsumerState<GroupEditModal> createState() => _GroupEditModalState();
}

class _GroupEditModalState extends ConsumerState<GroupEditModal> {
  late final Group? _group = widget.group;
  late final bool _isEdit = _group != null;
  late final bool _isDefault = _group?.isDefault ?? false;
  late final TextEditingController _name =
      TextEditingController(text: _isEdit ? _group!.name : '');
  late final TextEditingController _subUrl =
      TextEditingController(text: _isEdit ? _group!.subUrl : '');
  late bool _autoUpdate = _isEdit ? _group!.autoUpdate : false;
  late final TextEditingController _interval = TextEditingController(
      text: '${_isEdit && _group!.updateIntervalHours > 0 ? _group.updateIntervalHours : 24}');
  bool _saving = false;

  bool get _hasSub => _subUrl.text.trim().isNotEmpty;
  bool get _canConfirm => _isEdit ? _isDefault || _name.text.trim().isNotEmpty : _name.text.trim().isNotEmpty;

  @override
  void dispose() {
    _name.dispose();
    _subUrl.dispose();
    _interval.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving || !_canConfirm) return;
    final app = ref.read(smAppProvider);
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      if (_isEdit) {
        app.updateGroup(Group(
          id: _group!.id,
          name: _isDefault ? _group.name : _name.text.trim(),
          isDefault: _group.isDefault,
          subUrl: _subUrl.text.trim(),
          autoUpdate: _hasSub && _autoUpdate,
          updateIntervalHours:
              _hasSub && _autoUpdate ? (int.tryParse(_interval.text) ?? 0) : 0,
          lastUpdate: _group.lastUpdate,
        ));
      } else {
        app.addGroup(_name.text.trim(), widget.afterID ?? '');
      }
    }, failurePrefix: _isEdit ? '编辑分组失败' : '新建分组失败');
    if (ok && mounted) Navigator.of(context).pop();
    if (mounted) setState(() => _saving = false);
    await ref.read(groupsProvider.notifier).reload();
    await ref.read(nodesProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const ModalFieldLabel('分组名称'),
        TextField(
          controller: _name,
          enabled: !_isDefault,
          autofocus: !_isEdit,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '输入分组名称…',
            helperText: _isDefault ? '默认分组名称固定' : null,
          ),
        ),
        if (_isEdit) ...[
          const ModalFieldLabel('订阅链接（可选）'),
          TextField(
            controller: _subUrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                hintText: '输入订阅链接 https://…'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: _hasSub && _autoUpdate,
                  onChanged: _hasSub
                      ? (v) => setState(() => _autoUpdate = v ?? false)
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text('自动更新订阅',
                  style: TextStyle(
                      color: _hasSub
                          ? SmPalette.text
                          : SmPalette.textDim,
                      fontSize: 12)),
              const Spacer(),
              Text('自动更新间隔（小时）',
                  style: TextStyle(
                      color: _hasSub && _autoUpdate
                          ? SmPalette.textDim
                          : SmPalette.textDim.withValues(alpha: 0.5),
                      fontSize: 12)),
              const SizedBox(width: 6),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _interval,
                  enabled: _hasSub && _autoUpdate,
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          if (!_hasSub)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('填写订阅链接后自动更新设置才会生效',
                  style:
                      TextStyle(color: SmPalette.textDim, fontSize: 11)),
            ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ModalButton(
              label: '取消',
              onPressed: () => Navigator.of(context).pop(),
            ),
            ModalButton(
              label: _saving ? '保存中…' : '确认',
              primary: true,
              onPressed: _canConfirm && !_saving ? _confirm : null,
            ),
          ],
        ),
      ],
    );
  }
}
