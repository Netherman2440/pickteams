plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pl.pickteams.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "pl.pickteams.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Production release identity comes from the protected local signing
    // environment (PICKTEAMS_SIGNING_KEYSTORE, PICKTEAMS_SIGNING_STORE_PASSWORD,
    // PICKTEAMS_SIGNING_KEY_ALIAS, PICKTEAMS_SIGNING_KEY_PASSWORD). The only
    // other release path is the explicitly opted-in ephemeral CI debug key
    // (pickteamsEphemeralDebugSigning=true, set only by app/tool/build_native_candidate.py
    // on an ephemeral runner); every other release build fails closed instead of
    // silently signing with debug keys.
    val productionKeystore = providers.environmentVariable("PICKTEAMS_SIGNING_KEYSTORE").orNull
    val ephemeralDebugSigning = findProperty("pickteamsEphemeralDebugSigning").toString() == "true"
    fun requiredSigningEnv(name: String): String {
        val value = providers.environmentVariable(name).orNull
        if (value.isNullOrBlank()) {
            throw GradleException("Release signing with PICKTEAMS_SIGNING_KEYSTORE also requires $name")
        }
        return value
    }
    signingConfigs {
        if (productionKeystore != null) {
            create("pickteamsRelease") {
                storeFile = file(productionKeystore)
                storePassword = requiredSigningEnv("PICKTEAMS_SIGNING_STORE_PASSWORD")
                keyAlias = requiredSigningEnv("PICKTEAMS_SIGNING_KEY_ALIAS")
                keyPassword = requiredSigningEnv("PICKTEAMS_SIGNING_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            when {
                productionKeystore != null -> signingConfig = signingConfigs.getByName("pickteamsRelease")
                ephemeralDebugSigning -> signingConfig = signingConfigs.getByName("debug")
                else -> if (gradle.startParameter.taskNames.any { it.contains("Release") }) {
                    throw GradleException(
                        "Release signing requires the protected production environment " +
                            "(PICKTEAMS_SIGNING_KEYSTORE and companion variables) or the bounded " +
                            "ephemeral CI opt-in (pickteamsEphemeralDebugSigning=true); " +
                            "refusing to sign a release build with debug keys.")
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
