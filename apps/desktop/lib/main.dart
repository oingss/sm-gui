// SM GUI 桌面端入口：初始化 SmApp（对齐 Go 版 portable 目录布局 + DesktopEngine），
// 接入窗口管理（window_manager）与系统托盘（tray_manager），
// 解析 `--silent`（自启动静默：不显示主窗口，仅托盘），注入 Riverpod 后启动主界面。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sm_core/sm_core.dart';
import 'package:sm_engine/sm_engine.dart';
import 'package:ui_desktop/ui_desktop.dart';
import 'package:ui_kit/ui_kit.dart';

import 'startup_args.dart';
import 'tray_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 自启动静默启动：applyAutoStart 写入的自启动项带 `--silent` 参数
  final silent = hasSilentArg(Platform.executableArguments);

  // portable 目录布局（对齐 Go 版 getDataDir/getConfigsDir/getRunDir）：
  // exe 同级为 data/（节点与设置持久化）、configs/、run/、bin/，
  // 全部数据落在程序目录内，移动程序目录即整体搬迁。
  // 内置路由规则集（run/rules/）与 bin/ 内核由 CI 打包时放入，程序不管理。
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final app = SmApp(
    dataDir: _join(exeDir, 'data'),
    appRootDir: exeDir,
    engine: DesktopEngine(maxLog: 500),
  );
  await app.init();

  // 窗口（1100x750 / SM GUI / 关闭隐藏到托盘）与系统托盘
  final navigatorKey = GlobalKey<NavigatorState>();
  final shell = DesktopShell(app: app, navigatorKey: navigatorKey);
  await shell.init(silent: silent);

  runApp(ProviderScope(
    overrides: [smAppProvider.overrideWithValue(app)],
    child: SmDesktopApplication(navigatorKey: navigatorKey),
  ));
}

String _join(String a, String b) => a.endsWith(Platform.pathSeparator)
    ? '$a$b'
    : '$a${Platform.pathSeparator}$b';

class SmDesktopApplication extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const SmDesktopApplication({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SM GUI',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildSmTheme(),
      home: const SmDesktopApp(),
    );
  }
}
