// android/settings.gradle.kts

pluginManagement {
    // Read flutter.sdk from local.properties without imports
    val localProps = java.util.Properties().apply {
        val lp = file("local.properties")
        if (!lp.exists()) {
            throw GradleException("local.properties not found at ${lp.absolutePath}")
        }
        lp.inputStream().use { load(it) }   // java.util.Properties.load(InputStream)
    }
    val flutterSdk = localProps.getProperty("flutter.sdk")
        ?: throw GradleException("Flutter SDK not found. Define flutter.sdk in local.properties.")

    // Attach Flutter's Gradle build
    includeBuild("$flutterSdk/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.3.15" apply false
}

rootProject.name = "servana_helper"
include(":app")
