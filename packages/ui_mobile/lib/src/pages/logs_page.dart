/// 日志页 — 与桌面端 widgets/log_panel.dart 结构完全一致：
/// 工具栏（标题 + 条数 + 自动滚动勾选 + 清空）+ 日志体，快照 + 增量、自动滚底、分级着色。
/// 不含自己的 Scaffold/AppBar，作为内容区嵌入移动端主壳。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../providers.dart';

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  final ScrollController _scroll = ScrollController();
  bool _autoScroll = true;
  int _lastCount = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeScroll(int count) {
    if (!_autoScroll || count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Color _lineColor(String line) {
    final lower = line.toLowerCase();
    if (lower.contains('error') || lower.contains('fatal')) {
      return SmPalette.red;
    }
    if (lower.contains('warn')) return SmPalette.yellow;
    if (lower.contains('started') ||
        lower.contains('已启动') ||
        lower.contains('success')) {
      return SmPalette.green;
    }
    return SmPalette.text;
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logProvider);
    _maybeScroll(logs.length);

    return Container(
      color: SmPalette.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 工具栏（与桌面 LogPanel 一致：标题 + 条数 + 自动滚动 + 清空）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: SmPalette.bgPanel,
              border: Border(bottom: BorderSide(color: SmPalette.border)),
            ),
            child: Row(
              children: [
                const Text('运行日志',
                    style: TextStyle(color: SmPalette.text, fontSize: 13)),
                const SizedBox(width: 10),
                Text('${logs.length} 条',
                    style: const TextStyle(
                        color: SmPalette.textDim, fontSize: 12)),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: _autoScroll,
                          onChanged: (v) =>
                              setState(() => _autoScroll = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('自动滚动',
                          style:
                              TextStyle(color: SmPalette.textDim, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => ref.read(logProvider.notifier).clear(),
                  child: const Text('清空',
                      style:
                          TextStyle(color: SmPalette.textDim, fontSize: 12)),
                ),
              ],
            ),
          ),
          // 日志体
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      '暂无日志，连接后日志将在此显示',
                      style: TextStyle(color: SmPalette.textDim, fontSize: 12),
                    ),
                  )
                : Container(
                    color: SmPalette.bg,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ListView.builder(
                      controller: _scroll,
                      itemCount: logs.length,
                      itemExtent: 18,
                      itemBuilder: (context, i) {
                        final line = logs[i];
                        return Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _lineColor(line),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
