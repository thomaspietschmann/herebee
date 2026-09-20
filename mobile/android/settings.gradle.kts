pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Upstream bug: maplibre_android 0.3.6 applies the ktlint Gradle plugin in
    // its own build.gradle.kts without a version. Its standalone settings.gradle
    // supplies one, but that file is ignored when Flutter includes the plugin as
    // a subproject, so the consumer build has to declare it. Build-time only —
    // nothing from it ends up in the APK. Remove once the plugin stops leaking
    // its lint configuration into consumers.
    id("org.jlleitschuh.gradle.ktlint") version "12.1.1" apply false
}

include(":app")
