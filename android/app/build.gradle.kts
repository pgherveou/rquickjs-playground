plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "io.parity.playground"
    compileSdk = 36
    // scripts/build-android.sh reads this to build the Rust library with the same NDK.
    ndkVersion = "29.0.14206865"

    defaultConfig {
        applicationId = "io.parity.rquickjs_playground"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        ndk { abiFilters += "arm64-v8a" }
    }

    sourceSets {
        getByName("main") {
            kotlin.srcDirs("src/main/kotlin", "src/generated/kotlin")
            assets.srcDirs("../../samples")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures { compose = true }

    // JNA also ships ABIs the NDK has no strip tool for; the app only targets arm64-v8a.
    packaging { jniLibs { excludes += listOf("lib/armeabi/**", "lib/mips/**", "lib/mips64/**") } }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.05.00"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("net.java.dev.jna:jna:5.14.0@aar")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
