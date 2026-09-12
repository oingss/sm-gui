// SM GUI 桌面端冒烟测试：构造临时目录 SmApp，pump 主界面验证基本渲染。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sm_core/sm_core.dart';
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_desktop/ui_desktop.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  late Directory tempDir;
  late SmApp app;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sm_desktop_test_');
    app = SmApp(
      dataDir: tempDir.path,
      engine: DesktopEngine(maxLog: 100),
    );
    await app.init();
  });

  tearDown(() async {
    await app.dispose();
    await tempDir.delete(recursive: true);
  });

  testWidgets('主界面冒烟', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [smAppProvider.overrideWithValue(app)],
        child: MaterialApp(
          theme: buildSmTheme(),
          home: const SmDesktopApp(),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('节点列表'), findsWidgets);
    expect(find.text('运行日志'), findsOneWidget);
    expect(find.text('系统代理'), findsOneWidget);
    expect(find.text('TUN 模式'), findsOneWidget);
    expect(find.text('默认'), findsOneWidget);
  });
}
