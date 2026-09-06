/// 日志页 — 快照 + 增量、自动滚底、清空（对齐 ui_desktop/log_panel 逻辑，
/// 改为移动端整页布局）。
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
    if (lower.contains('started') || lower.contains('success')) {
      return SmPalette.green;
    }
    return SmPalette.text;
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logProvider);
    _maybeScroll(logs.length);

    return Scaffold(
      appBar: AppBar(
        title: Text('运行日志（${logs.length} 条）',
            style: const TextStyle(fontSize: 16)),
        backgroundColor: SmPalette.bgPanel,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '自动滚动',
            isSelected: _autoScroll,
            icon: Icon(
              _autoScroll
                  ? Icons.vertical_align_bottom
                  : Icons.vertical_align_bottom_outlined,
              size: 20,
              color: _autoScroll ? SmPalette.accent : SmPalette.textDim,
            ),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline,
                size: 20, color: SmPalette.textDim),
            onPressed: () => ref.read(logProvider.notifier).clear(),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text(
                '暂无日志，连接后日志将在此显示',
                style: TextStyle(color: SmPalette.textDim, fontSize: 13),
              ),
            )
          : Container(
              color: SmPalette.bg,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListView.builder(
                controller: _scroll,
                itemCount: logs.length,
                itemBuilder: (context, i) {
                  final line = logs[i];
                  return Text(
                    line,
                    maxLines: 3,
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
    );
  }
}
