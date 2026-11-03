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
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }

# ─── SharedPreferences Plugin (Fix NoSuchMethodError under R8) ───
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembers class io.flutter.plugins.sharedpreferences.** { *; }
-keepclassmembernames class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ─── Firebase & Google Play Services ────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.messaging.FirebaseMessagingService { *; }
-keep class com.google.firebase.iid.FirebaseInstanceId { *; }
-keep class * extends com.google.firebase.messaging.FirebaseMessagingService { *; }
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

# ─── Suppress Benign Library Warnings ───────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn com.google.android.play.core.**
-dontwarn io.ktor.**
-dontwarn io.github.jan-tennert.supabase.**
-dontwarn androidx.activity.EdgeToEdge**
-dontwarn androidx.core.view.WindowInsets**

