package com.syntex.imports

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Android document picker uses the Google Drive provider already signed into the phone.
// No separate OAuth application credentials; user chooses a cloud JSON file.
class MainActivity : FlutterActivity() {
    private val channelName = "syntex.drive"
    private val createCode = 9382
    private val openCode = 9383
    private var pending: MethodChannel.Result? = null
    private val prefs by lazy { getSharedPreferences("syntex_drive", MODE_PRIVATE) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "connected" -> result.success(prefs.getString("uri", null) != null)
                    "create", "open" -> {
                        if (pending != null) {
                            result.error("BUSY", "File chooser is already open", null)
                            return@setMethodCallHandler
                        }
                        pending = result
                        val create = call.method == "create"
                        val intent = Intent(if (create) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                        intent.addCategory(Intent.CATEGORY_OPENABLE)
                        intent.type = "application/json"
                        intent.addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                        )
                        if (create) intent.putExtra(Intent.EXTRA_TITLE, "SyntexImportsBackup.json")
                        startActivityForResult(intent, if (create) createCode else openCode)
                    }
                    "read" -> result.success(readSelected())
                    "write" -> {
                        val json = call.arguments as? String
                            ?: throw IllegalArgumentException("Missing backup JSON")
                        if (!json.trimStart().startsWith("{")) throw IllegalArgumentException("Invalid JSON")
                        writeSelected(json)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("DRIVE_ERROR", e.message ?: "Drive file error", null)
            }
        }
    }

    private fun selectedUri(): Uri {
        return Uri.parse(prefs.getString("uri", null)
            ?: throw IllegalStateException("Choose a Google Drive backup first"))
    }

    private fun readSelected(): String {
        return contentResolver.openInputStream(selectedUri())?.bufferedReader(Charsets.UTF_8)
            ?.use { it.readText() } ?: ""
    }

    private fun writeSelected(json: String) {
        contentResolver.openOutputStream(selectedUri(), "wt")
            ?.use { it.write(json.toByteArray(Charsets.UTF_8)) }
            ?: throw IllegalStateException("Cannot write selected Drive file")
    }

    @Deprecated("Using the platform file picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != createCode && requestCode != openCode) return
        val callback = pending ?: return
        pending = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            callback.error("CANCELLED", "Cloud file not selected", null)
            return
        }
        try {
            val uri = data.data!!
            val permissions = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            if (permissions != 0) contentResolver.takePersistableUriPermission(uri, permissions)
            prefs.edit().putString("uri", uri.toString()).apply()
            callback.success(readSelected())
        } catch (e: Exception) {
            callback.error("DRIVE_ERROR", e.message ?: "Failed to connect Drive file", null)
        }
    }
}