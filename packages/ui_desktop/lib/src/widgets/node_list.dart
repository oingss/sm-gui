/// 节点列表 — 按分组分区展示；节点行右键菜单（应用/取消应用/测延迟/
/// 上移/下移/编辑/删除）；组头显示订阅更新时间、刷新按钮与分组右键菜单。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../actions.dart';
import '../modals/edit_node_modal.dart';
import '../modals/group_edit_modal.dart';
import '../providers.dart';

/// 延迟/测速结果。
class _TestState {
  final bool testing;
  final int? ms;
  final double? mbps;
  const _TestState.testing() : testing = true, ms = null, mbps = null;
  const _TestState.done(this.ms) : testing = false, mbps = null;
  const _TestState.speed(this.mbps) : testing = false, ms = null;
  const _TestState.failed() : testing = false, ms = null, mbps = null;
}

class NodeList extends ConsumerStatefulWidget {
  const NodeList({super.key});

  @override
  ConsumerState<NodeList> createState() => _NodeListState();
}

class _NodeListState extends ConsumerState<NodeList> {
  final Map<String, _TestState> _tests = {};

  List<Node> _nodesOf(List<Node> nodes, Group g) =>
      nodes.where((n) => (n.groupId.isEmpty ? defaultGroupID : n.groupId) == g.id).toList();

  // ─── 节点动作 ──────────────────────────────────────────────────────────────

  Future<void> _applyNode(Node node) async {
    final app = ref.read(smAppProvider);
    await runAction(context, () => app.applyNode(node.id),
        successMsg: '节点已应用', failurePrefix: '应用节点失败');
    ref.read(settingsVersionProvider.notifier).bump();
  }

  Future<void> _unapply() async {
    final app = ref.read(smAppProvider);
    final ok = await runAction(context, () => app.unapplyNode(),
        successMsg: '已取消应用节点', failurePrefix: '取消应用失败');
    if (!ok) ref.invalidate(settingsVersionProvider);
  }

  Future<void> _deleteNode(Node node) async {
    final app = ref.read(smAppProvider);
    final confirmed = await _confirm('确认删除节点「${node.name}」？');
    if (!confirmed || !mounted) return;
    await runAction(context, () async => app.deleteNode(node.id),
        successMsg: '节点已删除', failurePrefix: '删除失败');
    await ref.read(nodesProvider.notifier).reload();
  }

  Future<void> _moveNode(Node node, int delta) async {
    final app = ref.read(smAppProvider);
    app.moveNode(node.id, delta); // 已在边界时返回 false，不提示
    await ref.read(nodesProvider.notifier).reload();
  }

  Future<void> _testLatency(Node node) async {
    final app = ref.read(smAppProvider);
    setState(() => _tests[node.id] = const _TestState.testing());
    final ms = await app.testLatency(node);
    if (!mounted) return;
    setState(() => _tests[node.id] = _TestState.done(ms));
    if (ms < 0 && mounted) {
      AppToast.show(context, '延迟测试失败: ${node.address}', ToastType.error);
    }
  }

  /// 测速（下载）：经临时 sing-box 实例下载测速，结果 Toast 提示
  /// （失败通常因为未安装 sing-box 内核）。
  Future<void> _testSpeed(Node node) async {
    final app = ref.read(smAppProvider);
    setState(() => _tests[node.id] = const _TestState.testing());
    try {
      final mbps = await app.testSpeed(node);
      if (!mounted) return;
      setState(() => _tests[node.id] = _TestState.speed(mbps));
      AppToast.show(context, '${mbps.toStringAsFixed(1)} Mbps',
          ToastType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _tests[node.id] = const _TestState.failed());
      final msg = e is AppException ? e.message : '$e';
      AppToast.show(context, '测速失败: $msg', ToastType.error);
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

  Future<void> _deleteGroup(Group group) async {
    if (group.isDefault) return;
    final confirmed =
        await _confirm('确认删除分组「${group.name}」？\n该分组内的节点将移入「默认」分组。');
    if (!confirmed || !mounted) return;
    final app = ref.read(smAppProvider);
    await runAction(context, () async => app.deleteGroup(group.id),
        successMsg: '分组已删除', failurePrefix: '删除分组失败');
    await ref.read(groupsProvider.notifier).reload();
    await ref.read(nodesProvider.notifier).reload();
  }

  Future<void> _moveGroup(Group group, int delta) async {
    final app = ref.read(smAppProvider);
    app.moveGroup(group.id, delta);
    await ref.read(groupsProvider.notifier).reload();
  }

  Future<void> _openGroupEdit(Group? group, String? afterID) {
    return AppModal.show<void>(
      context,
      title: group == null ? '新建分组' : (group.isDefault ? '编辑默认分组' : '编辑分组'),
      width: 460,
      builder: (_) => GroupEditModal(group: group, afterID: afterID),
    );
  }

  Future<void> _openNodeEdit(Node node) {
    return AppModal.show<void>(
      context,
      title: '编辑节点 — ${protocolDisplayName(node.protocol)}',
      width: 620,
      builder: (_) => EditNodeModal(node: node),
    );
  }

  Future<bool> _confirm(String message) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    return res == true;
  }

  // ─── 右键菜单 ──────────────────────────────────────────────────────────────

  void _showNodeMenu(Offset pos, Node node, bool applied, int index, int total) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Text(node.name,
              style: const TextStyle(
                  color: SmPalette.textDim, fontSize: 12)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: applied ? 'unapply' : 'apply',
          child: Text(applied ? '取消应用' : '应用此节点'),
        ),
        const PopupMenuItem(value: 'latency', child: Text('测试延迟')),
        const PopupMenuItem(value: 'speed', child: Text('测速（下载）')),
        PopupMenuItem(value: 'up', enabled: index > 0, child: const Text('上移')),
        PopupMenuItem(
            value: 'down',
            enabled: index < total - 1,
            child: const Text('下移')),
        const PopupMenuItem(value: 'edit', child: Text('编辑')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: const Text('删除节点',
              style: TextStyle(color: SmPalette.red)),
        ),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'apply':
          _applyNode(node);
        case 'unapply':
          _unapply();
        case 'latency':
          _testLatency(node);
        case 'speed':
          _testSpeed(node);
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

  void _showGroupMenu(Offset pos, Group group, int index, int total) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Text('分组：${group.name}',
              style: const TextStyle(
                  color: SmPalette.textDim, fontSize: 12)),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'create', child: Text('新建分组')),
        const PopupMenuItem(value: 'edit', child: Text('编辑')),
        if (group.subUrl.isNotEmpty)
          const PopupMenuItem(value: 'refresh', child: Text('更新订阅')),
        PopupMenuItem(
            value: 'up',
            enabled: index > 1,
            child: const Text('上移')),
        PopupMenuItem(
            value: 'down',
            enabled: !group.isDefault && index < total - 1,
            child: const Text('下移')),
        PopupMenuItem(
          value: 'delete',
          enabled: !group.isDefault,
          child: const Text('删除分组',
              style: TextStyle(color: SmPalette.red)),
        ),
      ],
    ).then((v) {
      if (v == null) return;
      switch (v) {
        case 'create':
          _openGroupEdit(null, group.id);
        case 'edit':
          _openGroupEdit(group, null);
        case 'refresh':
          _refreshSubscription(group);
        case 'up':
          _moveGroup(group, -1);
        case 'down':
          _moveGroup(group, 1);
        case 'delete':
          _deleteGroup(group);
      }
    });
  }

  // ─── 构建 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).valueOrNull;
    final nodes = ref.watch(nodesProvider).valueOrNull;
    final appliedId = ref.watch(appliedIdProvider);

    if (groups == null || nodes == null) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 分组操作栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              Text('${groups.length} 个分组 / ${nodes.length} 个节点',
                  style: const TextStyle(
                      color: SmPalette.textDim, fontSize: 12)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openGroupEdit(null, ''),
                icon: const Icon(Icons.create_new_folder_outlined, size: 15),
                label: const Text('新建分组'),
                style: TextButton.styleFrom(
                  foregroundColor: SmPalette.textDim,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
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
                groupIndex: i,
                groupCount: groups.length,
                onGroupMenu: (pos) =>
                    _showGroupMenu(pos, g, i, groups.length),
                onNodeMenu: (pos, node) {
                  final idx = groupNodes.indexOf(node);
                  _showNodeMenu(pos, node, node.id == appliedId, idx,
                      groupNodes.length);
                },
                onRefreshSub: () => _refreshSubscription(g),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GroupSection extends StatelessWidget {
  final Group group;
  final List<Node> nodes;
  final String appliedId;
  final Map<String, _TestState> tests;
  final int groupIndex;
  final int groupCount;
  final void Function(Offset) onGroupMenu;
  final void Function(Offset, Node) onNodeMenu;
  final VoidCallback onRefreshSub;

  const _GroupSection({
    required this.group,
    required this.nodes,
    required this.appliedId,
    required this.tests,
    required this.groupIndex,
    required this.groupCount,
    required this.onGroupMenu,
    required this.onNodeMenu,
    required this.onRefreshSub,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 组头
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapUp: (d) => onGroupMenu(d.globalPosition),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                Text(
                  group.name,
                  style: const TextStyle(
                    color: SmPalette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text('${nodes.length} 个节点',
                    style: const TextStyle(
                        color: SmPalette.textDim, fontSize: 11)),
                if (group.subUrl.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text('更新于 ${formatLastUpdate(group.lastUpdate)}',
                      style: const TextStyle(
                          color: SmPalette.textDim, fontSize: 11)),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onRefreshSub,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.refresh,
                          size: 14, color: SmPalette.accent),
                    ),
                  ),
                ],
                const Spacer(),
                Text('右键管理分组',
                    style: TextStyle(
                        color: SmPalette.textDim.withValues(alpha: 0.6),
                        fontSize: 11)),
              ],
            ),
          ),
        ),
        // 节点行
        if (nodes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text('该分组暂无节点，可使用「导入节点」或「订阅」添加',
                  style: TextStyle(color: SmPalette.textDim, fontSize: 12)),
            ),
          )
        else
          for (final n in nodes)
            _NodeRow(
              node: n,
              applied: n.id == appliedId,
              test: tests[n.id],
              onMenu: (pos) => onNodeMenu(pos, n),
            ),
        const Divider(height: 1, color: SmPalette.border),
      ],
    );
  }
}

class _NodeRow extends StatelessWidget {
  final Node node;
  final bool applied;
  final _TestState? test;
  final void Function(Offset) onMenu;

  const _NodeRow({
    required this.node,
    required this.applied,
    required this.onMenu,
    this.test,
  });

  Color get _latencyColor {
    if (test?.mbps != null) return SmPalette.green;
    final ms = test?.ms;
    if (ms == null) return SmPalette.textDim;
    if (ms < 0) return SmPalette.red;
    if (ms < 300) return SmPalette.green;
    if (ms < 800) return SmPalette.yellow;
    return SmPalette.red;
  }

  @override
  Widget build(BuildContext context) {
    final test = this.test;
    return InkWell(
      onTap: () {},
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 2,
              color: applied ? SmPalette.green : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            ProtocolBadge(protocol: node.protocol),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                node.name.isEmpty ? '未命名节点' : node.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: SmPalette.text, fontSize: 12),
              ),
            ),
            if (applied) ...[
              const SizedBox(width: 6),
              const MetaBadge(label: '已应用', color: SmPalette.green),
            ],
            const SizedBox(width: 10),
            Text(
              '${node.address}:${node.port}',
              style: const TextStyle(
                  color: SmPalette.textDim, fontSize: 11),
            ),
            const Spacer(),
            if (test != null)
              Text(
                test.testing
                    ? '测试中…'
                    : (test.mbps != null
                        ? '${test.mbps!.toStringAsFixed(1)} Mbps'
                        : (test.ms != null && test.ms! >= 0
                            ? '${test.ms} ms'
                            : '失败')),
                style: TextStyle(
                    color: _latencyColor, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }
}
