/// 导入节点弹窗 — 对齐原 ImportModal.jsx：粘贴 URI/订阅/base64/JSON，
/// 选择导入到哪个分组。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../providers.dart';

class ImportModal extends ConsumerStatefulWidget {
  const ImportModal({super.key});

  @override
  ConsumerState<ImportModal> createState() => _ImportModalState();
}

class _ImportModalState extends ConsumerState<ImportModal> {
  final _content = TextEditingController();
  String _groupId = defaultGroupID;
  bool _loading = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = await Clipboard.getData(Clipboard.kTextPlain);
    if (text?.text != null) {
      _content.text = text!.text!;
    }
  }

  Future<void> _import() async {
    final text = _content.text.trim();
    if (text.isEmpty || _loading) return;
    final app = ref.read(smAppProvider);
    setState(() => _loading = true);
    final ok = await runAction(context, () async {
      final count = app.addNodesFromText(text, _groupId, '');
      if (mounted) {
        AppToast.show(context, '成功导入 $count 个节点', ToastType.success);
      }
    }, failurePrefix: '导入失败');
    if (ok && mounted) {
      Navigator.of(context).pop();
    }
    if (mounted) setState(() => _loading = false);
    await ref.read(nodesProvider.notifier).reload();
    await ref.read(groupsProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).valueOrNull ?? const [];
    if (!groups.any((g) => g.id == _groupId)) {
      _groupId = groups.isEmpty ? defaultGroupID : groups.first.id;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '粘贴节点链接（每行一个）或 base64 编码内容\n'
          '支持：vmess:// vless:// trojan:// ss:// hysteria2:// hysteria:// tuic://\n'
          'socks:// anytls:// ssr:// wireguard:// 及 sing-box / Clash 完整配置',
          style: TextStyle(color: SmPalette.textDim, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('导入到分组',
                style: TextStyle(color: SmPalette.textDim, fontSize: 12)),
            const SizedBox(width: 8),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: _groupId,
                items: [
                  for (final g in groups)
                    DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (v) => setState(() => _groupId = v ?? _groupId),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.content_paste, size: 14),
              label: const Text('从剪贴板粘贴'),
              style: TextButton.styleFrom(
                foregroundColor: SmPalette.accent,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _content,
          maxLines: 10,
          autofocus: true,
          style: const TextStyle(
              color: SmPalette.text, fontSize: 12, fontFamily: 'Consolas'),
          decoration: const InputDecoration(
            hintText: 'vmess://...\nvless://...\ntrojan://...',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ModalButton(
              label: '取消',
              onPressed: () => Navigator.of(context).pop(),
            ),
            ModalButton(
              label: _loading ? '导入中…' : '导入',
              primary: true,
              onPressed:
                  _content.text.trim().isEmpty || _loading ? null : _import,
            ),
          ],
        ),
      ],
    );
  }
}
