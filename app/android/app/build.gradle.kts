import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Maps/Places API keys stay out of git (T23 D3). Order: android/secrets.properties
// (gitignored, see secrets.properties.example), env NAPSTOP_<name>, placeholder.
// The placeholder builds fine; the app then shows no map and no address search.
val napSecrets =
    Properties().apply {
        val f = rootProject.file("secrets.properties")
        if (f.isFile) f.inputStream().use { load(it) }
    }

fun napSecret(name: String): String =
    napSecrets.getProperty(name)?.trim()?.takeIf { it.isNotEmpty() }
        ?: System.getenv("NAPSTOP_$name")?.trim()?.takeIf { it.isNotEmpty() }
        ?: "DEFAULT_API_KEY"

android {
    namespace = "app.napstop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.napstop"
        // PRD §5: Android 8.0+ (API 26). Overrides flutter.minSdkVersion (24).
        minSdk = 26
        // = 36 with Flutter 3.47, meets the Google Play target API requirement.
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Default flavor is "dev" (pubspec `default-flavor`). App name per flavor
    // comes from src/<flavor>/res/values/strings.xml, not resValue.
    flavorDimensions += "default"
    productFlavors {
        create("dev") {
            dimension = "default"
            // app.napstop.dev, installable side by side with prod.
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["mapsApiKey"] = napSecret("MAPS_API_KEY_DEV")
        }
        create("prod") {
            dimension = "default"
            manifestPlaceholders["mapsApiKey"] = napSecret("MAPS_API_KEY_PROD")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Trip Engine (T12). Not used by :app yet (T15 wires it); proves the JVM library dexes into the APK.
    implementation(project(":core-trip"))
    // Pigeon @async host methods are suspend functions (T14 §5.1).
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}

flutter {
    source = "../.."
}
