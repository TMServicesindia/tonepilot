plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Build number from CI so every release installs over the previous one.
val buildNumber = (System.getenv("GITHUB_RUN_NUMBER") ?: "1").toInt()

android {
    namespace = "com.tonepilot.app"
    compileSdk = 35
    // The NDK the Swift SDK for Android was set up with (CI sets ANDROID_NDK_HOME).
    System.getenv("ANDROID_NDK_HOME")?.let { ndkPath = it }

    defaultConfig {
        applicationId = "com.tonepilot.app"
        minSdk = 28
        targetSdk = 35
        versionCode = buildNumber
        versionName = "0.4.$buildNumber"
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    signingConfigs {
        // A fixed key kept in the repo so each new APK installs as an update (personal sideload
        // builds, not a Play Store identity).
        create("sideload") {
            storeFile = file("tonepilot-sideload.keystore")
            storePassword = "tonepilot"
            keyAlias = "tonepilot"
            keyPassword = "tonepilot"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("sideload")
        }
        debug {
            signingConfig = signingConfigs.getByName("sideload")
        }
    }

    // Set TONEPILOT_NO_NATIVE=1 to compile only the Kotlin side (quick local check without the NDK).
    if (System.getenv("TONEPILOT_NO_NATIVE") == null) {
        externalNativeBuild {
            cmake {
                path = file("src/main/cpp/CMakeLists.txt")
                version = "3.22.1"
            }
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    packaging {
        jniLibs { useLegacyPackaging = true }
    }
    // The 30 MB SoundFont is already compressed audio data; storing it uncompressed is faster to copy.
    androidResources { noCompress += listOf("sf2") }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
