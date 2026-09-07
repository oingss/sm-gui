/// 设置页 — 移动端保留项：内核选择（sing-box / mihomo 双内核）、
/// 代理端口（mixed 端口显示用）、路由模式、DNS 模式、
/// 配置文件选择（自定义模式）、订阅 UA/超时、日志行数、内置模式 DNS 参数。
/// 桌面专属概念（系统代理/TUN 开关/提权/自启动）隐藏——
/// 移动端恒为 Android VPN 模式。保存统一走 app.saveSettings
/// （normalize/validate 流程对齐 apps/desktop settings_modal）。
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

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late Settings _s;
  late BuiltinSettings _b;
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
  late String _routingMode;
  late String _dnsMode;
  late String _core;
  late String _sbDirectType;
  late String _sbProxyType;
  String? _configFile;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _subTimeout = TextEditingController();
    _logLines = TextEditingController();
    _subUa = TextEditingController();
    _resolverDns = TextEditingController();
    _resolverDnsBackup = TextEditingController();
    _sbDirectPort = TextEditingController();
    _sbProxyPort = TextEditingController();
    _sbDirectAddr = TextEditingController();
    _sbProxyAddr = TextEditingController();
    _mihomoDirect0 = TextEditingController();
    _mihomoDirect1 = TextEditingController();
    _mihomoProxy0 = TextEditingController();
    _mihomoProxy1 = TextEditingController();
    _loadForm(ref.read(smAppProvider).settings);
  }

  /// 用设置快照填充表单（初始 & 恢复默认时复用，对齐桌面 SettingsPanel._loadForm）。
  void _loadForm(Settings s) {
    _s = s;
    _b = _s.builtin;
    _routingMode = _s.routingMode;
    _dnsMode = _b.dnsMode;
    _core = _s.core;
    _sbDirectType = _b.singBoxDirect.type;
    _sbProxyType = _b.singBoxProxy.type;
    _configFile = _s.activeConfigPath().isEmpty ? null : _s.activeConfigPath();
    _subTimeout.text = '${_s.subTimeoutSec}';
    _logLines.text = '${_s.logMaxLines}';
    _subUa.text = _s.subUserAgent;
    _resolverDns.text = _b.resolverDNS;
    _resolverDnsBackup.text = _b.resolverDNSBackup;
    _sbDirectPort.text =
        _b.singBoxDirect.port > 0 ? '${_b.singBoxDirect.port}' : '';
    _sbProxyPort.text =
        _b.singBoxProxy.port > 0 ? '${_b.singBoxProxy.port}' : '';
    _sbDirectAddr.text = _b.singBoxDirect.address;
    _sbProxyAddr.text = _b.singBoxProxy.address;
    _mihomoDirect0.text = _b.mihomoDirect != null && _b.mihomoDirect!.isNotEmpty
        ? _b.mihomoDirect![0]
        : '';
    _mihomoDirect1.text =
        _b.mihomoDirect != null && _b.mihomoDirect!.length > 1
            ? _b.mihomoDirect![1]
            : '';
    _mihomoProxy0.text = _b.mihomoProxy != null && _b.mihomoProxy!.isNotEmpty
        ? _b.mihomoProxy![0]
        : '';
    _mihomoProxy1.text = _b.mihomoProxy != null && _b.mihomoProxy!.length > 1
        ? _b.mihomoProxy![1]
        : '';
  }

  /// 恢复默认（保留内核选择，避免误切内核，对齐桌面 SettingsPanel._reset）。
  void _resetForm() {
    final keepCore = _core;
    final def = Settings.defaults();
    def.core = keepCore;
    setState(() => _loadForm(def));
  }

  @override
  void dispose() {
    for (final c in [
      _subTimeout, _logLines, _subUa, _resolverDns, _resolverDnsBackup,
      _sbDirectPort, _sbProxyPort, _sbDirectAddr, _sbProxyAddr,
      _mihomoDirect0, _mihomoDirect1, _mihomoProxy0, _mihomoProxy1,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isCustom => _routingMode == modeCustom;

  /// 切换内核时，自定义配置文件跟随切换到该内核记住的文件。
  void _onCoreChanged(String core) {
    setState(() {
      _core = core;
      final remembered =
          core == coreMihomo ? _s.configPathMihomo : _s.configPathSingBox;
      _configFile = remembered.isEmpty ? null : remembered;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final app = ref.read(smAppProvider);
    setState(() => _saving = true);
    // 表单值写入设置快照（克隆），校验失败不污染运行中的设置对象
    final ns = Settings.fromJson(_s.toJson());
    final nb = ns.builtin;
    // 移动端恒为 Android VPN 模式；内核可选 sing-box / mihomo
    ns.core = _core;
    ns.routingMode = _routingMode;
    if (_isCustom && _configFile != null) {
      ns.setCoreConfigPath(_core, _configFile!);
    }
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
      // normalize/validate + 持久化 + 日志行数立即生效（对齐桌面流程）
      await app.saveSettings(ns);
      ref.read(settingsVersionProvider.notifier).bump();
      if (mounted) {
        AppToast.show(context, '设置已保存', ToastType.success);
      }
    } on AppException catch (e) {
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

  // ─── 构建 ──────────────────────────────────────────────────────────────────
  // 与桌面端 SettingsPanel 结构一致：滚动表单体 + 底部固定按钮栏（恢复默认 / 保存）；
  // 不含自己的 Scaffold/AppBar，作为内容区嵌入移动端主壳。

  @override
  Widget build(BuildContext context) {
    final configFiles = ref.watch(configFilesProvider).valueOrNull;
    final settings = ref.watch(settingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
          _section('代理与路由'),
          _infoRow('代理端口（mixed）', '${settings.proxyPort}',
              hint: 'VPN 模式下仅显示，本地调试用'),
          _dropdownRow('内核', _core, const [
            (coreSingBox, 'sing-box'),
            (coreMihomo, 'mihomo'),
          ], _onCoreChanged),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              '切换内核后需重新连接生效',
              style: TextStyle(color: SmPalette.textDim, fontSize: 11),
            ),
          ),
          _dropdownRow('路由模式', _routingMode, const [
            (modeCustom, '自定义（跟随配置文件）'),
            (modeBypass, '内置：绕过大陆'),
            (modeBlacklist, '内置：GFW 列表'),
            (modeGlobal, '内置：全局代理'),
          ], (v) => setState(() => _routingMode = v)),
          if (_isCustom) ...[
            _dropdownRow(
              '配置文件',
              _configFile ?? '',
              [
                ('', '未选择'),
                for (final f in configFiles ?? const <String>[]) (f, f),
              ],
              (v) => setState(() => _configFile = v.isEmpty ? null : v),
            ),
          ],

          _section('内置模式 DNS 参数'),
          _dropdownRow('DNS 模式', _dnsMode, const [
            ('redir-host', 'redir-host（真实 IP）'),
            ('fake-ip', 'fake-ip（假 IP）'),
          ], (v) => setState(() => _dnsMode = v)),
          _fieldRow('解析 DNS 主', _resolverDns, hint: '必须是 IP，如 223.5.5.5'),
          _fieldRow('解析 DNS 备用', _resolverDnsBackup, hint: '仅 mihomo 生效'),
          _sbDnsField('sing-box 直连 DNS', _sbDirectType,
              (v) => setState(() => _sbDirectType = v), _sbDirectAddr,
              _sbDirectPort),
          _sbDnsField('sing-box 代理 DNS', _sbProxyType,
              (v) => setState(() => _sbProxyType = v), _sbProxyAddr,
              _sbProxyPort),
          _twoFieldRow('mihomo 直连 DNS', _mihomoDirect0, _mihomoDirect1),
          _twoFieldRow('mihomo 代理 DNS', _mihomoProxy0, _mihomoProxy1),

          _section('订阅'),
          _fieldRow('User-Agent', _subUa, hint: 'clash.meta'),
          _numFieldRow('请求超时（秒）', _subTimeout),

          _section('日志'),
          _numFieldRow('日志保留行数', _logLines),

          const SizedBox(height: 8),
          const Text(
            '提示：「内置模式 DNS 参数」仅作用于绕过大陆 / GFW 列表 / 全局代理三种模式'
            '合成的 VPN 配置；移动端恒为 Android VPN 模式，TUN 由原生层建立。',
            style: TextStyle(color: SmPalette.textDim, fontSize: 11),
          ),
          const SizedBox(height: 24),
            ],
          ),
        ),
        // ── 底部按钮（与桌面 SettingsPanel 一致：恢复默认 / 保存）──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: SmPalette.bgPanel,
            border: Border(top: BorderSide(color: SmPalette.border)),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: _saving ? null : _resetForm,
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
        ),
      ],
    );
  }

  // ─── 表单小部件 ────────────────────────────────────────────────────────────

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(title,
            style: const TextStyle(
                color: SmPalette.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );

  Widget _infoRow(String label, String value, {String? hint}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: SmPalette.textDim, fontSize: 13)),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: SmPalette.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                if (hint != null)
                  Text(hint,
                      style: const TextStyle(
                          color: SmPalette.textDim, fontSize: 10)),
              ],
            ),
          ],
        ),
      );

  Widget _fieldRow(String label, TextEditingController c, {String? hint}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: SmPalette.textDim, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(controller: c, decoration: InputDecoration(hintText: hint)),
          ],
        ),
      );

  Widget _numFieldRow(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: SmPalette.textDim, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
                controller: c, keyboardType: TextInputType.number),
          ],
        ),
      );

  Widget _dropdownRow<T>(
    String label,
    T value,
    List<(T, String)> options,
    ValueChanged<T> onChanged,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: SmPalette.textDim, fontSize: 12)),
            const SizedBox(height: 4),
            DropdownButtonFormField<T>(
              initialValue: value,
              isExpanded: true,
              items: [
                for (final (v, l) in options)
                  DropdownMenuItem(value: v, child: Text(l)),
              ],
              onChanged: (v) => v != null ? onChanged(v) : null,
            ),
          ],
        ),
      );

  Widget _sbDnsField(
    String label,
    String type,
    ValueChanged<String> onType,
    TextEditingController addr,
    TextEditingController port,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: SmPalette.textDim, fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<String>(
                    initialValue: type,
                    isExpanded: true,
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
                      decoration:
                          const InputDecoration(hintText: '地址（必填）')),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        hintText: '${_dnsDefaultPorts[type] ?? 53}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _twoFieldRow(
          String label, TextEditingController a, TextEditingController b) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: SmPalette.textDim, fontSize: 12)),
            const SizedBox(height: 4),
            Row(
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
            ),
          ],
        ),
      );
}
