import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Top-style toasts mirroring the portal's react-hot-toast usage.
class AppToast {
  static void success(String msg) => _show(msg, AppColors.brand600);
  static void error(String msg) => _show(msg, AppColors.rose);

  static void _show(String msg, Color bg) {
    Fluttertoast.showToast(
      msg: msg,
      gravity: ToastGravity.TOP,
      backgroundColor: bg,
      textColor: Colors.white,
      fontSize: 14,
      toastLength: Toast.LENGTH_LONG,
    );
  }
}
