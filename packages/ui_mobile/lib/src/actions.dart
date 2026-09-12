/// 统一动作执行助手（移动端）— 组织方式对齐 ui_desktop/actions.dart。
/// 捕获 AppException/ParseException → Toast。
/// 移动端无 UAC 提权/退出进程逻辑（桌面专属概念）。
library;

import 'package:flutter/material.dart';
import 'package:sm_core/sm_core.dart';
import 'package:ui_kit/ui_kit.dart';

/// 统一动作错误处理：
/// - AppException/ParseException → `[failurePrefix]: message`；
/// - 其他异常 → `[failurePrefix]: error`。
void showActionError(
  BuildContext? context,
  Object error, {
  String failurePrefix = '操作失败',
}) {
  final String msg;
  if (error is AppException) {
    msg = error.message;
  } else if (error is ParseException) {
    msg = error.message;
  } else {
    msg = '$error';
  }
  _showToast(context, '$failurePrefix: $msg', ToastType.error);
}

/// Toast 前置检查 mounted（与 async 逻辑隔离，避免跨 async 使用 context）。
void _showToast(BuildContext? context, String message, ToastType type) {
  if (context == null || !context.mounted) return;
  AppToast.show(context, message, type);
}

/// 执行一个后端动作；失败弹 Toast（前缀 [failurePrefix]），成功可选提示。
/// 返回是否成功。
Future<bool> runAction(
  BuildContext context,
  Future<void> Function() fn, {
  String failurePrefix = '操作失败',
  String? successMsg,
}) async {
  try {
    await fn();
    if (context.mounted && successMsg != null) {
      AppToast.show(context, successMsg, ToastType.success);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showActionError(context, e, failurePrefix: failurePrefix);
    }
  }
  return false;
}

/// 确认对话框（删除等危险操作用）。返回是否确认。
Future<bool> confirmDialog(BuildContext context, String message) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('确认'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认'),
        ),
      ],
    ),
  );
  return res == true;
}

/// 格式化订阅上次更新时间（unix 秒 → 本地时间字符串）。
String formatLastUpdate(int unixSec) {
  if (unixSec <= 0) return '从未更新';
  final t = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 格式化运行时长（秒 → "1h 02m 03s" / "02m 03s"）。
String formatUptime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
