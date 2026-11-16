package com.remigl.reveil

import android.content.Context
import java.io.File

/**
 * Le modèle de langage (fichier GGUF) est embarqué dans l'APK, dans
 * `assets/models/`. llama.cpp ayant besoin d'un vrai fichier sur disque, il
 * est copié une fois dans le stockage privé de l'application.
 */
object ModelFiles {

    private const val ASSET_DIR = "models"

    /**
     * Renvoie le chemin du modèle prêt à l'emploi, ou `null` si l'APK a été
     * compilé sans modèle. Peut prendre plusieurs secondes au premier appel :
     * ne pas appeler depuis le thread principal.
     */
    fun prepare(context: Context): String? {
        val name = context.assets.list(ASSET_DIR)
            ?.firstOrNull { it.endsWith(".gguf") }
            ?: return null
        val asset = "$ASSET_DIR/$name"

        val dir = File(context.filesDir, "models")
        if (!dir.isDirectory && !dir.mkdirs()) return null
        val target = File(dir, name)

        // Taille attendue (le modèle est stocké non compressé dans l'APK).
        val expected = try {
            context.assets.openFd(asset).use { it.length }
        } catch (_: Exception) {
            -1L
        }
        if (target.isFile && (expected < 0 || target.length() == expected)) {
            return target.path
        }

        // Première utilisation, copie interrompue ou ancien modèle : on recopie.
        dir.listFiles()?.forEach { it.delete() }
        val temp = File(dir, "$name.tmp")
        context.assets.open(asset).use { input ->
            temp.outputStream().use { output -> input.copyTo(output, 1 shl 20) }
        }
        return if (temp.renameTo(target)) target.path else null
    }
}
