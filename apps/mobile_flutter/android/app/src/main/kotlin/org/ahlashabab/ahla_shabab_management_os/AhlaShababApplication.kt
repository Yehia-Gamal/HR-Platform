package org.ahlashabab.ahla_shabab_management_os

import io.flutter.app.FlutterApplication

class AhlaShababApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        UrgentNotificationManager.createChannel(this)
    }
}
