import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.spendrix"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 1.2 and older shipped as com.example.expenses_tracker; CI builds a second apk with that id so those installs update too
        applicationId = System.getenv("SPENDRIX_APP_ID") ?: "com.spendrix"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // android/key.properties is never committed; CI writes it from secrets
    val keys = Properties().apply {
        rootProject.file("key.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
    }
    signingConfigs {
        create("release") {
            keyAlias = keys.getProperty("keyAlias")
            keyPassword = keys.getProperty("keyPassword")
            storePassword = keys.getProperty("storePassword")
            storeFile = keys.getProperty("storeFile")?.let { file(it) }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // qualcomm npu libs (the app never picks the npu) and webgpu libs whose dawn runtime isn't shipped on android
    packaging {
        jniLibs.excludes += listOf(
            "**/libQnn*.so",
            "**/libLiteRtDispatch_Qualcomm.so",
            "**/libLiteRtGpuAccelerator.so",
            "**/libLiteRtWebGpuAccelerator.so",
            "**/libLiteRtTopKWebGpuSampler.so",
        )
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
