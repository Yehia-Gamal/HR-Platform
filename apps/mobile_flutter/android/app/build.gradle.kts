plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "org.ahlashabab.ahla_shabab_management_os"
    // flutter_secure_storage requires compileSdk 36 (backward compatible; targetSdk unchanged).
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // flutter_local_notifications يتطلب core library desugaring
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        val keystorePath = System.getenv("RELEASE_KEYSTORE_PATH")
        val keystoreFile = keystorePath?.let { file(it) } ?: file("release-keystore.jks")
        val storePasswordValue = System.getenv("RELEASE_STORE_PASSWORD")
        val keyPasswordValue = System.getenv("RELEASE_KEY_PASSWORD")
        val keyAliasValue = System.getenv("RELEASE_KEY_ALIAS") ?: "ahla-shabab"
        if (keystoreFile.exists() && storePasswordValue != null && keyPasswordValue != null) {
            create("release") {
                storeFile = keystoreFile
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
                enableV1Signing = false
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    defaultConfig {
        applicationId = "org.ahlashabab.ahla_shabab_management_os"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Flutter selects its supported ABIs. Defining ndk.abiFilters here conflicts
        // with `flutter build apk --split-per-abi` on current Android Gradle Plugin.
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.findByName("release")
            if (releaseSigning != null) {
                signingConfig = releaseSigning
            } else if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
                throw GradleException(
                    "Release signing is required. Set RELEASE_STORE_PASSWORD, " +
                        "RELEASE_KEY_PASSWORD, and optionally RELEASE_KEYSTORE_PATH/RELEASE_KEY_ALIAS."
                )
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // مطلوب لـ flutter_local_notifications (core library desugaring)
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Firebase BoM — يحدد إصدارات جميع مكتبات Firebase بشكل متوافق
    implementation(platform("com.google.firebase:firebase-bom:34.16.0"))
    implementation("com.google.firebase:firebase-messaging")
}
