package com.timlorne.wiringpro

import android.app.Application
import com.timlorne.wiringpro.data.db.AppDatabase
import com.timlorne.wiringpro.data.repository.WiringRepository

// Deliberately no DI framework (Hilt/Koin) yet — one repository singleton
// off the Application is enough at this stage and keeps the build simple.
// Worth revisiting once there's more than a couple of ViewModels to wire up.
class WiringProApplication : Application() {
    lateinit var repository: WiringRepository
        private set

    override fun onCreate() {
        super.onCreate()
        val db = AppDatabase.getInstance(this)
        repository = WiringRepository(db)
    }
}

