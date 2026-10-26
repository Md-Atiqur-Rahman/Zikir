plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.himel.digital_tasbih"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // needed by the ota_update plugin (in-app updates)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.himel.digital_tasbih"
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

    // Every release must be signed with the SAME key, otherwise Android refuses to install
    // a new build over the old one (and the user would have to uninstall and lose data).
    // CI passes the permanent key through these environment variables; without them a local
    // release build falls back to the debug key so `flutter run --release` still works.
    val keystorePath: String? = System.getenv("ZIKIR_KEYSTORE")
    signingConfigs {
        if (keystorePath != null) {
            create("zikir") {
                storeFile = file(keystorePath)
                storeType = "pkcs12"
                storePassword = System.getenv("ZIKIR_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ZIKIR_KEY_ALIAS") ?: "zikir"
                keyPassword = System.getenv("ZIKIR_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePath != null) {
                signingConfigs.getByName("zikir")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
