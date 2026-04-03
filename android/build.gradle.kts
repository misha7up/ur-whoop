// Top-level build file — здесь объявляются плагины для всех модулей
plugins {
    id("com.android.application") version "8.3.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.23" apply false
    // kotlin.plugin.compose существует только с Kotlin 2.0+
    // В Kotlin 1.9.x Compose подключается через composeOptions в app/build.gradle.kts
}
