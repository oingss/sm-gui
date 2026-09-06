/// 导入节点弹层（BottomSheet）— 移植 ui_desktop/import_modal 交互：
/// 粘贴 URI/base64/订阅 JSON / sing-box / Clash 配置，选择导入分组。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../providers.dart';

/// 弹出导入节点 BottomSheet。
Future<void> showImportSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SmPalette.bgPanel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const ImportSheet(),
  );
}

class ImportSheet extends ConsumerStatefulWidget {
  const ImportSheet({super.key});

  @override
  ConsumerState<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<ImportSheet> {
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '导入节点',
              style: TextStyle(
                  color: SmPalette.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '粘贴节点链接（每行一个）或 base64 编码内容\n'
              '支持：vmess:// vless:// trojan:// ss:// hysteria2:// hysteria:// '
              'tuic://\nsocks:// anytls:// ssr:// wireguard:// 及 '
              'sing-box / Clash 完整配置',
              style: TextStyle(color: SmPalette.textDim, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('导入到分组',
                    style:
                        TextStyle(color: SmPalette.textDim, fontSize: 12)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _groupId,
                    isExpanded: true,
                    items: [
                      for (final g in groups)
                        DropdownMenuItem(value: g.id, child: Text(g.name)),
                    ],
                    onChanged: (v) => setState(() => _groupId = v ?? _groupId),
                  ),
                ),
                TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste, size: 14),
                  label: const Text('粘贴',
                      style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                      foregroundColor: SmPalette.accent),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 160,
              child: TextField(
                controller: _content,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                    color: SmPalette.text,
                    fontSize: 12,
                    fontFamily: 'monospace'),
                decoration:
                    const InputDecoration(hintText: 'vmess://...\nvless://...'),
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
        ),
      ),
    );
  }
}
