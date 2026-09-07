/// sing-box/mihomo 配置文件增量编辑 — 移植自 Go: backend/config/editor.go。
///
/// mihomo 侧实现见 mihomo_edit.dart（移植自 Go: backend/config/mihomo.go）。
library;

import 'dart:convert';
import 'dart:io';

import '../models/node.dart';
import '../parsing/common.dart';
import 'mihomo_edit.dart';

/// 内核标识 — 移植自 Go: backend/config/manager.go
const String coreSingBox = 'sing-box';
const String coreMihomo = 'mihomo';

// ─── JSON load / save ─────────────────────────────────────────────────────────

/// 读取 JSON 配置 — 移植自 Go: editor.go loadJSON。
/// 读文件/解析失败抛 [ParseException]。
Map<String, dynamic> loadJson(String path) {
  String data;
  try {
    data = File(path).readAsStringSync();
  } catch (e) {
    throw ParseException('读取配置文件失败: $e');
  }
  dynamic decoded;
  try {
    decoded = jsonDecode(data);
  } catch (e) {
    throw ParseException('解析配置文件失败: $e');
  }
  if (decoded is! Map) {
    throw ParseException('解析配置文件失败: 配置根节点不是对象');
  }
  return Map<String, dynamic>.from(decoded);
}

/// 写 JSON 配置（缩进 2 空格，原子写：临时文件 + rename）—
/// 移植自 Go: editor.go saveJSON（MarshalIndent + tmp + os.Rename）。
void saveJson(String path, Map<String, dynamic> cfg) {
  String data;
  try {
    data = const JsonEncoder.withIndent('  ').convert(cfg);
  } catch (e) {
    throw ParseException('序列化配置失败: $e');
  }
  final tmp = '$path.tmp';
  try {
    File(tmp).writeAsStringSync(data, flush: true);
    File(tmp).renameSync(path);
  } catch (e) {
    throw ParseException('写入配置文件失败: $e');
  }
}

/// Go 的类型断言 `cfg["inbounds"].([]interface{})` 等价物：非列表返回空列表。
List<dynamic> _inbounds(Map<String, dynamic> cfg) {
  final v = cfg['inbounds'];
  return v is List ? List<dynamic>.from(v) : <dynamic>[];
}

List<dynamic> _outbounds(Map<String, dynamic> cfg) {
  final v = cfg['outbounds'];
  return v is List ? List<dynamic>.from(v) : <dynamic>[];
}

// ─── Apply Node ───────────────────────────────────────────────────────────────

/// 按内核把节点写入配置文件 — 移植自 Go: editor.go ApplyNodeToConfig。
/// sing-box：替换 tag 为 "proxy" 的 outbound；mihomo：替换 name 为 "proxy" 的 proxies 条目。
void applyNodeToConfig(String core, String cfgPath, Node n) {
  if (core == coreMihomo) {
    applyNodeToMihomoConfig(cfgPath, n);
    return;
  }
  applyNodeToSingBoxConfig(cfgPath, n);
}

/// 替换 sing-box JSON 配置中的 "proxy" outbound —
/// 移植自 Go: editor.go applyNodeToSingBoxConfig。
void applyNodeToSingBoxConfig(String cfgPath, Node n) {
  final cfg = loadJson(cfgPath);
  Map<String, dynamic> outbound;
  if (n.rawOutbound != null) {
    // 原始 sing-box outbound JSON 无损回写（v2rayN 做法）。
    // 覆盖所有 outbound 协议与所有 TLS 类型（标准/uTLS/Reality/ECH）的任意字段组合。
    // （Go 版直接引用该 map；这里深拷贝避免污染调用方的节点数据。）
    outbound = cloneMap(n.rawOutbound!);
  } else {
    outbound = nodeToSingBoxOutbound(n);
  }
  final outbounds = _outbounds(cfg);
  var replaced = false;
  for (var i = 0; i < outbounds.length; i++) {
    final ob = outbounds[i];
    if (ob is Map && ob['tag'] == 'proxy') {
      outbound['tag'] = 'proxy';
      outbounds[i] = outbound;
      replaced = true;
      break;
    }
  }
  if (!replaced) {
    outbound['tag'] = 'proxy';
    outbounds.add(outbound);
  }
  cfg['outbounds'] = outbounds;
  saveJson(cfgPath, cfg);
}

/// 把 Node 转换为 sing-box outbound map，字段名与 sing-box 官方文档一致 —
/// 移植自 Go: editor.go nodeToSingBoxOutbound。失败抛 [ParseException]。
Map<String, dynamic> nodeToSingBoxOutbound(Node n) {
  final ob = <String, dynamic>{
    'tag': 'proxy',
    'server': n.address,
    'server_port': n.port,
  };

  switch (n.protocol) {
    // ── VMess ───────────────────────────────────────────────────────────────
    case 'vmess':
      final vm = n.vMess;
      if (vm == null) throw ParseException('VMess 配置为空');
      ob['type'] = 'vmess';
      ob['uuid'] = vm.uuid;
      ob['alter_id'] = vm.alterId;
      // security 不能是空串 — 默认 "auto"
      ob['security'] = orDefault(vm.security, 'auto');
      final t = buildTransport(vm.transport);
      if (t != null) {
        ob['transport'] = t;
      }
      if (vm.tls) {
        ob['tls'] = buildTls(vm.sni, vm.alpn, vm.insecure, vm.fingerprint, vm.echConfig);
      }

    // ── VLESS ───────────────────────────────────────────────────────────────
    case 'vless':
      final vl = n.vless;
      if (vl == null) throw ParseException('VLESS 配置为空');
      ob['type'] = 'vless';
      ob['uuid'] = vl.uuid;
      if (vl.flow.isNotEmpty) {
        ob['flow'] = vl.flow;
      }
      final t = buildTransport(vl.transport);
      if (t != null) {
        ob['transport'] = t;
      }
      if (vl.tls) {
        if (vl.publicKey.isNotEmpty) {
          final tls = buildRealityTls(vl.sni, vl.publicKey, vl.shortId, vl.fingerprint);
          if (vl.insecure) {
            tls['insecure'] = true;
          }
          ob['tls'] = tls;
        } else {
          ob['tls'] = buildTls(vl.sni, vl.alpn, vl.insecure, vl.fingerprint, vl.echConfig);
        }
      }

    // ── Trojan ──────────────────────────────────────────────────────────────
    case 'trojan':
      final tj = n.trojan;
      if (tj == null) throw ParseException('Trojan 配置为空');
      ob['type'] = 'trojan';
      ob['password'] = tj.password;
      final t = buildTransport(tj.transport);
      if (t != null) {
        ob['transport'] = t;
      }
      // Trojan 总是使用 TLS
      ob['tls'] = buildTls(tj.sni, tj.alpn, tj.insecure, tj.fingerprint, tj.echConfig);

    // ── Shadowsocks ─────────────────────────────────────────────────────────
    case 'ss':
      final ss = n.ss;
      if (ss == null) throw ParseException('Shadowsocks 配置为空');
      ob['type'] = 'shadowsocks';
      ob['method'] = ss.method;
      ob['password'] = ss.password;
      if (ss.plugin.isNotEmpty) {
        ob['plugin'] = ss.plugin;
        if (ss.pluginOpts.isNotEmpty) {
          ob['plugin_opts'] = ss.pluginOpts;
        }
      }

    // ── Hysteria (v1, sing-box 1.12 起废弃 — tls 必填) ───────────────────────
    case 'hysteria':
      final h = n.hysteria;
      if (h == null) throw ParseException('Hysteria 配置为空');
      ob['type'] = 'hysteria';
      if (h.authStr.isNotEmpty) {
        ob['auth_str'] = h.authStr;
      }
      if (h.upMbps > 0) {
        ob['up_mbps'] = h.upMbps;
      }
      if (h.downMbps > 0) {
        ob['down_mbps'] = h.downMbps;
      }
      if (h.obfs.isNotEmpty) {
        ob['obfs'] = h.obfs;
      }
      final tls = <String, dynamic>{'enabled': true};
      if (h.sni.isNotEmpty) {
        tls['server_name'] = h.sni;
      }
      if (h.insecure) {
        tls['insecure'] = true;
      }
      if (h.alpn != null && h.alpn!.isNotEmpty) {
        tls['alpn'] = h.alpn;
      }
      ob['tls'] = tls;

    // ── Hysteria2（tls 必填）────────────────────────────────────────────────
    case 'hysteria2':
      final h = n.hysteria2;
      if (h == null) throw ParseException('Hysteria2 配置为空');
      ob['type'] = 'hysteria2';
      if (h.password.isNotEmpty) {
        ob['password'] = h.password;
      }
      if (h.upMbps > 0) {
        ob['up_mbps'] = h.upMbps;
      }
      if (h.downMbps > 0) {
        ob['down_mbps'] = h.downMbps;
      }
      if (h.obfs.isNotEmpty) {
        final obfs = <String, dynamic>{'type': h.obfs};
        if (h.obfsPassword.isNotEmpty) {
          obfs['password'] = h.obfsPassword;
        }
        ob['obfs'] = obfs;
      }
      // tls 必填 — 始终带 enabled:true
      final tls = <String, dynamic>{'enabled': true};
      if (h.sni.isNotEmpty) {
        tls['server_name'] = h.sni;
      }
      if (h.insecure) {
        tls['insecure'] = true;
      }
      if (h.alpn != null && h.alpn!.isNotEmpty) {
        tls['alpn'] = h.alpn;
      }
      if (h.echConfig.isNotEmpty) {
        tls['ech'] = <String, dynamic>{
          'enabled': true,
          'config': h.echConfig,
        };
      }
      ob['tls'] = tls;

    // ── TUIC（tls 必填）─────────────────────────────────────────────────────
    case 'tuic':
      final t = n.tuic;
      if (t == null) throw ParseException('TUIC 配置为空');
      ob['type'] = 'tuic';
      ob['uuid'] = t.uuid;
      if (t.password.isNotEmpty) {
        ob['password'] = t.password;
      }
      // congestion_control: cubic(默认) | new_reno | bbr
      ob['congestion_control'] = orDefault(t.congestionControl, 'cubic');
      // udp_relay_mode: native(默认) | quic — 留空表示用默认值
      if (t.udpRelayMode.isNotEmpty) {
        ob['udp_relay_mode'] = t.udpRelayMode;
      }
      // tls 必填 — 始终带 enabled:true
      final tls = <String, dynamic>{'enabled': true};
      if (t.sni.isNotEmpty) {
        tls['server_name'] = t.sni;
      }
      if (t.insecure) {
        tls['insecure'] = true;
      }
      if (t.alpn != null && t.alpn!.isNotEmpty) {
        tls['alpn'] = t.alpn;
      }
      ob['tls'] = tls;

    // ── Socks ───────────────────────────────────────────────────────────────
    case 'socks':
      final s = n.socks;
      if (s == null) throw ParseException('Socks 配置为空');
      ob['type'] = 'socks';
      ob['version'] = orDefault(s.version, '5');
      if (s.username.isNotEmpty) {
        ob['username'] = s.username;
      }
      if (s.password.isNotEmpty) {
        ob['password'] = s.password;
      }

    // ── HTTP(S) ─────────────────────────────────────────────────────────────
    case 'http':
      final h = n.http;
      if (h == null) throw ParseException('HTTP 配置为空');
      ob['type'] = 'http';
      if (h.username.isNotEmpty) {
        ob['username'] = h.username;
      }
      if (h.password.isNotEmpty) {
        ob['password'] = h.password;
      }
      if (h.tls) {
        ob['tls'] = buildTls(h.sni, h.alpn, h.insecure, '', '');
      }

    // ── AnyTLS（tls 必填）───────────────────────────────────────────────────
    case 'anytls':
      final a = n.anytls;
      if (a == null) throw ParseException('AnyTLS 配置为空');
      ob['type'] = 'anytls';
      ob['password'] = a.password;
      final tls = <String, dynamic>{'enabled': true};
      if (a.sni.isNotEmpty) {
        tls['server_name'] = a.sni;
      }
      if (a.insecure) {
        tls['insecure'] = true;
      }
      if (a.alpn != null && a.alpn!.isNotEmpty) {
        tls['alpn'] = a.alpn;
      }
      if (a.fingerprint.isNotEmpty) {
        tls['utls'] = <String, dynamic>{
          'enabled': true,
          'fingerprint': a.fingerprint,
        };
      }
      if (a.echConfig.isNotEmpty) {
        tls['ech'] = <String, dynamic>{
          'enabled': true,
          'config': a.echConfig,
        };
      }
      ob['tls'] = tls;

    // ── ShadowsocksR（sing-box 1.13 移除，老内核仍支持）─────────────────────
    case 'ssr':
      final sr = n.ssr;
      if (sr == null) throw ParseException('SSR 配置为空');
      ob['type'] = 'shadowsocksr';
      ob['method'] = sr.method;
      ob['password'] = sr.password;
      if (sr.protocol.isNotEmpty) {
        ob['protocol'] = sr.protocol;
      }
      if (sr.protocolParam.isNotEmpty) {
        ob['protocol_param'] = sr.protocolParam;
      }
      if (sr.obfs.isNotEmpty) {
        ob['obfs'] = sr.obfs;
      }
      if (sr.obfsParam.isNotEmpty) {
        ob['obfs_param'] = sr.obfsParam;
      }

    // ── WireGuard（sing-box 1.13+ 建议 endpoint，outbound 仍兼容）───────────
    case 'wireguard':
      final wg = n.wireGuard;
      if (wg == null) throw ParseException('WireGuard 配置为空');
      ob['type'] = 'wireguard';
      ob['private_key'] = wg.privateKey;
      ob['peer_public_key'] = wg.publicKey;
      if (wg.presharedKey.isNotEmpty) {
        ob['pre_shared_key'] = wg.presharedKey;
      }
      if (wg.localAddress != null && wg.localAddress!.isNotEmpty) {
        ob['local_address'] = wg.localAddress;
      } else {
        ob['local_address'] = <String>['172.16.0.2/32'];
      }
      if (wg.reserved != null && wg.reserved!.length == 3) {
        ob['reserved'] = wg.reserved;
      }
      if (wg.mtu > 0) {
        ob['mtu'] = wg.mtu;
      }
      if (wg.dns != null && wg.dns!.isNotEmpty) {
        ob['dns'] = wg.dns;
      }

    default:
      throw ParseException('不支持的协议: ${n.protocol}');
  }
  return ob;
}

// ─── Transport builder ────────────────────────────────────────────────────────
// 把 TransportConfig 转成 sing-box "transport" 对象 —
// 移植自 Go: editor.go buildTransport（字段布局注释见 Go 版）。

Map<String, dynamic>? buildTransport(TransportConfig? t) {
  if (t == null || t.type.isEmpty) {
    return null;
  }
  final m = <String, dynamic>{'type': t.type};

  switch (t.type) {
    case 'ws':
      if (t.path.isNotEmpty) {
        m['path'] = t.path;
      }
      // WebSocket 的 Host 放 headers["Host"]
      if (t.host.isNotEmpty) {
        m['headers'] = <String, dynamic>{'Host': t.host};
      }
      // Early data 支持
      if (t.maxEarlyData > 0) {
        m['max_early_data'] = t.maxEarlyData;
        m['early_data_header_name'] =
            orDefault(t.earlyDataHeaderName, 'Sec-WebSocket-Protocol');
      }

    case 'http':
      // path: 普通字符串（不是数组）
      if (t.path.isNotEmpty) {
        m['path'] = t.path;
      }
      // host: []string 数组
      if (t.host.isNotEmpty) {
        m['host'] = <String>[t.host];
      }

    case 'grpc':
      if (t.serviceName.isNotEmpty) {
        m['service_name'] = t.serviceName;
      }

    case 'httpupgrade':
      if (t.path.isNotEmpty) {
        m['path'] = t.path;
      }
      // host: 顶层字符串字段（不是 headers["Host"] — 那是 WebSocket 的行为）
      if (t.host.isNotEmpty) {
        m['host'] = t.host;
      }

    case 'quic':
      // 无用户侧字段
      break;

    case 'xhttp':
      // Xray xhttp transport（sing-box fork）。按 Xray 规范：
      // path 是普通字符串，host 是 []string 数组，mode 选 packet-up /
      // stream-up / stream-one / auto。
      if (t.path.isNotEmpty) {
        m['path'] = t.path;
      }
      if (t.host.isNotEmpty) {
        m['host'] = <String>[t.host];
      }
      if (t.mode.isNotEmpty) {
        m['mode'] = t.mode;
      }
  }
  return m;
}

// ─── TLS builders ─────────────────────────────────────────────────────────────

/// 标准 TLS 块 — 移植自 Go: editor.go buildTLS。
Map<String, dynamic> buildTls(String sni, List<String>? alpn, bool insecure,
    String fingerprint, String echConfig) {
  final tls = <String, dynamic>{'enabled': true};
  if (sni.isNotEmpty) {
    tls['server_name'] = sni;
  }
  if (insecure) {
    tls['insecure'] = true;
  }
  if (alpn != null && alpn.isNotEmpty) {
    tls['alpn'] = alpn;
  }
  // uTLS 指纹（浏览器伪装）
  if (fingerprint.isNotEmpty) {
    tls['utls'] = <String, dynamic>{
      'enabled': true,
      'fingerprint': fingerprint,
    };
  }
  // Encrypted Client Hello
  if (echConfig.isNotEmpty) {
    tls['ech'] = <String, dynamic>{
      'enabled': true,
      'config': echConfig,
    };
  }
  return tls;
}

/// VLESS+Reality 的 TLS 块 — 移植自 Go: editor.go buildRealityTLS。
/// Reality 需要：public_key、short_id 和 uTLS 指纹（默认 "chrome"）。
Map<String, dynamic> buildRealityTls(
    String sni, String publicKey, String shortId, String fingerprint) {
  final tls = <String, dynamic>{
    'enabled': true,
    'reality': <String, dynamic>{
      'enabled': true,
      'public_key': publicKey,
      'short_id': shortId,
    },
    'utls': <String, dynamic>{
      'enabled': true,
      'fingerprint': orDefault(fingerprint, 'chrome'),
    },
  };
  if (sni.isNotEmpty) {
    tls['server_name'] = sni;
  }
  return tls;
}

// ─── TUN inbound ─────────────────────────────────────────────────────────────

/// 按内核开关 TUN — 移植自 Go: editor.go SetTun。
/// mihomo 无 strict_route，该参数对 mihomo 被忽略。
void setTun(String core, String cfgPath, bool enable, String stack, int mtu,
    bool strictRoute) {
  if (core == coreMihomo) {
    setTunMihomo(cfgPath, enable, stack, mtu);
    return;
  }
  _setTunSingBox(cfgPath, enable, stack, mtu, strictRoute);
}

/// 根据用户设置构建 tun inbound — 移植自 Go: editor.go buildTunInbound。
/// address 与 interface_name 保持固定（修改会导致路由残留风险，不暴露为设置项）。
Map<String, dynamic> buildTunInbound(String stack, int mtu, bool strictRoute) {
  if (stack != 'gvisor' && stack != 'system' && stack != 'mixed') {
    stack = 'gvisor';
  }
  if (mtu <= 0) {
    mtu = 9000;
  }
  return <String, dynamic>{
    'type': 'tun',
    'tag': 'tun-in',
    'interface_name': 'singbox_tun',
    'address': <String>['172.18.0.1/30'],
    'mtu': mtu,
    'auto_route': true,
    'strict_route': strictRoute,
    'stack': stack,
  };
}

/// 开关 sing-box 配置中的 tun inbound — 移植自 Go: editor.go setTunSingBox。
void _setTunSingBox(String cfgPath, bool enable, String stack, int mtu,
    bool strictRoute) {
  final cfg = loadJson(cfgPath);
  final inbounds = _inbounds(cfg);
  final newInbounds = <dynamic>[];
  for (final ib in inbounds) {
    if (ib is Map && ib['type'] == 'tun') {
      continue;
    }
    newInbounds.add(ib);
  }
  if (enable) {
    newInbounds.add(buildTunInbound(stack, mtu, strictRoute));
  }
  cfg['inbounds'] = newInbounds;
  saveJson(cfgPath, cfg);
}

// ─── Mixed inbound ────────────────────────────────────────────────────────────

/// 按内核开关 mixed 入站（系统代理）— 移植自 Go: editor.go SetMixedInbound。
void setMixedInbound(String core, String cfgPath, bool enable, String listen,
    int port) {
  if (core == coreMihomo) {
    setMixedInboundMihomo(cfgPath, enable, listen, port);
    return;
  }
  _setMixedInboundSingBox(cfgPath, enable, listen, port);
}

/// 开关 sing-box 配置中的 mixed inbound — 移植自 Go: editor.go setMixedInboundSingBox。
void _setMixedInboundSingBox(String cfgPath, bool enable, String listen, int port) {
  if (listen.trim().isEmpty) {
    listen = '127.0.0.1';
  }
  if (port <= 0) {
    port = 2080;
  }
  final cfg = loadJson(cfgPath);
  final inbounds = _inbounds(cfg);
  final newInbounds = <dynamic>[];
  for (final ib in inbounds) {
    if (ib is Map && ib['type'] == 'mixed') {
      continue;
    }
    newInbounds.add(ib);
  }
  if (enable) {
    newInbounds.add(<String, dynamic>{
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': listen,
      'listen_port': port,
    });
  }
  cfg['inbounds'] = newInbounds;
  saveJson(cfgPath, cfg);
}

// ─── Applied node detection ──────────────────────────────────────────────────

/// 判断配置文件当前是否启用了 TUN（用于切换配置前探测 TUN 状态）—
/// 移植自 Go: editor.go HasTunInbound。
bool hasTunInbound(String core, String cfgPath) {
  if (core == coreMihomo) {
    return hasTunMihomo(cfgPath);
  }
  Map<String, dynamic> cfg;
  try {
    cfg = loadJson(cfgPath);
  } on ParseException {
    return false;
  }
  for (final ib in _inbounds(cfg)) {
    if (ib is Map && ib['type'] == 'tun') {
      return true;
    }
  }
  return false;
}

/// 找出配置文件中当前应用的节点 ID（按内核定位方式：
/// sing-box 为 tag "proxy" 的 outbound，mihomo 为 name "proxy" 的 proxies 条目）—
/// 移植自 Go: editor.go FindAppliedNodeID。找不到匹配返回 ""。
String findAppliedNodeId(String core, String cfgPath, List<Node> nodes) {
  if (core == coreMihomo) {
    return findAppliedNodeIDMihomo(cfgPath, nodes);
  }
  return _findAppliedNodeIDSingBox(cfgPath, nodes);
}

/// 读取 sing-box JSON 配置，找出当前 "proxy" outbound 对应的节点 ID —
/// 移植自 Go: editor.go findAppliedNodeIDSingBox。
String _findAppliedNodeIDSingBox(String cfgPath, List<Node> nodes) {
  Map<String, dynamic> cfg;
  try {
    cfg = loadJson(cfgPath);
  } on ParseException {
    return '';
  }
  Map<String, dynamic>? proxyOb;
  for (final ob in _outbounds(cfg)) {
    if (ob is Map && ob['tag'] == 'proxy') {
      proxyOb = Map<String, dynamic>.from(ob);
      break;
    }
  }
  if (proxyOb == null) {
    return '';
  }
  // Go 版依赖 json.Marshal 对 map key 排序保证比较确定；这里显式排序。
  final current = _canonicalJson(proxyOb);
  for (final n in nodes) {
    Map<String, dynamic> ob;
    if (n.rawOutbound != null) {
      ob = cloneMap(n.rawOutbound!);
    } else {
      try {
        ob = nodeToSingBoxOutbound(n);
      } on ParseException {
        continue;
      }
    }
    ob['tag'] = 'proxy';
    if (_canonicalJson(ob) == current) {
      return n.id;
    }
  }
  return '';
}

/// 递归按 key 排序后的 JSON 序列化（Go json.Marshal 对 map 输出按 key 排序）。
String _canonicalJson(Object? v) => jsonEncode(_sortedDeep(v));

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

// ─── 其他导出 ────────────────────────────────────────────────────────────────

/// 返回某节点 tag 为 "proxy" 的 sing-box outbound（rawOutbound 原样优先）—
/// 移植自 Go: editor.go SingBoxOutboundForNode。供 probe 包构建临时测试配置用。
Map<String, dynamic> singBoxOutboundForNode(Node n) {
  if (n.rawOutbound != null) {
    final ob = cloneMap(n.rawOutbound!);
    ob['tag'] = 'proxy';
    return ob;
  }
  return nodeToSingBoxOutbound(n);
}

/// 撤销 applyNodeToConfig：移除 "proxy" outbound（sing-box）/ "proxy"
/// proxies 条目（mihomo），并清理残留引用 — 移植自 Go: editor.go RemoveNodeFromConfig。
void removeNodeFromConfig(String core, String cfgPath) {
  if (core == coreMihomo) {
    removeNodeFromMihomoConfig(cfgPath);
    return;
  }
  _removeNodeFromSingBoxConfig(cfgPath);
}

/// 从 sing-box JSON 配置中移除 "proxy" outbound —
/// 移植自 Go: editor.go removeNodeFromSingBoxConfig。
void _removeNodeFromSingBoxConfig(String cfgPath) {
  final cfg = loadJson(cfgPath);
  final outbounds = _outbounds(cfg);
  final kept = <dynamic>[];
  var removed = false;
  for (final ob in outbounds) {
    if (ob is Map && ob['tag'] == 'proxy') {
      removed = true;
      continue;
    }
    kept.add(ob);
  }
  if (!removed) {
    return; // 未应用过节点 — 无事可做
  }
  cfg['outbounds'] = kept;
  // route.final 引用 proxy 时回退为 direct，避免残留悬空引用导致内核无法启动
  final route = cfg['route'];
  if (route is Map && route['final'] == 'proxy') {
    route['final'] = 'direct';
  }
  saveJson(cfgPath, cfg);
}
