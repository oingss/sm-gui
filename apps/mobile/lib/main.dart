// SM GUI 移动端（Android）入口：
// 数据目录取 <ApplicationDocuments>/sm_gui，引擎为 VpnEngine（平台通道桥接），
// vpnMode: true —— startCore 强制生成 tun 配置、跳过内核二进制检查。
// Android 双内核：sing-box（libbox）/ mihomo（gomobile AAR 桥），
// 内核选择由设置页保存，Kotlin 侧按 core 路由到不同的前台 VpnService。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:ui_mobile/ui_mobile.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 数据目录：<ApplicationDocuments>/sm_gui
  final docsDir = await getApplicationDocumentsDirectory();
  final dataDir = Directory('${docsDir.path}${Platform.pathSeparator}sm_gui');

  final engine = VpnEngine(maxLog: 500);
  final app = SmApp(
    dataDir: dataDir.path,
    engine: engine,
    vpnMode: true,
  );
  await app.init();
  // 引擎：连接事件流并同步原生 VPN 运行状态（进程被杀后重启恢复显示），
  // 按新契约携带当前内核查询；注入 TUN 协议栈提供者（start 时传给原生）
  engine.stackProvider = () => app.settings.tunStack;
  await engine.init(core: app.settings.core);
  // 内核不合法（如旧版 settings.json core 为空）时才回退 sing-box；
  // mihomo 选择必须能正常保存，不做强制纠正
  if (app.settings.core.isEmpty) {
    app.settings.core = coreSingBox;
    app.cfgManager.save();
  }

  runApp(ProviderScope(
    overrides: [smAppProvider.overrideWithValue(app)],
    child: const SmMobileApplication(),
  ));
}

class SmMobileApplication extends StatelessWidget {
  const SmMobileApplication({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SM GUI',
      debugShowCheckedModeBanner: false,
      theme: buildSmTheme(),
      home: const SmMobileApp(),
    );
  }
}
