import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties().apply {
    val configuration = rootProject.file("key.properties")
    if (configuration.exists()) configuration.inputStream().use { load(it) }
}
fun signingValue(environment: String, property: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(property)?.takeIf { it.isNotBlank() }
val releaseStore = signingValue("LOCKIN_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("LOCKIN_KEYSTORE_PASSWORD", "storePassword")
val releaseAlias = signingValue("LOCKIN_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("LOCKIN_KEY_PASSWORD", "keyPassword")
val hasReleaseSigning = listOf(releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword).all { it != null }
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) } && !hasReleaseSigning) {
    throw GradleException("Release signing is not configured. Supply LOCKIN_KEYSTORE_PATH, LOCKIN_KEYSTORE_PASSWORD, LOCKIN_KEY_ALIAS and LOCKIN_KEY_PASSWORD, or android/key.properties. Debug keys are never used for a release.")
}

android {
    namespace = "app.lockin.lockin"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.lockin.lockin"
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

    // sideload: the APK on the website. play: the Google Play edition, which
    // adds the optional instant blocking accessibility service. Android builds
    // name one: flutter run --flavor sideload.
    flavorDimensions += "store"
    productFlavors {
        create("sideload") { dimension = "store" }
        // A separate listing on Google Play: Play re-signs it, so it could
        // never update the website APK anyway.
        create("play") {
            dimension = "store"
            applicationId = "app.grindset"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStore!!)
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
