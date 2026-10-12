package com.timlorne.wiringpro.pdf

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.IOException

/**
 * Copies an already-generated PDF into a destination the user picked
 * themselves via Android's system file picker (Storage Access Framework).
 *
 * This replaces an earlier version that tried to guess the right way to
 * write into "Downloads" directly (MediaStore on newer Android, legacy
 * external storage + a runtime permission on older Android). That worked
 * inconsistently on a Samsung Tab Active 2 — writes succeeded with no
 * error, but the file didn't show up where expected, most likely due to
 * Samsung/Knox-specific storage behavior that's hard to predict from app
 * code. Handing the destination choice to the system's own picker sidesteps
 * the whole problem: wherever Android's picker UI shows the file living
 * after you pick a spot is exactly where it lives — no guessing.
 */
object PdfSaver {
    fun copyToUri(context: Context, sourceFile: File, destination: Uri) {
        context.contentResolver.openOutputStream(destination)?.use { out ->
            sourceFile.inputStream().use { input -> input.copyTo(out) }
        } ?: throw IOException("Could not open an output stream for the chosen save location")
    }
}

