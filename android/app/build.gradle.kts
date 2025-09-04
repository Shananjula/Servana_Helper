import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val flutterVersionCode = (localProperties.getProperty("flutter.versionCode") ?: "1").toInt()
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0.0"

android {
    namespace = "com.servana.helper"

    compileSdk = 35
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.servana.helper"
        minSdk = 23
        targetSdk = 35

        versionCode = flutterVersionCode
        versionName = flutterVersionName

        multiDexEnabled = true
    }

    buildTypes {
        release {
            // Use debug keystore for now; replace with your real signingConfig when ready
            signingConfig = signingConfigs.getByName("debug")
            // isMinifyEnabled = true // enable later with proper rules
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }
}

// Required by the Flutter Android plugin
flutter {
    source = "../.."
}

dependencies {
    // Desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Firebase (BOM keeps versions aligned)
    implementation(platform("com.google.firebase:firebase-bom:33.0.0"))
    implementation("com.google.firebase:firebase-analytics-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-storage-ktx")

    // If you ever drop minSdk below 21, add:
    // implementation("androidx.multidex:multidex:2.0.1")
}
