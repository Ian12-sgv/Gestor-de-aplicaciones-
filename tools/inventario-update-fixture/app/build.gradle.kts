plugins {
    id("com.android.application")
}

android {
    namespace = "com.example.inventario_app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.inventario_app"
        minSdk = 24
        targetSdk = 35
        versionCode = 2
        versionName = "1.0.1"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}
