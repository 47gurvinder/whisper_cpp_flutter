import AVFoundation
import Darwin
import Flutter
import UIKit
#if SWIFT_PACKAGE
import WhisperCppFlutterBridge
#endif

public final class WhisperCppFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private let engine = AVAudioEngine()
  private var tapInstalled = false

  public static func register(with registrar: FlutterPluginRegistrar) {
#if SWIFT_PACKAGE
    // Keep the native target linked so Dart FFI can resolve its wf_* symbols.
    _ = wf_version()
#endif

    let instance = WhisperCppFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(name: "whisper_cpp_flutter/recorder", binaryMessenger: registrar.messenger()))
    FlutterEventChannel(name: "whisper_cpp_flutter/audio", binaryMessenger: registrar.messenger()).setStreamHandler(instance)
  }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      AVAudioSession.sharedInstance().requestRecordPermission { granted in DispatchQueue.main.async { result(granted) } }
    case "start":
      let args = call.arguments as? [String: Any]
      let rate = (args?["sampleRate"] as? NSNumber)?.doubleValue ?? 16000
      let chunkMilliseconds = (args?["chunkMilliseconds"] as? NSNumber)?.doubleValue ?? 100
      do { try start(rate: rate, chunkMilliseconds: chunkMilliseconds); result(nil) }
      catch { result(FlutterError(code:"recording", message:error.localizedDescription, details:nil)) }
    case "stop": stop(); result(nil)
    case "deviceInfo":
      var system = utsname()
      uname(&system)
      let machine = withUnsafePointer(to: &system.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
          String(cString: $0)
        }
      }
      let device = UIDevice.current
      result([
        "manufacturer": "Apple",
        "model": device.model,
        "device": machine,
        "hardware": machine,
        "architecture": machine,
        "identity": "Apple/\(device.model)/\(machine)"
      ])
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func start(rate: Double, chunkMilliseconds: Double) throws {
    if engine.isRunning { return }
    let session=AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode:.measurement, options:[.duckOthers])
    try session.setActive(true)
    let input=engine.inputNode
    let hardwareFormat=input.outputFormat(forBus:0)
    guard let format=AVAudioFormat(commonFormat:.pcmFormatFloat32, sampleRate:rate, channels:1, interleaved:false),
          let converter=AVAudioConverter(from:hardwareFormat,to:format) else { throw NSError(domain:"WhisperRecorder",code:1) }
    let requestedFrames = max(1, AVAudioFrameCount(
      hardwareFormat.sampleRate * chunkMilliseconds / 1000
    ))
    input.installTap(onBus:0, bufferSize:requestedFrames, format:hardwareFormat) { [weak self] buffer, _ in
      let capacity=AVAudioFrameCount(Double(buffer.frameLength)*rate/hardwareFormat.sampleRate)+1
      guard let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:capacity) else{return}
      var supplied=false
      try? converter.convert(to:output,error:nil){_,status in
        if supplied { status.pointee = .noDataNow; return nil }
        supplied=true; status.pointee = .haveData; return buffer
      }
      guard let data=output.floatChannelData?[0], output.frameLength>0 else{return}
      let bytes=Data(bytes:data,count:Int(output.frameLength)*MemoryLayout<Float>.size)
      DispatchQueue.main.async{self?.sink?(FlutterStandardTypedData(bytes:bytes))}
    }
    tapInstalled = true
    engine.prepare(); try engine.start()
  }
  private func stop(){
    if tapInstalled { engine.inputNode.removeTap(onBus:0); tapInstalled=false }
    if engine.isRunning { engine.stop() }
    try? AVAudioSession.sharedInstance().setActive(false)
  }
  public func onListen(withArguments arguments:Any?, eventSink events:@escaping FlutterEventSink)->FlutterError?{sink=events;return nil}
  public func onCancel(withArguments arguments:Any?)->FlutterError?{sink=nil;return nil}
}
