package com.tecsattv.fileguard

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException

/// "FileGuard" no menu lateral do seletor de arquivos do Android (a tela
/// que muitos apps abrem para anexar ou salvar um arquivo). Mostra o
/// armazenamento interno e o cartão SD, com as pastas do jeito que estão.
class DocsProvider : DocumentsProvider() {
    private val rootCols = arrayOf(
        Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE,
        Root.COLUMN_SUMMARY, Root.COLUMN_FLAGS, Root.COLUMN_ICON,
        Root.COLUMN_AVAILABLE_BYTES
    )
    private val docCols = arrayOf(
        Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_MIME_TYPE, Document.COLUMN_LAST_MODIFIED,
        Document.COLUMN_SIZE, Document.COLUMN_FLAGS
    )

    private val authority get() = "${context!!.packageName}.documents"

    override fun onCreate(): Boolean = true

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val c = MatrixCursor(projection ?: rootCols)
        for (v in Storage.volumes(context!!)) {
            c.newRow()
                .add(Root.COLUMN_ROOT_ID, v.path)
                .add(Root.COLUMN_DOCUMENT_ID, v.path)
                .add(Root.COLUMN_TITLE, "FileGuard")
                .add(Root.COLUMN_SUMMARY, if (v.removable) "Cartão SD" else "Armazenamento interno")
                .add(
                    Root.COLUMN_FLAGS,
                    Root.FLAG_SUPPORTS_CREATE or Root.FLAG_SUPPORTS_IS_CHILD or Root.FLAG_LOCAL_ONLY
                )
                .add(Root.COLUMN_ICON, R.mipmap.ic_launcher)
                .add(Root.COLUMN_AVAILABLE_BYTES, v.free)
        }
        return c
    }

    private fun fileOf(id: String?): File {
        if (id == null) throw FileNotFoundException("sem id")
        return File(id)
    }

    private fun addRow(c: MatrixCursor, f: File) {
        val dir = f.isDirectory
        var flags = 0
        if (dir) {
            if (f.canWrite()) {
                flags = flags or Document.FLAG_DIR_SUPPORTS_CREATE or
                    Document.FLAG_SUPPORTS_DELETE or Document.FLAG_SUPPORTS_RENAME
            }
        } else if (f.canWrite()) {
            flags = flags or Document.FLAG_SUPPORTS_WRITE or
                Document.FLAG_SUPPORTS_DELETE or Document.FLAG_SUPPORTS_RENAME
        }
        c.newRow()
            .add(Document.COLUMN_DOCUMENT_ID, f.absolutePath)
            .add(Document.COLUMN_DISPLAY_NAME, f.name)
            .add(Document.COLUMN_MIME_TYPE, if (dir) Document.MIME_TYPE_DIR else Storage.mimeOf(f))
            .add(Document.COLUMN_LAST_MODIFIED, f.lastModified())
            .add(Document.COLUMN_SIZE, if (dir) null else f.length())
            .add(Document.COLUMN_FLAGS, flags)
    }

    override fun queryDocument(documentId: String?, projection: Array<out String>?): Cursor {
        val c = MatrixCursor(projection ?: docCols)
        val f = fileOf(documentId)
        if (!f.exists()) throw FileNotFoundException(documentId)
        addRow(c, f)
        // Raiz do volume aparece como "Armazenamento interno" / "Cartão SD".
        return c
    }

    override fun queryChildDocuments(
        parentDocumentId: String?,
        projection: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val c = MatrixCursor(projection ?: docCols)
        val dir = fileOf(parentDocumentId)
        dir.listFiles()?.filter { !it.name.startsWith(".") }?.forEach { addRow(c, it) }
        c.setNotificationUri(
            context!!.contentResolver,
            DocumentsContract.buildChildDocumentsUri(authority, dir.absolutePath)
        )
        return c
    }

    override fun openDocument(
        documentId: String?,
        mode: String?,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        val f = fileOf(documentId)
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.parseMode(mode ?: "r"))
    }

    override fun isChildDocument(parentDocumentId: String?, documentId: String?): Boolean {
        if (parentDocumentId == null || documentId == null) return false
        return documentId.startsWith("$parentDocumentId/")
    }

    private fun notifyParent(f: File) {
        val p = f.parentFile ?: return
        context!!.contentResolver.notifyChange(
            DocumentsContract.buildChildDocumentsUri(authority, p.absolutePath), null
        )
    }

    /// Nome livre: "foto.jpg" já existe → "foto (1).jpg".
    private fun unique(dir: File, name: String): File {
        var f = File(dir, name)
        if (!f.exists()) return f
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 1
        while (f.exists()) {
            f = File(dir, "$stem ($i)$ext")
            i++
        }
        return f
    }

    override fun createDocument(
        parentDocumentId: String?,
        mimeType: String?,
        displayName: String?
    ): String {
        val dir = fileOf(parentDocumentId)
        val f = unique(dir, (displayName ?: "novo").replace("/", "_"))
        val ok = if (mimeType == Document.MIME_TYPE_DIR) f.mkdir() else f.createNewFile()
        if (!ok) throw IllegalStateException("Não foi possível criar ${f.name}")
        notifyParent(f)
        return f.absolutePath
    }

    override fun deleteDocument(documentId: String?) {
        val f = fileOf(documentId)
        if (!f.deleteRecursively()) throw IllegalStateException("Não foi possível apagar ${f.name}")
        notifyParent(f)
    }

    override fun renameDocument(documentId: String?, displayName: String?): String? {
        val f = fileOf(documentId)
        val name = (displayName ?: return null).replace("/", "_")
        val target = unique(f.parentFile ?: return null, name)
        if (!f.renameTo(target)) throw IllegalStateException("Não foi possível renomear ${f.name}")
        notifyParent(target)
        return target.absolutePath
    }
}
