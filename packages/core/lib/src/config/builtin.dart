/// 内置路由模式配置合成 — 移植自 Go: backend/config/builtin.go。
///
/// 参照 v2rayN 的三种路由模板生成 sing-box / mihomo 配置，直接合成到 run 目录，
/// 不修改用户 configs/ 中的配置文件。
///
///   - bypass    绕过大陆（v2rayN "Whitelist"）：国内/私网直连，其余走代理，final=proxy
///   - blacklist GFW列表（v2rayN "Blacklist"）：被墙域名/海外服务 IP 走代理，其余直连，final=direct
///   - global    全局代理（v2rayN "Global"）：仅私网直连，其余走代理，final=proxy
///
/// geosite/geoip 规则引用本地规则文件：
///   - sing-box: run/rules/srs/`<tag>`.srs（local rule_set, format=binary）
///   - mihomo:   run/rules/mrs/`<tag>`.mrs（file rule-provider, format=mrs）
///
/// 节点出站 / Clash 条目转换复用独立模块（Go 中位于 editor.go /
/// node/clash_write.go）：nodeToSingBoxOutbound、buildTunInbound 来自
/// editor.dart；nodeToClashProxy 来自 ../export/clash_write.dart。
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml_writer/yaml_writer.dart';

import '../export/clash_write.dart' show nodeToClashProxy;
import '../models/node.dart';
import '../parsing/common.dart';
import 'editor.dart' show buildTunInbound, nodeToSingBoxOutbound;
import 'mihomo_edit.dart' show cloneMap;
import 'settings.dart';

// 路由模式常量（modeCustom / modeBypass / modeBlacklist / modeGlobal）
// 移植自 builtin.go，为避免循环引用集中定义在 settings.dart。

/// DNS 模式常量（与 Settings.Builtin.DNSMode 对应）。
const String dnsModeRedirHost = 'redir-host';
const String dnsModeFakeIP = 'fake-ip';

/// mihomo 合成配置中代理条目 / 代理组的固定名（移植自 Go: mihomo.go）。
const String mihomoProxyName = 'proxy';
const String mihomoGroupName = 'PROXY';

/// BuiltinPrefix 内置配置在下拉列表中的显示前缀。
const String builtinPrefix = '内置配置：';

/// 内置模式 → 显示名（顺序即下拉顺序）。
const List<(String, String)> _builtinModeNames = [
  (modeBypass, '绕过大陆'),
  (modeBlacklist, 'GFW列表'),
  (modeGlobal, '全局代理'),
];

/// IsBuiltinMode 判断是否为内置路由模式。
bool isBuiltinMode(String mode) =>
    mode == modeBypass || mode == modeBlacklist || mode == modeGlobal;

/// BuiltinDisplayName 返回内置模式的下拉显示名（如 "内置配置：绕过大陆"）；
/// 非内置模式返回 null。
String? builtinDisplayName(String mode) {
  for (final (m, name) in _builtinModeNames) {
    if (m == mode) return builtinPrefix + name;
  }
  return null;
}

/// ParseBuiltinName 把下拉项解析为路由模式（仅接受 "内置配置：xxx" 形式）；
/// 失败返回 null。
String? parseBuiltinName(String name) {
  for (final (m, n) in _builtinModeNames) {
    if (name == builtinPrefix + n) return m;
  }
  return null;
}

/// BuiltinDisplayNames 返回全部内置配置的显示名（供 GetConfigFiles 追加）。
List<String> builtinDisplayNames() =>
    [for (final (_, n) in _builtinModeNames) builtinPrefix + n];

// ─── 规则文件 ────────────────────────────────────────────────────────────────

/// singboxRuleFiles / mihomoRuleFiles 各内核各模式需要的规则文件基础名
/// （不含扩展名）。geosite-* → mihomo behavior=domain；geoip-* → behavior=ipcidr。
/// sing-box 私网用原生 ip_is_private，不需要 private 规则文件；mihomo 需要。
/// fake-ip 模式追加 geosite-fakeipfilter（fakeip 白名单域名走直连 DNS）。
List<String> singboxRuleFiles(String mode, String dnsMode) {
  final Map<String, List<String>> files = {
    modeBypass: ['geosite-cn', 'geosite-google', 'geoip-cn'],
    modeBlacklist: [
      'geosite-google', 'geosite-gfw', 'geosite-greatfire', //
      'geoip-facebook', 'geoip-fastly', 'geoip-google', //
      'geoip-netflix', 'geoip-telegram', 'geoip-twitter', //
    ],
    modeGlobal: [],
  };
  var result = files[mode] ?? const [];
  if (dnsMode == dnsModeFakeIP) {
    result = [...result, 'geosite-fakeipfilter'];
  }
  return result;
}

List<String> mihomoRuleFiles(String mode, String dnsMode) {
  final Map<String, List<String>> files = {
    modeBypass: ['geosite-private', 'geoip-private', 'geosite-cn', 'geosite-google', 'geoip-cn'],
    modeBlacklist: [
      'geosite-private', 'geoip-private', //
      'geosite-google', 'geosite-gfw', 'geosite-greatfire', //
      'geoip-facebook', 'geoip-fastly', 'geoip-google', //
      'geoip-netflix', 'geoip-telegram', 'geoip-twitter', //
    ],
    modeGlobal: ['geosite-private', 'geoip-private'],
  };
  var result = files[mode] ?? const [];
  if (dnsMode == dnsModeFakeIP) {
    // fake-ip-filter 引用 rule-set:geosite-fakeipfilter，需要对应的 rule-provider
    result = [...result, 'geosite-fakeipfilter'];
  }
  return result;
}

/// builtinRuleFilesAll 两种内核规则文件的并集（供 CheckRuleFiles 校验，宁多勿缺）。
List<String> builtinRuleFilesAll(String mode, String dnsMode) {
  final seen = <String>{};
  final all = <String>[];
  for (final tag in singboxRuleFiles(mode, dnsMode)) {
    if (seen.add(tag)) all.add(tag);
  }
  for (final tag in mihomoRuleFiles(mode, dnsMode)) {
    if (seen.add(tag)) all.add(tag);
  }
  return all;
}

/// isGeositeTag 判断规则 tag 是否为 geosite 类（决定 mihomo rule-provider 的 behavior）。
bool isGeositeTag(String tag) => tag.length > 7 && tag.startsWith('geosite');

/// CheckRuleFiles 校验内置模式所需的规则文件是否齐全（rulesDir 下 srs/ 与 mrs/ 子目录）。
/// 抛出的 [ParseException] 一次性列出全部缺失文件。
void checkRuleFiles(String mode, String dnsMode, String rulesDir) {
  final files = builtinRuleFilesAll(mode, dnsMode);
  if (files.isEmpty) return;
  final missing = <String>[];
  for (final f in files) {
    final srs = File(_pathJoin([rulesDir, 'srs', '$f.srs']));
    final mrs = File(_pathJoin([rulesDir, 'mrs', '$f.mrs']));
    if (!srs.existsSync()) missing.add('run/rules/srs/$f.srs');
    if (!mrs.existsSync()) missing.add('run/rules/mrs/$f.mrs');
  }
  if (missing.isNotEmpty) {
    throw ParseException(
        '缺少规则文件:\n  ${missing.join('\n  ')}\n'
        '请将对应 .srs/.mrs 文件放入上述目录'
        '（srs 来源: SagerNet/sing-geosite、SagerNet/sing-geoip；'
        'mrs 来源: MetaCubeX/meta-rules-dat）');
  }
}

// ─── 私网直连 ────────────────────────────────────────────────────────────────
// sing-box：原生 ip_is_private 字段，不依赖规则文件；
// mihomo：geosite-private / geoip-private 规则集（private.mrs）。

/// mihomoIPRule mihomo IP 类规则集的 no-resolve 策略：
/// 仅 geoip-cn 不加（域名需解析为 IP 以命中国内 IP 段），其余 IP 规则集都加
/// （域名连接跳过 IP 匹配，避免不必要的 DNS 解析）。
String _mihomoIPRule(String tag, String target) {
  if (tag == 'geoip-cn') {
    return 'RULE-SET,$tag,$target';
  }
  return 'RULE-SET,$tag,$target,no-resolve';
}

// ─── 配置生成入口 ─────────────────────────────────────────────────────────────

/// BuiltinOptions 内置配置生成参数（运行时开关状态 + Settings.Builtin）。
class BuiltinOptions {
  String mode;
  bool tunEnabled;
  String tunStack;
  int tunMTU;
  bool tunStrictRoute;
  bool proxyEnabled; // 系统代理开关（决定 mixed inbound / mixed-port）
  String proxyListen;
  int proxyPort;
  String rulesDir; // run/rules 绝对路径
  String uiDir; // clash-api 的 external-ui 绝对路径（run/ui）
  String cachePath; // cache_file 绝对路径（run/cache.db）
  BuiltinSettings? cfg; // 可配置参数（null 时用 DefaultBuiltin）

  BuiltinOptions({
    this.mode = '',
    this.tunEnabled = false,
    this.tunStack = '',
    this.tunMTU = 0,
    this.tunStrictRoute = false,
    this.proxyEnabled = false,
    this.proxyListen = '',
    this.proxyPort = 0,
    this.rulesDir = '',
    this.uiDir = '',
    this.cachePath = '',
    this.cfg,
  });

  /// 返回可配置参数（null 兜底为默认值）。
  BuiltinSettings settings() => cfg ?? defaultBuiltin();
}

/// BuildBuiltinConfig 按内核生成内置模式配置
/// （JSON 文本 for sing-box / YAML 文本 for mihomo）。
/// 非内置模式或无节点抛 [ParseException]。
String buildBuiltinConfig(String core, BuiltinOptions opts, Node? n) {
  if (!isBuiltinMode(opts.mode)) {
    throw ParseException('非内置路由模式: ${opts.mode}');
  }
  if (n == null) {
    throw ParseException('内置路由模式需要先应用一个节点');
  }
  if (core == coreMihomo) {
    return _buildBuiltinMihomo(opts, n);
  }
  return _buildBuiltinSingBox(opts, n);
}

/// mapLogLevel UI 日志等级 → 内核等级：mihomo 原生 warning；sing-box 是 warn。
String _mapLogLevel(String level, String core) {
  if (core == coreSingBox && level == 'warning') {
    return 'warn';
  }
  return level;
}

// ─── 序列化 ──────────────────────────────────────────────────────────────────

/// 生成 JSON 配置（缩进两空格；map 键按字母序输出，
/// 与 Go json.Marshal 对 map 的按键名排序行为一致，保证快照可比）。
String _marshalJSON(Map<String, dynamic> cfg) {
  Object? sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {
        for (final k in keys) k: sorted(v[k]),
      };
    }
    if (v is List) return [for (final e in v) sorted(e)];
    return v;
  }

  return const JsonEncoder.withIndent('  ').convert(sorted(cfg));
}

/// 生成 YAML 配置（用 yaml_writer 包编码；int/bool 保持原生类型，
/// 与 Go yaml.v3 一致；Dart LinkedHashMap 保持插入序）。
String _marshalYAML(Map<String, dynamic> cfg) {
  // YamlWriter.config()：仅在必要时加引号（默认构造会强制给所有字符串加引号）。
  return YamlWriter.config().write(cfg);
}

/// filepath.Join 对应实现（Windows 用 \，其余用 /）。
String _pathJoin(List<String> parts) {
  final sep = Platform.isWindows ? r'\' : '/';
  return parts.where((p) => p.isNotEmpty).join(sep);
}

// ─── sing-box ────────────────────────────────────────────────────────────────

/// buildBuiltinSingBox 合成 sing-box JSON 配置。
/// DNS 用 1.12 新格式（server 必须带 type）；路由规则对齐 v2rayN 三模板。
String _buildBuiltinSingBox(BuiltinOptions opts, Node n) {
  final b = opts.settings();

  // proxy outbound：复用节点出站构造（RawOutbound 无损回写优先）
  Map<String, dynamic> proxyOut;
  if (n.rawOutbound != null) {
    proxyOut = Map<String, dynamic>.from(n.rawOutbound!);
  } else {
    proxyOut = nodeToSingBoxOutbound(n);
  }
  proxyOut['tag'] = 'proxy';

  final cfg = <String, dynamic>{
    'log': {
      'level': _mapLogLevel(b.logLevel, coreSingBox),
      'timestamp': true,
    },
    'dns': _buildBuiltinSingBoxDNS(opts),
    'inbounds': _buildBuiltinSingBoxInbounds(opts),
    'outbounds': [
      proxyOut,
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': _buildBuiltinSingBoxRoute(opts),
  };
  // experimental：cache_file 恒定生成（连接状态缓存；fake-ip 模式下同时持久化
  // fakeip 映射，重启不掉网）；clash-api 开关关闭时不生成
  final experimental = <String, dynamic>{
    'cache_file': {
      'enabled': true,
      'path': opts.cachePath,
      'store_fakeip': b.dnsMode == dnsModeFakeIP,
    },
  };
  if (!b.clashAPIDisabled) {
    experimental['clash_api'] = {
      'external_controller': '${b.clashAPI.listen}:${b.clashAPI.port}',
      'external_ui': opts.uiDir,
      'secret': b.clashAPI.secret,
      'default_mode': 'rule',
    };
  }
  cfg['experimental'] = experimental;
  return _marshalJSON(cfg);
}

/// singBoxDNSServerMap 把 DNSServer 设置转为 sing-box DNS server 对象。
/// 地址必填；端口、路径选填：端口为零值时按类型补默认端口（udp/tcp 53、tls 853、
/// https/quic 443），保证配置到手即用；路径仅 https 类型写入。
/// viaProxy: 代理 DNS 加 detour 出站（直连/解析 DNS 不加，内核报错）；
/// withResolver: 直连/代理 DNS 加 domain_resolver 指向解析 DNS。
Map<String, dynamic> _singBoxDNSServerMap(
    String tag, DNSServer ds, bool viaProxy, bool withResolver) {
  final m = <String, dynamic>{
    'type': ds.type,
    'tag': tag,
    'server': ds.address,
  };
  var port = ds.port;
  if (port <= 0) {
    port = _dnsDefaultPort(ds.type);
  }
  m['server_port'] = port;
  if (ds.type == 'https' && ds.path.isNotEmpty) {
    m['path'] = ds.path;
  }
  if (viaProxy) {
    m['detour'] = 'proxy';
  }
  if (withResolver) {
    m['domain_resolver'] = {'server': 'dns-resolver'};
  }
  return m;
}

/// dnsDefaultPort DNS 类型默认端口。
int _dnsDefaultPort(String t) {
  switch (t) {
    case 'tls':
      return 853;
    case 'https':
    case 'quic':
      return 443;
    default: // udp / tcp
      return 53;
  }
}

/// buildBuiltinSingBoxDNS 生成 DNS 段（sing-box 1.12 新格式）。
///   - redir-host：按模式分流（bypass: cn→直连；blacklist: gfw/google→代理），
///     其余走 final；
///   - fake-ip：geosite-fakeipfilter 域名走直连 DNS（真实解析），
///     其余 A/AAAA 查询返回 fakeip。
Map<String, dynamic> _buildBuiltinSingBoxDNS(BuiltinOptions opts) {
  final b = opts.settings();

  final resolver = <String, dynamic>{
    'type': 'udp',
    'tag': 'dns-resolver',
    'server': b.resolverDNS,
  };
  final direct = _singBoxDNSServerMap('dns-direct', b.singBoxDirect, false, true);
  final proxy = _singBoxDNSServerMap('dns-proxy', b.singBoxProxy, true, true);
  final servers = <dynamic>[proxy, direct, resolver];

  // Go: var rules []interface{} — 未追加时保持 nil（JSON 输出 null）
  List<dynamic>? rules;
  var finalDNS = 'dns-proxy';
  if (b.dnsMode == dnsModeFakeIP) {
    // fakeip 白名单：规则集内域名走直连 DNS 真实解析
    (rules ??= []).add({
      'rule_set': ['geosite-fakeipfilter'],
      'server': 'dns-direct',
    });
    // 其余 A/AAAA 查询返回 fakeip；域名靠 sniff 命中路由规则
    final fakeip = <String, dynamic>{
      'type': 'fakeip',
      'tag': 'dns-fakeip',
      'inet4_range': '198.18.0.0/15',
    };
    if (b.ipv6) {
      fakeip['inet6_range'] = 'fc00::/18';
    }
    servers.add(fakeip);
    rules.add({
      'action': 'route',
      'query_type': ['A', 'AAAA'],
      'server': 'dns-fakeip',
    });
  } else {
    // redir-host：按模式分流
    switch (opts.mode) {
      case modeBypass:
        // 国内域名走直连 DNS，其余走代理 DNS
        (rules ??= []).add({
          'rule_set': ['geosite-cn'],
          'server': 'dns-direct',
        });
      case modeBlacklist:
        // 被墙/Google 域名走代理 DNS，其余直连
        (rules ??= []).add({
          'rule_set': ['geosite-gfw', 'geosite-greatfire', 'geosite-google'],
          'server': 'dns-proxy',
        });
        finalDNS = 'dns-direct';
      case modeGlobal:
        // 全部走代理 DNS
        break;
    }
  }
  return {
    'servers': servers,
    'rules': rules,
    'final': finalDNS,
  };
}

/// buildBuiltinSingBoxInbounds 按开关生成 mixed / tun inbound。
List<dynamic> _buildBuiltinSingBoxInbounds(BuiltinOptions opts) {
  // 保持空数组而非 null，避免内核解析失败
  final inbounds = <dynamic>[];
  if (opts.proxyEnabled) {
    var listen = opts.proxyListen;
    if (listen.isEmpty) listen = '127.0.0.1';
    var port = opts.proxyPort;
    if (port <= 0) port = 2080;
    inbounds.add({
      'type': 'mixed',
      'tag': 'mixed-in',
      'listen': listen,
      'listen_port': port,
    });
  }
  if (opts.tunEnabled) {
    final tun = buildTunInbound(opts.tunStack, opts.tunMTU, opts.tunStrictRoute);
    if (opts.settings().ipv6) {
      // IPv6 开启：TUN 地址补充 IPv6 段
      tun['address'] = [..._toList(tun['address']), 'fdfe:dcba:9876::1/126'];
    }
    inbounds.add(tun);
  }
  return inbounds;
}

/// toIfaceList 把 address 字段统一为 List。
List<dynamic> _toList(dynamic v) {
  if (v is List) return List<dynamic>.from(v);
  return [];
}

/// buildBuiltinSingBoxRoute 生成 route 段：规则对齐 v2rayN 模板，
/// geosite/geoip 走本地 rule_set。
Map<String, dynamic> _buildBuiltinSingBoxRoute(BuiltinOptions opts) {
  final b = opts.settings();
  final rules = <dynamic>[
    // 首条嗅探：mixed inbound 的流量只有嗅探后才有域名信息，否则 geosite 规则不命中
    {'action': 'sniff'},
  ];
  if (opts.tunEnabled) {
    rules.add({'port': 53, 'action': 'hijack-dns'});
  }

  final privateDirect = <String, dynamic>{'ip_is_private': true, 'outbound': 'direct'};
  final udpQUICReject = <String, dynamic>{
    'port': 443,
    'network': ['udp'],
    'action': 'reject',
  };

  var finalOutbound = 'proxy';
  switch (opts.mode) {
    case modeBypass:
      rules.addAll([
        udpQUICReject,
        {
          'rule_set': ['geosite-google'],
          'outbound': 'proxy',
        },
        privateDirect,
        {
          'rule_set': ['geosite-cn'],
          'outbound': 'direct',
        },
        {
          'rule_set': ['geoip-cn'],
          'outbound': 'direct',
        },
      ]);
    case modeBlacklist:
      finalOutbound = 'direct';
      rules.addAll([
        // 对齐 v2rayN black 模板（mihomo 无 protocol 匹配，此规则仅 sing-box 有）
        {
          'protocol': ['bittorrent'],
          'outbound': 'direct',
        },
        {
          'domain': ['api.ip.sb'],
          'outbound': 'proxy',
        },
        udpQUICReject,
        {
          'rule_set': ['geosite-google'],
          'outbound': 'proxy',
        },
        privateDirect,
        {
          'rule_set': [
            'geoip-facebook', 'geoip-fastly', 'geoip-google', //
            'geoip-netflix', 'geoip-telegram', 'geoip-twitter', //
          ],
          'outbound': 'proxy',
        },
        {
          'rule_set': ['geosite-gfw', 'geosite-greatfire'],
          'outbound': 'proxy',
        },
      ]);
    case modeGlobal:
      rules.addAll([udpQUICReject, privateDirect]);
  }

  // 本地 rule_set（引用 run/rules/srs/ 下的 .srs 文件）
  List<dynamic>? ruleSet;
  for (final tag in singboxRuleFiles(opts.mode, b.dnsMode)) {
    (ruleSet ??= []).add({
      'type': 'local',
      'tag': tag,
      'format': 'binary',
      'path': _pathJoin([opts.rulesDir, 'srs', '$tag.srs']),
    });
  }

  final route = <String, dynamic>{
    'rules': rules,
    'final': finalOutbound,
    // 域名默认解析器指向直连 DNS（sing-box 1.12 必需字段，缺省时域名出站解析无依据）
    'default_domain_resolver': {
      'server': 'dns-direct',
      'strategy': _ipv6Strategy(b.ipv6),
    },
  };
  if (ruleSet != null) {
    route['rule_set'] = ruleSet;
  }
  if (opts.tunEnabled) {
    route['auto_detect_interface'] = true;
  }
  return route;
}

/// ipv6Strategy IPv6 开关对应的解析策略：开 = 双栈优先 IPv4，关 = 仅 IPv4。
String _ipv6Strategy(bool ipv6) => ipv6 ? 'prefer_ipv4' : 'ipv4_only';

// ─── mihomo ──────────────────────────────────────────────────────────────────

/// buildBuiltinMihomo 合成 mihomo YAML 配置（与 sing-box 版逐条对齐；
/// 唯一差异：mihomo 没有 protocol 匹配，bittorrent 直连规则仅 sing-box 生成）。
String _buildBuiltinMihomo(BuiltinOptions opts, Node n) {
  final b = opts.settings();

  // proxy 条目：RawClashProxy 无损回写优先
  Map<String, dynamic> proxy;
  if (n.rawClashProxy != null) {
    try {
      proxy = cloneMap(n.rawClashProxy!);
    } catch (e) {
      throw ParseException('节点原始 Clash 数据无效');
    }
  } else {
    proxy = nodeToClashProxy(n);
  }
  proxy['name'] = mihomoProxyName;

  final cfg = <String, dynamic>{
    'mode': 'rule',
    'log-level': _mapLogLevel(b.logLevel, coreMihomo),
    // IPv6：全局 + DNS 两处开关
    'ipv6': b.ipv6,
    'proxies': [proxy],
    'proxy-groups': [
      {
        'name': mihomoGroupName,
        'type': 'select',
        'proxies': [mihomoProxyName, 'DIRECT'],
      },
    ],
    'dns': _buildBuiltinMihomoDNS(opts),
    'sniffer': _buildBuiltinMihomoSniffer(),
  };
  // clash-api：开关关闭时完全不生成
  if (!b.clashAPIDisabled) {
    cfg['external-controller'] = '${b.clashAPI.listen}:${b.clashAPI.port}';
    cfg['external-ui'] = opts.uiDir;
    cfg['secret'] = b.clashAPI.secret;
  }
  _appendBuiltinMihomoMixed(cfg, opts);
  if (opts.tunEnabled) {
    cfg['tun'] = _buildBuiltinMihomoTun(opts);
  }
  _appendBuiltinMihomoRoute(cfg, opts);
  return _marshalYAML(cfg);
}

/// resolverNS 返回 mihomo default-nameserver 列表：主 + 备用解析 DNS（去重、去空）。
List<String> _resolverNS(BuiltinSettings b) {
  final out = <String>[];
  final seen = <String>{};
  for (var s in [b.resolverDNS, b.resolverDNSBackup]) {
    s = s.trim();
    if (s.isEmpty || !seen.add(s)) continue;
    out.add(s);
  }
  return out;
}

/// buildBuiltinMihomoDNS 生成 DNS 段（redir-host / fake-ip）。
///   - 绕过大陆：默认 nameserver = 代理 DNS（#PROXY 经代理组出站，避免 UDP 53
///     直连被污染），直连域名规则集 → 直连 DNS；
///   - GFW列表：默认 nameserver = 直连 DNS，代理域名规则集 → 代理 DNS；
///   - 全局：默认 nameserver = 代理 DNS（全部流量走代理），无 policy。
///   - fake-ip：以上结构不变，enhanced-mode 切 fake-ip，
///     fake-ip-filter = rule-set:geosite-fakeipfilter。
Map<String, dynamic> _buildBuiltinMihomoDNS(BuiltinOptions opts) {
  final b = opts.settings();
  final directDNS = b.mihomoDirect ?? <String>[];
  final proxyDNS = _withProxySuffix(b.mihomoProxy ?? <String>[]);

  final dns = <String, dynamic>{
    'enable': true,
    'ipv6': b.ipv6,
    'nameserver': directDNS,
    // 代理服务器域名的解析走直连 DNS（避免经代理解析节点的鸡生蛋问题）
    'proxy-server-nameserver': directDNS,
    // 解析 DNS 服务器自身的域名：主 + 备用（去重）
    'default-nameserver': _resolverNS(b),
  };
  if (b.dnsMode == dnsModeFakeIP) {
    dns['enhanced-mode'] = dnsModeFakeIP;
    dns['fake-ip-range'] = '198.18.0.1/16';
    // 白名单：规则集内域名真实解析，其余返回 fakeip
    dns['fake-ip-filter'] = ['rule-set:geosite-fakeipfilter'];
    dns['fake-ip-filter-mode'] = 'blacklist';
  } else {
    dns['enhanced-mode'] = dnsModeRedirHost;
  }

  Map<String, dynamic>? policy;
  switch (opts.mode) {
    case modeBypass:
      dns['nameserver'] = proxyDNS;
      policy = {
        'rule-set:geosite-private': directDNS,
        'rule-set:geosite-cn': directDNS,
      };
    case modeBlacklist:
      policy = {
        'rule-set:geosite-google': proxyDNS,
        'rule-set:geosite-gfw': proxyDNS,
        'rule-set:geosite-greatfire': proxyDNS,
      };
    case modeGlobal:
      // 全部走代理：默认 nameserver 也用代理 DNS，无代理域名规则集可写进策略
      dns['nameserver'] = proxyDNS;
  }
  if (policy != null && policy.isNotEmpty) {
    dns['nameserver-policy'] = policy;
  }
  return dns;
}

/// withProxySuffix mihomo 代理 DNS 追加 #PROXY 后缀（查询经代理组出站）。
List<String> _withProxySuffix(List<String> ss) => [
      for (final s in ss) s.contains('#') ? s : '$s#PROXY',
    ];

/// buildBuiltinMihomoSniffer 域名嗅探（三种模式固定）：让 TUN/redir-host 下的
/// 连接获得真实域名，域名类规则（RULE-SET geosite-* 等）才能命中。
Map<String, dynamic> _buildBuiltinMihomoSniffer() {
  return {
    'enable': true,
    'sniff': {
      'HTTP': {
        'ports': [80, '8080-8880'],
        'override-destination': true,
      },
      'TLS': {
        'ports': [443, 8443],
      },
      'QUIC': {
        'ports': [443, 8443],
      },
    },
  };
}

/// buildBuiltinMihomoTun TUN 配置（对齐 SetTunMihomo 写入的字段）。
Map<String, dynamic> _buildBuiltinMihomoTun(BuiltinOptions opts) {
  var stack = opts.tunStack;
  if (stack != 'gvisor' && stack != 'system' && stack != 'mixed') {
    stack = 'gvisor';
  }
  var mtu = opts.tunMTU;
  if (mtu <= 0) mtu = 9000;
  return {
    'enable': true,
    'stack': stack,
    'mtu': mtu,
    'auto-route': true,
    'auto-detect-interface': true,
    'dns-hijack': ['any:53'],
  };
}

/// appendBuiltinMihomoMixed 按系统代理开关写 mixed-port / allow-lan
/// （对齐 SetMixedInboundMihomo）。
void _appendBuiltinMihomoMixed(Map<String, dynamic> cfg, BuiltinOptions opts) {
  if (!opts.proxyEnabled) return;
  var port = opts.proxyPort;
  if (port <= 0) port = 2080;
  cfg['mixed-port'] = port;
  final allowLan = opts.proxyListen != '127.0.0.1';
  cfg['allow-lan'] = allowLan;
  if (allowLan) {
    cfg['bind-address'] = '*';
  }
}

/// appendBuiltinMihomoRoute 写 rule-providers（file 型 .mrs）与 rules
/// （对齐 sing-box 版顺序）。
void _appendBuiltinMihomoRoute(Map<String, dynamic> cfg, BuiltinOptions opts) {
  final dnsMode = opts.settings().dnsMode;
  // rule-providers：仅生成当前模式引用的条目
  final providers = <String, dynamic>{};
  for (final tag in mihomoRuleFiles(opts.mode, dnsMode)) {
    final behavior = isGeositeTag(tag) ? 'domain' : 'ipcidr';
    providers[tag] = {
      'type': 'file',
      'behavior': behavior,
      'format': 'mrs',
      'path': _pathJoin([opts.rulesDir, 'mrs', '$tag.mrs']),
    };
  }
  if (providers.isNotEmpty) {
    cfg['rule-providers'] = providers;
  }

  // 私网直连：private 规则集（geosite 匹配局域网域名，geoip 匹配私网 IP）
  final privateDirect = <String>[
    'RULE-SET,geosite-private,DIRECT',
    _mihomoIPRule('geoip-private', 'DIRECT'),
  ];

  const udpQUICReject = 'AND,((NETWORK,udp),(DST-PORT,443)),REJECT';
  final rules = <String>[];
  switch (opts.mode) {
    case modeBypass:
      rules.addAll([
        udpQUICReject,
        'RULE-SET,geosite-google,$mihomoGroupName',
      ]);
      rules.addAll(privateDirect);
      rules.addAll([
        'RULE-SET,geosite-cn,DIRECT',
        _mihomoIPRule('geoip-cn', 'DIRECT'),
        'MATCH,$mihomoGroupName',
      ]);
    case modeBlacklist:
      rules.addAll([
        'DOMAIN,api.ip.sb,$mihomoGroupName',
        udpQUICReject,
        'RULE-SET,geosite-google,$mihomoGroupName',
      ]);
      rules.addAll(privateDirect);
      for (final tag in [
        'geoip-facebook', 'geoip-fastly', 'geoip-google', //
        'geoip-netflix', 'geoip-telegram', 'geoip-twitter', //
      ]) {
        rules.add(_mihomoIPRule(tag, 'PROXY'));
      }
      rules.addAll([
        'RULE-SET,geosite-gfw,PROXY',
        'RULE-SET,geosite-greatfire,PROXY',
        'MATCH,DIRECT',
      ]);
    case modeGlobal:
      rules.add(udpQUICReject);
      rules.addAll(privateDirect);
      rules.add('MATCH,$mihomoGroupName');
  }
  cfg['rules'] = rules;
}

