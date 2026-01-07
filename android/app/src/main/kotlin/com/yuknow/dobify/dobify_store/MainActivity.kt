package com.yuknow.dobify.dobify_store

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.yuknow.dobify.dobify_store/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    val title = call.argument<String>("title") ?: "Share"
                    val text = call.argument<String>("text") ?: ""
                    val phoneNumber = call.argument<String>("phoneNumber") ?: ""

                    if (path != null) {
                        try {
                            val file = File(path)
                            val uri = FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )

                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = mimeType
                                putExtra(Intent.EXTRA_STREAM, uri)
                                putExtra(Intent.EXTRA_TEXT, text)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }

                            // Try WhatsApp first if phone number provided
                            if (phoneNumber.isNotEmpty()) {
                                val whatsappIntent = Intent(Intent.ACTION_SEND).apply {
                                    type = mimeType
                                    setPackage("com.whatsapp")
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    putExtra(Intent.EXTRA_TEXT, text)
                                    putExtra("jid", "$phoneNumber@s.whatsapp.net")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }

                                try {
                                    startActivity(whatsappIntent)
                                    result.success(true)
                                    return@setMethodCallHandler
                                } catch (e: Exception) {
                                    // WhatsApp not installed or failed, continue to general share
                                }
                            }

                            // General share chooser
                            val chooser = Intent.createChooser(shareIntent, title)
                            startActivity(chooser)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_PATH", "File path is null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}