# ---------------------------------------------------------------------------
# BLINK companion app — R8 keep rules
#
# pubspec.yaml pins flutter_blue_plus to 1.35.5, which is still the
# MethodChannel implementation under com.boskokg / com.lib — those two keeps are
# the ones doing work today.
#
# The jnigen/JNI keeps below are for 1.36.x, which moved the Android side to
# resolving Java classes and methods reflectively by name. R8 renames exactly
# those, giving a BLE stack that binds fine in debug and silently fails in
# release. They are kept ahead of the version bump so lifting the pin does not
# reintroduce that failure; they cost nothing while unused.
# ---------------------------------------------------------------------------
-keep class com.lib.flutter_blue_plus.** { *; }
-keep class com.boskokg.flutter_blue_plus.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.lib.flutter_blue_plus.**
-dontwarn com.github.dart_lang.jni.**

# AndroidX App Startup / baseline profile installer are instantiated by name
# from the merged manifest.
-keep class androidx.startup.** { *; }
-keep class androidx.profileinstaller.** { *; }

# Bluetooth callbacks are invoked from the platform, keep their signatures.
-keepclassmembers class * extends android.bluetooth.BluetoothGattCallback { *; }

# Keep Gson/reflection-based serializers
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep Parcelable creators
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Notification receivers/services are resolved by class name from the manifest.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# Keep method references accessed via MethodChannel reflection
-keep class io.flutter.plugin.editing.** { *; }
-keep class io.flutter.embedding.** { *; }

# Enum valueOf/values are used reflectively by several plugins.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# NOTE: -optimizationpasses / -dontskipnonpubliclibraryclasses /
# -dontusemixedcaseclassnames are ProGuard-only directives that R8 ignores.
# They were removed rather than left as dead configuration.
-verbose
