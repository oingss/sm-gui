/// 引擎控制抽象 — 按「移动端将来是嵌入式库而非子进程」设计：
/// start 收配置内容与路径参数，由实现层决定拉起进程或喂给 libbox。
library;

import 'core_process.dart';

/// 内核标识（与 settings.dart 的 coreSingBox/coreMihomo 常量一致）。
abstract final class CoreTypes {
  static const singBox = 'sing-box';
  static const mihomo = 'mihomo';
}

/// 引擎启动参数。
class EngineRunConfig {
  /// 内核类型："sing-box" | "mihomo"
  final String core;

  /// 内核可执行文件路径（桌面端）。
  final String binPath;

  /// 运行目录（存放配置与规则文件的目录，桌面端为 <exe>/run，与 Go 版一致）。
  final String runDir;

  /// 已写好的配置文件路径（runDir/config.json 或 config.yaml）。
  final String configPath;

  const EngineRunConfig({
    required this.core,
    required this.binPath,
    required this.runDir,
    required this.configPath,
  });
}

/// 引擎控制接口。桌面端 = 子进程；移动端二期 = libbox 嵌入实现。
abstract interface class Engine {
  Future<void> start(EngineRunConfig config);
  Future<void> stop();
  ProcessStatus get status;
  Stream<String> get logLines;
  Stream<ProcessStatus> get statusChanges;
  List<String> get logSnapshot;

  /// 更新日志保留行数（对齐 Go: sbProcess.SetMaxLog，设置保存后立即生效）。
  void setMaxLog(int maxLog);
}

/// 桌面端引擎实现：拉起内核子进程。
/// 内核参数构造对齐 Go 版（app.go）：
///   sing-box: run -D <runDir> -c <configPath>
///   mihomo:   -d <runDir> -f <configPath>
class DesktopEngine implements Engine {
  final CoreProcess _process;

  DesktopEngine({int maxLog = 500}) : _process = CoreProcess(maxLog: maxLog);

  @override
  Future<void> start(EngineRunConfig config) {
    final List<String> args;
    switch (config.core) {
      case CoreTypes.singBox:
        args = ['run', '-D', config.runDir, '-c', config.configPath];
      case CoreTypes.mihomo:
        args = ['-d', config.runDir, '-f', config.configPath];
      default:
        throw ArgumentError('未知内核类型: ${config.core}');
    }
    return _process.start(config.binPath, args, label: config.core);
  }

  @override
  Future<void> stop() => _process.stop();

  @override
  ProcessStatus get status => _process.getStatus();

  @override
  Stream<String> get logLines => _process.logLines;

  @override
  Stream<ProcessStatus> get statusChanges => _process.statusChanges;

  @override
  List<String> get logSnapshot => _process.getLog();

  @override
  void setMaxLog(int maxLog) => _process.setMaxLog(maxLog);
}
