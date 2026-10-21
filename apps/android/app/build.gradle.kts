import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)

    id("kotlin-parcelize")

    id("com.google.devtools.ksp")
    id("com.google.dagger.hilt.android")
    id("com.google.gms.google-services")

//    kotlin("kapt") // For annotation processing
}

android {
    namespace = "com.eatfair.app"
    compileSdk = 35

    lint {
        disable += "NullSafeMutableLiveData"
        disable += "FrequentlyChangingValue"
        disable += "RememberInComposition"
        disable += "AutoboxingStateCreation"
        checkReleaseBuilds = false
        abortOnError = false
    }

    // Load properties from local.properties
    val localProperties = Properties()
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localProperties.load(localPropertiesFile.inputStream())
    }

    signingConfigs {
        create("release") {
            // Release signing - keys loaded from local.properties
            val keystorePath = localProperties.getProperty("RELEASE_KEYSTORE_PATH", "")
            if (keystorePath.isNotEmpty()) {
                storeFile = file(keystorePath)
                storePassword = localProperties.getProperty("RELEASE_KEYSTORE_PASSWORD", "")
                keyAlias = localProperties.getProperty("RELEASE_KEY_ALIAS", "")
                keyPassword = localProperties.getProperty("RELEASE_KEY_PASSWORD", "")
            }
        }
    }

    // Dollor.ai by Vibing World Inc - Customer App
    defaultConfig {
        applicationId = "ai.dollor.customer"
        minSdk = 24
        targetSdk = 35
        versionCode = 261020
        versionName = "1.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // API Keys from local.properties
        buildConfigField("String", "GOOGLE_MAPS_API_KEY", "\"${localProperties.getProperty("GOOGLE_MAPS_API_KEY", "")}\"")
        buildConfigField("String", "STRIPE_PUBLISHABLE_KEY", "\"${localProperties.getProperty("STRIPE_PUBLISHABLE_KEY", "")}\"")

        // Manifest placeholders
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = localProperties.getProperty("GOOGLE_MAPS_API_KEY", "")

        // App name
        resValue("string", "app_name", "Dollor.ai")
    }

    // Environment-specific configurations
    flavorDimensions += "environment"
    productFlavors {
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            buildConfigField("Boolean", "IS_PRODUCTION", "false")
            buildConfigField("String", "API_BASE_URL", "\"https://d34u5ixl0bulv4.cloudfront.net/api\"")
            buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"107524350806-5kauv5lbp58hvsob7tsuuvrin99ql2bj.apps.googleusercontent.com\"")
            resValue("string", "app_name", "Dollor.ai Staging")
        }
        create("production") {
            dimension = "environment"
            buildConfigField("Boolean", "IS_PRODUCTION", "true")
            buildConfigField("String", "API_BASE_URL", "\"https://api.dollor.ai/api\"")
            buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"65740760476-31o2a074qeh2nsc6hlbt8peqpmivmq32.apps.googleusercontent.com\"")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            ndk {
                debugSymbolLevel = "FULL"
            }
            // Use release signing config if keystore is configured
            val keystorePath = localProperties.getProperty("RELEASE_KEYSTORE_PATH", "")
            if (keystorePath.isNotEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        // Debug build for testing without minification
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(project(":shared"))
    implementation(libs.kotlin.stdlib)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)

    implementation(libs.core.splashscreen)
    implementation(libs.androidx.compose.ui.text.google.fonts)
    implementation(libs.androidx.navigation.compose)

    implementation(libs.accompanist.pager)
    implementation(libs.accompanist.pager.indicators)
    implementation(libs.accompanist.permissions)

    implementation(libs.androidx.compose.material.icons.extended)

    // Hilt dependencies
    implementation(libs.hilt.android)
    ksp(libs.hilt.android.compiler)

    // Hilt Compose integration
    implementation(libs.androidx.hilt.navigation.compose) // Check for latest version

    //Coil Image Loading
    implementation(libs.coil.kt.coil.compose)

    //Google Maps
    implementation(libs.maps.compose)
    implementation(libs.play.services.maps)
    implementation(libs.play.services.location)
    implementation(libs.kotlinx.coroutines.play.services)

    //Google Sign-In
    implementation(libs.play.services.auth)

    //Room SQLite DB
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx) // For coroutines support
    ksp(libs.androidx.room.compiler)

    //Stripe Payment
    implementation(libs.stripe.android) // Use a recent stable version

    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.datastore.preferences)

    implementation(libs.accompanist.flowlayout)

    // Networking for rideshare API
    implementation(libs.okhttp)
    implementation(libs.gson)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
configurations.all {
    resolutionStrategy {
        force("androidx.core:core-ktx:1.15.0")
        force("androidx.core:core:1.15.0")
    }
}
