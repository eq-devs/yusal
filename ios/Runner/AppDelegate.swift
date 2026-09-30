import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var importChannel: FlutterMethodChannel?
  private var pending: [[String: Any]] = []
  private var ready = false

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HouseImport") else { return }
    let channel = FlutterMethodChannel(name: "yusal/house_import", binaryMessenger: registrar.messenger())
    importChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      if call.method == "getPending" {
        self.ready = true
        result(self.pending)
        self.pending.removeAll()
      } else { result(FlutterMethodNotImplemented) }
    }
  }

  func receiveHouse(_ url: URL) {
    guard url.isFileURL else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      var payload: [String: Any]
      do {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > 10_485_760 {
          payload = ["error": "FILE_TOO_LARGE"]
        } else {
          guard let stream = InputStream(url: url) else { throw CocoaError(.fileReadUnknown) }
          stream.open()
          defer { stream.close() }
          var data = Data()
          var buffer = [UInt8](repeating: 0, count: 8192)
          while true {
            let count = stream.read(&buffer, maxLength: min(buffer.count, 10_485_761 - data.count))
            if count < 0 { throw stream.streamError ?? CocoaError(.fileReadUnknown) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            if data.count > 10_485_760 { break }
          }
          payload = data.count > 10_485_760 ? ["error": "FILE_TOO_LARGE"] : ["bytes": FlutterStandardTypedData(bytes: data)]
        }
      } catch { payload = ["error": "IO_ERROR"] }
      DispatchQueue.main.async {
        if self.ready { self.importChannel?.invokeMethod("importFile", arguments: payload) }
        else { self.pending.append(payload) }
      }
    }
  }
}
