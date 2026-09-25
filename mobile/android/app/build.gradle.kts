import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.herebee"
    // Pinned rather than inherited: the app must build reproducibly across
    // Flutter upgrades, and Play requires a recent target.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.herebee"
        // 26 = Android 8.0. Below that, notification channels (required for the
        // sharing foreground service) do not exist.
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Release signing. CI injects the keystore and its secrets through the
        // SIGNING_* environment variables; a developer machine can instead keep
        // an android/key.properties next to this file (gitignored). Neither
        // present: fall through to debug signing so `flutter run --release`
        // still works, but never ship such a build.
        val keystorePath = System.getenv("SIGNING_KEYSTORE_PATH")
        val keyProps = Properties()
        val keyPropsFile = rootProject.file("key.properties")
        if (keyPropsFile.exists()) keyPropsFile.inputStream().use { keyProps.load(it) }
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("SIGNING_STORE_PASSWORD") ?: ""
                keyAlias = System.getenv("SIGNING_KEY_ALIAS") ?: ""
                keyPassword = System.getenv("SIGNING_KEY_PASSWORD") ?: ""
            }
        } else if (keyProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
