/// config 包测试 — 移植自 Go: backend/config/builtin_test.go + manager_test.go，
/// 用例数据原样照抄，作为移植验收标准。
///
/// Go 版对生成配置做精确字符串比较的地方，本移植改为「解析后结构比较」
/// （断言点一一对应），因此 sing-box JSON / mihomo YAML 的输出只需保证
/// 反序列化后结构等价。
library;

import 'dart:convert';
import 'dart:io';

import 'package:sm_core/src/config/builtin.dart';
import 'package:sm_core/src/config/settings.dart';
import 'package:sm_core/src/config/settings_manager.dart';
import 'package:sm_core/src/models/node.dart';
import 'package:sm_core/src/parsing/common.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

// ─── 测试辅助 ────────────────────────────────────────────────────────────────

Map<String, dynamic> parseJSONBytes(String data) =>
    (jsonDecode(data) as Map).cast<String, dynamic>();

Map<String, dynamic> parseYAMLBytes(String data) =>
    _yamlToDart(loadYaml(data)) as Map<String, dynamic>;

dynamic _yamlToDart(dynamic v) {
  if (v is YamlMap) {
    return {
      for (final e in v.entries) e.key.toString(): _yamlToDart(e.value),
    };
  }
  if (v is YamlList) return [for (final e in v) _yamlToDart(e)];
  return v;
}

List<String> toStringSlice(List<dynamic> v) => [for (final e in v) e as String];

/// 把 rule_set 字段拼成字符串便于断言（对应 Go 的 fmtJoin）。
String fmtJoin(dynamic v) {
  if (v is List) return toStringSlice(v).join(',');
  return '';
}

/// 临时目录（对应 Go 的 t.TempDir()）。
Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('sm_config_test_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  return dir;
}

/// 测试用节点（vless，带 RawOutbound / RawClashProxy 两条路径都覆盖）。
Node testNode() => Node(
      id: 'n1',
      protocol: 'vless',
      address: 'example.com',
      port: 443,
      vless: VLESSConfig(
        uuid: 'b831381d-6324-4d53-ad4f-8cda48b30811',
        tls: true,
        sni: 'example.com',
      ),
    );

// ─── 测试 ────────────────────────────────────────────────────────────────────

void main() {
  group('builtin', () {
    // TestBuiltinNameRoundTrip
    test('name round trip', () {
      for (final mode in [modeBypass, modeBlacklist, modeGlobal]) {
        final name = builtinDisplayName(mode);
        expect(name, isNotNull);
        expect(name, startsWith(builtinPrefix));
        final got = parseBuiltinName(name!);
        expect(got, mode);
      }
      expect(parseBuiltinName('config.json'), isNull,
          reason: '真实文件名不应被解析为内置模式');
      expect(isBuiltinMode(modeCustom), isFalse, reason: 'custom 不应被视为内置模式');
    });

    // TestCheckRuleFiles
    test('check rule files', () {
      final dir = tempDir();
      // redir-host：global 也要 private 两个
      expect(() => checkRuleFiles(modeGlobal, dnsModeRedirHost, dir.path),
          throwsA(predicate<ParseException>((e) =>
              e.toString().contains('geosite-private.mrs') &&
              e.toString().contains('geoip-private.mrs'))),
          reason: '空目录应报缺失');
      // fake-ip：额外要求 fakeipfilter
      expect(() => checkRuleFiles(modeGlobal, dnsModeFakeIP, dir.path),
          throwsA(predicate<ParseException>(
              (e) => e.toString().contains('geosite-fakeipfilter'))));

      // 补齐全部文件后两种 DNS 模式都通过
      for (final dnsMode in [dnsModeRedirHost, dnsModeFakeIP]) {
        for (final mode in [modeBypass, modeBlacklist, modeGlobal]) {
          for (final tag in builtinRuleFilesAll(mode, dnsMode)) {
            Directory('${dir.path}/srs').createSync(recursive: true);
            Directory('${dir.path}/mrs').createSync(recursive: true);
            File('${dir.path}/srs/$tag.srs').writeAsStringSync('x');
            File('${dir.path}/mrs/$tag.mrs').writeAsStringSync('x');
          }
        }
      }
      for (final dnsMode in [dnsModeRedirHost, dnsModeFakeIP]) {
        for (final mode in [modeBypass, modeBlacklist, modeGlobal]) {
          expect(() => checkRuleFiles(mode, dnsMode, dir.path), returnsNormally,
              reason: '补齐后不应报错');
        }
      }
    });

    // TestBuildBuiltinSingBox
    test('build builtin sing-box', () {
      final base = BuiltinOptions(
        tunStack: 'gvisor',
        tunMTU: 9000,
        tunStrictRoute: true,
        proxyEnabled: true,
        proxyListen: '127.0.0.1',
        proxyPort: 2080,
        rulesDir: '/run/rules',
        uiDir: '/run/ui',
        // cfg 为 null 时使用默认 BuiltinSettings
      );
      final cases = [
        (modeBypass, 'proxy', 'dns-proxy', 3),
        (modeBlacklist, 'direct', 'dns-direct', 9),
        (modeGlobal, 'proxy', 'dns-proxy', 0),
      ];
      for (final (mode, wantFinal, wantDNS, wantSets) in cases) {
        final opts = BuiltinOptions(
          mode: mode,
          tunEnabled: true,
          tunStack: base.tunStack,
          tunMTU: base.tunMTU,
          tunStrictRoute: base.tunStrictRoute,
          proxyEnabled: base.proxyEnabled,
          proxyListen: base.proxyListen,
          proxyPort: base.proxyPort,
          rulesDir: base.rulesDir,
          uiDir: base.uiDir,
        );
        final data = buildBuiltinConfig(coreSingBox, opts, testNode());
        final cfg = parseJSONBytes(data);
        final route = cfg['route'] as Map<String, dynamic>;
        expect(route['final'], wantFinal, reason: '[$mode] route.final');
        // default_domain_resolver 必须指向直连 DNS，且 IPv6 关闭时仅 IPv4
        final dds = route['default_domain_resolver'] as Map<String, dynamic>;
        expect(dds['server'], 'dns-direct', reason: '[$mode]');
        expect(dds['strategy'], 'ipv4_only', reason: '[$mode]');
        // sniff 必须是首条规则
        final rules = route['rules'] as List<dynamic>;
        final first = rules[0] as Map<String, dynamic>;
        expect(first['action'], 'sniff', reason: '[$mode] 首条规则应为 sniff');
        // TUN 开启 → 含 hijack-dns + auto_detect_interface
        final foundHijack = rules.any(
            (r) => r is Map && r['action'] == 'hijack-dns');
        expect(foundHijack, isTrue, reason: '[$mode] TUN 开启时应含 hijack-dns 规则');
        expect(route['auto_detect_interface'], true,
            reason: '[$mode] TUN 开启时应含 auto_detect_interface');
        // rule_set 数量与引用路径
        if (wantSets > 0) {
          final rs = route['rule_set'] as List<dynamic>;
          expect(rs, hasLength(wantSets), reason: '[$mode] rule_set 数量');
        } else {
          expect(route.containsKey('rule_set'), isFalse,
              reason: '[$mode] 不应生成 rule_set');
        }
        // DNS：final + server 标签
        final dns = cfg['dns'] as Map<String, dynamic>;
        expect(dns['final'], wantDNS, reason: '[$mode] dns.final');
        // 1.12 新格式：每个 DNS server 必须带 type 字段；直连/代理带 domain_resolver
        for (final s in dns['servers'] as List<dynamic>) {
          final sm = s as Map<String, dynamic>;
          expect(sm['type'], isNotNull, reason: '[$mode] dns server ${sm['tag']} 缺少 type');
          if (sm['tag'] == 'dns-direct' || sm['tag'] == 'dns-proxy') {
            final dr = sm['domain_resolver'] as Map<String, dynamic>?;
            expect(dr?['server'], 'dns-resolver',
                reason: '[$mode] dns server ${sm['tag']} 应含 domain_resolver→dns-resolver');
          }
        }
        // outbounds: proxy + direct
        final obs = cfg['outbounds'] as List<dynamic>;
        expect(obs, hasLength(2), reason: '[$mode] outbounds 应为 [proxy direct]');
        // 日志等级（warning → sing-box warn）/ clash-api
        final lg = cfg['log'] as Map<String, dynamic>;
        expect(lg['level'], 'warn', reason: '[$mode] log.level');
        final api = (cfg['experimental'] as Map<String, dynamic>)['clash_api']
            as Map<String, dynamic>;
        expect(api['external_controller'], '127.0.0.1:9090', reason: '[$mode]');
        expect(api['secret'], '', reason: '[$mode]');
        expect(api['external_ui'], '/run/ui',
            reason: '[$mode] clash_api.external_ui');
        // inbounds: mixed + tun
        final ibs = cfg['inbounds'] as List<dynamic>;
        final kinds = <String, bool>{};
        for (final ib in ibs) {
          final m = ib as Map<String, dynamic>;
          kinds[m['type'] as String] = true;
        }
        expect(kinds['mixed'], isTrue, reason: '[$mode] inbounds 应含 mixed+tun: $kinds');
        expect(kinds['tun'], isTrue, reason: '[$mode] inbounds 应含 mixed+tun: $kinds');
      }
    });

    // TestBuildBuiltinSingBoxFakeIP
    // fake-ip 模式：fakeipfilter 白名单 → 直连 DNS，其余 A/AAAA → fakeip
    test('build builtin sing-box fake-ip', () {
      final opts = BuiltinOptions(
        mode: modeBypass,
        rulesDir: '/run/rules',
        uiDir: '/run/ui',
        cfg: BuiltinSettings(dnsMode: dnsModeFakeIP),
      );
      final data = buildBuiltinConfig(coreSingBox, opts, testNode());
      final cfg = parseJSONBytes(data);
      final dns = cfg['dns'] as Map<String, dynamic>;

      // servers 含 fakeip
      final hasFakeIP = (dns['servers'] as List<dynamic>)
          .any((s) => (s as Map)['type'] == 'fakeip');
      expect(hasFakeIP, isTrue, reason: 'fake-ip 模式 servers 应含 fakeip server');
      // rules：白名单 → dns-direct，其后 A/AAAA → dns-fakeip
      final rules = dns['rules'] as List<dynamic>;
      final r0 = rules[0] as Map<String, dynamic>;
      expect(fmtJoin(r0['rule_set']), contains('geosite-fakeipfilter'));
      expect(r0['server'], 'dns-direct');
      final r1 = rules[1] as Map<String, dynamic>;
      expect(r1['action'], 'route');
      expect(r1['server'], 'dns-fakeip');
      // route 段 rule_set 应含 geosite-fakeipfilter
      final foundFilter = ((cfg['route']
                  as Map<String, dynamic>)['rule_set'] as List<dynamic>)
          .any((rs) => (rs as Map)['tag'] == 'geosite-fakeipfilter');
      expect(foundFilter, isTrue,
          reason: 'fake-ip 模式 route.rule_set 应含 geosite-fakeipfilter');
    });

    // TestBuildBuiltinSingBoxDNSFields
    // DNS 服务器字段：地址必填；端口/路径选填（端口零值时按类型补默认端口，
    // 保证配置到手即用）
    test('build builtin sing-box dns fields', () {
      final opts = BuiltinOptions(
        mode: modeGlobal,
        rulesDir: '/run/rules',
        cfg: BuiltinSettings(
          singBoxDirect: DNSServer(
              type: 'https', address: 'dns.alidns.com', path: '/dns-query'),
          singBoxProxy: DNSServer(type: 'udp', address: '8.8.8.8', port: 53),
        ),
      );
      final data = buildBuiltinConfig(coreSingBox, opts, testNode());
      final cfg = parseJSONBytes(data);
      final dns = cfg['dns'] as Map<String, dynamic>;
      for (final s in dns['servers'] as List<dynamic>) {
        final m = s as Map<String, dynamic>;
        switch (m['tag']) {
          case 'dns-direct':
            expect(m['server_port'], 443,
                reason: 'https 端口为 0 时应补默认 443: $m');
            expect(m['path'], '/dns-query', reason: 'https 直连 DNS 应带 path: $m');
          case 'dns-proxy':
            expect(m['server_port'], 53, reason: '代理 DNS 应带 server_port=53: $m');
            expect(m.containsKey('path'), isFalse,
                reason: '非 https 类型不应写 path: $m');
        }
      }
    });

    // TestBuildBuiltinSingBoxIPv6
    // IPv6 开关：TUN 地址补 IPv6 段 + 解析策略 prefer_ipv4
    test('build builtin sing-box ipv6', () {
      final opts = BuiltinOptions(
        mode: modeBypass,
        tunEnabled: true,
        rulesDir: '/run/rules',
        cfg: BuiltinSettings(dnsMode: dnsModeRedirHost, ipv6: true),
      );
      final data = buildBuiltinConfig(coreSingBox, opts, testNode());
      final cfg = parseJSONBytes(data);
      List<dynamic>? tunAddr;
      for (final ib in cfg['inbounds'] as List<dynamic>) {
        final m = ib as Map<String, dynamic>;
        if (m['type'] == 'tun') tunAddr = m['address'] as List<dynamic>;
      }
      expect(tunAddr, hasLength(2),
          reason: 'IPv6 开启时 TUN 地址应含 IPv6 段: $tunAddr');
      expect(tunAddr![1], 'fdfe:dcba:9876::1/126');
      final dds = (cfg['route'] as Map<String, dynamic>)['default_domain_resolver']
          as Map<String, dynamic>;
      expect(dds['strategy'], 'prefer_ipv4', reason: 'IPv6 开启时解析策略应为 prefer_ipv4');
    });

    // TestBuildBuiltinSingBoxInboundSwitches
    test('build builtin sing-box inbound switches', () {
      final opts = BuiltinOptions(mode: modeGlobal, rulesDir: '/run/rules');
      final data = buildBuiltinConfig(coreSingBox, opts, testNode());
      final cfg = parseJSONBytes(data);
      expect(cfg['inbounds'] as List<dynamic>, isEmpty,
          reason: 'TUN/代理全关时 inbounds 应为空');
      expect(
          (cfg['route'] as Map<String, dynamic>).containsKey('auto_detect_interface'),
          isFalse,
          reason: 'TUN 关闭时不应有 auto_detect_interface');
    });

    // TestBuildBuiltinMihomo
    test('build builtin mihomo', () {
      final base = BuiltinOptions(
        tunStack: 'gvisor',
        tunMTU: 9000,
        proxyEnabled: true,
        proxyListen: '127.0.0.1',
        proxyPort: 2080,
        rulesDir: '/run/rules',
        uiDir: '/run/ui',
      );
      final cases = [
        // mode, wantMatch, wantSets, wantBypass（绕过大陆应有 geosite-cn 直连）
        (modeBypass, 'MATCH,PROXY', 5, true),
        (modeBlacklist, 'MATCH,DIRECT', 11, false),
        (modeGlobal, 'MATCH,PROXY', 2, false),
      ];
      for (final (mode, wantMatch, wantSets, wantBypass) in cases) {
        final opts = BuiltinOptions(
          mode: mode,
          tunEnabled: true,
          tunStack: base.tunStack,
          tunMTU: base.tunMTU,
          proxyEnabled: base.proxyEnabled,
          proxyListen: base.proxyListen,
          proxyPort: base.proxyPort,
          rulesDir: base.rulesDir,
          uiDir: base.uiDir,
        );
        final data = buildBuiltinConfig(coreMihomo, opts, testNode());
        final cfg = parseYAMLBytes(data);
        // rules 末条 MATCH
        final rules = toStringSlice(cfg['rules'] as List<dynamic>);
        expect(rules.last, wantMatch, reason: '[$mode] 末条规则');
        // 私网直连走 private 规则集（不再内联 CIDR）
        final rulesSet = rules.toSet();
        expect(rulesSet.contains('RULE-SET,geosite-private,DIRECT'), isTrue,
            reason: '[$mode] 应含 RULE-SET,geosite-private,DIRECT');
        expect(rulesSet.contains('RULE-SET,geoip-private,DIRECT,no-resolve'),
            isTrue, reason: '[$mode] 应含 RULE-SET,geoip-private,DIRECT,no-resolve');
        // no-resolve 策略：仅 geoip-cn 不加
        if (wantBypass) {
          expect(rulesSet.contains('RULE-SET,geoip-cn,DIRECT'), isTrue,
              reason: '[$mode] geoip-cn 规则应不带 no-resolve');
        }
        // rule-providers
        if (wantSets > 0) {
          final providers =
              cfg['rule-providers'] as Map<String, dynamic>;
          expect(providers, hasLength(wantSets), reason: '[$mode] rule-providers 数量');
          providers.forEach((name, p) {
            final pm = p as Map<String, dynamic>;
            expect(pm['type'], 'file', reason: '[$mode] provider $name 应为 file/mrs');
            expect(pm['format'], 'mrs', reason: '[$mode] provider $name 应为 file/mrs');
            final wantBehavior = isGeositeTag(name) ? 'domain' : 'ipcidr';
            expect(pm['behavior'], wantBehavior,
                reason: '[$mode] provider $name behavior');
          });
        } else {
          expect(cfg.containsKey('rule-providers'), isFalse,
              reason: '[$mode] 不应生成 rule-providers');
        }
        // 绕过大陆：geosite-cn 直连存在且在 MATCH 之前
        if (wantBypass) {
          final idxCN = rules.indexOf('RULE-SET,geosite-cn,DIRECT');
          final idxMatch = rules.indexOf(wantMatch);
          expect(idxCN, greaterThanOrEqualTo(0),
              reason: '[$mode] geosite-cn 直连规则缺失或顺序错误');
          expect(idxCN <= idxMatch, isTrue,
              reason: '[$mode] geosite-cn 直连规则缺失或顺序错误');
        }
        // proxies / proxy-groups / tun / mixed-port
        final proxies = cfg['proxies'] as List<dynamic>;
        expect(proxies, hasLength(1), reason: '[$mode] proxies 应只含 name=proxy 条目');
        expect((proxies[0] as Map<String, dynamic>)['name'], mihomoProxyName,
            reason: '[$mode] proxies 应只含 name=proxy 条目');
        expect(cfg['mixed-port'], 2080, reason: '[$mode] mixed-port');
        final tun = cfg['tun'] as Map<String, dynamic>;
        expect(tun['enable'], true, reason: '[$mode] tun 配置不完整');
        expect(tun['auto-route'], true, reason: '[$mode] tun 配置不完整');
        // 日志等级 / clash-api / ipv6
        expect(cfg['log-level'], 'warning', reason: '[$mode] log-level');
        expect(cfg['external-controller'], '127.0.0.1:9090', reason: '[$mode] clash-api');
        expect(cfg['secret'], '', reason: '[$mode] clash-api');
        expect(cfg['external-ui'], '/run/ui', reason: '[$mode] external-ui');
        expect(cfg['ipv6'], false, reason: '[$mode] 默认 ipv6 应为 false');
        // sniffer（三种模式固定）
        final sn = cfg['sniffer'] as Map<String, dynamic>?;
        expect(sn?['enable'], true, reason: '[$mode] sniffer 应存在且启用');
        // DNS：redir-host + nameserver-policy 分流
        _assertMihomoDNS(mode, cfg['dns']);
      }
    });

    // TestBuildBuiltinMihomoFakeIP
    // fake-ip 模式：fake-ip-filter 引用 fakeipfilter 规则集
    test('build builtin mihomo fake-ip', () {
      final opts = BuiltinOptions(
        mode: modeBypass,
        rulesDir: '/run/rules',
        cfg: BuiltinSettings(dnsMode: dnsModeFakeIP, ipv6: true),
      );
      final data = buildBuiltinConfig(coreMihomo, opts, testNode());
      final cfg = parseYAMLBytes(data);
      final dns = cfg['dns'] as Map<String, dynamic>;
      expect(dns['enhanced-mode'], 'fake-ip');
      final filter = toStringSlice(dns['fake-ip-filter'] as List<dynamic>);
      expect(filter, ['rule-set:geosite-fakeipfilter']);
      expect(dns['ipv6'], true, reason: 'IPv6 开启时顶层与 dns 的 ipv6 都应为 true');
      expect(cfg['ipv6'], true, reason: 'IPv6 开启时顶层与 dns 的 ipv6 都应为 true');
      // rule-providers 应含 geosite-fakeipfilter
      final providers = cfg['rule-providers'] as Map<String, dynamic>;
      expect(providers.containsKey('geosite-fakeipfilter'), isTrue,
          reason: 'fake-ip 模式 rule-providers 应含 geosite-fakeipfilter');
    });

    // TestBuildBuiltinClashAPIDisabled
    // 关闭 clash-api：双内核完全不生成 clash-api 字段
    // （sing-box 的 cache_file 与 clash-api 无关，仍然生成）
    test('build builtin clash-api disabled', () {
      final opts = BuiltinOptions(
        mode: modeBypass,
        rulesDir: '/run/rules',
        cachePath: '/run/cache.db',
        cfg: BuiltinSettings(dnsMode: dnsModeRedirHost, clashAPIDisabled: true),
      );
      final data = buildBuiltinConfig(coreSingBox, opts, testNode());
      var cfg = parseJSONBytes(data);
      final exp = cfg['experimental'] as Map<String, dynamic>;
      expect(exp.containsKey('clash_api'), isFalse,
          reason: 'clash-api 关闭时 sing-box 不应生成 clash_api 段');
      final cf = exp['cache_file'] as Map<String, dynamic>;
      expect(cf['enabled'], true, reason: 'cache_file 配置错误');
      expect(cf['store_fakeip'], false, reason: 'cache_file 配置错误');
      expect(cf['path'], '/run/cache.db', reason: 'cache_file.path');
      final data2 = buildBuiltinConfig(coreMihomo, opts, testNode());
      cfg = parseYAMLBytes(data2);
      for (final k in ['external-controller', 'external-ui', 'secret']) {
        expect(cfg.containsKey(k), isFalse,
            reason: 'clash-api 关闭时 mihomo 不应生成 $k');
      }
    });

    // TestBuildBuiltinSingBoxCacheFileFakeIP
    // fake-ip 模式下 store_fakeip 应为 true
    test('build builtin sing-box cache file fake-ip', () {
      final opts = BuiltinOptions(
        mode: modeBypass,
        rulesDir: '/run/rules',
        cachePath: '/run/cache.db',
        cfg: BuiltinSettings(dnsMode: dnsModeFakeIP),
      );
      final data = buildBuiltinConfig(coreSingBox, opts, testNode());
      final cfg = parseJSONBytes(data);
      final cf = ((cfg['experimental'] as Map<String, dynamic>)['cache_file']
          as Map<String, dynamic>);
      expect(cf['store_fakeip'], true, reason: 'fake-ip 模式 store_fakeip 应为 true');
    });

    // TestBuildBuiltinErrors
    test('build builtin errors', () {
      final opts = BuiltinOptions(mode: modeBypass, rulesDir: '/run/rules');
      // 无节点
      expect(() => buildBuiltinConfig(coreSingBox, opts, null), throwsA(anything),
          reason: '无节点应报错');
      // 非内置模式
      expect(
          () => buildBuiltinConfig(coreSingBox,
              BuiltinOptions(mode: modeCustom), testNode()),
          throwsA(anything),
          reason: 'custom 模式不应生成内置配置');
    });

    // TestSettingsRoutingModeDefaults
    test('settings routing mode defaults', () {
      var s = Settings();
      s.applyDefaults();
      expect(s.routingMode, modeCustom, reason: '缺省路由模式应为 custom');
      // builtin 段默认值
      expect(s.builtin.logLevel, 'warning', reason: 'builtin 默认值错误');
      expect(s.builtin.dnsMode, 'redir-host', reason: 'builtin 默认值错误');
      expect(s.builtin.clashAPI.port, 9090, reason: 'builtin 默认值错误');
      // 全新默认设置必须带完整 builtin 段（此前全新安装漏填，界面显示全 0）
      final d = Settings.defaults();
      expect(d.builtin.clashAPI.port, 9090, reason: 'Defaults() 的 builtin 段缺省');
      expect(d.builtin.resolverDNS, isNotEmpty, reason: 'Defaults() 的 builtin 段缺省');
      expect(d.builtin.resolverDNSBackup, isNotEmpty,
          reason: 'Defaults() 的 builtin 段缺省');
      // 解析 DNS 备用默认值
      expect(s.builtin.resolverDNSBackup, '119.29.29.29', reason: '解析 DNS 备用默认值错误');
      // Validate 拒绝非法值
      s.routingMode = 'bogus';
      expect(() => s.validate(), throwsA(isA<ParseException>()),
          reason: '非法路由模式应校验失败');

      s = Settings();
      s.applyDefaults();
      s.builtin.dnsMode = 'bogus';
      expect(() => s.validate(), throwsA(isA<ParseException>()),
          reason: '非法 DNS 模式应校验失败');

      s = Settings();
      s.applyDefaults();
      s.builtin.resolverDNS = 'not-an-ip';
      expect(() => s.validate(), throwsA(isA<ParseException>()),
          reason: '解析 DNS 非 IP 应校验失败');

      s = Settings();
      s.applyDefaults();
      s.builtin.resolverDNSBackup = 'not-an-ip';
      expect(() => s.validate(), throwsA(isA<ParseException>()),
          reason: '解析 DNS 备用非 IP 应校验失败');

      s = Settings();
      s.applyDefaults();
      s.builtin.clashAPI.port = 0;
      expect(() => s.validate(), throwsA(isA<ParseException>()),
          reason: 'clash-api 端口为 0 应校验失败');
    });
  });

  group('manager', () {
    // TestSettingsPathAndBuiltinDefaults（manager_test.go）
    // settings.json 只存 configs 目录下的文件名；builtin 段缺省补默认；
    // clash_api_disabled 反转语义：缺省 false = 启用，显式关闭后往返保持。
    test('settings path and builtin defaults', () {
      final dir = tempDir();
      const old = '''
{
  "core": "sing-box",
  "config_path": "",
  "config_path_singbox": "config.json",
  "config_path_mihomo": "white.yaml",
  "routing_mode": "custom"
}''';
      File('${dir.path}/settings.json').writeAsStringSync(old);
      var m = SettingsManager('${dir.path}/settings.json');
      m.load();
      final s = m.settings;
      expect(s.configPathSingBox, 'config.json', reason: '路径应保持文件名');
      expect(s.configPathMihomo, 'white.yaml', reason: '路径应保持文件名');
      // builtin 缺段 → 全默认（clash-api 默认启用）
      expect(s.builtin.logLevel, 'warning', reason: 'builtin 默认值错误');
      expect(s.builtin.clashAPIDisabled, false, reason: 'builtin 默认值错误');
      // 保存/重载往返
      s.setCoreConfigPath(coreSingBox, 'config.json');
      m.save();
      var m2 = SettingsManager('${dir.path}/settings.json');
      m2.load();
      expect(m2.settings.configPathSingBox, 'config.json',
          reason: '重新加载后 config_path_singbox');
      expect(m2.settings.builtin.clashAPIDisabled, false,
          reason: '缺省 clash_api_disabled 应为 false（启用）');
      // 显式关闭后往返保持关闭
      m2.settings.builtin.clashAPIDisabled = true;
      m2.save();
      final m3 = SettingsManager('${dir.path}/settings.json');
      m3.load();
      expect(m3.settings.builtin.clashAPIDisabled, true,
          reason: '显式关闭的 clash_api_disabled 重载后应保持 true');
    });
  });
}

/// assertMihomoDNS 校验各模式 mihomo DNS：redir-host + nameserver-policy 分流策略。
/// （移植自 Go: builtin_test.go assertMihomoDNS）
void _assertMihomoDNS(String mode, dynamic dnsV) {
  final dns = dnsV as Map<String, dynamic>?;
  expect(dns, isNotNull, reason: '[$mode] dns 段缺失');
  expect(dns!['enable'], true, reason: '[$mode] dns 应为启用的 redir-host 模式');
  expect(dns['enhanced-mode'], 'redir-host',
      reason: '[$mode] dns 应为启用的 redir-host 模式');
  const direct = ['223.5.5.5', '119.29.29.29'];
  const proxy = ['1.1.1.1#PROXY', '8.8.8.8#PROXY'];
  final policy = dns['nameserver-policy'] as Map<String, dynamic>?;
  final hasPolicy = dns.containsKey('nameserver-policy');
  switch (mode) {
    case modeBypass:
      expect((dns['nameserver'] as List<dynamic>)[0], proxy[0],
          reason: '[$mode] nameserver 应为代理 DNS');
      expect(
          hasPolicy &&
              ((policy!['rule-set:geosite-cn'] as List<dynamic>).length == 2),
          isTrue,
          reason: '[$mode] nameserver-policy 应含 rule-set:geosite-cn → 直连 DNS');
    case modeBlacklist:
      expect((dns['nameserver'] as List<dynamic>)[0], direct[0],
          reason: '[$mode] nameserver 应为直连 DNS');
      expect(
          hasPolicy &&
              ((policy!['rule-set:geosite-gfw'] as List<dynamic>).length == 2),
          isTrue,
          reason: '[$mode] nameserver-policy 应含 rule-set:geosite-gfw → 代理 DNS');
      expect(policy?.containsKey('rule-set:geosite-cn'), isFalse,
          reason: '[$mode] blacklist 不应把 cn 规则集写进 DNS 策略');
    case modeGlobal:
      // 全部走代理：默认 nameserver 也是代理 DNS
      expect((dns['nameserver'] as List<dynamic>)[0], proxy[0],
          reason: '[$mode] nameserver 应为代理 DNS');
      expect(hasPolicy, isFalse, reason: '[$mode] global 不应有 nameserver-policy');
  }
}
