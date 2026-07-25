# Flutter keeps the required embedding and plugin entry points automatically.
# Project-specific keep rules can be added here if native integrations are
# introduced later.

# Keep Gson/Reflection-based serializers used by flutter_blue_plus
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep SharedPreferences serialized data classes
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Prevent R8 from stripping notification channel metadata
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep method references accessed via MethodChannel reflection
-keep class io.flutter.plugin.editing.** { *; }

# Aggressive optimization
-optimizationpasses 5
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-verbose
