/// 设置页 — 对齐 Go 版 SettingsPanel.jsx：
/// 「程序 / 配置」两个子视图，全部设置项与提示文案一致，
/// 前端预校验 + 保存编排（核心在跑则停 → 重建 TUN/系统代理 → 拉起）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import 'actions.dart';
import 'providers.dart';

const _cores = [
  (coreSingBox, 'sing-box（配置为 JSON）'),
  (coreMihomo, 'mihomo / Clash.Meta（配置为 YAML）'),
];

const _tunStacks = [
  ('gvisor', 'gvisor（默认，兼容性好）'),
  ('system', 'system（性能好，需内核支持）'),
  ('mixed', 'mixed（混合模式）'),
];

/// 系统代理监听地址可选项（Windows 系统代理始终指向 127.0.0.1）
const _listenAddrs = ['127.0.0.1', '0.0.0.0', '::'];

const _logLevels = ['debug', 'info', 'warning', 'error'];

const _dnsModes = [
  ('redir-host', 'redir-host（真实 IP）'),
  ('fake-ip', 'fake-ip（假 IP，白名单真实解析）'),
];

const _singboxDnsTypes = ['tcp', 'udp', 'tls', 'https', 'quic'];

/// DNS 类型默认端口（与后端 dnsDefaultPort 一致）
int _dnsDefaultPort(String t) =>
    const {'udp': 53, 'tcp': 53, 'tls': 853, 'https': 443, 'quic': 443}[t] ??
    53;

const _clashApiListens = ['127.0.0.1', '0.0.0.0'];

class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({super.key});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  /// 表单快照（克隆，校验失败不污染运行中的设置对象）。
  late Settings _f;
  String _view = 'app'; // app = 程序 | conf = 配置
  bool _saving = false;

  // 文本/数字输入控制器
  final _subUa = TextEditingController();
  final _subTimeout = TextEditingController();
  final _logLines = TextEditingController();
  final _poll = TextEditingController();
  final _proxyPort = TextEditingController();
  final _tunMtu = TextEditingController();
  final _resolverDns = TextEditingController();
  final _resolverDnsBackup = TextEditingController();
  final _sbDirectAddr = TextEditingController();
  final _sbDirectPort = TextEditingController();
  final _sbDirectPath = TextEditingController();
  final _sbProxyAddr = TextEditingController();
  final _sbProxyPort = TextEditingController();
  final _sbProxyPath = TextEditingController();
  final _mihomoDirect0 = TextEditingController();
  final _mihomoDirect1 = TextEditingController();
  final _mihomoProxy0 = TextEditingController();
  final _mihomoProxy1 = TextEditingController();
  final _clashPort = TextEditingController();
  final _clashSecret = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadForm(ref.read(smAppProvider).settings);
  }

  @override
  void dispose() {
    for (final c in [
      _subUa, _subTimeout, _logLines, _poll, _proxyPort, _tunMtu,
      _resolverDns, _resolverDnsBackup, _sbDirectAddr, _sbDirectPort,
      _sbDirectPath, _sbProxyAddr, _sbProxyPort, _sbProxyPath,
      _mihomoDirect0, _mihomoDirect1, _mihomoProxy0, _mihomoProxy1,
      _clashPort, _clashSecret,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 用设置快照填充表单（初始 & 恢复默认时复用）。
  void _loadForm(Settings s) {
    _f = Settings.fromJson(s.toJson());
    final b = _f.builtin;
    if (_f.subscriptions == null) _f.subscriptions = [];
    _subUa.text = _f.subUserAgent;
    _subTimeout.text = '${_f.subTimeoutSec}';
    _logLines.text = '${_f.logMaxLines}';
    _poll.text = '${_f.pollIntervalMs}';
    _proxyPort.text = '${_f.proxyPort}';
    _tunMtu.text = '${_f.tunMTU}';
    _resolverDns.text = b.resolverDNS;
    _resolverDnsBackup.text = b.resolverDNSBackup;
    _sbDirectAddr.text = b.singBoxDirect.address;
    _sbDirectPort.text =
        b.singBoxDirect.port > 0 ? '${b.singBoxDirect.port}' : '';
    _sbDirectPath.text = b.singBoxDirect.path;
    _sbProxyAddr.text = b.singBoxProxy.address;
    _sbProxyPort.text =
        b.singBoxProxy.port > 0 ? '${b.singBoxProxy.port}' : '';
    _sbProxyPath.text = b.singBoxProxy.path;
    _mihomoDirect0.text = b.mihomoDirect != null && b.mihomoDirect!.isNotEmpty
        ? b.mihomoDirect![0]
        : '';
    _mihomoDirect1.text =
        b.mihomoDirect != null && b.mihomoDirect!.length > 1
            ? b.mihomoDirect![1]
            : '';
    _mihomoProxy0.text = b.mihomoProxy != null && b.mihomoProxy!.isNotEmpty
        ? b.mihomoProxy![0]
        : '';
    _mihomoProxy1.text = b.mihomoProxy != null && b.mihomoProxy!.length > 1
        ? b.mihomoProxy![1]
        : '';
    _clashPort.text = '${b.clashAPI.port}';
    _clashSecret.text = b.clashAPI.secret;
  }

  /// 恢复默认（保留内核选择，避免误切内核，对齐 React handleReset）。
  void _reset() {
    final keepCore = _f.core;
    final def = Settings.defaults();
    def.core = keepCore;
    setState(() => _loadForm(def));
  }

  Future<void> _alert(String msg) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ─── 保存 ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    // 把控制器值写回表单快照
    final b = _f.builtin;
    _f
      ..subUserAgent = _subUa.text.trim()
      ..subTimeoutSec = int.tryParse(_subTimeout.text) ?? 0
      ..logMaxLines = int.tryParse(_logLines.text) ?? 0
      ..pollIntervalMs = int.tryParse(_poll.text) ?? 0
      ..proxyPort = int.tryParse(_proxyPort.text) ?? 0
      ..tunMTU = int.tryParse(_tunMtu.text) ?? 0
      ..builtin
        ..resolverDNS = _resolverDns.text.trim()
        ..resolverDNSBackup = _resolverDnsBackup.text.trim()
        ..singBoxDirect
          ..address = _sbDirectAddr.text.trim()
          ..port = int.tryParse(_sbDirectPort.text) ?? 0
          ..path = _sbDirectPath.text.trim()
        ..singBoxProxy
          ..address = _sbProxyAddr.text.trim()
          ..port = int.tryParse(_sbProxyPort.text) ?? 0
          ..path = _sbProxyPath.text.trim()
        ..mihomoDirect = [_mihomoDirect0.text.trim(), _mihomoDirect1.text.trim()]
        ..mihomoProxy = [_mihomoProxy0.text.trim(), _mihomoProxy1.text.trim()]
        ..clashAPI
          ..port = int.tryParse(_clashPort.text) ?? 0
          ..secret = _clashSecret.text;

    // ── 前端预校验（对齐 React handleSave，alert 提示）──
    final port = _f.proxyPort;
    if (port < 1 || port > 65535) {
      await _alert('代理端口必须是 1-65535 的整数');
      return;
    }
    if (_f.subUserAgent.trim().isEmpty) {
      await _alert('订阅 User-Agent 不能为空');
      return;
    }
    final checks = [
      (_f.subTimeoutSec, 1, 600, '订阅超时'),
      (_f.logMaxLines, 50, 100000, '日志行数'),
      (_f.pollIntervalMs, 500, 60000, '轮询间隔'),
      (_f.tunMTU, 576, 65535, 'TUN MTU'),
    ];
    for (final (v, min, max, label) in checks) {
      if (v < min || v > max) {
        await _alert('$label必须是 $min-$max 的整数');
        return;
      }
    }
    if (!_isIP(b.resolverDNS)) {
      await _alert('解析 DNS 主服务器必须是 IP 地址');
      return;
    }
    if (!_isIP(b.resolverDNSBackup)) {
      await _alert('解析 DNS 备用服务器必须是 IP 地址');
      return;
    }
    if (b.clashAPI.port < 1 || b.clashAPI.port > 65535) {
      await _alert('clash-api 端口必须是 1-65535 的整数');
      return;
    }
    if (b.singBoxDirect.address.trim().isEmpty) {
      await _alert('sing-box 直连 DNS 地址不能为空');
      return;
    }
    if (b.singBoxProxy.address.trim().isEmpty) {
      await _alert('sing-box 代理 DNS 地址不能为空');
      return;
    }
    for (final v in b.mihomoDirect ?? const <String>[]) {
      if (v.trim().isEmpty) {
        await _alert('mihomo 直连 DNS 不能为空');
        return;
      }
    }
    for (final v in b.mihomoProxy ?? const <String>[]) {
      if (v.trim().isEmpty) {
        await _alert('mihomo 代理 DNS 不能为空');
        return;
      }
    }

    // ── 保存编排（对齐 React handleSaveSettings）──
    setState(() => _saving = true);
    final app = ref.read(smAppProvider);
    try {
      final coreChanged = _f.core != app.settings.core;
      await app.saveSettings(_f);
      final fresh = app.settings;
      // 核心在跑则先停 → 重写 TUN/系统代理配置 → 再拉起核心
      final wasRunning = app.coreRunning;
      if (wasRunning) {
        try {
          await app.stopCore();
        } catch (_) {}
      }
      final isBuiltin = isBuiltinMode(fresh.routingMode);
      final hasConfig = fresh.activeConfigPath().isNotEmpty || isBuiltin;
      if (hasConfig) {
        if (fresh.tunEnabled) {
          await app.disableTun();
          await app.enableTun();
        }
        if (await app.sysProxyEnabled()) {
          await app.disableSystemProxy();
          await app.enableSystemProxy();
        }
      }
      if (wasRunning && hasConfig) {
        await app.startCore();
      }
      ref.read(settingsVersionProvider.notifier).bump();
      ref.read(configFilesProvider.notifier).reload();
      if (mounted) {
        AppToast.show(
            context,
            wasRunning && hasConfig ? '设置已保存，核心已重启生效' : '设置已保存',
            ToastType.success);
        if (coreChanged) {
          AppToast.show(
              context,
              '已切换内核: ${_f.core == coreMihomo ? 'mihomo' : 'sing-box'}'
              '${fresh.activeConfigPath().isEmpty ? '（请先选择该内核的配置文件）' : ''}',
              ToastType.info);
        }
      }
    } on AppException catch (e) {
      // 提权重启信号：Toast 后退出进程（对齐 actions.dart 统一处理）
      if (isElevationRestart(e)) {
        if (mounted) await showActionError(context, e);
        return;
      }
      ref.read(settingsVersionProvider.notifier).bump();
      if (mounted) {
        AppToast.show(context, '保存设置失败: ${e.message}', ToastType.error);
      }
    } on ParseException catch (e) {
      if (mounted) AppToast.show(context, '保存设置失败: ${e.message}', ToastType.error);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '保存设置失败: $e', ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isIP(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    final v4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    final v6 = RegExp(r'^[0-9a-fA-F:]+$');
    return v4.hasMatch(t) || v6.hasMatch(t);
  }

  // ─── 构建 ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final b = _f.builtin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 顶部视图切换 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: const BoxDecoration(
            color: SmPalette.bgPanel,
            border: Border(bottom: BorderSide(color: SmPalette.border)),
          ),
          child: Row(
            children: [
              _viewBtn('程序', 'app'),
              const SizedBox(width: 6),
              _viewBtn('配置', 'conf'),
            ],
          ),
        ),
        // ── 表单体 ──
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_view == 'app') ...[
                  _section('启动'),
                  _row('开机自启动', _check(_f.autoStart, (v) {
                    setState(() => _f.autoStart = v);
                  }), hint: '以管理员身份运行时注册计划任务（开机后仍以管理员运行）；普通权限时写入注册表 Run 键'),
                  _row('静默启动', _check(_f.silentStart, (v) {
                    setState(() => _f.silentStart = v);
                  }), hint: '仅开机自启动时生效：不显示主窗口，只保留任务栏托盘图标；手动启动不受影响'),
                  _section('内核'),
                  _row(
                    '代理内核',
                    _dropdown(_f.core, _cores, (v) => setState(() => _f.core = v)),
                    hint: '切换后使用各自记忆的配置文件（configs 目录 json / yaml）',
                  ),
                  _section('订阅'),
                  _row('User-Agent', _text(_subUa, hint: 'clash.meta')),
                  _row('请求超时', _num(_subTimeout), hint: '秒'),
                  _section('日志与界面'),
                  _row('日志保留行数', _num(_logLines)),
                  _row('状态轮询间隔', _num(_poll), hint: '毫秒'),
                ],
                if (_view == 'conf') ...[
                  _section('系统代理'),
                  _row(
                    '监听地址',
                    _dropdown(
                        _listenAddrs.contains(_f.proxyListen)
                            ? _f.proxyListen
                            : '127.0.0.1',
                        [for (final a in _listenAddrs) (a, a)],
                        (v) => setState(() => _f.proxyListen = v)),
                    hint: '0.0.0.0 / :: 允许局域网访问',
                  ),
                  _row('代理端口', _num(_proxyPort), hint: 'mixed inbound 监听端口'),
                  _row('退出时关闭系统代理', _check(_f.exitDisableProxy, (v) {
                    setState(() => _f.exitDisableProxy = v);
                  }), hint: '退出程序前自动还原系统代理设置'),
                  _section('TUN 模式'),
                  _row('协议栈', _dropdown(_f.tunStack, _tunStacks,
                      (v) => setState(() => _f.tunStack = v))),
                  _row('MTU', _num(_tunMtu)),
                  _row('strict_route', _check(_f.tunStrictRoute, (v) {
                    setState(() => _f.tunStrictRoute = v);
                  }), hint: '严格路由，防止流量绕过 TUN（仅 sing-box 生效，mihomo 无此选项）'),
                  _section('生成配置（内置路由模式）'),
                  _row(
                    '日志等级',
                    _dropdown(b.logLevel,
                        [for (final l in _logLevels) (l, l)],
                        (v) => setState(() => b.logLevel = v)),
                  ),
                  _row(
                    'DNS 模式',
                    _dropdown(b.dnsMode, _dnsModes,
                        (v) => setState(() => b.dnsMode = v)),
                    hint: 'fake-ip：fakeipfilter 白名单域名真实解析，其余返回假 IP',
                  ),
                  _row('IPv6', _check(b.ipv6, (v) {
                    setState(() => b.ipv6 = v);
                  }), hint: 'mihomo 全局与 DNS 的 ipv6；sing-box 同步调整解析策略与 TUN 地址'),
                  _row('解析 DNS 主', _text(_resolverDns, hint: '必须是 IP，如 223.5.5.5'),
                      hint: '用于解析 DNS 服务器自身的域名（sing-box 取主；mihomo 对应 default-nameserver）'),
                  _row('解析 DNS 备用', _text(_resolverDnsBackup, hint: '必须是 IP，如 119.29.29.29'),
                      hint: '仅 mihomo 生效（default-nameserver 填主 + 备用两个）'),
                  // sing-box DNS 服务器
                  _row('sing-box 直连 DNS', _sbDns(
                    type: b.singBoxDirect.type,
                    onType: (v) => setState(() => b.singBoxDirect.type = v),
                    addr: _sbDirectAddr,
                    port: _sbDirectPort,
                    path: _sbDirectPath,
                  )),
                  _row('sing-box 代理 DNS', _sbDns(
                    type: b.singBoxProxy.type,
                    onType: (v) => setState(() => b.singBoxProxy.type = v),
                    addr: _sbProxyAddr,
                    port: _sbProxyPort,
                    path: _sbProxyPath,
                  ), hint: '直连与代理 DNS 自动携带 domain_resolver → 解析 DNS'),
                  // mihomo DNS
                  _row('mihomo 直连 DNS',
                      _twoFields(_mihomoDirect0, _mihomoDirect1)),
                  _row('mihomo 代理 DNS',
                      _twoFields(_mihomoProxy0, _mihomoProxy1),
                      hint: '生成时自动追加 #PROXY（查询经代理组出站）'),
                  _section('clash-api'),
                  _row('启用 clash-api', _check(!b.clashAPIDisabled, (v) {
                    setState(() => b.clashAPIDisabled = !v);
                  }), hint: '关闭后生成的配置完全不含 clash-api 字段'),
                  if (!b.clashAPIDisabled) ...[
                    _row(
                      '监听地址',
                      _dropdown(
                          _clashApiListens.contains(b.clashAPI.listen)
                              ? b.clashAPI.listen
                              : '127.0.0.1',
                          [for (final a in _clashApiListens) (a, a)],
                          (v) => setState(() => b.clashAPI.listen = v)),
                    ),
                    _row('端口', _num(_clashPort),
                        hint:
                            '面板地址 http://${b.clashAPI.listen}:${b.clashAPI.port}/ui'),
                    _row('密码', _text(_clashSecret, hint: '留空表示无密码')),
                  ],
                ],
                const SizedBox(height: 12),
                const Text(
                  '提示：「生成配置」仅作用于内置路由模式（绕过大陆 / GFW列表 / 全局代理）合成的配置文件；\n'
                  '切换内核 / 代理端口 / TUN / 生成配置相关设置在下次「开启系统代理 / 开启 TUN / 启动核心」时生效；\n'
                  '日志行数与轮询间隔保存后立即生效。',
                  style: TextStyle(color: SmPalette.textDim, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        // ── 底部按钮 ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: SmPalette.bgPanel,
            border: Border(top: BorderSide(color: SmPalette.border)),
          ),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _saving ? null : _reset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: SmPalette.textMid,
                  side: const BorderSide(color: SmPalette.border),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                ),
                child: const Text('恢复默认'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: SmPalette.accent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 10),
                ),
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _viewBtn(String label, String view) {
    final active = _view == view;
    return InkWell(
      onTap: () => setState(() => _view = view),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: active ? SmPalette.accentDim : SmPalette.bgInput,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? SmPalette.accent : Colors.transparent,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? SmPalette.accent : SmPalette.textMid,
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(title,
            style: const TextStyle(
                color: SmPalette.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  Widget _row(String label, Widget child, {String? hint}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 150,
              child: Text(label,
                  style: const TextStyle(
                      color: SmPalette.textMid, fontSize: 12)),
            ),
            SizedBox(width: 220, child: child),
            if (hint != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(hint,
                    style: const TextStyle(
                        color: SmPalette.textDim, fontSize: 11)),
              ),
            ],
          ],
        ),
      );

  Widget _dropdown<T>(T value, List<(T, String)> options,
          ValueChanged<T> onChanged) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        isDense: true,
        isExpanded: true,
        items: [
          for (final (v, label) in options)
            DropdownMenuItem(
                value: v,
                child: Text(label,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) => v != null ? onChanged(v) : null,
      );

  Widget _text(TextEditingController c, {String? hint}) => TextField(
        controller: c,
        decoration: InputDecoration(hintText: hint),
      );

  Widget _num(TextEditingController c) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
      );

  Widget _check(bool value, ValueChanged<bool> onChanged) => Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
          ),
        ],
      );

  Widget _sbDns({
    required String type,
    required ValueChanged<String> onType,
    required TextEditingController addr,
    required TextEditingController port,
    required TextEditingController path,
  }) =>
      Row(
        children: [
          SizedBox(
            width: 76,
            child: DropdownButtonFormField<String>(
              initialValue: type,
              isDense: true,
              items: [
                for (final t in _singboxDnsTypes)
                  DropdownMenuItem(
                      value: t,
                      child: Text(t, style: const TextStyle(fontSize: 12))),
              ],
              onChanged: (v) => v != null ? onType(v) : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: addr,
              decoration: const InputDecoration(hintText: '地址（必填）'),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: TextField(
              controller: port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  hintText: '${_dnsDefaultPort(type)}'),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 90,
            child: TextField(
              controller: path,
              decoration: const InputDecoration(hintText: '路径'),
            ),
          ),
        ],
      );

  Widget _twoFields(TextEditingController a, TextEditingController b) => Row(
        children: [
          Expanded(
              child: TextField(
                  controller: a,
                  decoration:
                      const InputDecoration(hintText: '第一个'))),
          const SizedBox(width: 6),
          Expanded(
              child: TextField(
                  controller: b,
                  decoration:
                      const InputDecoration(hintText: '第二个'))),
        ],
      );
}
