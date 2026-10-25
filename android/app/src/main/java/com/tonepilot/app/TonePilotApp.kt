package com.tonepilot.app

import android.app.Application

class TonePilotApp : Application() {
    lateinit var appState: AppState
        private set

    override fun onCreate() {
        super.onCreate()
        BuildConfigInfo.versionName = runCatching { packageManager.getPackageInfo(packageName, 0).versionName }.getOrNull() ?: ""
        appState = AppState(this)
    }
}
