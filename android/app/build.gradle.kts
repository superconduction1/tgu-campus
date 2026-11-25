plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "edu.tgu.tgu_campus"
    compileSdk = flutter.compileSdkVersion
    // 用本机 .tools/android-sdk 里装好的 NDK（r28c）。不写这一行，AGP 会跳过
    // stripDebugSymbols，所有 .so 的调试符号都留在包里，APK 会涨到 1.4GB。
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "edu.tgu.tgu_campus"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // 关掉 release 的 lint（lintVitalAnalyzeRelease）。AGP 自带的 lint 在
    // webview_flutter_android 的 Kotlin 代码上会崩（`java.util.List.removeLast()`
    // 是 JDK 21 才有的方法，本机 JDK 17 跑不了），属于 lint 自身的 bug。
    // 这个工程只自用、不上架，静态检查由 CI 的 flutter analyze + 本地 resolve.dart 兜着。
    lint {
        checkReleaseBuilds = false
        abortOnError = false
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
