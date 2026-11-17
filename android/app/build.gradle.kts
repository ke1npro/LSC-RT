import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// H-08 (M7/M8): firma de release con llave propia. key.properties NUNCA se versiona (ver .gitignore).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.academic.asl.sign_language_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.academic.asl.sign_language_app"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Con llave propia si existe; si no, solo se permite la de debug con -PallowDebugSigning=true
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    aaptOptions {
        noCompress("tflite", "lite")
    }
}

// Bloquea builds de release firmados con la llave de debug (APK que se compartiria como "oficial").
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any {
        val n = it.name
        n.contains("Release") && (n.startsWith("assemble") || n.startsWith("bundle") || n.startsWith("package"))
    }
    if (buildingRelease && !hasReleaseKey && !project.hasProperty("allowDebugSigning")) {
        throw GradleException(
            "Release sin llave propia: falta android/key.properties. " +
                "No se permite firmar un release con la llave de debug (usa -PallowDebugSigning=true solo para pruebas locales)."
        )
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
    implementation("com.google.mediapipe:tasks-vision:0.10.29")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
