import 'web_update_bridge_stub.dart'
    if (dart.library.html) 'web_update_bridge_web.dart';

/// Platform-agnostic bridge to trigger client web reloads on updates
class WebUpdateBridge {
  static void reload() {
    performWebReload();
  }
}
