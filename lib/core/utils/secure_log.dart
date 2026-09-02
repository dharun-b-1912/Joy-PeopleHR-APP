import 'package:flutter/foundation.dart';

/// Secure logging utility that only outputs in debug mode.
/// In release builds, all calls are stripped by tree-shaking.
void secureLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
