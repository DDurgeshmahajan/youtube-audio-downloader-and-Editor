package com.ytdownloader.ytdownloader

import android.os.Bundle
import android.os.Environment
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import com.yausername.ffmpeg.FFmpeg

import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ytdownloader/ytdl"
    private val PROGRESS_CHANNEL = "com.ytdownloader/progress"
    private var eventSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            YoutubeDL.getInstance().init(application)
            FFmpeg.getInstance().init(application)
        } catch (e: YoutubeDLException) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFormats" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val request = YoutubeDLRequest(url)
                                request.addOption("-J") // Dump JSON info
                                val response = YoutubeDL.getInstance().execute(request)
                                withContext(Dispatchers.Main) {
                                    result.success(response.out)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "URL is required", null)
                    }
                }
                "download" -> {
                    val url = call.argument<String>("url")
                    val format = call.argument<String>("format")
                    val title = call.argument<String>("title") ?: "Media_${System.currentTimeMillis()}"
                    if (url != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            try {
                                val request = YoutubeDLRequest(url)
                                if (format != null) {
                                    request.addOption("-f", format)
                                } else {
                                    request.addOption("-f", "bestvideo+bestaudio/best")
                                }
                                val extractAudio = call.argument<Boolean>("extractAudio") ?: false
                                if (extractAudio) {
                                    request.addOption("-x")
                                    request.addOption("--audio-format", "mp3")
                                    request.addOption("--audio-quality", "0")
                                } else {
                                    request.addOption("--merge-output-format", "mp4")
                                }
                                
                                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                                val extension = if (extractAudio) "mp3" else "mp4"
                                val outputFile = File(downloadsDir, "$title.$extension")
                                request.addOption("-o", outputFile.absolutePath)
                                
                                YoutubeDL.getInstance().execute(request) { progress, etaInSeconds, line ->
                                    CoroutineScope(Dispatchers.Main).launch {
                                        val data = mapOf(
                                            "progress" to progress,
                                            "eta" to etaInSeconds,
                                            "line" to line
                                        )
                                        eventSink?.success(data)
                                    }
                                }
                                
                                android.media.MediaScannerConnection.scanFile(
                                    applicationContext,
                                    arrayOf(outputFile.absolutePath),
                                    arrayOf(if (extractAudio) "audio/mpeg" else "video/mp4"),
                                    null
                                )

                                withContext(Dispatchers.Main) {
                                    result.success(outputFile.absolutePath)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("ERROR", e.message, null)
                                    eventSink?.success("Error: ${e.message}")
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "URL and Output Path are required", null)
                    }
                }
                "update" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        try {
                            val status = YoutubeDL.getInstance().updateYoutubeDL(applicationContext, YoutubeDL.UpdateChannel.STABLE)
                            withContext(Dispatchers.Main) {
                                result.success(status?.toString() ?: "Updated successfully")
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("ERROR", e.message, null)
                            }
                        }
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
