import Flutter
import MetricKit
import Network
import UIKit
import os

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The forensic build (branch ios-debug): native logging from the first
    // moment, before Flutter exists.
    BreezeForensics.shared.start(launchOptions: launchOptions)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BreezeForensics") {
      BreezeForensics.shared.attach(registrar.messenger())
    }
  }
}

/// An Objective-C exception nobody caught: written down before the process
/// goes. (A Swift crash is a signal, not this; MetricKit reports those on
/// the next launch, and iOS keeps its own crash report.)
private func breezeUncaughtException(_ exception: NSException) {
  BreezeForensics.shared.crashed(exception)
}

/// What only iOS can tell, for lib/src/forensics/native.dart: the device, the
/// keychain's own list of the app's items (attributes, never data), the
/// provisioning profile the app was signed with, the network path, whether
/// the local network permission lets a connection through, and events the
/// Dart side cannot see (memory warnings, thermal state, the keychain
/// locking, the network changing). Each event goes to the system log
/// (subsystem app.breeze.forensics), to Documents/forensics/native-*.log,
/// and to the Dart log once Flutter is running.
final class BreezeForensics: NSObject, MXMetricManagerSubscriber {
  static let shared = BreezeForensics()

  private let logger = Logger(subsystem: "app.breeze.forensics", category: "native")
  private let fileQueue = DispatchQueue(label: "app.breeze.forensics.file")
  private let pathQueue = DispatchQueue(label: "app.breeze.forensics.path")
  private let monitor = NWPathMonitor()
  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var nativeLog: FileHandle?
  private var lastPath = "unknown"
  private var launchUptime: TimeInterval = 0
  private var observers: [NSObjectProtocol] = []

  private lazy var dir: URL = {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let d = docs.appendingPathComponent("forensics", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }()

  private static func stamp() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f.string(from: Date())
  }

  private static let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  // MARK: - Starting

  func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
    launchUptime = ProcessInfo.processInfo.systemUptime
    let url = dir.appendingPathComponent("native-\(Self.stamp()).log")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    nativeLog = try? FileHandle(forWritingTo: url)
    pruneNativeLogs()
    NSSetUncaughtExceptionHandler(breezeUncaughtException)

    let info = Bundle.main.infoDictionary ?? [:]
    event("launch: \(info["CFBundleIdentifier"] ?? "?") \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?")), "
      + "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion), \(Self.machine()), "
      + "options \(launchOptions?.keys.map { $0.rawValue } ?? [])")
    event("state: protected data \(UIApplication.shared.isProtectedDataAvailable ? "available" : "NOT available (the keychain is locked)"), "
      + "thermal \(Self.thermal(ProcessInfo.processInfo.thermalState)), low power \(ProcessInfo.processInfo.isLowPowerModeEnabled), "
      + "memory available \(os_proc_available_memory() / 1_048_576) MB")

    let center = NotificationCenter.default
    let watched: [(Notification.Name, String)] = [
      (UIApplication.didReceiveMemoryWarningNotification, "MEMORY WARNING"),
      (UIApplication.protectedDataWillBecomeUnavailableNotification, "protected data going unavailable (keychain locking)"),
      (UIApplication.protectedDataDidBecomeAvailableNotification, "protected data available (keychain unlocked)"),
      (UIApplication.didBecomeActiveNotification, "app active"),
      (UIApplication.willResignActiveNotification, "app resigning active"),
      (UIApplication.didEnterBackgroundNotification, "app in background"),
      (UIApplication.willEnterForegroundNotification, "app entering foreground"),
      (UIApplication.willTerminateNotification, "app terminating"),
      (UIApplication.significantTimeChangeNotification, "significant time change"),
      (NSLocale.currentLocaleDidChangeNotification, "locale changed"),
      (.NSSystemTimeZoneDidChange, "time zone changed"),
      (UIContentSizeCategory.didChangeNotification, "text size changed"),
      (UIAccessibility.voiceOverStatusDidChangeNotification, "VoiceOver changed"),
    ]
    for (name, text) in watched {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        guard let self else { return }
        var t = text
        if name == UIApplication.didReceiveMemoryWarningNotification {
          t += ": footprint \(Self.footprintMB()) MB, available \(os_proc_available_memory() / 1_048_576) MB"
        }
        self.event(t)
      })
    }
    observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.event("thermal state \(Self.thermal(ProcessInfo.processInfo.thermalState))")
    })
    observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
      self?.event("low power mode \(ProcessInfo.processInfo.isLowPowerModeEnabled)")
    })

    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      let d = Self.describe(path)
      DispatchQueue.main.async {
        if d != self.lastPath {
          self.lastPath = d
          self.event("network path: \(d)")
        }
      }
    }
    monitor.start(queue: pathQueue)

    MXMetricManager.shared.add(self)
    // What iOS delivered before this launch (crashes, hangs), kept.
    let past = MXMetricManager.shared.pastDiagnosticPayloads
    if !past.isEmpty {
      for p in past { save(p) }
      event("MetricKit: \(past.count) earlier diagnostic payload(s) saved")
    }
  }

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "breeze/forensics", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "drain":
        result(self.pending)
        self.pending.removeAll()
      case "info": result(self.info())
      case "keychain": result(self.keychain())
      case "provisioning": result(self.provisioning())
      case "connect":
        let args = call.arguments as? [String: Any] ?? [:]
        self.connect(host: args["host"] as? String ?? "", port: args["port"] as? Int ?? 0, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  // MARK: - Writing down

  /// One event: the system log, the native log file, and the Dart log.
  func event(_ text: String) {
    logger.notice("\(text, privacy: .public)")
    let line = "\(Self.iso.string(from: Date())) \(text)\n"
    fileQueue.async { [weak self] in
      guard let h = self?.nativeLog, let data = line.data(using: .utf8) else { return }
      _ = try? h.seekToEnd()
      try? h.write(contentsOf: data)
    }
    let send = { [weak self] in
      guard let self else { return }
      if let ch = self.channel {
        ch.invokeMethod("event", arguments: text)
      } else {
        self.pending.append(text)
        if self.pending.count > 500 { self.pending.removeFirst() }
      }
    }
    if Thread.isMainThread { send() } else { DispatchQueue.main.async(execute: send) }
  }

  func crashed(_ e: NSException) {
    let text = "UNCAUGHT EXCEPTION \(e.name.rawValue): \(e.reason ?? "")\n\(e.callStackSymbols.joined(separator: "\n"))\n"
    logger.fault("\(text, privacy: .public)")
    let url = dir.appendingPathComponent("native-crash-\(Self.stamp()).txt")
    try? text.data(using: .utf8)?.write(to: url, options: .atomic)
    if let h = nativeLog, let data = text.data(using: .utf8) {
      _ = try? h.seekToEnd()
      try? h.write(contentsOf: data)
      try? h.synchronize()
    }
  }

  private func pruneNativeLogs() {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
    let logs = names.filter { $0.hasPrefix("native-") && $0.hasSuffix(".log") }.sorted()
    for old in logs.dropLast(20) {
      try? fm.removeItem(at: dir.appendingPathComponent(old))
    }
  }

  private func save(_ payload: MXDiagnosticPayload) {
    let name = "metrickit-diagnostics-\(Int(payload.timeStampEnd.timeIntervalSince1970)).json"
    let url = dir.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: url.path) { return }
    try? payload.jsonRepresentation().write(to: url, options: .atomic)
  }

  // MARK: - MetricKit

  func didReceive(_ payloads: [MXMetricPayload]) {
    for p in payloads {
      let url = dir.appendingPathComponent("metrickit-metrics-\(Int(p.timeStampEnd.timeIntervalSince1970)).json")
      try? p.jsonRepresentation().write(to: url, options: .atomic)
    }
    event("MetricKit: \(payloads.count) metric payload(s) saved")
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for p in payloads {
      save(p)
      event("MetricKit diagnostics: \(p.crashDiagnostics?.count ?? 0) crash(es), \(p.hangDiagnostics?.count ?? 0) hang(s), "
        + "\(p.cpuExceptionDiagnostics?.count ?? 0) CPU exception(s), \(p.diskWriteExceptionDiagnostics?.count ?? 0) disk-write exception(s)")
    }
  }

  // MARK: - Answers

  private static func machine() -> String {
    var u = utsname()
    uname(&u)
    return withUnsafeBytes(of: &u.machine) { raw in
      String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
  }

  private static func thermal(_ s: ProcessInfo.ThermalState) -> String {
    switch s {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }

  /// What iOS counts against the app's memory limit (jetsam uses this).
  private static func footprintMB() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
  }

  static func describe(_ p: NWPath) -> String {
    let kinds: [(NWInterface.InterfaceType, String)] = [
      (.wifi, "Wi-Fi"), (.cellular, "cellular"), (.wiredEthernet, "Ethernet"), (.loopback, "loopback"), (.other, "other"),
    ]
    let using = kinds.filter { p.usesInterfaceType($0.0) }.map { $0.1 }
    var parts = ["\(p.status)", "via \(using.isEmpty ? "nothing" : using.joined(separator: "+"))"]
    parts.append("interfaces \(p.availableInterfaces.map { "\($0.name)" }.joined(separator: ","))")
    if p.status != .satisfied { parts.append("why: \(p.unsatisfiedReason)") }
    if p.isExpensive { parts.append("expensive") }
    if p.isConstrained { parts.append("Low Data Mode") }
    parts.append("IPv4 \(p.supportsIPv4), IPv6 \(p.supportsIPv6), DNS \(p.supportsDNS)")
    return parts.joined(separator: ", ")
  }

  private func info() -> [String: Any] {
    let p = ProcessInfo.processInfo
    let app = UIApplication.shared
    let bundle = Bundle.main.infoDictionary ?? [:]
    var d: [String: Any] = [
      "machine": Self.machine(),
      "model": UIDevice.current.model,
      "system": "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
      "identifierForVendor": UIDevice.current.identifierForVendor?.uuidString ?? "",
      "bundle": "\(Bundle.main.bundleIdentifier ?? "?") \(bundle["CFBundleShortVersionString"] ?? "?") (\(bundle["CFBundleVersion"] ?? "?"))",
      "physicalMemoryMB": Int(p.physicalMemory / 1_048_576),
      "footprintMB": Self.footprintMB(),
      "availableMemoryMB": Int(os_proc_available_memory() / 1_048_576),
      "processors": "\(p.activeProcessorCount) of \(p.processorCount) active",
      "thermalState": Self.thermal(p.thermalState),
      "lowPowerMode": p.isLowPowerModeEnabled,
      "systemUptimeH": String(format: "%.1f", p.systemUptime / 3600),
      "appUptimeS": Int(p.systemUptime - launchUptime),
      "protectedDataAvailable": app.isProtectedDataAvailable,
      "backgroundRefresh": "\(app.backgroundRefreshStatus.rawValue) (0 restricted, 1 denied, 2 available)",
      "applicationState": "\(app.applicationState.rawValue) (0 active, 1 inactive, 2 background)",
      "locale": Locale.current.identifier,
      "preferredLanguages": Locale.preferredLanguages.joined(separator: ", "),
      "timeZone": TimeZone.current.identifier,
      "contentSize": app.preferredContentSizeCategory.rawValue,
      "voiceOver": UIAccessibility.isVoiceOverRunning,
      "reduceMotion": UIAccessibility.isReduceMotionEnabled,
      "boldText": UIAccessibility.isBoldTextEnabled,
      "networkPath": lastPath,
      "documents": dir.path,
    ]
    if let screen = app.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.screen {
      d["screen"] = "\(screen.bounds.size.width)x\(screen.bounds.size.height) pt at \(screen.scale)x (native \(screen.nativeScale)x), "
        + "\(screen.maximumFramesPerSecond) Hz, brightness \(String(format: "%.2f", screen.brightness))"
    }
    if let v = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
      d["diskFreeMB"] = Int((v.volumeAvailableCapacityForImportantUsage ?? 0) / 1_048_576)
      d["diskTotalMB"] = (v.volumeTotalCapacity ?? 0) / 1_048_576
    }
    return d
  }

  /// The app's keychain items as iOS lists them: attributes only, never the
  /// data. flutter_secure_storage keeps each key as the account of a generic
  /// password item.
  private func keychain() -> [String: Any] {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnAttributes as String: true,
      kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
    ]
    var out: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &out)
    let text = SecCopyErrorMessageString(status, nil) as String? ?? ""
    var items: [[String: String]] = []
    for a in (out as? [[String: Any]]) ?? [] {
      func s(_ k: CFString) -> String {
        guard let v = a[k as String] else { return "" }
        if let date = v as? Date { return Self.iso.string(from: date) }
        return "\(v)"
      }
      items.append([
        "service": s(kSecAttrService),
        "account": s(kSecAttrAccount),
        "accessible": s(kSecAttrAccessible),
        "accessGroup": s(kSecAttrAccessGroup),
        "synchronizable": s(kSecAttrSynchronizable),
        "created": s(kSecAttrCreationDate),
        "modified": s(kSecAttrModificationDate),
      ])
    }
    items.sort { $0["account"] ?? "" < $1["account"] ?? "" }
    return ["status": Int(status), "statusText": text, "items": items]
  }

  /// The embedded provisioning profile: who signed this copy, until when
  /// (a free Apple ID's lasts seven days), and what it allows.
  private func provisioning() -> [String: Any] {
    guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
          let data = try? Data(contentsOf: url) else {
      return ["present": false, "note": "no embedded.mobileprovision: not signed with a profile (App Store, or not signed)"]
    }
    let text = String(decoding: data, as: UTF8.self)
    guard let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>"),
          let plist = try? PropertyListSerialization.propertyList(
            from: Data(text[start.lowerBound..<end.upperBound].utf8), format: nil) as? [String: Any] else {
      return ["present": true, "note": "the profile could not be read"]
    }
    func date(_ k: String) -> String { (plist[k] as? Date).map { Self.iso.string(from: $0) } ?? "" }
    var d: [String: Any] = [
      "present": true,
      "name": plist["Name"] as? String ?? "",
      "appIdName": plist["AppIDName"] as? String ?? "",
      "teamName": plist["TeamName"] as? String ?? "",
      "teamId": (plist["TeamIdentifier"] as? [String])?.first ?? "",
      "created": date("CreationDate"),
      "expires": date("ExpirationDate"),
      "devices": (plist["ProvisionedDevices"] as? [Any])?.count ?? 0,
    ]
    if let ent = plist["Entitlements"] as? [String: Any] {
      var e: [String: String] = [:]
      for (k, v) in ent { e[k] = "\(v)" }
      d["entitlements"] = e
    }
    return d
  }

  /// A TCP connection by iOS's own networking: whether the local network
  /// permission lets it through says itself here (".waiting" with
  /// "localNetworkDenied"), where a socket only fails with "no route".
  private func connect(host: String, port: Int, result: @escaping FlutterResult) {
    guard !host.isEmpty, let p = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
      return result(["state": "bad host or port"])
    }
    let conn = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
    let queue = DispatchQueue(label: "app.breeze.forensics.connect")
    let began = Date()
    var done = false
    func finish(_ state: String, _ error: NWError? = nil) {
      if done { return }
      done = true
      var d: [String: Any] = ["state": state, "ms": Int(Date().timeIntervalSince(began) * 1000)]
      if let error { d["error"] = "\(error)" }
      if let path = conn.currentPath {
        d["path"] = Self.describe(path)
        d["unsatisfiedReason"] = "\(path.unsatisfiedReason)"
      }
      conn.cancel()
      DispatchQueue.main.async { result(d) }
    }
    conn.stateUpdateHandler = { state in
      switch state {
      case .ready: finish("ready")
      case .waiting(let e): finish("waiting", e)
      case .failed(let e): finish("failed", e)
      default: break
      }
    }
    conn.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 6) { finish("timeout") }
  }
}
