plugins {
    id("com.android.application")
    // Le plugin Flutter doit être appliqué après le plugin Android.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.remigl.reveil"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.remigl.reveil"
        // Android 8.0+ : canaux de notification, services au premier plan et
        // java.time disponibles sans bibliothèque supplémentaire.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // MVP : signé avec la clé de debug pour que
            // `flutter build apk --release` fonctionne sans configuration.
            // À remplacer par une vraie clé avant toute publication.
            signingConfig = signingConfigs.getByName("debug")
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
