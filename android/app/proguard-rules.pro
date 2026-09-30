# ============================================================
# ProGuard / R8 Rules for JOY PeopleHR
# ============================================================

# ─── Flutter ────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# ─── Firebase & Google Play Services ────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.firebase.messaging.FirebaseMessagingService { *; }
-keep class com.google.firebase.iid.FirebaseInstanceId { *; }
-keep class * extends com.google.firebase.messaging.FirebaseMessagingService { *; }

# ─── Supabase ───────────────────────────────────────────────────
-keep class io.github.jan-tennert.supabase.** { *; }
-keep class io.ktor.** { *; }
-keep class kotlinx.serialization.** { *; }
-keepattributes *Annotation*, InnerClasses, EnclosingMethod

# ─── Kotlin Serialization ──────────────────────────────────────
-keepattributes *Annotation*, InnerClasses, EnclosingMethod
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn kotlinx.serialization.**
-keepclassmembers class * {
    @kotlinx.serialization.Serializable <fields>;
}

# ─── Data Models (prevent stripping during minification) ───────
-keep class com.joypeoplehr.app.models.** { *; }
-keepclassmembers class * extends com.google.android.gms.cloudservice.** { *; }

# ─── Native Methods ─────────────────────────────────────────────
-keepclasseswithmembernames class * {
    native <methods>;
}

# ─── Enums ──────────────────────────────────────────────────────
-keepclassmembers class * extends java.lang.Enum {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ─── Parcelable ─────────────────────────────────────────────────
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# ─── Gson / JSON Serialization ─────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# ─── Play Core (Flutter deferred components) ───────────────────
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# ─── General Best Practices ────────────────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**

# ─── Flutter Local Notifications ───────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }

