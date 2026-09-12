/// mihomo（Clash.Meta）配置文件增量编辑 — 移植自 Go: backend/config/mihomo.go。
///
/// 约定（与 Go 版一致）：
///   - proxies 中 name 为 "proxy" 的条目代表"当前应用的节点"（对齐 sing-box 的 tag:proxy）；
///   - proxy-groups 中有一个名为 "PROXY" 的 select 组引用它（组名大写，避免与节点同名冲突）；
///   - TUN 是顶层 tun 对象（enable/stack/mtu/auto-route...），mihomo 没有 strict_route；
///   - 系统代理对应顶层 mixed-port + allow-lan。
///
/// [nodeToClashProxy] 及相关 helpers 已统一使用 packages/core/lib/src/export/clash_write.dart
/// 的实现（对齐 Go: backend/node/clash_write.go 的
/// NodeToClashProxy / setClashTLS / applyClashTransport / parsePluginOpts /
/// cloneClashProxy），语义与 Go 版唯一对齐。
library;

import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

import '../export/clash_write.dart' show nodeToClashProxy;
import '../models/node.dart';
import '../parsing/common.dart';

/// mihomo 中"当前应用的节点"的固定条目名 — 移植自 Go: mihomo.go mihomoProxyName
const String mihomoProxyName = 'proxy';

/// mihomo 中引用当前节点的选择组名 — 移植自 Go: mihomo.go mihomoGroupName
const String mihomoGroupName = 'PROXY';

final YamlWriter _yamlWriter = YamlWriter(allowUnquotedStrings: true);

// ─── YAML load / save ─────────────────────────────────────────────────────────

/// 读取 YAML 配置为普通 Map — 移植自 Go: mihomo.go loadYAML。
/// 读文件/解析失败抛 [ParseException]。
Map<String, dynamic> loadYamlFile(String path) {
  String data;
  try {
    data = File(path).readAsStringSync();
  } catch (e) {
    throw ParseException('读取配置文件失败: $e');
  }
  dynamic doc;
  try {
    doc = loadYaml(data);
  } on YamlException catch (e) {
    throw ParseException('解析配置文件失败: ${e.message}');
  } catch (e) {
    throw ParseException('解析配置文件失败: $e');
  }
  if (doc == null) return <String, dynamic>{};
  if (doc is! Map) {
    throw ParseException('解析配置文件失败: 配置根节点不是映射');
  }
  return _toPlainMap(doc);
}

/// 写 YAML 配置（yaml_writer 输出，原子写：临时文件 + rename）—
/// 移植自 Go: mihomo.go saveYAML（yaml.Marshal + tmp + rename）。
void saveYamlFile(String path, Map<String, dynamic> cfg) {
  String data;
  try {
    data = _yamlWriter.write(cfg);
  } catch (e) {
    throw ParseException('序列化配置失败: $e');
  }
  _atomicWrite(path, data);
}

/// 原子写：临时文件 + rename，避免崩溃时损坏配置（对应 Go 版的 tmp + os.Rename）。
void _atomicWrite(String path, String data) {
  final tmp = '$path.tmp';
  try {
    File(tmp).writeAsStringSync(data, flush: true);
    File(tmp).renameSync(path);
  } catch (e) {
    throw ParseException('写入配置文件失败: $e');
  }
}

/// YamlMap/嵌套结构 → 普通 Map/List（保持插入顺序），便于后续修改与比较。
Map<String, dynamic> _toPlainMap(Map m) {
  final out = <String, dynamic>{};
  m.forEach((k, v) {
    out[k.toString()] = _toPlainValue(v);
  });
  return out;
}

dynamic _toPlainValue(dynamic node) {
  if (node is Map) return _toPlainMap(node);
  if (node is List) return node.map(_toPlainValue).toList();
  return node;
}

/// 返回配置中的 proxies 列表 — 移植自 Go: mihomo.go getProxies。
List<dynamic> getProxies(Map<String, dynamic> cfg) {
  final v = cfg['proxies'];
  return v is List ? List<dynamic>.from(v) : <dynamic>[];
}

/// 深拷贝一个 map — 移植自 Go: mihomo.go cloneMap。
/// Go 版经 yaml 序列化往返把类型规范化为 yaml.v3 原生类型；Dart 侧数据本身
/// 即原生 int/bool/String/List/Map，递归深拷贝即可保证写入与回读后逐字段可比较。
Map<String, dynamic> cloneMap(Map m) {
  final out = <String, dynamic>{};
  m.forEach((k, v) {
    out[k.toString()] = _deepCopyValue(v);
  });
  return out;
}

dynamic _deepCopyValue(dynamic v) {
  if (v is Map) return cloneMap(v);
  if (v is List) return v.map(_deepCopyValue).toList();
  return v;
}

// ─── Apply Node ───────────────────────────────────────────────────────────────

/// 把节点写入 mihomo 配置：替换/追加 name 为 "proxy" 的 proxies 条目，
/// 并确保 PROXY 选择组引用它 — 移植自 Go: mihomo.go ApplyNodeToMihomoConfig。
void applyNodeToMihomoConfig(String cfgPath, Node n) {
  final cfg = loadYamlFile(cfgPath);
  Map<String, dynamic> proxy;
  if (n.rawClashProxy != null) {
    // 原始 Clash YAML 条目无损回写（同 sing-box rawOutbound 的做法）
    proxy = cloneMap(n.rawClashProxy!);
  } else {
    proxy = nodeToClashProxy(n);
  }
  proxy['name'] = mihomoProxyName;

  final proxies = getProxies(cfg);
  var replaced = false;
  for (var i = 0; i < proxies.length; i++) {
    final pr = proxies[i];
    if (pr is Map && pr['name'] == mihomoProxyName) {
      proxies[i] = proxy;
      replaced = true;
      break;
    }
  }
  if (!replaced) {
    proxies.add(proxy);
  }
  cfg['proxies'] = proxies;
  ensureMihomoProxyGroup(cfg);
  saveYamlFile(cfgPath, cfg);
}

/// 确保 proxy-groups 中存在引用 "proxy" 条目的 PROXY select 组；
/// 不存在则创建，存在则把 "proxy" 补进其成员列表 —
/// 移植自 Go: mihomo.go ensureMihomoProxyGroup。
void ensureMihomoProxyGroup(Map<String, dynamic> cfg) {
  final pg = cfg['proxy-groups'];
  final groups = pg is List ? List<dynamic>.from(pg) : <dynamic>[];
  for (final g in groups) {
    if (g is! Map || g['name'] != mihomoGroupName) continue;
    final raw = g['proxies'];
    final members = raw is List ? List<dynamic>.from(raw) : <dynamic>[];
    for (final mem in members) {
      if (mem is String && mem == mihomoProxyName) {
        return; // 已引用，无需修改
      }
    }
    members.add(mihomoProxyName);
    g['proxies'] = members;
    return;
  }
  groups.add(<String, dynamic>{
    'name': mihomoGroupName,
    'type': 'select',
    'proxies': <dynamic>[mihomoProxyName, 'DIRECT'],
  });
  cfg['proxy-groups'] = groups;
}

// ─── TUN ──────────────────────────────────────────────────────────────────────

/// 写/删顶层 tun 配置 — 移植自 Go: mihomo.go SetTunMihomo。
/// mihomo 没有 strict_route，调用方已忽略该开关。
/// 启用时保留用户 tun 块中的其他字段，仅覆盖本 GUI 管理的字段。
void setTunMihomo(String cfgPath, bool enable, String stack, int mtu) {
  final cfg = loadYamlFile(cfgPath);
  if (!enable) {
    cfg.remove('tun');
    saveYamlFile(cfgPath, cfg);
    return;
  }
  final existing = cfg['tun'];
  final tun = existing is Map ? cloneMap(existing) : <String, dynamic>{};
  if (stack != 'gvisor' && stack != 'system' && stack != 'mixed') {
    stack = 'gvisor';
  }
  if (mtu <= 0) {
    mtu = 9000;
  }
  tun['enable'] = true;
  tun['stack'] = stack;
  tun['mtu'] = mtu;
  tun['auto-route'] = true;
  tun['auto-detect-interface'] = true;
  if (!tun.containsKey('dns-hijack')) {
    tun['dns-hijack'] = <dynamic>['any:53'];
  }
  cfg['tun'] = tun;
  saveYamlFile(cfgPath, cfg);
}

/// 判断配置是否启用了 tun（tun.enable == true）— 移植自 Go: mihomo.go HasTunMihomo。
bool hasTunMihomo(String cfgPath) {
  Map<String, dynamic> cfg;
  try {
    cfg = loadYamlFile(cfgPath);
  } on ParseException {
    return false;
  }
  final tun = cfg['tun'];
  if (tun is! Map) return false;
  return tun['enable'] == true;
}

// ─── 系统代理（mixed-port）─────────────────────────────────────────────────────

/// 写/删顶层 mixed-port — 移植自 Go: mihomo.go SetMixedInboundMihomo。
/// mihomo 没有逐 inbound 的监听地址：127.0.0.1 → 仅本机（allow-lan: false），
/// 0.0.0.0 / :: → 允许局域网（allow-lan: true + bind-address: "*"）。
void setMixedInboundMihomo(String cfgPath, bool enable, String listen, int port) {
  final cfg = loadYamlFile(cfgPath);
  if (!enable) {
    cfg.remove('mixed-port');
    saveYamlFile(cfgPath, cfg);
    return;
  }
  if (port <= 0) {
    port = 2080;
  }
  cfg['mixed-port'] = port;
  final allowLan = listen != '127.0.0.1';
  cfg['allow-lan'] = allowLan;
  if (allowLan) {
    cfg['bind-address'] = '*';
  }
  saveYamlFile(cfgPath, cfg);
}

// ─── Applied node detection ──────────────────────────────────────────────────

/// 找出配置中 name 为 "proxy" 的条目对应的节点 ID —
/// 移植自 Go: mihomo.go FindAppliedNodeIDMihomo。
/// 比较方式：把该条目与每个节点的（rawClashProxy 或生成的 Clash 条目）
/// 规范化为 YAML 后逐一比对。找不到匹配返回 ""。
String findAppliedNodeIDMihomo(String cfgPath, List<Node> nodes) {
  Map<String, dynamic> cfg;
  try {
    cfg = loadYamlFile(cfgPath);
  } on ParseException {
    return '';
  }
  Map<String, dynamic>? current;
  for (final pr in getProxies(cfg)) {
    if (pr is Map && pr['name'] == mihomoProxyName) {
      current = cloneMap(pr);
      break;
    }
  }
  if (current == null) return '';
  final curData = _canonicalYaml(current);
  for (final n in nodes) {
    Map<String, dynamic> p;
    if (n.rawClashProxy != null) {
      p = cloneMap(n.rawClashProxy!);
    } else {
      try {
        p = nodeToClashProxy(n);
      } on ParseException {
        continue;
      }
    }
    p['name'] = mihomoProxyName;
    if (_canonicalYaml(p) == curData) {
      return n.id;
    }
  }
  return '';
}

/// 把 map 递归按 key 排序后写为 YAML。Go yaml.v3 输出 map 时会对 key 排序
/// （Go map 本身无序），这里显式排序以保持与 Go 版一致的比较语义。
String _canonicalYaml(Map m) => _yamlWriter.write(_sortedDeep(m));

dynamic _sortedDeep(dynamic v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    final out = <String, dynamic>{};
    for (final k in keys) {
      out[k] = _sortedDeep(v[k]);
    }
    return out;
  }
  if (v is List) return v.map(_sortedDeep).toList();
  return v;
}

// ─── Remove Node ──────────────────────────────────────────────────────────────

/// 移除 "proxy" proxies 条目以及所有 proxy-group 对它的引用 —
/// 移植自 Go: mihomo.go removeNodeFromMihomoConfig（取消应用）。
void removeNodeFromMihomoConfig(String cfgPath) {
  final cfg = loadYamlFile(cfgPath);
  final proxies = getProxies(cfg);
  final keptProxies = <dynamic>[];
  var removed = false;
  for (final pr in proxies) {
    if (pr is Map && pr['name'] == mihomoProxyName) {
      removed = true;
      continue;
    }
    keptProxies.add(pr);
  }
  if (!removed) {
    return; // 未应用过节点 — 无事可做
  }
  cfg['proxies'] = keptProxies;
  // proxy-groups 成员里去掉 "proxy"，避免悬空引用
  final pg = cfg['proxy-groups'];
  if (pg is List) {
    for (final g in pg) {
      if (g is! Map) continue;
      final raw = g['proxies'];
      if (raw is! List) continue;
      final kept = <dynamic>[];
      for (final mem in raw) {
        if (mem is String && mem == mihomoProxyName) continue;
        kept.add(mem);
      }
      g['proxies'] = kept;
    }
  }
  saveYamlFile(cfgPath, cfg);
}

