// BLEProbe — throwaway hardware probe, not part of the LedFan app target.
// Scans for BLE peripherals and, with --connect, dumps a peripheral's GATT map.

import CoreBluetooth
import Foundation

// MARK: - Options

struct Options {
    var connectMatch: String?
    var seconds: Double = 12

    static func parse(_ argv: [String]) -> Options {
        var options = Options()
        var index = 1
        while index < argv.count {
            switch argv[index] {
            case "--connect":
                options.connectMatch = index + 1 < argv.count ? argv[index + 1] : nil
                index += 2
            case "--seconds":
                options.seconds = Double(index + 1 < argv.count ? argv[index + 1] : "") ?? 12
                index += 2
            default:
                index += 1
            }
        }
        return options
    }
}

// MARK: - Sighting

struct Sighting {
    var name: String
    var rssi: Int
    var services: [String]
    var manufacturerData: String
    var connectable: Bool
}

// MARK: - Probe

final class Probe: NSObject {
    private let options: Options
    private var central: CBCentralManager?
    private var sightings: [UUID: Sighting] = [:]
    private var target: CBPeripheral?
    private var pendingCharacteristics = 0

    init(options: Options) {
        self.options = options
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    private func finishScan() {
        central?.stopScan()
        print("\n--- \(sightings.count) peripheral(s) seen ---\n")
        for sighting in sightings.values.sorted(by: { $0.rssi > $1.rssi }) {
            print(String(format: "%-28@  %4d dBm  %@", sighting.name as NSString, sighting.rssi,
                         sighting.connectable ? "connectable" : "broadcast-only"))
            if !sighting.services.isEmpty { print("    services: \(sighting.services.joined(separator: ", "))") }
            if !sighting.manufacturerData.isEmpty { print("    mfg data: \(sighting.manufacturerData)") }
        }
        print("\nRe-run with --connect \"<name fragment>\" to dump a device's GATT map.")
        exit(0)
    }

    private func dump(_ peripheral: CBPeripheral) {
        print("\n=== GATT map: \(peripheral.name ?? "unnamed") ===")
        for service in peripheral.services ?? [] {
            print("\nservice \(service.uuid)")
            for characteristic in service.characteristics ?? [] {
                print("  char \(characteristic.uuid)  [\(describe(characteristic.properties))]")
            }
        }
        print("\nWritable characteristics are the candidates for pushing a message.")
        exit(0)
    }

    private func describe(_ properties: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if properties.contains(.read) { names.append("read") }
        if properties.contains(.write) { names.append("write") }
        if properties.contains(.writeWithoutResponse) { names.append("writeNoResp") }
        if properties.contains(.notify) { names.append("notify") }
        if properties.contains(.indicate) { names.append("indicate") }
        return names.joined(separator: "|")
    }
}

// MARK: - CBCentralManagerDelegate

extension Probe: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Scanning for \(Int(options.seconds))s… (allow Bluetooth if macOS prompts)")
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            if options.connectMatch == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + options.seconds) { [weak self] in self?.finishScan() }
            }
        case .unauthorized:
            print("Bluetooth permission denied. System Settings ▸ Privacy & Security ▸ Bluetooth ▸ enable Terminal.")
            exit(1)
        case .poweredOff:
            print("Bluetooth is off.")
            exit(1)
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "(unnamed \(peripheral.identifier.uuidString.prefix(8)))"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let manufacturerData = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?
            .map { String(format: "%02x", $0) }.joined() ?? ""
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false

        sightings[peripheral.identifier] = Sighting(name: name, rssi: RSSI.intValue, services: services,
                                                    manufacturerData: manufacturerData, connectable: connectable)
        print("  \(name)  \(RSSI.intValue) dBm")

        guard let match = options.connectMatch, target == nil,
              name.localizedCaseInsensitiveContains(match) else { return }
        target = peripheral
        peripheral.delegate = self
        central.stopScan()
        print("\nConnecting to \(name)…")
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected. Discovering services…")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Connect failed: \(error?.localizedDescription ?? "unknown")")
        exit(1)
    }
}

// MARK: - CBPeripheralDelegate

extension Probe: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        pendingCharacteristics = services.count
        guard pendingCharacteristics > 0 else { dump(peripheral); return }
        for service in services { peripheral.discoverCharacteristics(nil, for: service) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        pendingCharacteristics -= 1
        if pendingCharacteristics == 0 { dump(peripheral) }
    }
}

// MARK: - Entry point

let probe = Probe(options: Options.parse(CommandLine.arguments))
RunLoop.main.run()
