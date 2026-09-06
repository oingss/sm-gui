/// 节点页 — 分组分区列表（组头：订阅更新时间/刷新按钮；节点长按菜单：
/// 应用此节点/测试延迟/上移/下移/编辑/删除）。本页仅含分组页签 + 节点列表本体，
/// 对齐桌面端 NodeList：配置文件/导入/订阅/清空由外层 ConfigBarMobile 承载。
/// 移动端测延迟用 TCP 直连（无内核二进制）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../modals/edit_node_sheet.dart';
import '../modals/group_edit_sheet.dart';
import '../providers.dart';

/// 延迟测试结果。
class _TestState {
  final bool testing;
  final int? ms;
  const _TestState.testing() : testing = true, ms = null;
  const _TestState.done(this.ms) : testing = false;
}

class NodesPage extends ConsumerStatefulWidget {
  const NodesPage({super.key});

  @override
  ConsumerState<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends ConsumerState<NodesPage> {
  final Map<String, _TestState> _tests = {};

  List<Node> _nodesOf(List<Node> nodes, Group g) => nodes
      .where((n) => (n.groupId.isEmpty ? defaultGroupID : n.groupId) == g.id)
      .toList();

  // ─── 节点动作 ──────────────────────────────────────────────────────────────

  Future<void> _applyNode(Node node) async {
    final app = ref.read(smAppProvider);
    await runAction(context, () => app.applyNode(node.id),
        successMsg: '节点已应用', failurePrefix: '应用节点失败');
    ref.read(settingsVersionProvider.notifier).bump();
  }

  Future<void> _unapply() async {
    final app = ref.read(smAppProvider);
    await runAction(context, () => app.unapplyNode(),
        successMsg: '已取消应用节点', failurePrefix: '取消应用失败');
    ref.read(settingsVersionProvider.notifier).bump();
  }

  Future<void> _deleteNode(Node node) async {
    final confirmed = await confirmDialog(
        context, '确认删除节点「${node.name}」？');
    if (!confirmed || !mounted) return;
    final app = ref.read(smAppProvider);
    await runAction(context, () async => app.deleteNode(node.id),
        successMsg: '节点已删除', failurePrefix: '删除失败');
    await ref.read(nodesProvider.notifier).reload();
  }

  Future<void> _moveNode(Node node, int delta) async {
    final app = ref.read(smAppProvider);
    app.moveNode(node.id, delta); // 已在边界时返回 false，不提示
    await ref.read(nodesProvider.notifier).reload();
  }

  /// TCP 直连测延迟（移动端无内核二进制，不用真实链路探针）。
  Future<void> _testLatency(Node node) async {
    final app = ref.read(smAppProvider);
    setState(() => _tests[node.id] = const _TestState.testing());
    final ms = await app.testLatencyTcp(node);
    if (!mounted) return;
    setState(() => _tests[node.id] = _TestState.done(ms));
    if (ms < 0) {
      AppToast.show(context, '延迟测试失败: ${node.address}', ToastType.error);
    }
  }

  // ─── 分组动作 ──────────────────────────────────────────────────────────────

  Future<void> _refreshSubscription(Group group) async {
    final app = ref.read(smAppProvider);
    final ok = await runAction(context, () async {
      final count = await app.refreshGroupSubscription(group.id);
      if (mounted) {
        AppToast.show(context, '订阅「${group.name}」更新成功，共 $count 个节点',
            ToastType.success);
      }
    }, failurePrefix: '订阅更新失败');
    if (ok) {
      await ref.read(nodesProvider.notifier).reload();
      await ref.read(groupsProvider.notifier).reload();
    }
  }

  Future<void> _openNodeEdit(Node node) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SmPalette.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => EditNodeSheet(node: node),
    );
  }

  // ─── 长按菜单 ──────────────────────────────────────────────────────────────

  Future<void> _showNodeMenu(Node node, bool applied, int index, int total) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: SmPalette.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                node.name.isEmpty ? '未命名节点' : node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: SmPalette.textDim, fontSize: 12),
              ),
            ),
            _menuItem(ctx, Icons.check_circle_outline,
                applied ? '取消应用' : '应用此节点', 'apply'),
            _menuItem(ctx, Icons.speed_outlined, '测试延迟', 'latency'),
            _menuItem(ctx, Icons.arrow_upward, '上移', 'up',
                enabled: index > 0),
            _menuItem(ctx, Icons.arrow_downward, '下移', 'down',
                enabled: index < total - 1),
            _menuItem(ctx, Icons.edit_outlined, '编辑', 'edit'),
            _menuItem(ctx, Icons.delete_outline, '删除节点', 'delete',
                color: SmPalette.red),
          ],
        ),
      ),
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'apply':
          applied ? _unapply() : _applyNode(node);
        case 'latency':
          _testLatency(node);
        case 'up':
          _moveNode(node, -1);
        case 'down':
          _moveNode(node, 1);
        case 'edit':
          _openNodeEdit(node);
        case 'delete':
          _deleteNode(node);
      }
    });
  }

  Widget _menuItem(BuildContext ctx, IconData icon, String label, String value,
      {bool enabled = true, Color? color}) {
    final c = color ?? SmPalette.text;
    return ListTile(
      leading: Icon(icon, size: 20, color: enabled ? c : SmPalette.textDim),
      title: Text(label,
          style: TextStyle(fontSize: 14, color: enabled ? c : SmPalette.textDim)),
      onTap: enabled ? () => Navigator.pop(ctx, value) : null,
      visualDensity: VisualDensity.compact,
    );
  }

  // ─── 构建 ──────────────────────────────────────────────────────────────────
  // 与桌面端一致：本页仅负责分组页签 + 节点列表本体，不含自己的 AppBar/FAB；
  // 配置文件选择 / 导入 / 订阅 / 清空 由外层 ConfigBarMobile（对齐桌面 ConfigBar）
  // 统一承载，标题栏 Tab 与状态胶囊由外层 MobileTitleBar 承载。

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).valueOrNull;
    final nodes = ref.watch(nodesProvider).valueOrNull;
    final appliedId = ref.watch(appliedIdProvider);

    if (groups == null || nodes == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (groups.isEmpty) {
      return const Center(
          child: Text('暂无分组', style: TextStyle(color: SmPalette.textDim)));
    }
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(groupsProvider.notifier).reload();
        await ref.read(nodesProvider.notifier).reload();
      },
      child: ListView.builder(
        itemCount: groups.length,
        itemBuilder: (context, i) {
          final g = groups[i];
          final groupNodes = _nodesOf(nodes, g);
          return _GroupSection(
            group: g,
            nodes: groupNodes,
            appliedId: appliedId,
            tests: _tests,
            onRefreshSub: () => _refreshSubscription(g),
            onEditGroup: () => showGroupEditSheet(context, group: g),
            onNodeMenu: (node) {
              final idx = groupNodes.indexOf(node);
              _showNodeMenu(node, node.id == appliedId, idx, groupNodes.length);
            },
          );
        },
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  final Group group;
  final List<Node> nodes;
  final String appliedId;
  final Map<String, _TestState> tests;
  final VoidCallback onRefreshSub;
  final VoidCallback onEditGroup;
  final void Function(Node) onNodeMenu;

  const _GroupSection({
    required this.group,
    required this.nodes,
    required this.appliedId,
    required this.tests,
    required this.onRefreshSub,
    required this.onEditGroup,
    required this.onNodeMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 组头
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: SmPalette.bgInput.withValues(alpha: 0.5),
          child: Row(
            children: [
              Icon(
                group.isDefault
                    ? Icons.home_outlined
                    : group.subUrl.isNotEmpty
                        ? Icons.rss_feed
                        : Icons.folder_outlined,
                size: 14,
                color: SmPalette.textDim,
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onEditGroup,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    group.name,
                    style: const TextStyle(
                        color: SmPalette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${nodes.length} 个节点',
                  style:
                      const TextStyle(color: SmPalette.textDim, fontSize: 11)),
              if (group.subUrl.isNotEmpty) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                      '更新于 ${formatLastUpdate(group.lastUpdate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: SmPalette.textDim, fontSize: 11)),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onRefreshSub,
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.refresh,
                        size: 16, color: SmPalette.accent),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 节点行
        if (nodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text('该分组暂无节点，可点击「导入节点」或「订阅管理」添加',
                  style: TextStyle(color: SmPalette.textDim, fontSize: 12)),
            ),
          )
        else
          for (final n in nodes)
            _NodeTile(
              node: n,
              applied: n.id == appliedId,
              test: tests[n.id],
              onLongPress: () => onNodeMenu(n),
            ),
        const Divider(height: 1, color: SmPalette.border),
      ],
    );
  }
}

class _NodeTile extends StatelessWidget {
  final Node node;
  final bool applied;
  final _TestState? test;
  final VoidCallback onLongPress;

  const _NodeTile({
    required this.node,
    required this.applied,
    required this.onLongPress,
    this.test,
  });

  Color get _latencyColor {
    final ms = test?.ms;
    if (ms == null) return SmPalette.textDim;
    if (ms < 0) return SmPalette.red;
    if (ms < 300) return SmPalette.green;
    if (ms < 800) return SmPalette.yellow;
    return SmPalette.red;
  }

  @override
  Widget build(BuildContext context) {
    final t = test;
    return InkWell(
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
                width: 2, color: applied ? SmPalette.green : Colors.transparent),
          ),
        ),
        child: Row(
          children: [
            ProtocolBadge(protocol: node.protocol),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                node.name.isEmpty ? '未命名节点' : node.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: SmPalette.text, fontSize: 13),
              ),
            ),
            if (applied) ...[
              const SizedBox(width: 6),
              const MetaBadge(label: '已应用', color: SmPalette.green),
            ],
            const SizedBox(width: 8),
            Text(
              '${node.address}:${node.port}',
              style: const TextStyle(color: SmPalette.textDim, fontSize: 11),
            ),
            if (t != null) ...[
              const SizedBox(width: 8),
              Text(
                t.testing
                    ? '测试中…'
                    : (t.ms != null && t.ms! >= 0 ? '${t.ms} ms' : '失败'),
                style: TextStyle(color: _latencyColor, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
