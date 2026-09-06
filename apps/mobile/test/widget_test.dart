// SM GUI 移动端冒烟测试：临时目录构造真实 SmApp（VpnEngine 不 init，
// 不触碰平台通道），pump 主界面验证底部导航与各页基本渲染。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:ui_mobile/ui_mobile.dart';

void main() {
  late Directory tempDir;
  late SmApp app;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sm_mobile_test_');
    app = SmApp(
      dataDir: tempDir.path,
      engine: VpnEngine(maxLog: 100),
      vpnMode: true,
    );
    await app.init();
    // 预置两个节点便于列表渲染
    app.addNodesFromText(
      'ss://YWVzLTI1Ni1nY206dGVzdA@1.2.3.4:8388#测试节点A\n'
      'trojan://pass@example.com:443?sni=example.com#测试节点B',
      defaultGroupID,
      '',
    );
  });

  tearDown(() async {
    await app.dispose();
    await tempDir.delete(recursive: true);
    AppToast.dismiss();
  });

  Widget wrap() => ProviderScope(
        overrides: [smAppProvider.overrideWithValue(app)],
        child: MaterialApp(
          theme: buildSmTheme(),
          home: const SmMobileApp(),
        ),
      );

  testWidgets('主界面冒烟：底部导航 / 首页卡片 / 节点列表', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 首页：状态卡片
    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('点击连接'), findsOneWidget);
    expect(find.text('当前节点：未应用'), findsOneWidget);
    // 快速入口
    expect(find.text('订阅刷新'), findsOneWidget);
    expect(find.text('查看日志'), findsOneWidget);
    // 底部导航
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('节点'), findsOneWidget);
    expect(find.text('日志'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });

  testWidgets('节点页渲染分组与节点，长按弹出菜单', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.text('节点'));
    await tester.pumpAndSettle();

    expect(find.text('默认'), findsOneWidget);
    expect(find.text('测试节点A'), findsOneWidget);
    expect(find.text('测试节点B'), findsOneWidget);
    expect(find.text('导入节点'), findsOneWidget);

    // 长按节点 → 底部菜单
    await tester.longPress(find.text('测试节点A'));
    await tester.pumpAndSettle();
    expect(find.text('应用此节点'), findsOneWidget);
    expect(find.text('测试延迟'), findsOneWidget);
    expect(find.text('删除节点'), findsOneWidget);
  });

  testWidgets('日志页与设置页切换冒烟', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.text('日志'));
    await tester.pumpAndSettle();
    expect(find.text('暂无日志，连接后日志将在此显示'), findsOneWidget);

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    // 双内核：内核下拉可见（sing-box / mihomo），桌面概念（TUN/系统代理）仍隐藏
    expect(find.text('代理端口（mixed）'), findsOneWidget);
    expect(find.text('内核'), findsOneWidget);
    expect(find.text('sing-box'), findsOneWidget);
    expect(find.text('切换内核后需重新连接生效'), findsOneWidget);
    expect(find.text('路由模式'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(find.text('TUN 模式'), findsNothing);
    expect(find.text('系统代理'), findsNothing);
  });
}
