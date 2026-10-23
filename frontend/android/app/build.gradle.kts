import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.care_connect_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    val keyPropertiesFile = rootProject.file("key.properties")
    val keyProperties = Properties()
    if (keyPropertiesFile.exists()) {
        keyProperties.load(keyPropertiesFile.inputStream())
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String?
            keyPassword = keyProperties["keyPassword"] as String?
            storeFile = keyProperties["storeFile"]?.let { rootProject.file(it as String) }
            storePassword = keyProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        applicationId = "edu.umgc.careconnect"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appAuthRedirectScheme"] = "edu.umgc.careconnect"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
        }
    }

    packagingOptions {
        pickFirst("**/libjingle_peerconnection_so.so")
        pickFirst("**/libc++_shared.so")
        pickFirst("**/libwebrtc.so")
        exclude("META-INF/DEPENDENCIES")
        exclude("META-INF/LICENSE")
        exclude("META-INF/LICENSE.txt")
        exclude("META-INF/NOTICE")
        exclude("META-INF/NOTICE.txt")
    }
}

// ===============================
// MINIMAL RESOLUTION - FIREBASE BOM + WEBRTC ONLY
// ===============================
configurations.all {
    resolutionStrategy {
        // Only force WebRTC - let packages handle React Native naturally
        force("org.jitsi:webrtc:124.0.0")
    }

    // Only exclude firebase-iid from ML Kit
    exclude(group = "com.google.firebase", module = "firebase-iid")
}

dependencies {
    // Firebase BOM - manages all Firebase Android SDK versions
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))

    // Firebase dependencies - versions managed by BOM
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.firebase:firebase-common") 
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("com.google.mediapipe:tasks-genai:0.10.14")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

}

flutter {
    source = "../.."
}
