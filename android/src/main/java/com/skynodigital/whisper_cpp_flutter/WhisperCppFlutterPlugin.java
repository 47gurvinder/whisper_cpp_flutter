package com.skynodigital.whisper_cpp_flutter;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Build;
import android.text.TextUtils;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

public final class WhisperCppFlutterPlugin implements
        FlutterPlugin,
        ActivityAware,
        MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler,
        PluginRegistry.RequestPermissionsResultListener {
    private static final int RECORD_AUDIO_PERMISSION_REQUEST = 9142;

    private MethodChannel methods;
    private EventChannel events;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private EventChannel.EventSink sink;
    private MethodChannel.Result permissionResult;
    private AudioRecord recorder;
    private Thread recordingThread;
    private final AtomicBoolean running = new AtomicBoolean(false);

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        methods = new MethodChannel(binding.getBinaryMessenger(), "whisper_cpp_flutter/recorder");
        methods.setMethodCallHandler(this);
        events = new EventChannel(binding.getBinaryMessenger(), "whisper_cpp_flutter/audio");
        events.setStreamHandler(this);
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "requestPermission":
                requestPermission(result);
                break;
            case "start":
                try {
                    Integer sampleRate = call.argument("sampleRate");
                    Integer chunkMilliseconds = call.argument("chunkMilliseconds");
                    start(sampleRate == null ? 16000 : sampleRate,
                            chunkMilliseconds == null ? 100 : chunkMilliseconds);
                    result.success(null);
                } catch (Exception error) {
                    result.error("recording", error.getMessage(), null);
                }
                break;
            case "stop":
                stop();
                result.success(null);
                break;
            case "deviceInfo":
                Map<String, String> info = new HashMap<>();
                info.put("manufacturer", Build.MANUFACTURER);
                info.put("model", Build.MODEL);
                info.put("device", Build.DEVICE);
                info.put("hardware", Build.HARDWARE);
                info.put("architecture", TextUtils.join(",", Build.SUPPORTED_ABIS));
                info.put("identity", Build.MANUFACTURER + "/" + Build.MODEL + "/"
                        + Build.DEVICE + "/" + Build.HARDWARE);
                result.success(info);
                break;
            default:
                result.notImplemented();
        }
    }

    private void requestPermission(MethodChannel.Result result) {
        if (activity == null) {
            result.success(false);
            return;
        }
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED) {
            result.success(true);
            return;
        }
        permissionResult = result;
        activity.requestPermissions(
                new String[]{Manifest.permission.RECORD_AUDIO},
                RECORD_AUDIO_PERMISSION_REQUEST);
    }

    private void start(int sampleRate, int chunkMilliseconds) {
        Activity currentActivity = activity;
        if (currentActivity == null) {
            throw new IllegalStateException("Plugin is not attached to an activity");
        }
        if (currentActivity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            throw new SecurityException("Microphone permission is required");
        }
        if (running.getAndSet(true)) {
            return;
        }

        try {
            int requestedSamples = sampleRate * chunkMilliseconds / 1000;
            int minBufferBytes = AudioRecord.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_FLOAT);
            if (minBufferBytes < 0) {
                throw new IllegalStateException("Unsupported microphone format");
            }

            int sampleCount = Math.max(requestedSamples, (minBufferBytes + 3) / 4);
            recorder = new AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_FLOAT,
                    Math.max(minBufferBytes, sampleCount * 4));
            recorder.startRecording();

            recordingThread = new Thread(() -> record(sampleCount), "whisper-recorder");
            recordingThread.start();
        } catch (Exception error) {
            running.set(false);
            if (recorder != null) {
                recorder.release();
                recorder = null;
            }
            throw error;
        }
    }

    private void record(int sampleCount) {
        float[] data = new float[sampleCount];
        while (running.get()) {
            AudioRecord currentRecorder = recorder;
            int read = currentRecorder == null
                    ? -1
                    : currentRecorder.read(data, 0, data.length, AudioRecord.READ_BLOCKING);
            if (read <= 0) {
                continue;
            }

            ByteBuffer bytes = ByteBuffer.allocate(read * Float.BYTES).order(ByteOrder.LITTLE_ENDIAN);
            for (int index = 0; index < read; index++) {
                bytes.putFloat(data[index]);
            }
            byte[] chunk = bytes.array();
            Activity currentActivity = activity;
            if (currentActivity != null) {
                currentActivity.runOnUiThread(() -> {
                    EventChannel.EventSink currentSink = sink;
                    if (currentSink != null) {
                        currentSink.success(chunk);
                    }
                });
            }
        }
    }

    private void stop() {
        running.set(false);
        if (recorder != null) {
            recorder.stop();
        }
        if (recordingThread != null) {
            try {
                recordingThread.join(500);
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
            }
        }
        if (recorder != null) {
            recorder.release();
        }
        recorder = null;
        recordingThread = null;
    }

    @Override
    public void onListen(@Nullable Object arguments, @Nullable EventChannel.EventSink eventSink) {
        sink = eventSink;
    }

    @Override
    public void onCancel(@Nullable Object arguments) {
        sink = null;
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        stop();
        methods.setMethodCallHandler(null);
        events.setStreamHandler(null);
    }

    @Override
    public boolean onRequestPermissionsResult(
            int requestCode,
            @NonNull String[] permissions,
            @NonNull int[] grantResults) {
        if (requestCode != RECORD_AUDIO_PERMISSION_REQUEST) {
            return false;
        }
        if (permissionResult != null) {
            permissionResult.success(
                    grantResults.length > 0
                            && grantResults[0] == PackageManager.PERMISSION_GRANTED);
            permissionResult = null;
        }
        return true;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachFromActivity();
    }

    private void detachFromActivity() {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        activityBinding = null;
        activity = null;
    }
}
