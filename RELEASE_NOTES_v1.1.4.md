# JOY PeopleHR — Release Notes v1.1.4 (Build 21)

## Google Play Console Release Notes (Ready to Copy-Paste)

### English (United States) - en-US / English (India) - en-IN
```text
• Fixed immediate app startup crash on OPPO and compatible Android devices.
• Enhanced Android 15 edge-to-edge system bar compatibility and window stability.
• Restored legacy native library packaging for seamless performance on Android 7.0 through Android 15.
• Improved startup memory handling and background push notification reliability.
• General performance, attendance check-in, and document viewer stability improvements.
```

---

## Detailed Technical Release Notes (v1.1.4+21)

### 1. Critical Startup Crash Fix (Release-Blocking Resolution)
- **Resolved "JOY PeopleHR keeps stopping" crash:** Fixed an issue where the application terminated immediately upon launch on OPPO CPH2505 and other compatible Android devices.
- **Native Activity Restoration:** Reverted `MainActivity` to the standard, rock-solid `FlutterActivity` base, eliminating invalid premature window decor access and theme incompatibilities during early Android lifecycle initialization.
- **Native Library Extraction (`extractNativeLibs="true"`):** Restored `useLegacyPackaging = true` in Gradle packaging options to guarantee native JNI `.so` libraries (`libflutter.so`, `libapp.so`) extract cleanly on all OEM device kernels and file systems without `dlopen` failures.

### 2. Android 15 & System Bar Compatibility
- **Clean Flutter Edge-to-Edge:** Replaced fragile native Android insets hooks with Flutter's official `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`, ensuring seamless transparent status and navigation bars across 3-button and gesture navigation modes on all supported OS versions.

### 3. R8 / ProGuard Optimization Hardening
- **Protected Flutter Engine JNI Bridge:** Restored essential `-keep class io.flutter.** { *; }` and `-keep class io.flutter.plugins.** { *; }` ProGuard rules to ensure native C++ engine signatures are never stripped or obfuscated during release minification.
- **Protected Firebase Services:** Preserved Firebase messaging, instance ID, and component discovery classes to prevent background push initialization failures.
- **Removed Destructive Repackaging:** Eliminated `-repackageclasses ''` and R8 full-mode aggressive inlining that broke reflection and dynamic component resolution.
- **Safe Resource Shrinking:** Configured `tools:shrinkMode="safe"` to retain FileProvider XML paths (`image_share_filepaths`) and document viewing assets.

### 4. Build & Distribution Artifacts
- **Play Console AAB:** `JOY_PeopleHR_v1.1.4_build21.aab` *(65.7 MB)*
- **Direct Test APK:** `JOY_PeopleHR_v1.1.4_build21.apk` *(33.2 MB)*
- **Target SDK:** 36 (Android 15/16)
- **Min SDK:** 24 (Android 7.0 Nougat+)
- **Automated Tests:** 123/123 passed (`flutter test`).
- **Static Analysis:** 0 errors / 0 warnings (`flutter analyze`).
