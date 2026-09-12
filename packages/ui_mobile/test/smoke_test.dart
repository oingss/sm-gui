// ui_mobile 冒烟测试：用临时目录构造真实 SmApp + 假引擎（不触碰平台通道），
// 验证首页状态卡片与节点列表渲染。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sm_core/sm_core.dart';
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:ui_mobile/ui_mobile.dart';

/// 测试用假引擎：实现 Engine 接口，不触碰平台通道。
class FakeEngine implements Engine {
  final _logCtrl = StreamController<String>.broadcast();
  final _statusCtrl = StreamController<ProcessStatus>.broadcast();

  @override
  Future<void> start(EngineRunConfig config) async {
    _statusCtrl.add(const ProcessStatus(running: true, pid: 1));
  }

  @override
  Future<void> stop() async {
    _statusCtrl.add(const ProcessStatus());
  }

  @override
  ProcessStatus get status => const ProcessStatus();

  @override
  Stream<String> get logLines => _logCtrl.stream;

  @override
  Stream<ProcessStatus> get statusChanges => _statusCtrl.stream;

  @override
  List<String> get logSnapshot => const [];

  @override
  void setMaxLog(int maxLog) {}
}

void main() {
  late Directory tempDir;
  late SmApp app;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ui_mobile_test_');
    app = SmApp(
      dataDir: tempDir.path,
      engine: FakeEngine(),
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

  testWidgets('首页卡片：状态灯 / 连接按钮 / 当前节点', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('点击连接'), findsOneWidget);
    expect(find.text('当前节点：未应用'), findsOneWidget);
    expect(find.text('内核：sing-box'), findsOneWidget);
    expect(find.text('运行时长 00:00'), findsOneWidget);
    // 快速入口
    expect(find.text('订阅刷新'), findsOneWidget);
    expect(find.text('查看日志'), findsOneWidget);
  });

  testWidgets('节点列表渲染分组与节点', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.text('节点'));
    await tester.pumpAndSettle();

    expect(find.text('默认'), findsOneWidget);
    expect(find.text('测试节点A'), findsOneWidget);
    expect(find.text('测试节点B'), findsOneWidget);
    expect(find.text('1.2.3.4:8388'), findsOneWidget);
    expect(find.text('导入节点'), findsOneWidget);
  });

  testWidgets('设置页保存内核选择：mihomo 可保存并生效', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle(const Duration(seconds: 1));

    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    // 打开内核下拉，选择 mihomo
    await tester.tap(find.text('sing-box'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mihomo').last);
    await tester.pumpAndSettle();

    // 保存 → 走 app.saveSettings 流程，settings.core 持久化为 mihomo
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(app.settings.core, coreMihomo);

    // 推进时间让「设置已保存」Toast 的自动消失定时器走完，避免测试收尾时报挂起 Timer
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // 首页状态卡跟随显示当前内核名
    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(find.text('内核：mihomo'), findsOneWidget);
  });
}
