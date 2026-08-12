import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Firebase / FCM. Requires android/app/google-services.json (added by the
    // app owner) for a release build; Dart analysis does not need it.
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. Create an `android/key.properties` (gitignored) holding:
//   storeFile=/absolute/path/to/carenclean-upload.jks
//   storePassword=...
//   keyAlias=partner
//   keyPassword=...
// `scripts/make_upload_keystore.sh` generates the keystore and writes that
// file. Without it we fall back to the debug key so `flutter run --release`
// still works locally — but that build is NOT uploadable, so the build warns
// loudly rather than producing a rejected bundle silently.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.carenclean.partner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.carenclean.partner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "[33mcnc_partner: no android/key.properties — signing " +
                    "the release build with the DEBUG key. This AAB cannot be " +
                    "uploaded to Play.[0m"
                )
                signingConfigs.getByName("debug")
            }
            // Shrink the Java/Kotlin layer and strip unused resources. Dart code
            // is compiled AOT and unaffected; the keep rules in
            // proguard-rules.pro cover the plugins that use reflection.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
