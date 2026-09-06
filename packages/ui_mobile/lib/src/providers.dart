/// Riverpod 状态层（移动端）— 组织方式对齐 ui_desktop/providers.dart：
/// SmApp 单例 + 设置版本号 + 节点/分组/配置文件 AsyncNotifier +
/// 内核状态 StreamProvider + 日志 Notifier + VPN 阶段 + 底部导航索引。
/// 移动端不提供系统代理/TUN provider（桌面专属概念已隐藏）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:sm_engine/sm_engine.dart';

import 'vpn_engine.dart';

/// SmApp 单例 provider。
/// 必须在 ProviderScope overrides 中注入（SmApp 构造需要 path_provider，
/// 由 app 壳在 main() 中先完成再传下来）。
final smAppProvider = Provider<SmApp>((ref) {
  throw UnimplementedError('smAppProvider 必须在应用启动时注入');
});

// ─── 设置 ────────────────────────────────────────────────────────────────────

/// 设置版本号：Settings 是可变对象，字段变化后 bump 触发依赖刷新。
class SettingsVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final settingsVersionProvider =
    NotifierProvider<SettingsVersion, int>(SettingsVersion.new);

/// 当前设置（读取 + 版本联动）。
final settingsProvider = Provider<Settings>((ref) {
  ref.watch(settingsVersionProvider);
  return ref.watch(smAppProvider).settings;
});

// ─── 节点 / 分组 / 配置文件 ─────────────────────────────────────────────────

class NodesNotifier extends AsyncNotifier<List<Node>> {
  @override
  Future<List<Node>> build() async => ref.watch(smAppProvider).allNodes();

  Future<void> reload() async {
    state = await AsyncValue.guard(() async => ref.read(smAppProvider).allNodes());
  }
}

final nodesProvider =
    AsyncNotifierProvider<NodesNotifier, List<Node>>(NodesNotifier.new);

class GroupsNotifier extends AsyncNotifier<List<Group>> {
  @override
  Future<List<Group>> build() async => ref.watch(smAppProvider).allGroups();

  Future<void> reload() async {
    state =
        await AsyncValue.guard(() async => ref.read(smAppProvider).allGroups());
  }
}

final groupsProvider =
    AsyncNotifierProvider<GroupsNotifier, List<Group>>(GroupsNotifier.new);

class ConfigFilesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async =>
      ref.watch(smAppProvider).listConfigFiles();

  Future<void> reload() async {
    state = await AsyncValue.guard(
        () => ref.read(smAppProvider).listConfigFiles());
  }
}

final configFilesProvider =
    AsyncNotifierProvider<ConfigFilesNotifier, List<String>>(
        ConfigFilesNotifier.new);

// ─── 内核状态 / 日志 ─────────────────────────────────────────────────────────

/// 内核状态流：先吐当前状态，再跟随状态变化。
final coreStatusProvider = StreamProvider<ProcessStatus>((ref) async* {
  final app = ref.watch(smAppProvider);
  yield app.coreStatus;
  await for (final s in app.coreStatusChanges) {
    yield s;
  }
});

/// VPN 细分阶段流（stopped/starting/started/stopping）：
/// VpnEngine 提供事件流驱动；非 VpnEngine 引擎回退为 running 布尔映射。
final enginePhaseProvider = StreamProvider<String>((ref) async* {
  final app = ref.watch(smAppProvider);
  final engine = app.engine;
  if (engine is VpnEngine) {
    yield engine.phase;
    await for (final p in engine.phaseChanges) {
      yield p;
    }
    return;
  }
  yield app.coreStatus.running ? phaseStarted : phaseStopped;
  await for (final s in app.coreStatusChanges) {
    yield s.running ? phaseStarted : phaseStopped;
  }
});

/// 日志列表：初始为快照，之后增量追加。
class LogController extends Notifier<List<String>> {
  StreamSubscription<String>? _sub;

  @override
  List<String> build() {
    final app = ref.watch(smAppProvider);
    _sub?.cancel();
    _sub = app.coreLogLines.listen(_append);
    ref.onDispose(() => _sub?.cancel());
    return List.of(app.coreLogSnapshot);
  }

  void _append(String line) {
    state = [...state, line];
  }

  /// 界面「清空」按钮：只清显示缓冲。
  void clear() => state = const [];
}

final logProvider = NotifierProvider<LogController, List<String>>(
    LogController.new);

// ─── 应用节点 ────────────────────────────────────────────────────────────────

/// 当前应用的节点 ID。
final appliedIdProvider =
    Provider<String>((ref) => ref.watch(settingsProvider).appliedNodeID);

/// 当前应用的节点对象（可能为 null）。
final appliedNodeProvider = Provider<Node?>((ref) {
  final id = ref.watch(appliedIdProvider);
  if (id.isEmpty) return null;
  final nodes = ref.watch(nodesProvider).value;
  if (nodes == null) return null;
  for (final n in nodes) {
    if (n.id == id) return n;
  }
  return null;
});

// ─── 底部导航 ────────────────────────────────────────────────────────────────

/// 底部导航索引：0 首页 / 1 节点 / 2 日志 / 3 设置。
final tabIndexProvider = StateProvider<int>((ref) => 0);
