package com.uremont.bluetooth

import android.app.Application

/**
 * Единый экземпляр [ObdConnectionManager] на процесс приложения.
 *
 * Соединение с ELM327 (Bluetooth или Wi-Fi) переживает пересоздание [MainActivity]
 * (поворот экрана, возврат из браузера, нехватка памяти с восстановлением Activity),
 * пока жив процесс.
 */
class UremontApp : Application() {
    val obdConnectionManager = ObdConnectionManager()
}
