/// 节点/分组存储 — 移植自 Go: backend/node/store.go。
///
/// 存储后端由 SQLite 改为 JSON 文件（零原生依赖，一期方案），
/// NodeStore 的完整 API 语义保持与 Go 版一致：
///   - 所有变更操作（addMany/update/delete/clear/removeByGroup/move、
///     各分组操作）立即写盘 — save() 保留用于显式写回。
///   - 节点完整结构（含各协议配置与 raw_outbound/raw_clash_proxy）以
///     Node.toJson() 形式存储；position 与 group_id 作为"列"单独保存
///     （对应 Go 版的 position / group_id 列，group_id 为权威值）。
///   - 节点归属分组；内建默认分组「默认」始终存在且不可重命名/删除。
///     move() 仅在同组内调整顺序。
///   - 错误统一抛 [ParseException]（Go 版通过 error 返回值表达）。
library;

import 'dart:convert';
import 'dart:io';

import '../models/group.dart';
import '../models/node.dart';
import '../parsing/common.dart';

/// JSON 文件格式版本。
const int _kStoreVersion = 1;

/// 节点记录：position / group_id "列" + 节点数据。
/// 对应 Go 版 nodes 表的一行（data 列 = Node JSON）。
class _NodeRecord {
  int position;
  String groupId;
  Node node;

  _NodeRecord({required this.position, required this.groupId, required this.node});

  Map<String, dynamic> toJson() => {
        'position': position,
        'group_id': groupId,
        'node': node.toJson(),
      };

  static _NodeRecord fromJson(Map<String, dynamic> j) => _NodeRecord(
        position: (j['position'] as num?)?.toInt() ?? 0,
        groupId: j['group_id'] as String? ?? '',
        node: Node.fromJson((j['node'] as Map? ?? const {}).cast<String, dynamic>()),
      );
}

/// 分组记录：position "列" + 分组数据。
/// 对应 Go 版 groups 表的一行。
class _GroupRecord {
  int position;
  Group group;

  _GroupRecord({required this.position, required this.group});

  Map<String, dynamic> toJson() => {
        'position': position,
        'group': group.toJson(),
      };

  static _GroupRecord fromJson(Map<String, dynamic> j) => _GroupRecord(
        position: (j['position'] as num?)?.toInt() ?? 0,
        group: Group.fromJson((j['group'] as Map? ?? const {}).cast<String, dynamic>()),
      );
}

/// 节点 + 分组存储（JSON 文件后端）。
class NodeStore {
  final String path;

  List<_NodeRecord> _nodes = [];
  List<_GroupRecord> _groups = [];
  bool _loaded = false;

  NodeStore(this.path);

  // ─── 持久化 ──────────────────────────────────────────────────────────────

  /// 读取存储文件。文件不存在时初始化默认结构（无节点 + 内建默认分组）
  /// 并落盘；文件损坏抛 [ParseException]。
  void load() {
    final f = File(path);
    if (!f.existsSync()) {
      _nodes = [];
      _groups = [
        _GroupRecord(
          position: 0,
          group: Group(id: defaultGroupID, name: defaultGroupName, isDefault: true),
        ),
      ];
      _loaded = true;
      _persist(); // Go 版 init 时即建库并写入默认分组，这里同样落盘
      return;
    }

    String text;
    try {
      text = f.readAsStringSync();
    } catch (e) {
      throw ParseException('读取存储文件失败: $e');
    }
    dynamic doc;
    try {
      doc = jsonDecode(text);
    } catch (e) {
      throw ParseException('存储文件 JSON 无效: $e');
    }
    if (doc is! Map) {
      throw ParseException('存储文件结构无效');
    }

    final rawNodes = doc['nodes'];
    final rawGroups = doc['groups'];
    if (rawNodes is! List || rawGroups is! List) {
      throw ParseException('存储文件结构无效');
    }
    try {
      _nodes = [
        for (final e in rawNodes) _NodeRecord.fromJson((e as Map).cast<String, dynamic>())
      ];
      _groups = [
        for (final e in rawGroups) _GroupRecord.fromJson((e as Map).cast<String, dynamic>())
      ];
    } catch (e) {
      throw ParseException('存储文件内容无效: $e');
    }
    _loaded = true;

    // 兼容旧数据（对应 Go init 的两条修复语句）：
    // group_id 为空的节点归入默认分组
    var changed = false;
    for (final r in _nodes) {
      if (r.groupId.isEmpty) {
        r.groupId = defaultGroupID;
        changed = true;
      }
    }
    // 内建默认分组始终存在（INSERT OR IGNORE 语义，position 0）
    if (!_groups.any((g) => g.group.id == defaultGroupID)) {
      _groups.add(_GroupRecord(
        position: 0,
        group: Group(id: defaultGroupID, name: defaultGroupName, isDefault: true),
      ));
      changed = true;
    }
    if (changed) _persist();
  }

  /// 写回当前状态到文件（Go 版 Save 为 no-op；JSON 后端此处为显式保存入口）。
  void save() {
    _ensureLoaded();
    _persist();
  }

  /// 释放资源（API 兼容，无连接需要关闭）。
  void close() {}

  void _ensureLoaded() {
    if (!_loaded) load();
  }

  void _persist() {
    final f = File(path);
    try {
      final dir = f.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final doc = {
        'version': _kStoreVersion,
        'nodes': [for (final r in _nodes) r.toJson()],
        'groups': [for (final r in _groups) r.toJson()],
      };
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(doc));
    } catch (e) {
      throw ParseException('写回存储文件失败: $e');
    }
  }

  // ─── 内部 helpers ────────────────────────────────────────────────────────

  /// 按 position 排序的节点记录（附原始下标保证稳定排序）。
  List<_NodeRecord> _sortedNodes() {
    final order = List<int>.generate(_nodes.length, (i) => i);
    order.sort((a, b) {
      final c = _nodes[a].position.compareTo(_nodes[b].position);
      return c != 0 ? c : a.compareTo(b);
    });
    return [for (final i in order) _nodes[i]];
  }

  /// 按 position 排序的分组记录（稳定排序）。
  List<_GroupRecord> _sortedGroups() {
    final order = List<int>.generate(_groups.length, (i) => i);
    order.sort((a, b) {
      final c = _groups[a].position.compareTo(_groups[b].position);
      return c != 0 ? c : a.compareTo(b);
    });
    return [for (final i in order) _groups[i]];
  }

  _NodeRecord? _nodeById(String id) {
    for (final r in _nodes) {
      if (r.node.id == id) return r;
    }
    return null;
  }

  _GroupRecord? _groupById(String id) {
    for (final r in _groups) {
      if (r.group.id == id) return r;
    }
    return null;
  }

  /// 读取节点副本：group_id 列为权威值（对应 Go 版 GetAll/Get 的扫描逻辑）。
  Node _recordToNode(_NodeRecord r) {
    final n = Node.fromJson(r.node.toJson());
    var gid = r.groupId;
    if (gid.isEmpty) gid = defaultGroupID;
    n.groupId = gid;
    return n;
  }

  // ─── 节点 API ────────────────────────────────────────────────────────────

  /// 返回全部节点，按 position 排序。
  List<Node> getAll() {
    _ensureLoaded();
    return [for (final r in _sortedNodes()) _recordToNode(r)];
  }

  /// 按 ID 查找节点，不存在返回 null。
  Node? get(String id) {
    _ensureLoaded();
    final r = _nodeById(id);
    if (r == null) return null;
    return _recordToNode(r);
  }

  /// 批量新增节点（INSERT OR REPLACE 语义）：同 ID 覆盖旧记录并排到末尾；
  /// group_id 为空的节点归入默认分组；position 从当前最大值递增。
  void addMany(List<Node> nodes) {
    _ensureLoaded();
    if (nodes.isEmpty) return;
    var pos = 0;
    for (final r in _nodes) {
      if (r.position > pos) pos = r.position;
    }
    for (final n in nodes) {
      // INSERT OR REPLACE：同 id 删除旧行后按新 position 插入
      _nodes.removeWhere((r) => r.node.id == n.id);
      pos++;
      var gid = n.groupId;
      if (gid.isEmpty) gid = defaultGroupID;
      _nodes.add(_NodeRecord(position: pos, groupId: gid, node: n));
    }
    _persist();
  }

  /// 更新节点（WHERE id）：position 不变；节点不存在时为 no-op。
  void update(Node n) {
    _ensureLoaded();
    final r = _nodeById(n.id);
    if (r == null) return;
    r.groupId = n.groupId;
    r.node = n;
    _persist();
  }

  /// 删除节点（不存在时为 no-op）。
  void delete(String id) {
    _ensureLoaded();
    _nodes.removeWhere((r) => r.node.id == id);
    _persist();
  }

  /// 在节点所属分组内按 delta（-1 = 上移，+1 = 下移）交换相邻位置。
  /// 返回是否成功（越界/节点不存在/同组仅一个节点时失败）。
  bool move(String id, int delta) {
    _ensureLoaded();
    if (delta == 0) return false;
    // 找到节点所属分组
    final target = _nodeById(id);
    if (target == null) return false;
    // 分组内按 position 排序的 (id, position) 列表
    final entries = _nodes.where((r) => r.groupId == target.groupId).toList();
    entries.sort((a, b) => a.position.compareTo(b.position));
    final idx = entries.indexWhere((e) => e.node.id == id);
    if (idx < 0) return false;
    final j = idx + delta;
    if (j < 0 || j >= entries.length) return false;
    // 交换两条记录的 position（同组内交换，不影响其他分组顺序）
    final posIdx = entries[idx].position;
    entries[idx].position = entries[j].position;
    entries[j].position = posIdx;
    _persist();
    return true;
  }

  /// 清空全部节点（分组保留）。
  void clear() {
    _ensureLoaded();
    _nodes.clear();
    _persist();
  }

  /// 删除指定分组内的全部节点
  /// （分组订阅「更新」用它整体替换组内节点）。
  void removeByGroup(String groupId) {
    _ensureLoaded();
    _nodes.removeWhere((r) => r.groupId == groupId);
    _persist();
  }

  /// 节点总数。
  int count() {
    _ensureLoaded();
    return _nodes.length;
  }

  // ─── 分组管理 ────────────────────────────────────────────────────────────

  /// 返回全部分组，按 position 排序。
  List<Group> getGroups() {
    _ensureLoaded();
    return [for (final r in _sortedGroups()) r.group.copy()];
  }

  /// 按 ID 查找分组，不存在返回 null。
  Group? groupByID(String id) {
    _ensureLoaded();
    final r = _groupById(id);
    if (r == null) return null;
    return r.group.copy();
  }

  /// 记录订阅上次成功更新时间。
  void setGroupLastUpdate(String id, int unixSec) {
    _ensureLoaded();
    final r = _groupById(id);
    if (r == null) return;
    r.group.lastUpdate = unixSec;
    _persist();
  }

  /// 指定 ID 的分组是否存在。
  bool groupExists(String id) {
    _ensureLoaded();
    return _groupById(id) != null;
  }

  /// 返回可用分组 ID：分组存在则原样返回，否则返回默认分组。
  /// （Go 版为包内私有 helper，供订阅更新等模块复用，这里保持公开。）
  String groupIDValid(String groupId) {
    if (groupId.isNotEmpty && groupId != defaultGroupID && groupExists(groupId)) {
      return groupId;
    }
    return defaultGroupID;
  }

  /// 新建分组，插入到 afterID 之后（"" = 追加到末尾）。拒绝重名。
  /// 成功返回新建分组（对应 Go 版 (Group, error) 的正常分支）。
  Group addGroup(String name, String afterID) {
    _ensureLoaded();
    name = name.trim();
    if (name.isEmpty) throw ParseException('分组名称不能为空');
    // 重名校验
    for (final r in _groups) {
      if (r.group.name == name) throw ParseException('分组名称已存在: $name');
    }
    // 按 position 排序的 id 列表
    final ids = [for (final r in _sortedGroups()) r.group.id];

    var insertAt = ids.length; // 默认追加到末尾
    if (afterID.isNotEmpty) {
      final i = ids.indexOf(afterID);
      if (i >= 0) insertAt = i + 1;
    }
    final newID = newUuid();
    ids.insert(insertAt, newID);

    // 全量重编号 position = i+1（对应 Go 版的 UPDATE 循环：
    // 新 id 尚未入库，UPDATE 对它无效果，因此跳过不存在的记录）
    for (var i = 0; i < ids.length; i++) {
      final rec = _groupById(ids[i]);
      if (rec != null) rec.position = i + 1;
    }
    // INSERT INTO groups ... VALUES (newID, name, insertAt+1, 0)
    _groups.add(_GroupRecord(
      position: insertAt + 1,
      group: Group(id: newID, name: name, isDefault: false),
    ));
    _persist();
    return Group(id: newID, name: name, isDefault: false);
  }

  /// 重命名分组。默认分组不可重命名。
  void renameGroup(String id, String name) {
    _ensureLoaded();
    name = name.trim();
    if (name.isEmpty) throw ParseException('分组名称不能为空');
    if (id == defaultGroupID) throw ParseException('默认分组不可重命名');
    for (final r in _groups) {
      if (r.group.name == name && r.group.id != id) {
        throw ParseException('分组名称已存在: $name');
      }
    }
    // 对应 UPDATE ... WHERE id = ? AND is_default = 0；影响 0 行 → 分组不存在
    final rec = _groupById(id);
    if (rec == null || rec.group.isDefault) throw ParseException('分组不存在');
    rec.group.name = name;
    _persist();
  }

  /// 编辑分组：名称 + 订阅设置。
  /// 默认分组保持名称（忽略改名请求），但可像其他分组一样设置订阅。
  void updateGroup(String id, String name, String subUrl, bool autoUpdate, int intervalHours) {
    _ensureLoaded();
    if (id == defaultGroupID) {
      name = defaultGroupName; // 默认分组名称固定
    } else {
      name = name.trim();
      if (name.isEmpty) throw ParseException('分组名称不能为空');
      for (final r in _groups) {
        if (r.group.name == name && r.group.id != id) {
          throw ParseException('分组名称已存在: $name');
        }
      }
    }
    // 订阅链接为空时自动更新设置无效
    subUrl = subUrl.trim();
    if (subUrl.isEmpty) {
      autoUpdate = false;
      intervalHours = 0;
    }
    final rec = _groupById(id);
    if (rec == null) throw ParseException('分组不存在');
    rec.group.name = name;
    rec.group.subUrl = subUrl;
    rec.group.autoUpdate = autoUpdate;
    rec.group.updateIntervalHours = intervalHours;
    _persist();
  }

  /// 与左（delta=-1）或右（delta=+1）邻居分组交换位置。
  /// 默认分组永远在最左：不可移动，任何分组也不能占据它的位置
  /// （这同时禁止了紧随默认分组之后的分组左移）。
  void moveGroup(String id, int delta) {
    _ensureLoaded();
    if (delta != -1 && delta != 1) throw ParseException('非法移动方向');
    if (id == defaultGroupID) throw ParseException('默认分组不可移动');
    final ids = [for (final r in _sortedGroups()) r.group.id];
    final idx = ids.indexOf(id);
    if (idx < 0) throw ParseException('分组不存在');
    final j = idx + delta;
    if (j < 0 || j >= ids.length) {
      if (delta == -1) throw ParseException('已在最左侧');
      throw ParseException('已在最右侧');
    }
    // 默认分组永远在最左：与它交换（左移第一个非默认分组）都禁止
    if (ids[idx] == defaultGroupID || ids[j] == defaultGroupID) {
      throw ParseException('默认分组必须保持在最左侧');
    }
    final recI = _groupById(ids[idx])!;
    final recJ = _groupById(ids[j])!;
    final posI = recI.position;
    recI.position = recJ.position;
    recJ.position = posI;
    _persist();
  }

  /// 删除分组，其节点移入默认分组。默认分组不可删除。
  void deleteGroup(String id) {
    _ensureLoaded();
    if (id == defaultGroupID) throw ParseException('默认分组不可删除');
    // 对应 DELETE ... WHERE id = ? AND is_default = 0；影响 0 行 → 分组不存在
    final rec = _groupById(id);
    if (rec == null || rec.group.isDefault) throw ParseException('分组不存在');
    // 组内节点移入默认分组
    for (final r in _nodes) {
      if (r.groupId == id) r.groupId = defaultGroupID;
    }
    _groups.remove(rec);
    // 压缩 position：按当前顺序重新编号 i+1
    final ordered = _sortedGroups();
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].position = i + 1;
    }
    _persist();
  }

  /// 存储文件路径（用于展示/调试）。
  String get dbPath => path;
}
