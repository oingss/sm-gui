/// Riverpod 状态层 — SmApp 单例 + 节点/分组/配置文件 AsyncNotifier +
/// 内核状态 StreamProvider + 日志 Notifier。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:sm_engine/sm_engine.dart';

/// SmApp 单例 provider。
/// 必须在 ProviderScope overrides 中注入（SmApp 在 main() 中
/// 完成 init 与规则集释放后再传下来）。
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

  /// 变更后刷新。
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

// ─── 系统代理 / TUN ──────────────────────────────────────────────────────────

class SysProxyNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() => ref.watch(smAppProvider).sysProxyEnabled();

  Future<void> reload() async {
    state = await AsyncValue.guard(
        () => ref.read(smAppProvider).sysProxyEnabled());
  }
}

final sysProxyProvider =
    AsyncNotifierProvider<SysProxyNotifier, bool>(SysProxyNotifier.new);

/// TUN 开关（读自 settings.tunEnabled，与设置版本联动）。
final tunEnabledProvider = Provider<bool>(
    (ref) => ref.watch(settingsProvider).tunEnabled);

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
