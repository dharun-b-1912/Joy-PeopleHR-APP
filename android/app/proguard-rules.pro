# ============================================================
# ProGuard / R8 Rules for JOY PeopleHR
# Optimized for Google Play Console High DEX Code Optimization
# ============================================================

# Strip verbose/debug logs in release build for memory reduction
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
}

# ─── Flutter Embedding & Plugin Bridge ──────────────────────────
# Keep only public embedding/plugin entrypoints so R8 can obfuscate & shrink internals
-keep class com.joypeoplehr.app.MainActivity { *; }
-keep class io.flutter.embedding.android.FlutterActivity { *; }
-keep class io.flutter.embedding.engine.FlutterJNI { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }

# ─── SharedPreferences Plugin (Fix NoSuchMethodError under R8) ───
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembers class io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembernames class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ─── Firebase & Google Play Services ────────────────────────────
# Keep only service/provider entrypoints instead of keeping all Firebase/GMS classes
-keep class * extends com.google.firebase.messaging.FirebaseMessagingService { *; }
-keep class com.google.firebase.components.ComponentRegistrar { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.firebase.provider.FirebaseInitProvider { *; }
-dontwarn com.google.firebase.**

# ─── Flutter Local Notifications ────────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }

# ─── Kotlin Serialization & Annotations ─────────────────────────
-keepattributes *Annotation*, InnerClasses, EnclosingMethod, Signature
-dontwarn kotlinx.serialization.**
-keepclassmembers class * {
    @kotlinx.serialization.Serializable <fields>;
}

# ─── Native JNI Methods ─────────────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}

# ─── Enums & Parcelables ────────────────────────────────────────
-keepclassmembers class * extends java.lang.Enum {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# ─── Gson Serialization ─────────────────────────────────────────
-dontwarn sun.misc.**
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ─── Image Compression & JNI Bridge ──────────────────────────────
-keep class com.fluttercandies.flutter_image_compress.** { *; }

# ─── PDFx & Document Viewing ────────────────────────────────────
-keep class io.scer.pdfx.** { *; }

# ─── Open Filex & File Picker ───────────────────────────────────
-keep class com.crazecoder.openfile.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-dontwarn com.crazecoder.openfile.**
-dontwarn com.mr.flutter.plugin.filepicker.**
-dontwarn io.flutter.plugins.imagepicker.**

# ─── Google Play In-App Updates & Play Core ───────────────────────
-keep class com.google.android.play.core.** { *; }
-keep class de.gigadroid.inappupdate.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn de.gigadroid.inappupdate.**

# ─── Camera, CameraX & Biometrics Hardware Plugin ─────────────────
-keep class io.flutter.plugins.camera.** { *; }
-keep class io.flutter.plugins.camerax.** { *; }
-keep class androidx.camera.** { *; }
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.camera2.** { *; }
-keep class androidx.camera.lifecycle.** { *; }
-keep class androidx.camera.view.** { *; }
-dontwarn io.flutter.plugins.camera.**
-dontwarn io.flutter.plugins.camerax.**
-dontwarn androidx.camera.**

# ─── Geolocator & Native Location Service ─────────────────────────
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.geolocator.GeolocatorLocationService { *; }
-dontwarn com.baseflow.geolocator.**

# ─── Package Info, Battery & Smart Auth ───────────────────────────
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-dontwarn dev.fluttercommunity.plus.packageinfo.**
-keep class dev.fluttercommunity.plus.battery.** { *; }
-dontwarn dev.fluttercommunity.plus.battery.**
-keep class fman.ge.smart_auth.** { *; }
-dontwarn fman.ge.smart_auth.**

# ─── Google Maps Android SDK ──────────────────────────────────────
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }
-keep class io.flutter.plugins.googlemaps.** { *; }
-dontwarn io.flutter.plugins.googlemaps.**

# ─── Suppress Benign Library Warnings ───────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn io.ktor.**
-dontwarn io.github.jan-tennert.supabase.**
-dontwarn androidx.activity.EdgeToEdge**
-dontwarn androidx.core.view.WindowInsets**

