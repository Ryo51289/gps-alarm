import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Uses AGP 9 built-in Kotlin (no org.jetbrains.kotlin.android plugin), see docs/spikes/S1.md §5.2.
plugins {
    id("com.android.application")
}

android {
    namespace = "app.napstop.probe"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.napstop.probe"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0-probe"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

// Debug only (S1 §5.2): the release variant is never built.
androidComponents {
    beforeVariants(selector().withBuildType("release")) { it.enable = false }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.activity:activity-ktx:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("com.google.android.gms:play-services-location:21.4.0")

    testImplementation("junit:junit:4.13.2")
}
