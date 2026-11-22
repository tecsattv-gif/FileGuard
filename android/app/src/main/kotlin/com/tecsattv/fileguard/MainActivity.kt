package com.tecsattv.fileguard

import android.Manifest
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

// Ponte com o Android: pastas do app, armazenamentos (interno e cartão SD),
// permissão "Acesso a todos os arquivos" e páginas de PDF (PdfRenderer do
// próprio Android, sem plugin).
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pdf: PdfRenderer? = null
    private var pdfFd: ParcelFileDescriptor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fileguard/native")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "dirs" -> result.success(
                            mapOf(
                                "docs" to getDir("flutter", MODE_PRIVATE).path,
                                "temp" to cacheDir.path
                            )
                        )
                        "volumes" -> result.success(volumes())
                        "hasAccess" -> result.success(hasAccess())
                        "requestAccess" -> {
                            requestAccess()
                            result.success(true)
                        }
                        "sdk" -> result.success(Build.VERSION.SDK_INT)
                        "pickRequest" -> result.success(pickRequest())
                        "pickResult" -> {
                            pickResult(call.argument<List<String>>("paths") ?: emptyList())
                            result.success(true)
                        }
                        "pickCancel" -> {
                            setResult(RESULT_CANCELED)
                            finish()
                            result.success(true)
                        }
                        "scan" -> {
                            // Avisa a Galeria/Música que arquivos mudaram.
                            val paths = call.argument<List<String>>("paths") ?: emptyList()
                            if (paths.isNotEmpty()) {
                                MediaScannerConnection.scanFile(this, paths.toTypedArray(), null, null)
                            }
                            result.success(true)
                        }
                        "pdfOpen" -> {
                            val path = call.argument<String>("path")!!
                            worker.execute {
                                try {
                                    closePdf()
                                    val fd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
                                    pdfFd = fd
                                    val r = PdfRenderer(fd)
                                    pdf = r
                                    runOnUiThread { result.success(r.pageCount) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("pdf", e.message, null) }
                                }
                            }
                        }
                        "pdfPage" -> {
                            val index = call.argument<Int>("index") ?: 0
                            val width = (call.argument<Int>("width") ?: 1080).coerceIn(200, 2400)
                            worker.execute {
                                try {
                                    val r = pdf ?: throw IllegalStateException("PDF fechado")
                                    val page = r.openPage(index)
                                    val h = (width.toDouble() * page.height / page.width).toInt().coerceAtLeast(1)
                                    val bmp = Bitmap.createBitmap(width, h, Bitmap.Config.ARGB_8888)
                                    bmp.eraseColor(Color.WHITE)
                                    page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                                    page.close()
                                    val out = ByteArrayOutputStream()
                                    bmp.compress(Bitmap.CompressFormat.JPEG, 88, out)
                                    bmp.recycle()
                                    val bytes = out.toByteArray()
                                    runOnUiThread { result.success(bytes) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("pdf", e.message, null) }
                                }
                            }
                        }
                        "pdfClose" -> {
                            worker.execute { closePdf() }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("native", e.message, null)
                }
            }
    }

    private fun closePdf() {
        try { pdf?.close() } catch (_: Exception) {}
        try { pdfFd?.close() } catch (_: Exception) {}
        pdf = null
        pdfFd = null
    }

    /// Armazenamento interno + cartões SD/USB, com espaço total e livre.
    private fun volumes(): List<Map<String, Any>> = Storage.volumes(this).map {
        mapOf(
            "path" to it.path,
            "removable" to it.removable,
            "total" to it.total,
            "free" to it.free
        )
    }

    /// Outro app pediu um arquivo (anexar, enviar, abrir…)? Devolve os tipos
    /// pedidos e se pode escolher vários; null = o app foi aberto normalmente.
    private fun pickRequest(): Map<String, Any>? {
        val i = intent ?: return null
        if (i.action != Intent.ACTION_GET_CONTENT && i.action != Intent.ACTION_PICK) return null
        val mimes = mutableListOf<String>()
        i.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.let { a -> mimes.addAll(a.filterNotNull()) }
        if (mimes.isEmpty()) mimes.add(i.type ?: "*/*")
        return mapOf(
            "mimes" to mimes,
            "multiple" to i.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
        )
    }

    /// Entrega os arquivos escolhidos para o app que pediu e fecha o seletor.
    private fun pickResult(paths: List<String>) {
        val uris = paths.map { FilesProvider.uriFor(this, File(it)) }
        if (uris.isEmpty()) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }
        val data = Intent()
        data.data = uris[0]
        val clip = ClipData.newRawUri(null, uris[0])
        for (u in uris.drop(1)) clip.addItem(ClipData.Item(u))
        data.clipData = clip
        data.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        setResult(RESULT_OK, data)
        finish()
    }

    private fun hasAccess(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                        .setData(Uri.parse("package:$packageName"))
                )
            } catch (e: Exception) {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            requestPermissions(
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE
                ), 7
            )
        }
    }

    override fun onDestroy() {
        closePdf()
        worker.shutdown()
        super.onDestroy()
    }
}
