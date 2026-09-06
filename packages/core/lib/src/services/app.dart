/// 应用门面 — 移植自 Go: app.go 的核心流程（startCore/syncRunConfig/
/// generateBuiltinRunConfig/TUN 与系统代理开关/订阅刷新/ApplyNode）。
/// 纯 Dart，供两套 UI 共用；UI 层用 Riverpod 包一层即可。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sm_engine/sm_engine.dart';

import '../config/builtin.dart';
import '../config/editor.dart' hide coreMihomo, coreSingBox;
import '../config/settings.dart';
import '../config/settings_manager.dart';
import '../export/node_export.dart' show nodeToUri;
import '../models/group.dart';
import '../models/node.dart';
import '../parsing/content.dart';
import '../storage/store.dart';
import 'probe.dart';
import 'real_probe.dart';

/// 应用级异常（对应 Go 的 guardE 包装）。
class AppException implements Exception {
  final String message;
  AppException(this.message);

  @override
  String toString() => message;
}

/// SM GUI 应用门面：节点/分组/订阅/配置/内核进程 的统一入口。
class SmApp {
  final String dataDir;

  /// 程序根目录（桌面端 portable 布局，对齐 Go 版）：
  /// configs/run/bin 与 data 同级（都在 exe 旁边）。
  /// 未设置（移动端）时所有目录仍在 dataDir 内（原行为）。
  final String? appRootDir;
  final Engine engine;
  final SysProxyManager proxy;

  /// Android VPN 模式：startCore 强制 tun 入站（全机 VPN），
  /// 不检查内核二进制（libbox 嵌入在宿主进程内），不涉及系统代理/提权。
  final bool vpnMode;

  late final NodeStore store;
  late final SettingsManager cfgManager;

  /// 目录基准：appRootDir 设置时（桌面端）configs/run/bin 与 data 同级，
  /// 未设置时（移动端）都在 dataDir 内。
  String get _baseDir => appRootDir ?? dataDir;

  String get runDir => _join(_baseDir, 'run');
  String get configsDir => _join(_baseDir, 'configs');
  String get binDir => _join(_baseDir, 'bin');
  String get rulesDir => _join(runDir, 'rules');

  SmApp({
    required this.dataDir,
    this.appRootDir,
    required this.engine,
    this.vpnMode = false,
    SysProxyManager? sysProxy,
  }) : proxy = sysProxy ?? SysProxyManager() {
    store = NodeStore(_join(dataDir, 'nodes.db'));
    cfgManager = SettingsManager(_join(dataDir, 'settings.json'));
  }

  Settings get settings => cfgManager.settings;

  /// 初始化：建目录、加载存储与设置。UI 启动时调用一次。
  /// 建目录对齐 Go 版 startup：data / configs / run 三个（bin 不预建）。
  Future<void> init() async {
    for (final d in [dataDir, runDir, configsDir]) {
      await Directory(d).create(recursive: true);
    }
    store.load();
    cfgManager.load();
    unawaited(_restoreAfterElevation());
    // 订阅自动更新定时器（每分钟检查一次）
    _subTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkAutoUpdates();
    });
  }

  Future<void> dispose() async {
    _subTimer?.cancel();
    store.close();
  }

  // ─── 目录与路径 ────────────────────────────────────────────────────────────

  String coreBinPath(String core) =>
      _join(binDir, core == coreMihomo ? 'mihomo.exe' : 'sing-box.exe');

  String runConfigPath(String core) =>
      _join(runDir, core == coreMihomo ? 'config.yaml' : 'config.json');

  String currentConfigPath() {
    final name = settings.activeConfigPath();
    if (name.isEmpty) return '';
    return _join(configsDir, name);
  }

  // ─── 配置同步（app.go: syncRunConfig / generateBuiltinRunConfig）───────────

  /// 把当前配置同步到 run 目录（先清除旧配置）：
  /// 内置模式由模板 + 已应用节点合成；custom 模式原样复制选中配置文件。
  Future<void> syncRunConfig(String core, String srcPath) async {
    if (isBuiltinMode(settings.routingMode)) {
      if (vpnMode) {
        await _generateVpnRunConfig(core);
        return;
      }
      await _generateBuiltinRunConfig(core);
      return;
    }
    if (srcPath.isEmpty) throw AppException('未选择配置文件');
    if (vpnMode) {
      final s = settings;
      // sing-box（libbox）：配置内写 tun；mihomo（gomobile 桥）：tun 由原生层建，配置不含 tun
      if (core != coreMihomo) {
        setTun(core, srcPath, true, s.tunStack, s.tunMTU, s.tunStrictRoute);
      }
    }
    _clearRunConfigSync();
    try {
      await File(srcPath).copy(runConfigPath(core));
    } catch (e) {
      throw AppException('同步 run 配置失败: $e');
    }
  }

  /// Android VPN 配置合成：强制 tun（忽略 settings.tunEnabled），系统代理关闭。
  Future<void> _generateVpnRunConfig(String core) async {
    final s = settings;
    checkRuleFiles(s.routingMode, s.builtin.dnsMode, rulesDir);
    Node? n;
    if (s.appliedNodeID.isNotEmpty) n = store.get(s.appliedNodeID);
    if (n == null) {
      throw AppException('内置路由模式需要先应用一个节点（在节点列表长按 → 应用此节点）');
    }
    final savedTun = s.tunEnabled;
    // sing-box：配置含 tun（libbox 平台接口接管）；
    // mihomo：Android 桥层建 TUN，配置不含 tun 段，保留 mixed 入站（系统代理可用）
    final forceTun = core != coreMihomo;
    s.tunEnabled = forceTun;
    try {
      final opts = BuiltinOptions(
        mode: s.routingMode,
        tunEnabled: forceTun,
        tunStack: s.tunStack,
        tunMTU: s.tunMTU,
        tunStrictRoute: s.tunStrictRoute,
        proxyEnabled: !forceTun,
        proxyListen: s.proxyListen,
        proxyPort: s.proxyPort,
        rulesDir: rulesDir,
        uiDir: _join(runDir, 'ui'),
        cachePath: _join(runDir, 'cache.db'),
        cfg: s.builtin,
      );
      final data = buildBuiltinConfig(core, opts, n);
      _clearRunConfigSync();
      await File(runConfigPath(core)).writeAsString(data);
    } finally {
      s.tunEnabled = savedTun;
    }
  }

  Future<void> _generateBuiltinRunConfig(String core) async {
    final s = settings;
    // 规则文件校验前置：缺文件时给出明确提示
    checkRuleFiles(s.routingMode, s.builtin.dnsMode, rulesDir);
    Node? n;
    if (s.appliedNodeID.isNotEmpty) n = store.get(s.appliedNodeID);
    if (n == null) {
      throw AppException('内置路由模式需要先应用一个节点（在节点列表右键 → 应用此节点）');
    }
    final opts = BuiltinOptions(
      mode: s.routingMode,
      tunEnabled: s.tunEnabled,
      tunStack: s.tunStack,
      tunMTU: s.tunMTU,
      tunStrictRoute: s.tunStrictRoute,
      proxyEnabled: await proxy.isEnabled(),
      proxyListen: s.proxyListen,
      proxyPort: s.proxyPort,
      rulesDir: rulesDir,
      uiDir: _join(runDir, 'ui'),
      cachePath: _join(runDir, 'cache.db'),
      cfg: s.builtin,
    );
    // clash-api external-ui 目录（目录为空时内核自动下载默认面板）；关闭时不建
    if (!s.builtin.clashAPIDisabled) {
      await Directory(_join(runDir, 'ui')).create(recursive: true);
    }
    final data = buildBuiltinConfig(core, opts, n);
    _clearRunConfigSync();
    try {
      await File(runConfigPath(core)).writeAsString(data);
    } catch (e) {
      throw AppException('写入 run 配置失败: $e');
    }
  }

  /// 清除 run 目录中的旧配置文件（对齐 Go 版 clearRunConfig：
  /// config.json/yaml/yml 及其 .tmp；geodata、rules 等数据文件不受影响）。
  void _clearRunConfigSync() {
    for (final name in [
      'config.json', 'config.yaml', 'config.yml',
      'config.json.tmp', 'config.yaml.tmp', 'config.yml.tmp',
    ]) {
      final f = File(_join(runDir, name));
      if (f.existsSync()) f.deleteSync();
    }
  }

  // ─── 内核进程（app.go: startCore）───────────────────────────────────────────

  /// 启动当前内核。TUN 需要管理员权限（tun inbound 建网卡）：非管理员运行时
  /// 申请 UAC 提权并重启程序，重启后自动恢复核心运行（参考 v2rayN）。抛
  /// AppException('正在以管理员身份重启程序…') 时 UI 应退出进程。
  Future<void> startCore() async {
    final s = settings;
    final core = s.core;
    if (s.activeConfigPath().isEmpty && !isBuiltinMode(s.routingMode)) {
      throw AppException('未选择配置文件');
    }
    if (vpnMode) {
      // Android：配置写好后由宿主 VpnService/libbox 拉起，无二进制/权限检查
      await syncRunConfig(core, currentConfigPath());
      await Directory(runDir).create(recursive: true);
      await engine.start(EngineRunConfig(
        core: core,
        binPath: '',
        runDir: runDir,
        configPath: runConfigPath(core),
      ));
      return;
    }
    // TUN 模式必须管理员权限；管理员身份运行时核心子进程自动继承管理员令牌
    if (s.tunEnabled && !isAdmin()) {
      await requestElevationAndRestart(true);
    }
    final binPath = coreBinPath(core);
    if (!await File(binPath).exists()) {
      final name = core == coreMihomo ? 'mihomo' : 'sing-box';
      throw AppException('未找到 $name 内核: $binPath（请将 $name.exe 放入 bin 目录）');
    }
    await syncRunConfig(core, currentConfigPath());
    await Directory(runDir).create(recursive: true);
    await engine.start(EngineRunConfig(
      core: core,
      binPath: binPath,
      runDir: runDir,
      configPath: runConfigPath(core),
    ));
  }

  Future<void> stopCore() => engine.stop();

  ProcessStatus get coreStatus => engine.status;
  Stream<String> get coreLogLines => engine.logLines;
  Stream<ProcessStatus> get coreStatusChanges => engine.statusChanges;
  List<String> get coreLogSnapshot => engine.logSnapshot;

  bool get coreRunning => engine.status.running;

  /// 重启内核（若正在运行）。返回是否发生了重启。
  Future<bool> restartIfRunning() async {
    if (!coreRunning) return false;
    await stopCore();
    await startCore();
    return true;
  }

  // ─── 应用节点（app.go: ApplyNode）───────────────────────────────────────────

  /// 应用节点：内置模式重合成 run 配置；custom 模式把节点写进选中配置文件。
  Future<void> applyNode(String id) async {
    final n = store.get(id);
    if (n == null) throw AppException('节点不存在: $id');
    final s = settings;
    s.appliedNodeID = id;
    cfgManager.save();
    if (!isBuiltinMode(s.routingMode)) {
      final cfgPath = currentConfigPath();
      if (cfgPath.isEmpty) throw AppException('未选择配置文件');
      applyNodeToConfig(s.core, cfgPath, n);
    }
    await restartIfRunning();
  }

  /// 取消应用（当前应用的节点从配置中移除）。
  Future<void> unapplyNode() async {
    final s = settings;
    if (s.appliedNodeID.isEmpty) return;
    if (!isBuiltinMode(s.routingMode)) {
      final cfgPath = currentConfigPath();
      if (cfgPath.isNotEmpty) removeNodeFromConfig(s.core, cfgPath);
    }
    s.appliedNodeID = '';
    cfgManager.save();
    await restartIfRunning();
  }

  // ─── TUN 开关（app.go: EnableTun/DisableTun）───────────────────────────────

  Future<void> enableTun() async {
    final s = settings;
    final core = s.core;
    final cfgPath = currentConfigPath();
    final builtin = isBuiltinMode(s.routingMode);
    if (cfgPath.isEmpty && !builtin) throw AppException('未选择配置文件');
    final wasRunning = coreRunning;
    if (wasRunning) await stopCore();
    s.tunEnabled = true;
    cfgManager.save();
    if (builtin) {
      await syncRunConfig(core, '');
    } else {
      setTun(core, cfgPath, true, s.tunStack, s.tunMTU, s.tunStrictRoute);
      await syncRunConfig(core, cfgPath);
    }
    if (wasRunning) await startCore();
  }

  Future<void> disableTun() async {
    final s = settings;
    final core = s.core;
    final cfgPath = currentConfigPath();
    final builtin = isBuiltinMode(s.routingMode);
    if (cfgPath.isEmpty && !builtin) throw AppException('未选择配置文件');
    final wasRunning = coreRunning;
    if (wasRunning) await stopCore();
    s.tunEnabled = false;
    cfgManager.save();
    if (builtin) {
      await syncRunConfig(core, '');
    } else {
      setTun(core, cfgPath, false, '', 0, false);
      await syncRunConfig(core, cfgPath);
    }
    if (wasRunning) await startCore();
  }

  // ─── 系统代理（app.go: EnableSystemProxy/DisableSystemProxy）───────────────

  Future<void> enableSystemProxy() async {
    final s = settings;
    final core = s.core;
    final cfgPath = currentConfigPath();
    final builtin = isBuiltinMode(s.routingMode);
    if (cfgPath.isEmpty && !builtin) throw AppException('未选择配置文件');
    final wasRunning = coreRunning;
    if (wasRunning) await stopCore();
    if (builtin) {
      // 内置模式：先设注册表再合成（合成时按注册表状态写入 mixed-port）
      await proxy.enable('127.0.0.1', s.proxyPort);
      await syncRunConfig(core, '');
    } else {
      setMixedInbound(core, cfgPath, true, s.proxyListen, s.proxyPort);
      await syncRunConfig(core, cfgPath);
    }
    if (wasRunning) await startCore();
    if (!builtin) {
      // 注册表里只能写 127.0.0.1（监听地址可以是 0.0.0.0/::）
      await proxy.enable('127.0.0.1', s.proxyPort);
    }
  }

  Future<void> disableSystemProxy() async {
    final s = settings;
    if (isBuiltinMode(s.routingMode)) {
      // 内置模式：关注册表后重新合成，移除配置中的 mixed-port
      await proxy.disable();
      if (coreRunning) {
        await stopCore();
        await syncRunConfig(s.core, '');
        await startCore();
      }
      return;
    }
    await proxy.disable();
  }

  Future<bool> sysProxyEnabled() => proxy.isEnabled();

  // ─── 配置文件管理（configs 目录）───────────────────────────────────────────

  /// 对齐 Go: GetConfigFiles — 按当前内核过滤扩展名（sing-box → .json；
  /// mihomo → .yaml/.yml），按名称排序，末尾追加内置路由配置项
  /// （内置配置：绕过大陆 / GFW列表 / 全局代理）。
  Future<List<String>> listConfigFiles() async {
    final dir = Directory(configsDir);
    if (!await dir.exists()) return builtinDisplayNames();
    final match = settings.core == coreMihomo
        ? const ['.yaml', '.yml']
        : const ['.json'];
    final names = <String>[];
    await for (final e in dir.list()) {
      if (e is File) {
        final lower = e.path.toLowerCase();
        if (match.any(lower.endsWith)) {
          names.add(e.path.split(Platform.pathSeparator).last);
        }
      }
    }
    names.sort();
    // 末尾追加内置路由配置项
    names.addAll(builtinDisplayNames());
    return names;
  }

  Future<String> readConfigFile(String name) =>
      File(_join(configsDir, name)).readAsString();

  Future<void> saveConfigFile(String name, String content) async {
    if (name.contains('/') || name.contains('\\') || name.contains('..')) {
      throw AppException('非法文件名');
    }
    await Directory(configsDir).create(recursive: true);
    await File(_join(configsDir, name)).writeAsString(content);
  }

  Future<void> deleteConfigFile(String name) async {
    final f = File(_join(configsDir, name));
    if (await f.exists()) await f.delete();
  }

  /// 对齐 Go: SelectConfigFile — 支持内置路由配置项（切 RoutingMode），
  /// 真实文件则校验扩展名并走「停核心 → 换配置 → 重建节点/inbound/tun →
  /// 复制到 run → 拉起核心」编排。返回当前生效的显示名。
  Future<String> selectConfigFile(String name) async {
    // 内置路由配置项：切换 RoutingMode，不涉及用户配置文件
    final mode = parseBuiltinName(name);
    if (mode != null) return selectBuiltinRouting(mode);
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw AppException('未指定配置文件');
    // 安全检查: 只允许纯文件名, 禁止路径穿越
    if (trimmed.contains('/') ||
        trimmed.contains('\\') ||
        trimmed.contains('..')) {
      throw AppException('非法文件名: $trimmed');
    }
    final full = _join(configsDir, trimmed);
    if (!await File(full).exists()) {
      throw AppException('配置文件不存在: $trimmed');
    }
    final s = settings;
    final core = s.core;
    // 扩展名必须与当前内核匹配
    final ext = trimmed.toLowerCase().contains('.')
        ? trimmed.substring(trimmed.lastIndexOf('.')).toLowerCase()
        : '';
    if (core == coreMihomo) {
      if (ext != '.yaml' && ext != '.yml') {
        throw AppException(
            'mihomo 内核需要 yaml 配置文件（.yaml/.yml），不支持: $trimmed');
      }
    } else if (ext != '.json') {
      throw AppException('sing-box 内核需要 json 配置文件（.json），不支持: $trimmed');
    }

    // ── 切换编排：停核心 → 换配置 → 重建节点/inbound/tun → 复制到 run → 拉起核心 ──
    final wasRunning = coreRunning;
    // 切换前探测旧状态（TUN 看持久化开关；系统代理看注册表）
    final tunWasOn = s.tunEnabled;
    final proxyWasOn = await proxy.isEnabled();

    if (wasRunning) await stopCore();

    // 选真实配置文件 = 路由回到 custom 模式
    s.routingMode = modeCustom;
    s.setCoreConfigPath(core, trimmed);
    cfgManager.save();

    // 重新应用节点（如果之前有应用过的节点）
    if (s.appliedNodeID.isNotEmpty) {
      final n = store.get(s.appliedNodeID);
      if (n != null) applyNodeToConfig(core, full, n);
    }

    // 系统代理开着则重建 mixed inbound / mixed-port 并重设注册表（端口可能已变）
    if (proxyWasOn) {
      setMixedInbound(core, full, true, s.proxyListen, s.proxyPort);
      await proxy.enable('127.0.0.1', s.proxyPort);
    }

    // TUN 开着则重建 TUN 配置
    if (tunWasOn) {
      setTun(core, full, true, s.tunStack, s.tunMTU, s.tunStrictRoute);
    }

    // 复制到 run 目录（先清除旧配置，保证只有一个当前内核的配置文件）
    await syncRunConfig(core, full);

    // 切换前核心在跑则重新拉起
    if (wasRunning) await startCore();
    return trimmed;
  }

  /// 对齐 Go: selectBuiltinRouting — 切换到内置路由模式
  /// （bypass / blacklist / global）。用户 configs/ 配置文件与其各内核记忆
  /// 路径不动；已应用节点才立即合成 run 配置，核心在跑则重启。
  Future<String> selectBuiltinRouting(String mode) async {
    final s = settings;
    final core = s.core;
    // 前置校验：规则文件（与节点无关，缺失早提示）
    checkRuleFiles(mode, s.builtin.dnsMode, rulesDir);
    final wasRunning = coreRunning;
    if (wasRunning) await stopCore();
    s.routingMode = mode;
    cfgManager.save();
    // 系统代理开着：先设注册表再合成（合成时按注册表状态写入 mixed inbound）
    if (await proxy.isEnabled()) {
      await proxy.enable('127.0.0.1', s.proxyPort);
    }
    // 已应用节点才立即合成；未应用则等 ApplyNode / 启动核心时合成
    if (s.appliedNodeID.isNotEmpty && store.get(s.appliedNodeID) != null) {
      await syncRunConfig(core, '');
    }
    if (wasRunning) await startCore();
    return builtinDisplayName(mode) ?? mode;
  }

  /// 打开 configs 目录（Windows 资源管理器）。
  Future<void> openConfigsDir() async {
    await Directory(configsDir).create(recursive: true);
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [configsDir]);
    }
  }

  // ─── 节点与分组（透传 store + 解析入口；Store 为同步 API）──────────────────

  List<Node> allNodes() => store.getAll();
  List<Node> nodesOf(String groupId) =>
      store.getAll().where((n) => n.groupId == groupId).toList();

  List<Group> allGroups() => store.getGroups();

  /// 从文本（URI 列表 / base64 订阅 / sing-box JSON / Clash YAML）导入节点。
  /// 返回导入数量。
  int addNodesFromText(String text, String groupId, String subUrl) {
    final parsed = parseContent(text);
    final groupValid = store.groupIDValid(groupId);
    for (final n in parsed) {
      n.groupId = groupValid;
      n.subUrl = subUrl;
    }
    store.addMany(parsed);
    return parsed.length;
  }

  void updateNode(Node n) => store.update(n);
  void deleteNode(String id) => store.delete(id);
  bool moveNode(String id, int delta) => store.move(id, delta);
  void clearAllNodes() => store.clear();
  void clearGroupNodes(String groupId) => store.removeByGroup(groupId);

  Group addGroup(String name, String afterID) => store.addGroup(name, afterID);
  void renameGroup(String id, String name) => store.renameGroup(id, name);
  void updateGroup(Group g) => store.updateGroup(
      g.id, g.name, g.subUrl, g.autoUpdate, g.updateIntervalHours);
  void moveGroup(String id, int delta) => store.moveGroup(id, delta);

  /// 删除分组（默认分组不可删；节点归属处理对齐 Go 版）。
  void deleteGroup(String id) => store.deleteGroup(id);

  /// 导出节点分享 URI（vless://… 等）。对齐 Go: ExportNodeURI。
  String exportNodeURI(String id) {
    final n = store.get(id);
    if (n == null) throw AppException('节点不存在: $id');
    final uri = nodeToUri(n);
    if (uri.isEmpty) throw AppException('导出为空');
    return uri;
  }

  // ─── 订阅（app.go: RefreshGroupSubscription + subscribe.go 拉取）────────────

  /// 拉取订阅并整组替换节点。返回新增数量。
  Future<int> refreshGroupSubscription(String groupID) async {
    final g = store.groupByID(groupID);
    if (g == null) throw AppException('分组不存在: $groupID');
    if (g.subUrl.isEmpty) throw AppException('该分组不是订阅');
    final body = await fetchSubscription(
      g.subUrl,
      userAgent: settings.subUserAgent,
      timeoutSec: settings.subTimeoutSec,
    );
    final parsed = parseContent(body);
    for (final n in parsed) {
      n.groupId = groupID;
      n.subUrl = g.subUrl;
    }
    store.removeByGroup(groupID);
    store.addMany(parsed);
    store.setGroupLastUpdate(
        groupID, DateTime.now().millisecondsSinceEpoch ~/ 1000);
    return parsed.length;
  }

  /// 新建订阅分组并立即拉取。
  Future<void> addSubscription({
    required String name,
    required String url,
    bool autoUpdate = false,
    int updateIntervalHours = 10,
    String? afterID,
  }) async {
    final g = addGroup(name, afterID ?? '');
    updateGroup(Group(
      id: g.id,
      name: name,
      isDefault: g.isDefault,
      subUrl: url,
      autoUpdate: autoUpdate,
      updateIntervalHours: updateIntervalHours,
    ));
    try {
      await refreshGroupSubscription(g.id);
    } catch (_) {
      // 拉取失败保留分组，用户可手动重试
    }
  }

  /// 对齐 Go: FetchSubscriptionAsGroup — 拉取成功 → 新建「订阅N」分组
  /// （最右侧，链接自动填充，不自动更新），节点全部放入该分组；
  /// 同时记录到全局订阅列表。返回（分组, 节点数）。
  Future<(Group, int)> fetchSubscriptionAsGroup(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw AppException('订阅链接不能为空');
    final body = await fetchSubscription(
      trimmed,
      userAgent: settings.subUserAgent,
      timeoutSec: settings.subTimeoutSec,
    );
    final parsed = parseContent(body);
    // 新建分组（追加到最右侧）并填入订阅链接（不自动更新）
    final g = store.addGroup(nextSubGroupName(store.getGroups()), '');
    store.updateGroup(g.id, g.name, trimmed, false, 0);
    for (final n in parsed) {
      n.groupId = g.id;
      n.subUrl = trimmed;
    }
    store.addMany(parsed);
    // 同步记录到全局订阅列表（弹窗的「已添加的订阅」）
    final subs = [...?settings.subscriptions];
    if (!subs.contains(trimmed)) subs.add(trimmed);
    settings.subscriptions = subs;
    cfgManager.save();
    return (store.groupByID(g.id) ?? g, parsed.length);
  }

  /// 对齐 Go: RemoveSubscription — 从全局订阅列表移除。
  void removeSubscription(String url) {
    settings.subscriptions = [...?settings.subscriptions]
        .where((u) => u != url)
        .toList();
    cfgManager.save();
  }

  /// 下一个可用的「订阅N」名称（N 取现有最大值 +1）。
  static String nextSubGroupName(List<Group> groups) {
    var maxN = 0;
    for (final g in groups) {
      final m = RegExp(r'^订阅(\d+)$').firstMatch(g.name);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > maxN) maxN = n;
      }
    }
    return '订阅${maxN + 1}';
  }

  // ─── 订阅自动更新 ──────────────────────────────────────────────────────────

  Timer? _subTimer;

  void _checkAutoUpdates() {
    () async {
      try {
        final now = DateTime.now();
        for (final g in allGroups()) {
          if (!g.autoUpdate || g.subUrl.isEmpty) continue;
          final last = g.lastUpdate > 0
              ? DateTime.fromMillisecondsSinceEpoch(g.lastUpdate * 1000)
              : null;
          final due = last == null ||
              now.difference(last) >= Duration(hours: g.updateIntervalHours);
          if (due) {
            try {
              await refreshGroupSubscription(g.id);
            } catch (_) {/* 下次再试 */}
          }
        }
      } catch (_) {/* 忽略定时任务错误 */}
    }();
  }

  // ─── 延迟测试 ──────────────────────────────────────────────────────────────

  /// TCP 连接延迟（毫秒）；失败返回 -1。直连近似，不经过代理。
  Future<int> testLatencyTcp(Node n) => probeTcp(n.address, n.port);

  /// 真实链路延迟（毫秒）：临时 sing-box 实例 + HTTP 经代理（对齐 Go 版 probe）。
  Future<int> testLatency(Node n) => testLatencyReal(coreBinPath(coreSingBox), n);

  /// 真实链路下载速度（Mbps，最长 10 秒）。
  Future<double> testSpeed(Node n) => testSpeedReal(coreBinPath(coreSingBox), n);

  // ─── 设置保存（app.go: SaveSettings）───────────────────────────────────────

  /// 保存设置快照：normalize/validate 后替换；处理内核切换路径记忆、
  /// 日志行数立即生效、自启动项同步。tunEnabled 是运行时状态，不接受覆盖。
  Future<void> saveSettings(Settings s) async {
    s.normalize();
    s.validate();
    final old = cfgManager.settings;
    final oldCore = old.core;
    final oldAutoStart = old.autoStart;
    final oldSilentStart = old.silentStart;
    // tun_enabled 只能经 EnableTun/DisableTun 改变，不允许被表单快照覆盖
    s.tunEnabled = old.tunEnabled;
    cfgManager.settings = s;
    // 切换内核：切换为各自记忆的配置文件（内置模式不回填真实路径）
    if (oldCore != s.core) {
      if (isBuiltinMode(s.routingMode)) {
        s.configPath = '';
      } else {
        s.configPath = s.activeConfigPath();
      }
    }
    try {
      cfgManager.save();
    } catch (e) {
      throw AppException('保存设置失败: $e');
    }
    // 立即生效的设置
    engine.setMaxLog(s.logMaxLines);
    // 开机自启动/静默启动变化时同步系统自启动项
    if (s.autoStart != oldAutoStart ||
        (s.autoStart && s.silentStart != oldSilentStart)) {
      try {
        await applyAutoStart(s.autoStart, s.silentStart);
      } catch (e) {
        throw AppException('设置已保存，但自启动项更新失败: $e');
      }
    }
  }

  /// 注册/移除开机自启动项（对齐 Go 版 applyAutoStart：两种机制先都清理。
  /// 管理员运行用计划任务 /RL HIGHEST，普通权限写注册表 Run 键）。
  Future<void> applyAutoStart(bool enable, bool silent) async {
    final exe = Platform.resolvedExecutable;
    try {
      await deleteRegistryRun();
    } catch (_) {}
    try {
      await deleteScheduledTask();
    } catch (_) {}
    if (!enable) return;
    if (isAdmin()) {
      await createScheduledTask(exe, silent);
    } else {
      await setRegistryRun(exe, silent);
    }
  }

  // ─── 提权重启（app.go: requestElevationAndRestart / restoreAfterElevation）──

  /// 触发 UAC 授权并以管理员身份重启程序：
  /// 写恢复标记 → runas 启动新实例 → 旧实例停核心释放端口后由 UI 退出进程。
  /// 抛 AppException('正在以管理员身份重启程序…')，UI 收到后应执行退出。
  Future<void> requestElevationAndRestart(bool startCoreAfter) async {
    final exe = Platform.resolvedExecutable;
    final markerPath = _join(dataDir, 'elevate.json');
    try {
      await File(markerPath)
          .writeAsString(jsonEncode({'start_core': startCoreAfter}));
    } catch (e) {
      throw AppException('写入提权标记失败: $e');
    }
    try {
      await launchElevated(exe);
    } catch (e) {
      // 用户取消 UAC：清理标记，原地不动
      final f = File(markerPath);
      if (f.existsSync()) f.deleteSync();
      throw AppException('需要管理员权限（TUN 模式），但授权被取消: $e');
    }
    // 新实例即将拉起：先停掉旧核心释放端口/网卡，再由 UI 退出当前实例
    await engine.stop();
    throw AppException('正在以管理员身份重启程序…');
  }

  /// 提权重启后的新实例：消费恢复标记并恢复原有状态（一次性）。
  Future<void> _restoreAfterElevation() async {
    final markerPath = _join(dataDir, 'elevate.json');
    final marker = File(markerPath);
    if (!marker.existsSync()) return; // 非提权重启，正常启动
    final data = await marker.readAsString();
    try {
      await marker.delete();
    } catch (_) {}
    final bool startCoreAfter;
    try {
      startCoreAfter = (jsonDecode(data) as Map)['start_core'] == true;
    } catch (_) {
      return;
    }
    if (!startCoreAfter) return;
    if (!settings.tunEnabled) return;
    // 等旧实例完全退出、释放 TUN 网卡与端口后拉起核心（最多等 15 秒）
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        await startCore();
        return;
      } catch (_) {/* 重试 */}
    }
  }

  // ─── utils ─────────────────────────────────────────────────────────────────

  static String _join(String a, String b) => a.endsWith(Platform.pathSeparator)
      ? '$a$b'
      : '$a${Platform.pathSeparator}$b';
}

/// 拉取订阅内容（subscribe.go 拉取部分：UA/超时语义一致）。
Future<String> fetchSubscription(
  String url, {
  String userAgent = '',
  int timeoutSec = 20,
}) async {
  final client = HttpClient();
  client.connectionTimeout = Duration(seconds: timeoutSec);
  try {
    final req = await client.getUrl(Uri.parse(url.trim()));
    if (userAgent.isNotEmpty) {
      req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    }
    final resp = await req.close().timeout(Duration(seconds: timeoutSec));
    if (resp.statusCode != 200) {
      throw AppException('订阅拉取失败: HTTP ${resp.statusCode}');
    }
    return await resp
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(Duration(seconds: timeoutSec));
  } on TimeoutException {
    throw AppException('订阅拉取超时');
  } finally {
    client.close();
  }
}
