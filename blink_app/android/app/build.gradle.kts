plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.blink.companion"
    compileSdk = 35
    ndkVersion = "28.2.13676358"

    // NOTE: the manual `splits { abi { ... } }` block was removed.
    //
    // It produced per-ABI APKs whose versionCode was silently offset by the
    // Flutter Gradle plugin (arm64 -> 2005, armeabi-v7a -> 1005, ...), while a
    // plain `flutter build apk` produced a universal APK at versionCode 5.
    // Sideloading then hit "downgrade not allowed", or installed a stale
    // universal build over a newer split one.
    //
    // Use `flutter build apk --release` for one universal APK (recommended for
    // manual installs) or `flutter build apk --release --split-per-abi` for
    // per-ABI artifacts; the Flutter plugin manages the offsets correctly in
    // the latter case.

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.blink.companion"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Derived from pubspec.yaml `version:` — there is exactly one source of
        // truth for the app version.  Hardcoding these here made the installed
        // versionName disagree with what the app reported about itself.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystoreFile = System.getenv("KEYSTORE_FILE")
            if (keystoreFile != null) {
                storeFile = file(keystoreFile)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            } else {
                // Fallback to debug keystore for local development
                storeFile = signingConfigs.getByName("debug").storeFile
                storePassword = signingConfigs.getByName("debug").storePassword
                keyAlias = signingConfigs.getByName("debug").keyAlias
                keyPassword = signingConfigs.getByName("debug").keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // R8 removes unreachable Android/Kotlin code and resources from
            // the distributable build. Flutter's Dart tree shaking remains
            // active as usual.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.play:core:1.10.3")
}
