// Fix for AGP AndroidLocationsException when both ANDROID_PREFS_ROOT and ANDROID_USER_HOME are set in environment
try {
    val peClass = Class.forName("java.lang.ProcessEnvironment")
    val envField = peClass.getDeclaredField("theEnvironment").apply { isAccessible = true }
    (envField.get(null) as? MutableMap<String, String>)?.remove("ANDROID_PREFS_ROOT")

    val ciEnvField = peClass.getDeclaredField("theCaseInsensitiveEnvironment").apply { isAccessible = true }
    (ciEnvField.get(null) as? MutableMap<String, String>)?.remove("ANDROID_PREFS_ROOT")
} catch (_: Throwable) {}

pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.1" apply false
    id("com.google.gms.google-services") version("4.4.4") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.4.20" apply false
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

include(":app")
