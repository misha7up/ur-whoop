plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // org.jetbrains.kotlin.plugin.compose удалён — он только для Kotlin 2.0+
}

android {
    namespace = "com.uremont.bluetooth"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.uremont.bluetooth"
        minSdk = 24
        targetSdk = 34
        versionCode = 7
        versionName = "1.7.0-stable"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    // Для Kotlin 1.9.23 версия Compose compiler = 1.5.11
    // Таблица совместимости: https://developer.android.com/jetpack/androidx/releases/compose-kotlin
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.11"
    }
}

dependencies {
    // Compose BOM — единая точка управления версиями Compose-библиотек
    implementation(platform("androidx.compose:compose-bom:2024.04.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")

    // Activity + Compose интеграция
    implementation("androidx.activity:activity-compose:1.9.0")

    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.4")

    // AndroidX Core KTX
    implementation("androidx.core:core-ktx:1.13.0")

    // Coroutines для асинхронной работы с Bluetooth-сокетами
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // ZXing — генерация QR-кодов без внешних зависимостей
    implementation("com.google.zxing:core:3.5.3")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
}
