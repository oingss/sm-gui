/// 配置增量编辑测试 — 移植自 Go: backend/config/mihomo_test.go，
/// 并为 nodeToSingBoxOutbound / applyNodeToSingBoxConfig 补充代表性用例。
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:sm_core/src/config/editor.dart';
import 'package:sm_core/src/config/mihomo_edit.dart';
import 'package:sm_core/src/models/node.dart';
import 'package:sm_core/src/parsing/common.dart';
import 'package:sm_core/src/parsing/content.dart';

const mihomoTestCfg = '''mixed-port: 7890
proxies:
  - name: proxy
    type: ss
    server: old.example.com
    port: 8388
    cipher: aes-128-gcm
    password: oldpass
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - proxy
      - DIRECT
rules:
  - MATCH,PROXY
''';

const singBoxTestCfg = '''{
  "log": { "level": "info" },
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "shadowsocks", "tag": "proxy", "server": "old.example.com",
      "server_port": 8388, "method": "aes-128-gcm", "password": "oldpass" },
    { "type": "block", "tag": "block" }
  ]
}''';

/// 在系统临时目录写测试配置文件，测试结束后清理。
String writeTempFile(String content, {String name = 'config.yaml'}) {
  final dir = Directory.systemTemp.createTempSync('sm_config_editor_test_');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });
  final p = '${dir.path}${Platform.pathSeparator}$name';
  File(p).writeAsStringSync(content);
  return p;
}

// ─── mihomo（移植自 mihomo_test.go）───────────────────────────────────────────

void main() {
  group('mihomo 配置编辑（移植自 mihomo_test.go）', () {
    test('TestApplyNodeToMihomoConfig: 应用 hysteria2 节点并替换 proxy 条目', () {
      final p = writeTempFile(mihomoTestCfg);
      final n = Node(
        id: 'n1',
        name: 'test-hy2',
        address: '1.2.3.4',
        port: 443,
        protocol: 'hysteria2',
        hysteria2: Hysteria2Config(
          password: 'pw',
          sni: 'sni.example.com',
          upMbps: 30,
          downMbps: 200,
          insecure: true,
        ),
      );
      applyNodeToMihomoConfig(p, n);

      final cfg = loadYamlFile(p);
      final proxies = getProxies(cfg);
      expect(proxies.length, 1);
      final pr = proxies[0] as Map;
      expect(pr['name'], mihomoProxyName);
      expect(pr['type'], 'hysteria2');
      expect(pr['server'], '1.2.3.4');
      expect(pr['password'], 'pw');
      expect(pr['up'], 30);
      expect(pr['down'], 200);
      expect(pr['skip-cert-verify'], true);

      // PROXY 组仍引用 proxy
      final groups = cfg['proxy-groups'] as List;
      expect(groups.length, 1);
      final g = groups[0] as Map;
      final members = g['proxies'] as List;
      expect(members.contains(mihomoProxyName), isTrue);

      // 已应用节点可被识别
      expect(findAppliedNodeId(coreMihomo, p, [n]), 'n1');
      // 其他节点不应误判
      final other = Node(
        id: 'n2',
        name: 'test-hy2',
        address: '1.2.3.4',
        port: 443,
        protocol: 'hysteria2',
        hysteria2: Hysteria2Config(
          password: 'different',
          sni: 'sni.example.com',
          upMbps: 30,
          downMbps: 200,
          insecure: true,
        ),
      );
      expect(findAppliedNodeId(coreMihomo, p, [other]), '');
    });

    test('TestMihomoRawClashProxyRoundTrip: Clash YAML 导入的节点无损回写', () {
      final p = writeTempFile(mihomoTestCfg);
      const clashYaml = '''proxies:
  - name: raw-node
    type: vless
    server: 5.6.7.8
    port: 443
    uuid: uuid-123
    tls: true
    servername: example.com
    network: ws
    client-fingerprint: chrome
    ws-opts:
      path: /ws
      headers:
        Host: example.com
''';
      final nodes = parseContent(clashYaml);
      expect(nodes.length, 1);
      final n = nodes[0];
      expect(n.rawClashProxy, isNotNull);

      applyNodeToMihomoConfig(p, n);
      final cfg = loadYamlFile(p);
      final proxies = getProxies(cfg);
      expect(proxies.length, 1);
      final pr = proxies[0] as Map;
      expect(pr['name'], mihomoProxyName);
      expect(pr['uuid'], 'uuid-123');
      expect(pr['servername'], 'example.com');
      final ws = pr['ws-opts'] as Map;
      expect(ws['path'], '/ws');
      expect(findAppliedNodeId(coreMihomo, p, [n]), n.id);
    });

    test('applyNodeToMihomoConfig: 未知 transport 仍写 network（对齐 Go 行为）', () {
      // Go 版 clash_write.go applyClashTransport 在 switch 之前先写
      // p["network"] = t.Type，未知 transport 走 default 分支 return 时
      // network 已写入（Go 源码注释“未知 transport 不写 network”与实际行为不符，
      // 以实际行为为准）。此用例防止回退到“不写 network”的偏差实现。
      final p = writeTempFile(mihomoTestCfg);
      final n = Node(
        id: 'n9',
        name: 'vmess-unknown-tx',
        address: '9.9.9.9',
        port: 10086,
        protocol: 'vmess',
        vMess: VMessConfig(
          uuid: 'uuid-9',
          transport: TransportConfig(type: 'splithttp', path: '/x'),
        ),
      );
      applyNodeToMihomoConfig(p, n);

      final cfg = loadYamlFile(p);
      final pr = getProxies(cfg)[0] as Map;
      expect(pr['type'], 'vmess');
      expect(pr['network'], 'splithttp');
      // 未知 transport 不写 *-opts
      expect(pr.containsKey('splithttp-opts'), isFalse);
      expect(findAppliedNodeId(coreMihomo, p, [n]), 'n9');
    });

    test('TestMihomoTunAndMixed: TUN 开关与 mixed-port', () {
      final p = writeTempFile(mihomoTestCfg);

      // TUN 开启
      setTun(coreMihomo, p, true, 'system', 8500, true);
      expect(hasTunInbound(coreMihomo, p), isTrue);
      final cfg = loadYamlFile(p);
      final tun = cfg['tun'] as Map;
      expect(tun['stack'], 'system');
      expect(tun['mtu'], 8500);
      expect(tun['enable'], true);
      expect(tun.containsKey('strict_route'), isFalse);

      // TUN 关闭
      setTun(coreMihomo, p, false, '', 0, false);
      expect(hasTunInbound(coreMihomo, p), isFalse);

      // mixed-port + allow-lan
      setMixedInbound(coreMihomo, p, true, '0.0.0.0', 2081);
      final cfg2 = loadYamlFile(p);
      expect(cfg2['mixed-port'], 2081);
      expect(cfg2['allow-lan'], true);
      expect(cfg2['bind-address'], '*');
      // 关闭
      setMixedInbound(coreMihomo, p, false, '127.0.0.1', 0);
      final cfg3 = loadYamlFile(p);
      expect(cfg3.containsKey('mixed-port'), isFalse);
    });

    test('TestMihomoProxyGroupAutoCreate: 无 proxy-groups 时自动创建 PROXY 组', () {
      final p = writeTempFile('port: 7890\n');
      final n = Node(
        id: 'n1',
        name: 'ss-node',
        address: '1.1.1.1',
        port: 8388,
        protocol: 'ss',
        ss: SSConfig(method: 'aes-128-gcm', password: 'pw'),
      );
      // 走 applyNodeToConfig 分发，覆盖 mihomo 分支
      applyNodeToConfig(coreMihomo, p, n);
      final cfg = loadYamlFile(p);
      final groups = cfg['proxy-groups'] as List;
      expect(groups.length, 1);
      final g = groups[0] as Map;
      expect(g['name'], mihomoGroupName);
      expect(g['type'], 'select');
      expect(findAppliedNodeId(coreMihomo, p, [n]), 'n1');
    });
  });

  group('nodeToSingBoxOutbound 代表性协议', () {
    test('vmess + ws + tls（security 空串回退 auto，Host 进 headers）', () {
      final n = Node(
        id: 'x1',
        address: 'a.example.com',
        port: 443,
        protocol: 'vmess',
        vMess: VMessConfig(
          uuid: 'u-1',
          alterId: 0,
          security: '',
          tls: true,
          sni: 'sni.example.com',
          insecure: true,
          transport: TransportConfig(type: 'ws', path: '/ws', host: 'cdn.example.com'),
        ),
      );
      final ob = nodeToSingBoxOutbound(n);
      expect(ob['type'], 'vmess');
      expect(ob['uuid'], 'u-1');
      expect(ob['alter_id'], 0);
      expect(ob['security'], 'auto');
      final tr = ob['transport'] as Map;
      expect(tr['type'], 'ws');
      expect(tr['path'], '/ws');
      expect((tr['headers'] as Map)['Host'], 'cdn.example.com');
      final tls = ob['tls'] as Map;
      expect(tls['enabled'], true);
      expect(tls['server_name'], 'sni.example.com');
      expect(tls['insecure'], true);
    });

    test('vless + reality + grpc（utls 指纹默认 chrome，flow 输出）', () {
      final n = Node(
        id: 'x2',
        address: 'b.example.com',
        port: 443,
        protocol: 'vless',
        vless: VLESSConfig(
          uuid: 'u-2',
          flow: 'xtls-rprx-vision',
          tls: true,
          sni: 'www.apple.com',
          publicKey: 'pbk-xyz',
          shortId: 'abcd',
          transport: TransportConfig(type: 'grpc', serviceName: 'grpc-svc'),
        ),
      );
      final ob = nodeToSingBoxOutbound(n);
      expect(ob['type'], 'vless');
      expect(ob['flow'], 'xtls-rprx-vision');
      final tr = ob['transport'] as Map;
      expect(tr['type'], 'grpc');
      expect(tr['service_name'], 'grpc-svc');
      final tls = ob['tls'] as Map;
      final reality = tls['reality'] as Map;
      expect(reality['enabled'], true);
      expect(reality['public_key'], 'pbk-xyz');
      expect(reality['short_id'], 'abcd');
      // 未指定指纹时默认 chrome
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
      expect(tls.containsKey('insecure'), isFalse);
    });

    test('hysteria2（obfs + ECH，tls 必填 enabled）', () {
      final n = Node(
        id: 'x3',
        address: 'c.example.com',
        port: 443,
        protocol: 'hysteria2',
        hysteria2: Hysteria2Config(
          password: 'pw',
          sni: 's.example.com',
          upMbps: 10,
          downMbps: 100,
          obfs: 'salamander',
          obfsPassword: 'obfspw',
          echConfig: 'ECHCFG',
          insecure: true,
        ),
      );
      final ob = nodeToSingBoxOutbound(n);
      expect(ob['type'], 'hysteria2');
      expect(ob['password'], 'pw');
      expect(ob['up_mbps'], 10);
      expect(ob['down_mbps'], 100);
      final obfs = ob['obfs'] as Map;
      expect(obfs['type'], 'salamander');
      expect(obfs['password'], 'obfspw');
      final tls = ob['tls'] as Map;
      expect(tls['enabled'], true);
      expect(tls['server_name'], 's.example.com');
      expect(tls['insecure'], true);
      final ech = tls['ech'] as Map;
      expect(ech['enabled'], true);
      expect(ech['config'], 'ECHCFG');
    });

    test('rawOutbound 直通：原样返回并打上 proxy tag，不污染原数据', () {
      final raw = <String, dynamic>{
        'type': 'ssh',
        'server': 's.example.com',
        'server_port': 22,
        'user': 'root',
      };
      final n = Node(
        id: 'x4',
        name: 'ssh-node',
        address: 's.example.com',
        port: 22,
        protocol: 'ssh',
        rawOutbound: raw,
      );
      // 结构化转换不支持 ssh，必须走 rawOutbound 直通
      expect(() => nodeToSingBoxOutbound(n), throwsA(isA<ParseException>()));

      final ob = singBoxOutboundForNode(n);
      expect(ob['type'], 'ssh');
      expect(ob['tag'], 'proxy');
      expect(ob['user'], 'root');
      // 深拷贝：原节点数据未被打上 tag（Go 版直接引用会污染）
      expect(raw.containsKey('tag'), isFalse);
    });
  });

  group('sing-box 配置编辑', () {
    test('applyNodeToConfig(sing-box): 替换 proxy outbound 且可识别已应用节点', () {
      final p = writeTempFile(singBoxTestCfg, name: 'config.json');
      final n = Node(
        id: 'n1',
        name: 'test-hy2',
        address: '1.2.3.4',
        port: 443,
        protocol: 'hysteria2',
        hysteria2: Hysteria2Config(
          password: 'pw',
          sni: 'sni.example.com',
          upMbps: 30,
          downMbps: 200,
          insecure: true,
        ),
      );
      applyNodeToConfig(coreSingBox, p, n);

      final cfg = jsonDecode(File(p).readAsStringSync()) as Map;
      final outbounds = cfg['outbounds'] as List;
      expect(outbounds.length, 3);
      final proxy = outbounds[1] as Map;
      expect(proxy['tag'], 'proxy');
      expect(proxy['type'], 'hysteria2');
      expect(proxy['server'], '1.2.3.4');
      expect(proxy['server_port'], 443);
      expect(proxy['password'], 'pw');
      expect((proxy['tls'] as Map)['enabled'], true);
      expect((proxy['tls'] as Map)['insecure'], true);
      // 其他 outbound 保留
      expect((outbounds[0] as Map)['tag'], 'direct');
      expect((outbounds[2] as Map)['tag'], 'block');

      // 已应用节点可被识别；其他节点不误判
      expect(findAppliedNodeId(coreSingBox, p, [n]), 'n1');
      final other = Node(
        id: 'n2',
        name: 'test-hy2',
        address: '1.2.3.4',
        port: 443,
        protocol: 'hysteria2',
        hysteria2: Hysteria2Config(
          password: 'different',
          sni: 'sni.example.com',
          upMbps: 30,
          downMbps: 200,
          insecure: true,
        ),
      );
      expect(findAppliedNodeId(coreSingBox, p, [other]), '');
    });

    test('applyNodeToConfig(sing-box): 无 proxy outbound 时追加到末尾', () {
      final p = writeTempFile('{"outbounds": [{"type": "direct", "tag": "direct"}]}',
          name: 'config.json');
      final n = Node(
        id: 'n1',
        address: '1.1.1.1',
        port: 8388,
        protocol: 'ss',
        ss: SSConfig(method: 'aes-128-gcm', password: 'pw'),
      );
      applyNodeToSingBoxConfig(p, n);
      final cfg = jsonDecode(File(p).readAsStringSync()) as Map;
      final outbounds = cfg['outbounds'] as List;
      expect(outbounds.length, 2);
      expect((outbounds[1] as Map)['tag'], 'proxy');
      expect((outbounds[1] as Map)['type'], 'shadowsocks');
      expect(findAppliedNodeId(coreSingBox, p, [n]), 'n1');
    });

    test('setTun / setMixedInbound (sing-box): 开关与默认值', () {
      final p = writeTempFile('{"inbounds": []}', name: 'config.json');

      // TUN 开启
      setTun(coreSingBox, p, true, 'system', 8500, true);
      expect(hasTunInbound(coreSingBox, p), isTrue);
      var cfg = jsonDecode(File(p).readAsStringSync()) as Map;
      final tun = (cfg['inbounds'] as List).single as Map;
      expect(tun['type'], 'tun');
      expect(tun['tag'], 'tun-in');
      expect(tun['stack'], 'system');
      expect(tun['mtu'], 8500);
      expect(tun['strict_route'], true);
      expect(tun['address'], ['172.18.0.1/30']);

      // 非法 stack/mtu 回退默认值
      setTun(coreSingBox, p, true, 'bogus', 0, false);
      cfg = jsonDecode(File(p).readAsStringSync()) as Map;
      final tun2 = (cfg['inbounds'] as List).single as Map;
      expect(tun2['stack'], 'gvisor');
      expect(tun2['mtu'], 9000);
      expect(tun2['strict_route'], false);

      // TUN 关闭
      setTun(coreSingBox, p, false, '', 0, false);
      expect(hasTunInbound(coreSingBox, p), isFalse);

      // mixed inbound：空参数回退 127.0.0.1:2080
      setMixedInbound(coreSingBox, p, true, '', 0);
      cfg = jsonDecode(File(p).readAsStringSync()) as Map;
      final mixed = (cfg['inbounds'] as List).single as Map;
      expect(mixed['type'], 'mixed');
      expect(mixed['listen'], '127.0.0.1');
      expect(mixed['listen_port'], 2080);

      // 关闭
      setMixedInbound(coreSingBox, p, false, '127.0.0.1', 0);
      cfg = jsonDecode(File(p).readAsStringSync()) as Map;
      expect((cfg['inbounds'] as List), isEmpty);
    });

    test('removeNodeFromConfig: sing-box 移除 proxy 并回退 route.final', () {
      final p = writeTempFile('''{
  "outbounds": [
    { "type": "direct", "tag": "direct" },
    { "type": "shadowsocks", "tag": "proxy", "server": "s", "server_port": 1,
      "method": "aes-128-gcm", "password": "pw" }
  ],
  "route": { "final": "proxy" }
}''', name: 'config.json');
      removeNodeFromConfig(coreSingBox, p);
      final cfg = jsonDecode(File(p).readAsStringSync()) as Map;
      final outbounds = cfg['outbounds'] as List;
      expect(outbounds.length, 1);
      expect((outbounds[0] as Map)['tag'], 'direct');
      expect((cfg['route'] as Map)['final'], 'direct');

      // 未应用过时不动文件
      removeNodeFromConfig(coreSingBox, p);
      final cfg2 = jsonDecode(File(p).readAsStringSync()) as Map;
      expect((cfg2['outbounds'] as List).length, 1);
    });

    test('removeNodeFromConfig: mihomo 移除 proxy 并清理组引用', () {
      final p = writeTempFile(mihomoTestCfg);
      removeNodeFromConfig(coreMihomo, p);
      final cfg = loadYamlFile(p);
      expect(getProxies(cfg), isEmpty);
      final groups = cfg['proxy-groups'] as List;
      final members = (groups[0] as Map)['proxies'] as List;
      expect(members.contains(mihomoProxyName), isFalse);
      expect(members.contains('DIRECT'), isTrue);
    });

    test('坏配置文件抛 ParseException', () {
      final bad = writeTempFile('{ not json', name: 'config.json');
      expect(
          () => applyNodeToSingBoxConfig(bad,
              Node(id: 'x', protocol: 'ss', ss: SSConfig(method: 'm'))),
          throwsA(isA<ParseException>()));
      final badYaml = writeTempFile('a: [1, b: 2\n', name: 'config.yaml');
      expect(() => hasTunMihomo(badYaml), returnsNormally); // 读失败返回 false
      expect(hasTunMihomo('/nonexistent/path/config.yaml'), isFalse);
    });
  });
}
