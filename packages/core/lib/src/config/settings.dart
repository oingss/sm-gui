/// 持久化设置 — 移植自 Go: backend/config/manager.go（Settings / DNSServer /
/// ClashAPIConfig / BuiltinSettings 类与 Defaults/Normalize/Validate/applyDefaults）。
///
/// JSON 字段名与 Go tag 完全一致（含 omitempty 语义），
/// 保证与旧版 settings.json 的兼容性。
/// 内核/路由模式常量（Go 中分别位于 manager.go 与 builtin.go）也集中在此，
/// 供本文件与 builtin.dart 共用。
library;

import 'dart:io';

import '../parsing/common.dart';

// ── 常量 ─────────────────────────────────────────────────────────────────────

/// 支持的内核（移植自 Go: manager.go）。
const String coreSingBox = 'sing-box';
const String coreMihomo = 'mihomo';

/// 路由模式常量（移植自 Go: builtin.go，与 Settings.RoutingMode 对应）。
const String modeCustom = 'custom';
const String modeBypass = 'bypass';
const String modeBlacklist = 'blacklist';
const String modeGlobal = 'global';

// ── 配置数据类 ───────────────────────────────────────────────────────────────

/// DNSServer sing-box DNS 服务器（类型/地址/端口/路径）。
/// 地址必填；端口、路径选填，零值时按类型补默认端口 / 不写入。
class DNSServer {
  String type; // tcp | udp | tls | https | quic
  String address; // IP 或域名（tls/https 建议域名）
  int port; // 0 = 按类型默认端口
  String path; // https 类型的 URL 路径

  DNSServer({
    this.type = '',
    this.address = '',
    this.port = 0,
    this.path = '',
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'address': address,
        'port': port,
        'path': path,
      };

  static DNSServer fromJson(Map<String, dynamic> j) => DNSServer(
        type: j['type'] as String? ?? '',
        address: j['address'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 0,
        path: j['path'] as String? ?? '',
      );
}

/// ClashAPIConfig clash-api 监听配置（双内核共用）。
class ClashAPIConfig {
  String listen; // 127.0.0.1 | 0.0.0.0
  int port;
  String secret;

  ClashAPIConfig({
    this.listen = '',
    this.port = 0,
    this.secret = '',
  });

  Map<String, dynamic> toJson() => {
        'listen': listen,
        'port': port,
        'secret': secret,
      };

  static ClashAPIConfig fromJson(Map<String, dynamic> j) => ClashAPIConfig(
        listen: j['listen'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 0,
        secret: j['secret'] as String? ?? '',
      );
}

/// BuiltinSettings 内置路由模式可配置参数（settings.json 的 builtin 段）。
/// 默认值即此前写死的值，旧 settings.json 缺段时自动补默认。
/// 注意：clashAPIDisabled 用反转语义——零值 false 即默认启用，无需缺字段探测。
class BuiltinSettings {
  String logLevel; // debug | info | warning | error
  String dnsMode; // redir-host | fake-ip
  bool ipv6;
  bool clashAPIDisabled; // true 时完全不生成 clash-api 配置
  String resolverDNS; // 解析 DNS 主服务器（必须是 IP）；sing-box 取此条，
                     // mihomo 对应 default_nameserver
  String resolverDNSBackup; // 解析 DNS 备用服务器（必须是 IP，默认 119.29.29.29）；
                            // 仅 mihomo 填两个
  ClashAPIConfig clashAPI;
  DNSServer singBoxDirect; // sing-box 直连 DNS
  DNSServer singBoxProxy; // sing-box 代理 DNS
  List<String>? mihomoDirect; // mihomo 直连 DNS（两个）
  List<String>? mihomoProxy; // mihomo 代理 DNS（两个，生成时自动加 #PROXY）

  BuiltinSettings({
    this.logLevel = '',
    this.dnsMode = '',
    this.ipv6 = false,
    this.clashAPIDisabled = false,
    this.resolverDNS = '',
    this.resolverDNSBackup = '',
    ClashAPIConfig? clashAPI,
    DNSServer? singBoxDirect,
    DNSServer? singBoxProxy,
    this.mihomoDirect,
    this.mihomoProxy,
  })  : clashAPI = clashAPI ?? ClashAPIConfig(),
        singBoxDirect = singBoxDirect ?? DNSServer(),
        singBoxProxy = singBoxProxy ?? DNSServer();

  Map<String, dynamic> toJson() => {
        'log_level': logLevel,
        'dns_mode': dnsMode,
        'ipv6': ipv6,
        'clash_api_disabled': clashAPIDisabled,
        'resolver_dns': resolverDNS,
        'resolver_dns_backup': resolverDNSBackup,
        'clash_api': clashAPI.toJson(),
        'singbox_direct': singBoxDirect.toJson(),
        'singbox_proxy': singBoxProxy.toJson(),
        // Go []string 无 omitempty：nil 序列化为 null，空表为 []
        'mihomo_direct': mihomoDirect,
        'mihomo_proxy': mihomoProxy,
      };

  static BuiltinSettings fromJson(Map<String, dynamic> j) => BuiltinSettings(
        logLevel: j['log_level'] as String? ?? '',
        dnsMode: j['dns_mode'] as String? ?? '',
        ipv6: j['ipv6'] as bool? ?? false,
        clashAPIDisabled: j['clash_api_disabled'] as bool? ?? false,
        resolverDNS: j['resolver_dns'] as String? ?? '',
        resolverDNSBackup: j['resolver_dns_backup'] as String? ?? '',
        clashAPI: j['clash_api'] == null
            ? ClashAPIConfig()
            : ClashAPIConfig.fromJson(
                (j['clash_api'] as Map).cast<String, dynamic>()),
        singBoxDirect: j['singbox_direct'] == null
            ? DNSServer()
            : DNSServer.fromJson(
                (j['singbox_direct'] as Map).cast<String, dynamic>()),
        singBoxProxy: j['singbox_proxy'] == null
            ? DNSServer()
            : DNSServer.fromJson(
                (j['singbox_proxy'] as Map).cast<String, dynamic>()),
        mihomoDirect: (j['mihomo_direct'] as List?)?.cast<String>(),
        mihomoProxy: (j['mihomo_proxy'] as List?)?.cast<String>(),
      );
}

/// DefaultBuiltin 返回内置路由参数的默认设置（与写死版本行为一致）。
/// 移植自 Go: manager.go DefaultBuiltin()。
BuiltinSettings defaultBuiltin() => BuiltinSettings(
      logLevel: 'warning',
      dnsMode: 'redir-host',
      resolverDNS: '223.5.5.5',
      resolverDNSBackup: '119.29.29.29',
      clashAPI: ClashAPIConfig(listen: '127.0.0.1', port: 9090),
      singBoxDirect: DNSServer(type: 'udp', address: '223.5.5.5', port: 53),
      singBoxProxy: DNSServer(type: 'udp', address: '8.8.8.8', port: 53),
      mihomoDirect: ['223.5.5.5', '119.29.29.29'],
      mihomoProxy: ['1.1.1.1', '8.8.8.8'],
    );

// ── Settings ─────────────────────────────────────────────────────────────────

/// Settings 持久化设置。新增字段必须同时在 applyDefaults 里给默认值，
/// 否则旧 settings.json 升级后会出现零值。
class Settings {
  // 内核：sing-box | mihomo
  String core;

  // 旧版字段：保留并同步为“当前内核选中的配置文件”，前端直接读取它回显。
  String configPath;

  // 两个内核各自记忆的配置文件路径（切换内核时互不丢失）。
  String configPathSingBox;
  String configPathMihomo;

  List<String>? subscriptions;

  // 当前应用的节点 ID（切配置文件后据此重新应用）
  String appliedNodeID;

  // 路由模式：custom（跟随用户配置文件）| bypass（内置:绕过大陆）|
  // blacklist（内置:GFW列表）| global（内置:全局代理）。
  // 内置模式下配置由程序模板合成，直接写入 run 目录，不碰用户 configs 文件。
  String routingMode;

  // TUN 开关持久化状态（内置模式据此生成 tun inbound；custom 模式与配置文件保持同步）。
  bool tunEnabled;

  // 系统代理
  String proxyListen; // mixed inbound 监听地址
  int proxyPort; // mixed inbound 监听端口
  bool exitDisableProxy; // 退出程序时自动关闭系统代理

  // 底部栏三个开关的期望状态持久化（TUN 复用上面的 tunEnabled）：
  // 记录"用户上一次主动设置的开关状态"，下次启动按此自动恢复，
  // 与 exitDisableProxy 等运行期自动动作互不覆盖对方语义。
  bool sysProxyDesired; // 系统代理：用户上一次主动开启/关闭的状态
  bool coreRunningDesired; // 启动核心：用户上一次主动启动/停止的状态

  // TUN 模式
  String tunStack; // gvisor | system | mixed
  int tunMTU; // TUN 网卡 MTU
  bool tunStrictRoute; // sing-box strict_route

  // 订阅
  String subUserAgent; // 拉取订阅时的 User-Agent
  int subTimeoutSec; // 拉取订阅超时秒数

  // 日志与界面
  int logMaxLines; // 运行日志最大保留行数
  int pollIntervalMs; // 前端状态轮询间隔(毫秒)

  // 启动
  bool autoStart; // 开机自启动
  bool silentStart; // 自启动时静默：不显示主窗口，仅托盘图标

  // 内置路由模式的可配置参数（合成 run 配置时使用，custom 模式不涉及）
  BuiltinSettings builtin;

  // 记录 JSON 文件中 bool 字段是否真实存在（不序列化），
  // 用于区分"旧文件缺字段"与"用户显式关闭"。
  // Go 版通过 settingsAlias 的指针字段在 unmarshal 后回填；
  // Dart 版在 fromJson 里直接按 key 是否存在记录。
  bool exitDisableProxySet;
  bool tunStrictRouteSet;

  Settings({
    this.core = '',
    this.configPath = '',
    this.configPathSingBox = '',
    this.configPathMihomo = '',
    this.subscriptions,
    this.appliedNodeID = '',
    this.routingMode = '',
    this.tunEnabled = false,
    this.proxyListen = '',
    this.proxyPort = 0,
    this.exitDisableProxy = false,
    this.sysProxyDesired = false,
    this.coreRunningDesired = false,
    this.tunStack = '',
    this.tunMTU = 0,
    this.tunStrictRoute = false,
    this.subUserAgent = '',
    this.subTimeoutSec = 0,
    this.logMaxLines = 0,
    this.pollIntervalMs = 0,
    this.autoStart = false,
    this.silentStart = false,
    BuiltinSettings? builtin,
    this.exitDisableProxySet = false,
    this.tunStrictRouteSet = false,
  }) : builtin = builtin ?? BuiltinSettings();

  /// 从 JSON 反序列化（对应 Go 的 settingsAlias unmarshal + presence 回填）。
  static Settings fromJson(Map<String, dynamic> j) => Settings(
        core: j['core'] as String? ?? '',
        configPath: j['config_path'] as String? ?? '',
        configPathSingBox: j['config_path_singbox'] as String? ?? '',
        configPathMihomo: j['config_path_mihomo'] as String? ?? '',
        subscriptions: (j['subscriptions'] as List?)?.cast<String>(),
        appliedNodeID: j['applied_node_id'] as String? ?? '',
        routingMode: j['routing_mode'] as String? ?? '',
        tunEnabled: j['tun_enabled'] as bool? ?? false,
        proxyListen: j['proxy_listen'] as String? ?? '',
        proxyPort: (j['proxy_port'] as num?)?.toInt() ?? 0,
        exitDisableProxy: j['exit_disable_proxy'] as bool? ?? false,
        sysProxyDesired: j['sys_proxy_desired'] as bool? ?? false,
        coreRunningDesired: j['core_running_desired'] as bool? ?? false,
        tunStack: j['tun_stack'] as String? ?? '',
        tunMTU: (j['tun_mtu'] as num?)?.toInt() ?? 0,
        tunStrictRoute: j['tun_strict_route'] as bool? ?? false,
        subUserAgent: j['sub_user_agent'] as String? ?? '',
        subTimeoutSec: (j['sub_timeout_sec'] as num?)?.toInt() ?? 0,
        logMaxLines: (j['log_max_lines'] as num?)?.toInt() ?? 0,
        pollIntervalMs: (j['poll_interval_ms'] as num?)?.toInt() ?? 0,
        autoStart: j['auto_start'] as bool? ?? false,
        silentStart: j['silent_start'] as bool? ?? false,
        builtin: j['builtin'] == null
            ? BuiltinSettings()
            : BuiltinSettings.fromJson(
                (j['builtin'] as Map).cast<String, dynamic>()),
        exitDisableProxySet: j.containsKey('exit_disable_proxy'),
        tunStrictRouteSet: j.containsKey('tun_strict_route'),
      );

  /// 序列化为 JSON map（字段名与 Go tag 完全一致，含 omitempty 语义；
  /// set 标志不序列化，与 Go unexported 字段行为一致）。
  Map<String, dynamic> toJson() => {
        'core': core,
        'config_path': configPath,
        if (configPathSingBox.isNotEmpty)
          'config_path_singbox': configPathSingBox,
        if (configPathMihomo.isNotEmpty)
          'config_path_mihomo': configPathMihomo,
        'subscriptions': subscriptions,
        if (appliedNodeID.isNotEmpty) 'applied_node_id': appliedNodeID,
        'routing_mode': routingMode,
        'tun_enabled': tunEnabled,
        'proxy_listen': proxyListen,
        'proxy_port': proxyPort,
        'exit_disable_proxy': exitDisableProxy,
        'sys_proxy_desired': sysProxyDesired,
        'core_running_desired': coreRunningDesired,
        'tun_stack': tunStack,
        'tun_mtu': tunMTU,
        'tun_strict_route': tunStrictRoute,
        'sub_user_agent': subUserAgent,
        'sub_timeout_sec': subTimeoutSec,
        'log_max_lines': logMaxLines,
        'poll_interval_ms': pollIntervalMs,
        'auto_start': autoStart,
        'silent_start': silentStart,
        'builtin': builtin.toJson(),
      };

  /// Defaults 返回一份全新默认设置（含内置路由参数——
  /// 此前全新安装漏填 Builtin 段，导致设置界面显示全 0）。
  static Settings defaults() => Settings(
        core: coreSingBox,
        routingMode: modeCustom,
        subscriptions: [],
        proxyListen: '127.0.0.1',
        proxyPort: 2080,
        exitDisableProxy: true,
        tunStack: 'gvisor',
        tunMTU: 9000,
        tunStrictRoute: true,
        subUserAgent: 'clash.meta',
        subTimeoutSec: 30,
        logMaxLines: 500,
        pollIntervalMs: 2000,
        builtin: defaultBuiltin(),
      );

  /// Normalize 为零值字段补默认值（供外部包在保存前调用）。
  void normalize() {
    applyDefaults();
    // mihomo DNS 列表去掉空白项
    builtin.mihomoDirect = _trimNonEmpty(builtin.mihomoDirect);
    builtin.mihomoProxy = _trimNonEmpty(builtin.mihomoProxy);
  }

  /// applyDefaults 为零值字段补默认值（兼容旧版 settings.json）。
  void applyDefaults() {
    final def = Settings.defaults();
    if (core.isEmpty) core = def.core;
    if (routingMode.isEmpty) routingMode = modeCustom;
    subscriptions ??= [];
    if (proxyListen.trim().isEmpty) proxyListen = def.proxyListen;
    if (proxyPort <= 0) proxyPort = def.proxyPort;
    if (tunStack.isEmpty) tunStack = def.tunStack;
    if (tunMTU <= 0) tunMTU = def.tunMTU;
    if (subUserAgent.trim().isEmpty) subUserAgent = def.subUserAgent;
    if (subTimeoutSec <= 0) subTimeoutSec = def.subTimeoutSec;
    if (logMaxLines <= 0) logMaxLines = def.logMaxLines;
    if (pollIntervalMs <= 0) pollIntervalMs = def.pollIntervalMs;
    // 内置路由参数逐字段补默认
    final b = builtin;
    final d = defaultBuiltin();
    if (b.logLevel.isEmpty) b.logLevel = d.logLevel;
    if (b.dnsMode.isEmpty) b.dnsMode = d.dnsMode;
    if (b.resolverDNS.isEmpty) b.resolverDNS = d.resolverDNS;
    if (b.resolverDNSBackup.isEmpty) b.resolverDNSBackup = d.resolverDNSBackup;
    if (b.clashAPI.listen.isEmpty) b.clashAPI.listen = d.clashAPI.listen;
    if (b.clashAPI.port == 0) b.clashAPI.port = d.clashAPI.port;
    if (b.singBoxDirect.type.isEmpty && b.singBoxDirect.address.isEmpty) {
      b.singBoxDirect = d.singBoxDirect;
    }
    if (b.singBoxProxy.type.isEmpty && b.singBoxProxy.address.isEmpty) {
      b.singBoxProxy = d.singBoxProxy;
    }
    if (b.mihomoDirect == null || b.mihomoDirect!.isEmpty) {
      b.mihomoDirect = d.mihomoDirect;
    }
    if (b.mihomoProxy == null || b.mihomoProxy!.isEmpty) {
      b.mihomoProxy = d.mihomoProxy;
    }
    // bool 零值为 false，但 exitDisableProxy / tunStrictRoute 的默认值是 true。
    // 旧文件中不存在这两个字段时无法区分"显式关闭"与"未设置"，
    // 用 fromJson 记录的存在标志判断。
    if (!exitDisableProxySet) exitDisableProxy = def.exitDisableProxy;
    if (!tunStrictRouteSet) tunStrictRoute = def.tunStrictRoute;
  }

  /// ActiveConfigPath 返回当前内核记忆的配置文件名（configs 目录下，非完整路径）。
  String activeConfigPath() =>
      core == coreMihomo ? configPathMihomo : configPathSingBox;

  /// SetCoreConfigPath 记录指定内核的配置文件名（同时同步旧字段 configPath）。
  void setCoreConfigPath(String core, String name) {
    if (core == coreMihomo) {
      configPathMihomo = name;
    } else {
      configPathSingBox = name;
    }
    configPath = name;
  }

  /// Validate 校验设置合法性（保存前调用）。
  /// 失败抛 [ParseException]（对应 Go 的 error 返回值）。
  void validate() {
    if (core != coreSingBox && core != coreMihomo) {
      throw ParseException('内核必须是 sing-box / mihomo');
    }
    if (routingMode != modeCustom &&
        routingMode != modeBypass &&
        routingMode != modeBlacklist &&
        routingMode != modeGlobal) {
      throw ParseException('路由模式必须是 custom / bypass / blacklist / global');
    }
    if (proxyListen.trim().isEmpty) {
      throw ParseException('监听地址不能为空');
    }
    if (proxyPort < 1 || proxyPort > 65535) {
      throw ParseException('代理端口必须在 1-65535 之间');
    }
    if (tunStack != 'gvisor' && tunStack != 'system' && tunStack != 'mixed') {
      throw ParseException('TUN 协议栈必须是 gvisor / system / mixed');
    }
    if (tunMTU < 576 || tunMTU > 65535) {
      throw ParseException('TUN MTU 必须在 576-65535 之间');
    }
    if (subUserAgent.trim().isEmpty) {
      throw ParseException('订阅 User-Agent 不能为空');
    }
    if (subTimeoutSec < 1 || subTimeoutSec > 600) {
      throw ParseException('订阅超时必须在 1-600 秒之间');
    }
    if (logMaxLines < 50 || logMaxLines > 100000) {
      throw ParseException('日志行数必须在 50-100000 之间');
    }
    if (pollIntervalMs < 500 || pollIntervalMs > 60000) {
      throw ParseException('轮询间隔必须在 500-60000 毫秒之间');
    }
    // 内置路由参数
    if (builtin.logLevel != 'debug' &&
        builtin.logLevel != 'info' &&
        builtin.logLevel != 'warning' &&
        builtin.logLevel != 'error') {
      throw ParseException('日志等级必须是 debug / info / warning / error');
    }
    if (builtin.dnsMode != 'redir-host' && builtin.dnsMode != 'fake-ip') {
      throw ParseException('DNS 模式必须是 redir-host / fake-ip');
    }
    if (!_isIP(builtin.resolverDNS.trim())) {
      throw ParseException('解析 DNS 服务器必须是 IP 地址');
    }
    if (!_isIP(builtin.resolverDNSBackup.trim())) {
      throw ParseException('解析 DNS 备用服务器必须是 IP 地址');
    }
    if (builtin.clashAPI.listen != '127.0.0.1' &&
        builtin.clashAPI.listen != '0.0.0.0') {
      throw ParseException('clash-api 监听地址必须是 127.0.0.1 / 0.0.0.0');
    }
    if (builtin.clashAPI.port < 1 || builtin.clashAPI.port > 65535) {
      throw ParseException('clash-api 端口必须在 1-65535 之间');
    }
    for (final ds in [
      ('直连 DNS', builtin.singBoxDirect),
      ('代理 DNS', builtin.singBoxProxy),
    ]) {
      final name = ds.$1;
      final svr = ds.$2;
      if (svr.type != 'tcp' &&
          svr.type != 'udp' &&
          svr.type != 'tls' &&
          svr.type != 'https' &&
          svr.type != 'quic') {
        throw ParseException(
            'sing-box $name 类型必须是 tcp / udp / tls / https / quic');
      }
      if (svr.address.trim().isEmpty) {
        throw ParseException('sing-box $name 地址不能为空');
      }
    }
    for (final l in [
      ('直连 DNS', builtin.mihomoDirect),
      ('代理 DNS', builtin.mihomoProxy),
    ]) {
      final name = l.$1;
      final list = l.$2;
      if (list == null || list.isEmpty) {
        throw ParseException('mihomo $name 至少填写一个');
      }
      for (final v in list) {
        if (v.trim().isEmpty) {
          throw ParseException('mihomo $name 不能为空');
        }
      }
    }
  }
}

/// trimNonEmpty 去掉空白项（对应 Go 的 trimNonEmpty）。
List<String>? _trimNonEmpty(List<String>? ss) {
  if (ss == null) return null;
  final out = <String>[];
  for (final v in ss) {
    final t = v.trim();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// Go 的 net.ParseIP 对应实现：IPv4 / IPv6 字面量校验。
bool _isIP(String s) {
  if (s.isEmpty) return false;
  return InternetAddress.tryParse(s) != null;
}
