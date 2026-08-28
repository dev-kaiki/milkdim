plugins {
    id("com.android.application")
    id("kotlin-android")
    // O plugin do Flutter DEVE vir depois dos plugins Android/Kotlin!
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.milkdim_admin" // Altere para seu package, se desejar
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.milkdim_admin"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true // Caso use muitos pacotes/dlls
    }

    buildTypes {
        release {
            // Para produção: defina sua signingConfig para release!
            signingConfig = signingConfigs.getByName("debug") // Troque para release ao publicar!
            // Ativar minify só se souber lidar com Proguard/R8:
            // isMinifyEnabled = true
            // proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
