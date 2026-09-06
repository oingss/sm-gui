/// 调色板 — 对齐原 React 版 App.css 的深色配色变量。
library;

import 'package:flutter/material.dart';

/// SM GUI 深色调色板。
abstract final class SmPalette {
  /// 主背景（窗口底色）。
  static const bg = Color(0xFF0f1117);

  /// 次级背景（面板/卡片）。
  static const bgPanel = Color(0xFF161923);

  /// 输入框/悬浮层背景。
  static const bgInput = Color(0xFF1d2130);

  /// 边框。
  static const border = Color(0xFF2a2f42);

  /// 主文字。
  static const text = Color(0xFFe2e6f0);

  /// 次级文字。
  static const textDim = Color(0xFF8b90a7);

  /// 主题强调色（蓝紫）。
  static const accent = Color(0xFF5b7cf6);

  /// 成功/绿色。
  static const green = Color(0xFF3ddc84);

  /// 警告/黄色。
  static const yellow = Color(0xFFf59e0b);

  /// 危险/红色。
  static const red = Color(0xFFf05252);

  /// 橙色。
  static const orange = Color(0xFFf97316);

  /// 青色。
  static const cyan = Color(0xFF22d3ee);
}
