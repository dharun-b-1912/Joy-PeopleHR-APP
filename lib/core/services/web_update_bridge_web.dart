// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:js' as js;

/// Web implementation of WebUpdateBridge
void performWebReload() {
  try {
    if (js.context.hasProperty('joyPerformWebUpdate')) {
      js.context.callMethod('joyPerformWebUpdate');
      return;
    }
  } catch (_) {}

  try {
    html.window.location.reload();
  } catch (_) {
    html.window.location.href = html.window.location.href;
  }
}
