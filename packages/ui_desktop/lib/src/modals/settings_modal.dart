/// 设置弹窗 — 对齐 SettingsPanel 核心项：
/// 代理端口/监听、TUN stack/MTU/strictRoute、订阅 UA/超时、日志行数、
/// 内置模式 DNS 参数、开机自启动/静默启动、退出关闭系统代理、内核选择。
/// 保存统一走 app.saveSettings（normalize/validate/自启动项同步）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

import '../providers.dart';

const _singBoxDnsTypes = ['tcp', 'udp', 'tls', 'https', 'quic'];
const _dnsDefaultPorts = {
  'udp': 53,
  'tcp': 53,
  'tls': 853,
  'https': 443,
  'quic': 443,
};

class SettingsModal extends ConsumerStatefulWidget {
  const SettingsModal({super.key});

  @override
  ConsumerState<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends ConsumerState<SettingsModal> {
  late final Settings _s;
  late final BuiltinSettings _b;
  late final TextEditingController _proxyPort;
  late final TextEditingController _tunMtu;
  late final TextEditingController _subTimeout;
  late final TextEditingController _logLines;
  late final TextEditingController _subUa;
  late final TextEditingController _resolverDns;
  late final TextEditingController _resolverDnsBackup;
  late final TextEditingController _sbDirectPort;
  late final TextEditingController _sbProxyPort;
  late final TextEditingController _sbDirectAddr;
  late final TextEditingController _sbProxyAddr;
  late final TextEditingController _mihomoDirect0;
  late final TextEditingController _mihomoDirect1;
  late final TextEditingController _mihomoProxy0;
  late final TextEditingController _mihomoProxy1;
  late final TextEditingController _clashPort;
  late String _core;
  late String _proxyListen;
  late bool _exitDisableProxy;
  late bool _autoStart;
  late bool _silentStart;
  late String _tunStack;
  late bool _tunStrictRoute;
  late String _dnsMode;
  late String _sbDirectType;
  late String _sbProxyType;
  late bool _saving = false;

  @override
  void initState() {
    super.initState();
    final app = ref.read(smAppProvider);
    _s = app.settings;
    _b = _s.builtin;
    _core = _s.core;
    _proxyListen = _s.proxyListen;
    _exitDisableProxy = _s.exitDisableProxy;
    _autoStart = _s.autoStart;
    _silentStart = _s.silentStart;
    _tunStack = _s.tunStack;
    _tunStrictRoute = _s.tunStrictRoute;
    _dnsMode = _b.dnsMode;
    _sbDirectType = _b.singBoxDirect.type;
    _sbProxyType = _b.singBoxProxy.type;
    _proxyPort = TextEditingController(text: '${_s.proxyPort}');
    _tunMtu = TextEditingController(text: '${_s.tunMTU}');
    _subTimeout = TextEditingController(text: '${_s.subTimeoutSec}');
    _logLines = TextEditingController(text: '${_s.logMaxLines}');
    _subUa = TextEditingController(text: _s.subUserAgent);
    _resolverDns = TextEditingController(text: _b.resolverDNS);
    _resolverDnsBackup = TextEditingController(text: _b.resolverDNSBackup);
    _sbDirectPort = TextEditingController(
        text: _b.singBoxDirect.port > 0 ? '${_b.singBoxDirect.port}' : '');
    _sbProxyPort = TextEditingController(
        text: _b.singBoxProxy.port > 0 ? '${_b.singBoxProxy.port}' : '');
    _sbDirectAddr = TextEditingController(text: _b.singBoxDirect.address);
    _sbProxyAddr = TextEditingController(text: _b.singBoxProxy.address);
    _mihomoDirect0 = TextEditingController(
        text: _b.mihomoDirect != null && _b.mihomoDirect!.isNotEmpty
            ? _b.mihomoDirect![0]
            : '');
    _mihomoDirect1 = TextEditingController(
        text: _b.mihomoDirect != null && _b.mihomoDirect!.length > 1
            ? _b.mihomoDirect![1]
            : '');
    _mihomoProxy0 = TextEditingController(
        text: _b.mihomoProxy != null && _b.mihomoProxy!.isNotEmpty
            ? _b.mihomoProxy![0]
            : '');
    _mihomoProxy1 = TextEditingController(
        text: _b.mihomoProxy != null && _b.mihomoProxy!.length > 1
            ? _b.mihomoProxy![1]
            : '');
    _clashPort = TextEditingController(text: '${_b.clashAPI.port}');
  }

  @override
  void dispose() {
    for (final c in [
      _proxyPort, _tunMtu, _subTimeout, _logLines, _subUa,
      _resolverDns, _resolverDnsBackup, _sbDirectPort, _sbProxyPort,
      _sbDirectAddr, _sbProxyAddr, _mihomoDirect0, _mihomoDirect1,
      _mihomoProxy0, _mihomoProxy1, _clashPort,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final app = ref.read(smAppProvider);
    setState(() => _saving = true);
    // 表单值写入设置快照（克隆），校验失败不污染运行中的设置对象
    final ns = Settings.fromJson(_s.toJson());
    final nb = ns.builtin;
    ns.core = _core;
    ns.proxyListen = _proxyListen.trim();
    ns.proxyPort = int.tryParse(_proxyPort.text) ?? 0;
    ns.exitDisableProxy = _exitDisableProxy;
    ns.autoStart = _autoStart;
    // 静默启动仅在自启动开启时有意义
    ns.silentStart = _autoStart && _silentStart;
    ns.tunStack = _tunStack;
    ns.tunMTU = int.tryParse(_tunMtu.text) ?? 0;
    ns.tunStrictRoute = _tunStrictRoute;
    ns.subUserAgent = _subUa.text.trim();
    ns.subTimeoutSec = int.tryParse(_subTimeout.text) ?? 0;
    ns.logMaxLines = int.tryParse(_logLines.text) ?? 0;
    nb.dnsMode = _dnsMode;
    nb.resolverDNS = _resolverDns.text.trim();
    nb.resolverDNSBackup = _resolverDnsBackup.text.trim();
    nb.singBoxDirect = nb.singBoxDirect
      ..type = _sbDirectType
      ..address = _sbDirectAddr.text.trim()
      ..port = int.tryParse(_sbDirectPort.text) ?? 0;
    nb.singBoxProxy = nb.singBoxProxy
      ..type = _sbProxyType
      ..address = _sbProxyAddr.text.trim()
      ..port = int.tryParse(_sbProxyPort.text) ?? 0;
    nb.mihomoDirect = [
      _mihomoDirect0.text.trim(),
      _mihomoDirect1.text.trim(),
    ];
    nb.mihomoProxy = [
      _mihomoProxy0.text.trim(),
      _mihomoProxy1.text.trim(),
    ];
    try {
      // normalize/validate + 持久化 + 内核切换路径记忆 + 日志行数生效 + 自启动项同步
      await app.saveSettings(ns);
      ref.read(settingsVersionProvider.notifier).bump();
      if (mounted) {
        AppToast.show(context, '设置已保存', ToastType.success);
        Navigator.of(context).pop();
      }
    } on AppException catch (e) {
      // 「保存设置失败…」/「设置已保存，但自启动项更新失败…」：直接展示
      ref.read(settingsVersionProvider.notifier).bump();
      if (mounted) {
        AppToast.show(context, e.message, ToastType.error);
      }
    } on ParseException catch (e) {
      if (mounted) {
        AppToast.show(context, '保存失败: ${e.message}', ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '保存失败: $e', ToastType.error);
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _section('内核与代理'),
        _row('代理内核', _dropdown(_core, const [
          (coreSingBox, 'sing-box（配置为 JSON）'),
          (coreMihomo, 'mihomo / Clash.Meta（配置为 YAML）'),
        ], (v) => setState(() => _core = v))),
        _row('监听地址', _dropdown(_proxyListen, const [
          ('127.0.0.1', '127.0.0.1'),
          ('0.0.0.0', '0.0.0.0（允许局域网）'),
          ('::', '::（允许局域网）'),
        ], (v) => setState(() => _proxyListen = v))),
        _row('代理端口',
            _numField(_proxyPort, hint: 'mixed inbound 监听端口')),

        _section('启动'),
        _row('开机自启动',
            _checkbox(_autoStart, (v) => setState(() {
                  _autoStart = v;
                  if (!v) _silentStart = false;
                }))),
        _row('静默启动', _checkbox(
          _silentStart,
          (v) => setState(() => _silentStart = v),
          enabled: _autoStart,
        )),
        _row('退出时关闭系统代理',
            _checkbox(_exitDisableProxy, (v) => setState(() => _exitDisableProxy = v))),

        _section('TUN 模式'),
        _row('协议栈', _dropdown(_tunStack, const [
          ('gvisor', 'gvisor（默认，兼容性好）'),
          ('system', 'system（性能好，需内核支持）'),
          ('mixed', 'mixed（混合模式）'),
        ], (v) => setState(() => _tunStack = v))),
        _row('MTU', _numField(_tunMtu)),
        _row('strict_route',
            _checkbox(_tunStrictRoute, (v) => setState(() => _tunStrictRoute = v))),

        _section('订阅'),
        _row('User-Agent', _textField(_subUa, hint: 'clash.meta')),
        _row('请求超时（秒）', _numField(_subTimeout)),
        _row('日志保留行数', _numField(_logLines)),

        _section('内置路由模式参数'),
        _row('DNS 模式', _dropdown(_dnsMode, const [
          ('redir-host', 'redir-host（真实 IP）'),
          ('fake-ip', 'fake-ip（假 IP）'),
        ], (v) => setState(() => _dnsMode = v))),
        _row('解析 DNS 主', _textField(_resolverDns, hint: '必须是 IP，如 223.5.5.5')),
        _row('解析 DNS 备用', _textField(_resolverDnsBackup, hint: '仅 mihomo 生效')),
        _row('sing-box 直连 DNS', _sbDnsField(
          type: _sbDirectType,
          onType: (v) => setState(() => _sbDirectType = v),
          addr: _sbDirectAddr,
          port: _sbDirectPort,
        )),
        _row('sing-box 代理 DNS', _sbDnsField(
          type: _sbProxyType,
          onType: (v) => setState(() => _sbProxyType = v),
          addr: _sbProxyAddr,
          port: _sbProxyPort,
        )),
        _row('mihomo 直连 DNS',
            _twoFields(_mihomoDirect0, _mihomoDirect1)),
        _row('mihomo 代理 DNS',
            _twoFields(_mihomoProxy0, _mihomoProxy1)),

        const SizedBox(height: 8),
        const Text(
          '提示：「内置路由模式参数」仅作用于绕过大陆 / GFW列表 / 全局代理三种模式合成的配置；'
          '内核 / 端口 / TUN 相关设置在下次「启动核心 / 开启系统代理 / 开启 TUN」时生效。',
          style: TextStyle(color: SmPalette.textDim, fontSize: 11),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ModalButton(
              label: '取消',
              onPressed: () => Navigator.of(context).pop(),
            ),
            ModalButton(
              label: _saving ? '保存中…' : '保存',
              primary: true,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ],
    );
  }

  // ─── 小部件 ───────────────────────────────────────────────────────────────

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(title,
            style: const TextStyle(
                color: SmPalette.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  Widget _row(String label, Widget child) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(
                      color: SmPalette.textDim, fontSize: 12)),
            ),
            Expanded(child: child),
          ],
        ),
      );

  Widget _dropdown<T>(
    T value,
    List<(T, String)> options,
    ValueChanged<T> onChanged,
  ) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        items: [
          for (final (v, label) in options)
            DropdownMenuItem(value: v, child: Text(label)),
        ],
        onChanged: (v) => v != null ? onChanged(v) : null,
      );

  Widget _textField(TextEditingController c, {String? hint}) =>
      TextField(controller: c, decoration: InputDecoration(hintText: hint));

  Widget _numField(TextEditingController c, {String? hint}) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: hint),
      );

  Widget _checkbox(bool value, ValueChanged<bool> onChanged,
          {bool enabled = true}) =>
      SizedBox(
        width: 16,
        height: 16,
        child: Checkbox(
          value: value,
          onChanged: enabled ? (v) => onChanged(v ?? false) : null,
        ),
      );

  Widget _sbDnsField({
    required String type,
    required ValueChanged<String> onType,
    required TextEditingController addr,
    required TextEditingController port,
  }) =>
      Row(
        children: [
          SizedBox(
            width: 90,
            child: DropdownButtonFormField<String>(
              initialValue: type,
              items: [
                for (final t in _singBoxDnsTypes)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => v != null ? onType(v) : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
                controller: addr,
                decoration: const InputDecoration(hintText: '地址（必填）')),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            child: TextField(
              controller: port,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  hintText: '${_dnsDefaultPorts[type] ?? 53}'),
            ),
          ),
        ],
      );

  Widget _twoFields(TextEditingController a, TextEditingController b) =>
      Row(
        children: [
          Expanded(
              child: TextField(
                  controller: a,
                  decoration: const InputDecoration(hintText: '第一个'))),
          const SizedBox(width: 6),
          Expanded(
              child: TextField(
                  controller: b,
                  decoration: const InputDecoration(hintText: '第二个'))),
        ],
      );
}
