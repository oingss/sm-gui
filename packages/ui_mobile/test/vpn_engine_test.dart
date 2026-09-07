// VpnEngine 平台通道契约测试：用 TestDefaultBinaryMessenger 拦截
// MethodChannel `sm_gui/vpn`，验证 start 携带 core/stack、isRunning 带 core。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sm_core/sm_core.dart' show coreMihomo, coreSingBox;
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_mobile/src/vpn_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sm_gui/vpn');

  late List<MethodCall> calls;
  // 每个测试用例自定义返回值
  Object? Function(MethodCall call) handler = (_) => null;

  setUp(() {
    calls = [];
    handler = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  VpnEngine newEngine() => VpnEngine(maxLog: 50);

  EngineRunConfig config(String core) => EngineRunConfig(
        core: core,
        binPath: '',
        runDir: '/tmp/run',
        configPath: '/tmp/run/config.yaml',
      );

  test('start 先 prepare 后 start，参数携带 configPath/core/stack', () async {
    handler = (call) => switch (call.method) {
          'prepare' => true,
          _ => null,
        };
    final engine = newEngine();
    engine.stackProvider = () => 'gvisor';
    addTearDown(engine.dispose);

    await engine.start(config(coreSingBox));

    expect(calls.map((c) => c.method).toList(), ['prepare', 'start']);
    expect(calls[1].arguments, {
      'configPath': '/tmp/run/config.yaml',
      'core': coreSingBox,
      'stack': 'gvisor',
    });
    // start 立即返回，乐观置为 starting
    expect(engine.phase, phaseStarting);
  });

  test('start 携带 mihomo 内核与注入的 stack', () async {
    handler = (call) => call.method == 'prepare' ? true : null;
    final engine = newEngine();
    engine.stackProvider = () => 'system';
    addTearDown(engine.dispose);

    await engine.start(config(coreMihomo));

    expect(calls[1].method, 'start');
    expect(calls[1].arguments['core'], coreMihomo);
    expect(calls[1].arguments['stack'], 'system');
  });

  test('stackProvider 未注入或返回空时 stack 回退 mixed', () async {
    handler = (call) => call.method == 'prepare' ? true : null;
    final engine = newEngine();
    addTearDown(engine.dispose);

    await engine.start(config(coreSingBox));
    expect(calls[1].arguments['stack'], 'mixed');

    calls.clear();
    engine.stackProvider = () => '  ';
    await engine.start(config(coreSingBox));
    expect(calls[1].arguments['stack'], 'mixed');
  });

  test('prepare 被拒绝时抛业务异常且不调用 start', () async {
    handler = (call) => call.method == 'prepare' ? false : null;
    final engine = newEngine();
    addTearDown(engine.dispose);

    await expectLater(
      engine.start(config(coreSingBox)),
      throwsA(isA<Exception>()),
    );
    expect(calls.map((c) => c.method), ['prepare']);
  });

  test('init 按契约携带 core 查询 isRunning 并同步阶段（运行中）', () async {
    handler = (call) => call.method == 'isRunning' ? true : null;
    final engine = newEngine();
    addTearDown(engine.dispose);

    await engine.init(core: coreMihomo);

    final isRunning = calls.where((c) => c.method == 'isRunning').toList();
    expect(isRunning, hasLength(1));
    expect(isRunning.single.arguments, {'core': coreMihomo});
    expect(engine.phase, phaseStarted);
  });

  test('init 查询 isRunning=false 时阶段为 stopped', () async {
    handler = (call) => call.method == 'isRunning' ? false : null;
    final engine = newEngine();
    addTearDown(engine.dispose);

    await engine.init(core: coreSingBox);
    expect(engine.phase, phaseStopped);
  });

  test('stop 调用一次 stop 方法并进入 stopping 阶段', () async {
    final engine = newEngine();
    addTearDown(engine.dispose);

    await engine.stop();

    expect(calls.map((c) => c.method).toList(), ['stop']);
    expect(engine.phase, phaseStopping);
  });
}
