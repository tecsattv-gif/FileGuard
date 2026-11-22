package com.tecsattv.fileguard

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/// Entrega para o outro app o arquivo escolhido no seletor do FileGuard.
/// Só leitura, e só os arquivos escolhidos (permissão dada pelo Android
/// para aquele endereço; o provider não é aberto para os outros apps).
class FilesProvider : ContentProvider() {
    companion object {
        fun authority(ctx: Context) = "${ctx.packageName}.files"

        fun uriFor(ctx: Context, f: File): Uri = Uri.Builder()
            .scheme("content")
            .authority(authority(ctx))
            .path("/f" + f.absolutePath)
            .build()
    }

    private fun fileOf(uri: Uri): File {
        val p = uri.path ?: throw FileNotFoundException("sem caminho")
        if (!p.startsWith("/f/")) throw FileNotFoundException(p)
        val f = File(p.substring(2))
        if (!f.isFile) throw FileNotFoundException(p)
        return f
    }

    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String? = try {
        Storage.mimeOf(fileOf(uri))
    } catch (_: Exception) {
        null
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor =
        ParcelFileDescriptor.open(fileOf(uri), ParcelFileDescriptor.MODE_READ_ONLY)

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val f = fileOf(uri)
        val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val c = MatrixCursor(cols)
        val row: List<Any?> = cols.map<String, Any?> {
            when (it) {
                OpenableColumns.DISPLAY_NAME -> f.name
                OpenableColumns.SIZE -> f.length()
                "mime_type" -> Storage.mimeOf(f)
                "last_modified", "date_modified" -> f.lastModified()
                else -> null
            }
        }
        c.addRow(row.toTypedArray<Any?>())
        return c
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0
}
