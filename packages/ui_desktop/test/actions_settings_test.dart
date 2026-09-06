// actions.dart 提权重启判断 + 设置弹窗保存流程（app.saveSettings）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sm_core/sm_core.dart';
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_desktop/src/actions.dart';
import 'package:ui_desktop/src/modals/settings_modal.dart';
import 'package:ui_desktop/src/providers.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  group('isElevationRestart', () {
    test('仅匹配提权重启消息', () {
      expect(
        isElevationRestart(AppException('正在以管理员身份重启程序…')),
        isTrue,
      );
      expect(isElevationRestart(AppException('未选择配置文件')), isFalse);
      expect(isElevationRestart(AppException('')), isFalse);
    });

    test('elevationRestartMessage 与 SmApp 抛出的消息一致', () {
      // 防止两侧文案漂移导致退出逻辑失效
      expect(elevationRestartMessage, '正在以管理员身份重启程序…');
    });
  });

  group('设置弹窗保存', () {
    late Directory tempDir;
    late SmApp app;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sm_gui_test_');
      app = SmApp(
        dataDir: tempDir.path,
        engine: DesktopEngine(maxLog: 100),
      );
      await app.init();
    });

    tearDown(() async {
      await app.dispose();
      await tempDir.delete(recursive: true);
      AppToast.dismiss();
    });

    Widget buildHost(WidgetTester tester) {
      // 设置弹窗内容很高（多行表单，测试字体 Ahem 行宽/行高偏大），
      // 放大测试视口保证整个弹窗可见；忽略仅测试字体导致的溢出异常
      tester.view.physicalSize = const Size(1000, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        final e = details.exception;
        if (e is FlutterError && e.message.contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);
      return ProviderScope(
        overrides: [smAppProvider.overrideWithValue(app)],
        child: MaterialApp(
          theme: buildSmTheme(),
          home: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => AppModal.show<void>(
                  ctx,
                  title: '设置',
                  width: 620,
                  builder: (_) => const SettingsModal(),
                ),
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      );
    }

    /// 弹窗内容在 maxHeight 720 的滚动区内，先把底部「保存」按钮滚进视野。
    Future<void> scrollSaveIntoView(WidgetTester tester) async {
      final scrollable = find
          .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
          .first;
      await tester.scrollUntilVisible(find.text('保存'), 250,
          scrollable: scrollable);
      await tester.pumpAndSettle();
    }

    testWidgets('保存成功：走 app.saveSettings 且弹「设置已保存」', (tester) async {
      await tester.pumpWidget(buildHost(tester));
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();

      // 新增的三组开关可见
      expect(find.text('开机自启动'), findsOneWidget);
      expect(find.text('静默启动'), findsOneWidget);
      expect(find.text('退出时关闭系统代理'), findsOneWidget);

      await scrollSaveIntoView(tester);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('设置已保存'), findsOneWidget);
      // 设置确实通过 saveSettings 写盘
      expect(File('${tempDir.path}/settings.json').existsSync(), isTrue);
      expect(app.settings.core, coreSingBox);
      // 推进 2.8s 让 Toast 计时器结束，避免测试结束时残留 pending timer
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('校验失败：弹窗保留并提示错误', (tester) async {
      await tester.pumpWidget(buildHost(tester));
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();

      // 日志行数改成非法值 30（合法范围 50-100000）→ validate 抛 ParseException
      // （saveSettings 会先 normalize 再 validate，端口类零值会被补默认，必须选非零非法值）
      final logField =
          find.ancestor(of: find.text('500'), matching: find.byType(TextField)).first;
      await tester.enterText(logField, '30');
      await scrollSaveIntoView(tester);
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(find.textContaining('保存失败'), findsOneWidget);
      // 弹窗未关闭
      expect(find.text('保存'), findsOneWidget);
      // 推进 2.8s 让 Toast 计时器结束，避免测试结束时残留 pending timer
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
