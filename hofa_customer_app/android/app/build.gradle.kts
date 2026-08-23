import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chỉ áp dụng plugin Google Services khi đã có file google-services.json thật (tải từ
// Firebase Console) — để tránh build lỗi ngay khi chưa cấu hình Firebase. Xem README.md.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Keystore ký bản release Google Play — KHÔNG commit key.properties/*.jks vào git (xem
// .gitignore). Chưa có file này (máy mới/CI chưa cấu hình) thì tự rơi về ký bằng debug key như
// trước, `flutter run --release` vẫn chạy được, chỉ không nộp lên Play Store được thôi.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.hofa.hofa_customer"
    // Pin cứng thay vì đọc flutter.compileSdkVersion (thả nổi theo Flutter SDK cài trên từng
    // máy) — tránh build ra kết quả khác nhau giữa các máy/CI khi ai đó dùng Flutter SDK khác
    // bản. Giá trị hiện khớp đúng mặc định của Flutter 3.44.8 đang dùng để build repo này.
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications yêu cầu bật desugaring (dùng java.time API mới hơn minSdk).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.hofa.hofa_customer"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
