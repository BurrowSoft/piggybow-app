import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The dart-defines Flutter passes (-Pdart-defines: base64 KEY=VALUE pairs,
// comma-separated), from --dart-define-from-file=env/<flavor>.json.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        .orEmpty()
        .split(",")
        .filter { it.isNotEmpty() }
        .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        .associate { it.substringBefore("=") to it.substringAfter("=", "") }

android {
    namespace = "com.burrowsoft.piggybow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.burrowsoft.piggybow"
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
        // The home-screen widget (AndroidManifest.xml) is a Plus perk, so it's
        // offered only in builds with Plus (feature 16). A release with Plus
        // stops below, so no release offers it yet.
        resValue("bool", "widget_enabled", (dartDefines["PLUS_ENABLED"] == "true").toString())
    }

    // The JVM tests (src/test) say each case, passed or not, so CI's log can
    // be read test by test; a failure with its full stack.
    testOptions {
        unitTests.all {
            it.testLogging {
                events("passed", "skipped", "failed")
                exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
            }
        }
    }

    // dev = local work, staging = testers + Maestro (Android forbids a flavor named "test"), prod = the store build.
    // They install side by side; Dart reads the matching env/<flavor>.json.
    // resValue (the per-flavor app name) is off by default in AGP 9.
    buildFeatures {
        resValues = true
    }

    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Piggybow Dev")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "Piggybow Staging")
        }
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Piggybow")
        }
    }

    // One committed DEBUG key for every debug build (dev, staging), so a CI
    // APK installs over the previous one and keeps app data (upgrade tests).
    // Public on purpose; never used for release (the upload key is in CI secrets).
    signingConfigs {
        create("sharedDebug") {
            storeFile = file("debug-shared.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        // The Play upload key: only from the environment of the manual
        // Release AAB workflow (GitHub secrets), never from this repo.
        // Google re-signs with the app key (Play App Signing).
        val uploadKeystore = System.getenv("PIGGYBOW_UPLOAD_KEYSTORE")
        if (!uploadKeystore.isNullOrEmpty()) {
            create("upload") {
                storeFile = file(uploadKeystore)
                storePassword = System.getenv("PIGGYBOW_UPLOAD_STORE_PASSWORD")
                keyAlias = System.getenv("PIGGYBOW_UPLOAD_KEY_ALIAS")
                keyPassword = System.getenv("PIGGYBOW_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("sharedDebug")
        }
        release {
            // The upload key when the workflow provides it; otherwise the
            // shared debug key, so a local `flutter run --release` still works.
            // A prod release build without the upload key fails (below).
            signingConfig = signingConfigs.findByName("upload")
                ?: signingConfigs.getByName("sharedDebug")
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

// Never a store build signed with a public key: a prod release task needs
// the upload key from the environment.
gradle.taskGraph.whenReady {
    val prodRelease = allTasks.any { it.name.contains("ProdRelease") }
    if (prodRelease && System.getenv("PIGGYBOW_UPLOAD_KEYSTORE").isNullOrEmpty()) {
        throw GradleException(
            "prod release needs PIGGYBOW_UPLOAD_KEYSTORE (the Release AAB workflow sets it)",
        )
    }
}

// A release build sends nothing: src/release/AndroidManifest.xml removes
// INTERNET and ACCESS_NETWORK_STATE. A release that would need the network
// (a Sentry DSN, or Plus with Play Billing) stops here, so that file changes
// in the same reviewed PR.
gradle.taskGraph.whenReady {
    val release = allTasks.any { it.name.contains("Release") }
    val dsn = dartDefines["SENTRY_DSN"].orEmpty().isNotBlank()
    val plus = dartDefines["PLUS_ENABLED"] == "true"
    val tips = dartDefines["AI_TIPS_ENABLED"] == "true"
    if (release && (dsn || plus || tips)) {
        throw GradleException(
            "this release build would need the network (" +
                listOfNotNull(
                    "SENTRY_DSN".takeIf { dsn },
                    "PLUS_ENABLED".takeIf { plus },
                    "AI_TIPS_ENABLED".takeIf { tips },
                ).joinToString() +
                "), but src/release/AndroidManifest.xml removes INTERNET and " +
                "ACCESS_NETWORK_STATE: change that file and " +
                "android/expected-permissions.txt in the same PR",
        )
    }
}

// Native crash handling is off (sentry_setup.dart: enableNativeCrashHandling
// and enableNdkScopeSync false), so ship none of sentry-native's .so files:
// smaller, and no 16 KB page-alignment risk. Dart errors still go
// through sentry-android-core.
configurations.all {
    exclude(group = "io.sentry", module = "sentry-android-ndk")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // The widget's logic, tested on the JVM (src/test): JUnit, and the JSON
    // parser Android has built in (android.jar only stubs it off a phone).
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

