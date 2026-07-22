package com.skynodigital.whisper_cpp_flutter

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicBoolean

class WhisperCppFlutterPlugin: FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, PluginRegistry.RequestPermissionsResultListener {
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var activity: Activity? = null
    private var sink: EventChannel.EventSink? = null
    private var recorder: AudioRecord? = null
    private var thread: Thread? = null
    private val running = AtomicBoolean(false)
    private var activityBinding: ActivityPluginBinding? = null
    private var permissionResult: MethodChannel.Result? = null
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods=MethodChannel(binding.binaryMessenger,"whisper_cpp_flutter/recorder").also{it.setMethodCallHandler(this)}
        events=EventChannel(binding.binaryMessenger,"whisper_cpp_flutter/audio").also{it.setStreamHandler(this)}
    }
    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when(call.method) {
            "requestPermission" -> { val a=activity ?: return result.success(false); if(a.checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED) result.success(true) else { permissionResult=result; a.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO),9142) } }
            "start" -> try { start(call.argument<Int>("sampleRate") ?: 16000, call.argument<Int>("chunkMilliseconds") ?: 100); result.success(null) } catch(e:Exception){result.error("recording",e.message,null)}
            "stop" -> { stop(); result.success(null) }
            "deviceInfo" -> result.success(mapOf(
                "manufacturer" to Build.MANUFACTURER,
                "model" to Build.MODEL,
                "device" to Build.DEVICE,
                "hardware" to Build.HARDWARE,
                "architecture" to Build.SUPPORTED_ABIS.joinToString(","),
                "identity" to "${Build.MANUFACTURER}/${Build.MODEL}/${Build.DEVICE}/${Build.HARDWARE}"
            ))
            else -> result.notImplemented()
        }
    }
    private fun start(rate:Int, chunkMs:Int) {
        val currentActivity=activity ?: throw IllegalStateException("Plugin is not attached to an activity")
        if(currentActivity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)!=PackageManager.PERMISSION_GRANTED) throw SecurityException("Microphone permission is required")
        if(running.getAndSet(true)) return
        try {
            val requestedSamples=rate*chunkMs/1000
            val minBufferBytes=AudioRecord.getMinBufferSize(rate,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_FLOAT)
            if(minBufferBytes<0)throw IllegalStateException("Unsupported microphone format")
            val count=maxOf(requestedSamples,(minBufferBytes+3)/4)
            recorder=AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION,rate,AudioFormat.CHANNEL_IN_MONO,AudioFormat.ENCODING_PCM_FLOAT,maxOf(minBufferBytes,count*4)).also{it.startRecording()}
            thread=Thread { val data=FloatArray(count); while(running.get()){ val n=recorder?.read(data,0,data.size,AudioRecord.READ_BLOCKING) ?: -1; if(n>0){ val bytes=ByteBuffer.allocate(n*4).order(ByteOrder.LITTLE_ENDIAN); for(i in 0 until n)bytes.putFloat(data[i]); activity?.runOnUiThread{sink?.success(bytes.array())} } } }.also{it.start()}
        } catch(error:Exception) {
            running.set(false)
            recorder?.release()
            recorder=null
            throw error
        }
    }
    private fun stop(){running.set(false);recorder?.stop();thread?.join(500);recorder?.release();recorder=null;thread=null}
    override fun onListen(arguments:Any?, events:EventChannel.EventSink?){sink=events}
    override fun onCancel(arguments:Any?){sink=null}
    override fun onDetachedFromEngine(binding:FlutterPlugin.FlutterPluginBinding){stop();methods.setMethodCallHandler(null);events.setStreamHandler(null)}
    override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<out String>,grantResults:IntArray):Boolean { if(requestCode!=9142)return false;permissionResult?.success(grantResults.isNotEmpty()&&grantResults[0]==PackageManager.PERMISSION_GRANTED);permissionResult=null;return true }
    override fun onAttachedToActivity(binding:ActivityPluginBinding){activity=binding.activity;activityBinding=binding;binding.addRequestPermissionsResultListener(this)}
    override fun onDetachedFromActivityForConfigChanges(){activityBinding?.removeRequestPermissionsResultListener(this);activityBinding=null;activity=null}
    override fun onReattachedToActivityForConfigChanges(binding:ActivityPluginBinding){onAttachedToActivity(binding)}
    override fun onDetachedFromActivity(){activityBinding?.removeRequestPermissionsResultListener(this);activityBinding=null;activity=null}
}
