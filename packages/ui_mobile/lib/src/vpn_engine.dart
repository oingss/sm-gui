/// VpnEngine — Android 平台通道桥接（implements sm_engine 的 Engine）。
///
/// 平台通道契约（Kotlin 侧按此实现，双内核：sing-box=libbox / mihomo=gomobile AAR）：
/// - MethodChannel `sm_gui/vpn`：
///   - prepare() → Future<bool>   请求 VPN 权限（弹系统授权页），true=已授权
///   - start(configPath: String, core: String, stack: String) → void
///     core 为 "sing-box" | "mihomo"（sm_core 的 coreSingBox/coreMihomo 常量），
///     stack 为 TUN 协议栈（settings.tunStack），Kotlin 按 core 路由到对应的
///     前台 VpnService 并建 TUN；立即返回，结果走事件流
///   - stop() → void  停止当前运行的内核（由 Kotlin 决定停哪个，Dart 只调一次）
///   - isRunning(core: String) → bool  按内核查询运行状态
/// - EventChannel `sm_gui/vpn/events`：Map 事件（双内核共用，不变）
///   - {type: 'status', status: 'starting'|'started'|'stopping'|'stopped'}
///   - {type: 'log', line: String}
///   - {type: 'error', message: String}
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sm_core/sm_core.dart' show AppException;
import 'package:sm_engine/sm_engine.dart';

/// VPN 运行阶段（原生事件流驱动，供 UI 展示「连接中/已连接/断开中/未连接」）。
const String phaseStopped = 'stopped';
const String phaseStarting = 'starting';
const String phaseStarted = 'started';
const String phaseStopping = 'stopping';

class VpnEngine implements Engine {
  static const MethodChannel _method = MethodChannel('sm_gui/vpn');
  static const EventChannel _events = EventChannel('sm_gui/vpn/events');

  ProcessStatus _status = const ProcessStatus();
  String _phase = phaseStopped;
  final List<String> _log = [];
  int _maxLog;

  final _logController = StreamController<String>.broadcast();
  final _statusController = StreamController<ProcessStatus>.broadcast();
  final _phaseController = StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _eventSub;

  VpnEngine({int maxLog = 500}) : _maxLog = maxLog < 1 ? 500 : maxLog;

  /// TUN 协议栈提供者：start 时随通道传给原生（Kotlin 据此建 TUN）。
  /// 由应用壳注入 `() => settings.tunStack`；未注入或返回空时回退 'mixed'。
  String Function()? stackProvider;

  String get _stack {
    final p = stackProvider;
    if (p != null) {
      final s = p();
      if (s.trim().isNotEmpty) return s;
    }
    return 'mixed';
  }

  /// 连接事件流并同步原生运行状态。应用启动时调用一次；
  /// 构造时不触碰平台通道，纯 Dart 测试（widget 冒烟）可直接实例化。
  /// [core] 为当前内核（coreSingBox/coreMihomo），按新契约随 isRunning 传递。
  Future<void> init({String? core}) async {
    _eventSub ??= _events.receiveBroadcastStream().listen(
          _onEvent,
          onError: (Object e) => _appendLog('[VPN] 事件流错误: $e'),
        );
    try {
      final running = await _method
          .invokeMethod<bool>('isRunning', {if (core != null) 'core': core});
      _setPhase(running == true ? phaseStarted : phaseStopped);
    } on PlatformException catch (e) {
      _appendLog('[VPN] 查询运行状态失败: ${e.message}');
    } on MissingPluginException {
      // 平台侧尚未实现（如纯 Dart 测试环境），忽略
    }
  }

  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _logController.close();
    _statusController.close();
    _phaseController.close();
  }

  // ─── 事件处理 ───────────────────────────────────────────────────────────────

  void _onEvent(Object? event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'status':
        final s = event['status'] as String? ?? phaseStopped;
        _setPhase(s);
      case 'log':
        final line = event['line'];
        if (line is String) _appendLog(line);
      case 'error':
        final msg = '${event['message']}';
        _appendLog('[错误] $msg');
        _status = ProcessStatus(running: _phase == phaseStarted, error: msg);
        _statusController.add(_status);
    }
  }

  void _setPhase(String phase) {
    _phase = phase;
    _status = ProcessStatus(running: phase == phaseStarted);
    _statusController.add(_status);
    _phaseController.add(phase);
    _appendLog('[VPN] 状态: $phase');
  }

  void _appendLog(String line) {
    _log.add(line);
    if (_log.length > _maxLog) {
      _log.removeRange(0, _log.length - _maxLog);
    }
    _logController.add(line);
  }

  // ─── Engine 接口实现 ────────────────────────────────────────────────────────

  @override
  Future<void> start(EngineRunConfig config) async {
    // 先请求 VPN 权限；被拒绝则抛业务异常（UI 统一 Toast）
    bool granted;
    try {
      granted = await _method.invokeMethod<bool>('prepare') == true;
    } on PlatformException catch (e) {
      throw AppException('请求 VPN 权限失败: ${e.message}');
    }
    if (!granted) {
      throw AppException('需要 VPN 权限');
    }
    try {
      await _method.invokeMethod<void>('start', {
        'configPath': config.configPath,
        'core': config.core,
        'stack': _stack,
      });
    } on PlatformException catch (e) {
      throw AppException('启动 VPN 服务失败: ${e.message}');
    }
    // start 立即返回，真正状态由事件流驱动；此处乐观置为 starting
    _setPhase(phaseStarting);
  }

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      throw AppException('停止 VPN 服务失败: ${e.message}');
    }
    _setPhase(phaseStopping);
  }

  @override
  ProcessStatus get status => _status;

  @override
  Stream<String> get logLines => _logController.stream;

  @override
  Stream<ProcessStatus> get statusChanges => _statusController.stream;

  @override
  List<String> get logSnapshot => List<String>.unmodifiable(_log);

  @override
  void setMaxLog(int maxLog) {
    if (maxLog <= 0) maxLog = 500;
    _maxLog = maxLog;
    if (_log.length > _maxLog) {
      _log.removeRange(0, _log.length - _maxLog);
    }
  }

  // ─── 移动端扩展（UI 展示细分阶段用）─────────────────────────────────────────

  /// 当前 VPN 阶段（stopped/starting/started/stopping）。
  String get phase => _phase;

  /// 阶段变化流（不含当前值；UI 侧先读 [phase] 再订阅）。
  Stream<String> get phaseChanges => _phaseController.stream;
}
