import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps
import Network

/// State shown in the tray: network, volume, battery.
@MainActor
final class SystemStatus: ObservableObject {
    enum Net { case wifi, ethernet, other, offline }

    @Published var network: Net = .wifi
    @Published var volume: Float = 0.5
    @Published var muted = false
    @Published var batteryLevel: Int?
    @Published var charging = false

    private let monitor = NWPathMonitor()
    private var timer: Timer?

    init() {
        if Demo.active {
            // Fixed sample state for demo snapshots.
            volume = 0.5
            batteryLevel = 80
            return
        }
        refresh()
        monitor.pathUpdateHandler = { [weak self] path in
            // With a VPN on, the path runs through a tunnel (type .other): show the physical link under it,
            // the first Wi-Fi or Ethernet interface the system lists as available.
            let physical = path.availableInterfaces.first { $0.type == .wifi || $0.type == .wiredEthernet }?.type
            let kind: Net = path.status != .satisfied ? .offline
                : path.usesInterfaceType(.wifi) || physical == .wifi ? .wifi
                : path.usesInterfaceType(.wiredEthernet) || physical == .wiredEthernet ? .ethernet : .other
            Task { @MainActor in self?.network = kind }
        }
        monitor.start(queue: .main)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 3
    }

    /// Volume and battery are read off the main thread: CoreAudio and IOKit ask other processes.
    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let volume = Audio.volume(), muted = Audio.isMuted(), battery = Self.readBattery()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let volume { self.volume = volume }
                    self.muted = muted
                    self.batteryLevel = battery.level
                    self.charging = battery.charging
                }
            }
        }
    }

    func setVolume(_ v: Float) {
        volume = v
        Audio.setVolume(v)
        if muted && v > 0 { setMuted(false) }
    }

    func setMuted(_ m: Bool) {
        muted = m
        Audio.setMuted(m)
    }

    nonisolated private static func readBattery() -> (level: Int?, charging: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = (d[kIOPSIsChargingKey] as? Bool ?? false) || d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (cur * 100 / max, charging)
        }
        return (nil, false)
    }

    var networkSymbol: String {
        switch network {
        case .wifi: "wifi"
        case .ethernet: "network"
        case .other: "globe"
        case .offline: "wifi.slash"
        }
    }

    var volumeSymbol: String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    var batterySymbol: String {
        guard let l = batteryLevel else { return "powerplug" }
        if charging { return "battery.100percent.bolt" }
        return l > 87 ? "battery.100percent" : l > 62 ? "battery.75percent" : l > 37 ? "battery.50percent" : l > 12 ? "battery.25percent" : "battery.0percent"
    }
}

/// CoreAudio volume of the default output device. Stateless, safe on any thread.
enum Audio {
    private static func device() -> AudioObjectID {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector, _ element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    static func volume() -> Float? {
        let dev = device()
        var vol = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        for var addr in [address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume), address(kAudioDevicePropertyVolumeScalar),
                         address(kAudioDevicePropertyVolumeScalar, 1)] {
            if AudioObjectHasProperty(dev, &addr), AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &vol) == noErr { return vol }
        }
        return nil
    }

    static func setVolume(_ v: Float) {
        let dev = device()
        var vol = Float32(max(0, min(1, v)))
        let size = UInt32(MemoryLayout<Float32>.size)
        var main = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if AudioObjectHasProperty(dev, &main), AudioObjectSetPropertyData(dev, &main, 0, nil, size, &vol) == noErr { return }
        for ch: UInt32 in [0, 1, 2] {
            var addr = address(kAudioDevicePropertyVolumeScalar, ch)
            if AudioObjectHasProperty(dev, &addr) { AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &vol) }
        }
    }

    static func isMuted() -> Bool {
        var addr = address(kAudioDevicePropertyMute)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let dev = device()
        guard AudioObjectHasProperty(dev, &addr), AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func setMuted(_ m: Bool) {
        var addr = address(kAudioDevicePropertyMute)
        var value = UInt32(m ? 1 : 0)
        let dev = device()
        if AudioObjectHasProperty(dev, &addr) {
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}
