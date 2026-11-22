package com.tecsattv.fileguard

import android.content.Context
import android.os.Environment
import android.os.StatFs
import android.webkit.MimeTypeMap
import java.io.File

/// Armazenamentos do telefone e tipo (MIME) de cada arquivo. Usado pela
/// tela do app, pelo seletor de arquivos e pelo FileGuard no seletor do Android.
object Storage {
    data class Vol(val path: String, val removable: Boolean, val total: Long, val free: Long)

    fun volumes(ctx: Context): List<Vol> {
        val list = mutableListOf<Vol>()
        val seen = mutableSetOf<String>()
        val internal = Environment.getExternalStorageDirectory()
        fun add(root: File, removable: Boolean) {
            val p = root.absolutePath
            if (!seen.add(p) || !root.exists()) return
            try {
                val s = StatFs(p)
                list.add(Vol(p, removable, s.totalBytes, s.availableBytes))
            } catch (_: Exception) {}
        }
        add(internal, false)
        // getExternalFilesDirs: .../Android/data/<app>/files em cada volume;
        // subindo 4 pastas chega à raiz do cartão.
        for (d in ctx.getExternalFilesDirs(null)) {
            if (d == null) continue
            var root: File? = d
            repeat(4) { root = root?.parentFile }
            val r = root ?: continue
            if (r.absolutePath != internal.absolutePath) add(r, true)
        }
        return list
    }

    fun mimeOf(f: File): String {
        if (f.isDirectory) return "inode/directory"
        val ext = f.extension.lowercase()
        if (ext.isEmpty()) return "application/octet-stream"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
            ?: "application/octet-stream"
    }
}
