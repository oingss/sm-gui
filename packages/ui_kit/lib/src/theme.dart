/// 深色主题（Material 3）— 对齐原 React 版的视觉基调。
library;

import 'package:flutter/material.dart';

import 'palette.dart';

/// 构建 SM GUI 桌面深色主题。
ThemeData buildSmTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: SmPalette.accent,
    brightness: Brightness.dark,
    primary: SmPalette.accent,
    surface: SmPalette.bgPanel,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: SmPalette.bg,
    canvasColor: SmPalette.bgPanel,
    fontFamily: 'Microsoft YaHei UI',
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: SmPalette.text, fontSize: 13),
      bodySmall: TextStyle(color: SmPalette.textDim, fontSize: 12),
      titleMedium: TextStyle(color: SmPalette.text, fontSize: 14),
    ),
    dividerColor: SmPalette.border,
    splashFactory: InkSparkle.splashFactory,
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor:
            WidgetStatePropertyAll(SmPalette.bgInput),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: const WidgetStatePropertyAll(
          BorderSide(color: SmPalette.border),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SmPalette.bgInput,
      hintStyle: const TextStyle(color: SmPalette.textDim),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SmPalette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SmPalette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SmPalette.accent),
      ),
      isDense: true,
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        foregroundColor: SmPalette.text,
        minimumSize: const Size(140, 34),
        textStyle: const TextStyle(fontSize: 13),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? SmPalette.accent
            : SmPalette.bgInput,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : SmPalette.textDim,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? SmPalette.accent
            : Colors.transparent,
      ),
      side: const BorderSide(color: SmPalette.textDim),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: SmPalette.bgInput),
      textStyle: TextStyle(color: SmPalette.text, fontSize: 12),
      waitDuration: Duration(milliseconds: 400),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: SmPalette.bgPanel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: SmPalette.border),
      ),
    ),
  );
}
