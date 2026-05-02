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

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.ytdownloader/ytdl"

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
                    val outputPath = call.argument<String>("outputPath")
                    if (url != null && outputPath != null) {
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
                                }
                                request.addOption("-o", outputPath)
                                
                                YoutubeDL.getInstance().execute(request) { progress, etaInSeconds, line ->
                                    // Could send progress via EventChannel if needed
                                }
                                withContext(Dispatchers.Main) {
                                    result.success("Success")
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGS", "URL and Output Path are required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
