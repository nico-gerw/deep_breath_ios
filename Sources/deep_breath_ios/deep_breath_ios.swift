import CoreBluetooth

public protocol DeepBreathDelegate {
    func didUpdate(scannedDevices: [CBPeripheral])
    func didConnect(device: CBPeripheral?)
    func didUpdate(batteryPercent: Double?)
    func didReadData(item: TrainingDataItem)
}

public class DeepBreath: NSObject, CBCentralManagerDelegate,
    CBPeripheralDelegate
{
    @MainActor public static let shared: DeepBreath = {
        let instance = DeepBreath()
        return instance
    }()

    override private init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    static let serviceIdData = "9FDD0001-FEC8-42A6-B569-EC3EC15505F4"
    static let serviceIdBattery = "D6240001-E814-4993-A135-7845BC91D225"

    public var delegate: DeepBreathDelegate?

    var centralManager: CBCentralManager?

    var deviceList: [CBPeripheral] = []

    var connectedDevice: CBPeripheral?

    var characteristicData: CBCharacteristic?
    var characteristicBattery: CBCharacteristic?

    public private(set) var batteryPercent: Double?

    var dataStartTime: DispatchTime?
    var dataTimer: DispatchSourceTimer?

    public func scanForDevices() {
        deviceList.removeAll()
        isBluetoothAvailable()
    }

    public func stopScan() {
        centralManager?.stopScan()
    }

    public func connect(device: CBPeripheral) {
        stopScan()
        device.delegate = self
        connectedDevice = device
        centralManager?.connect(device)
    }

    public func disconnect() {
        characteristicBattery = nil
        characteristicData = nil
        batteryPercent = nil
        dataTimer?.cancel()
        dataTimer = nil
        dataStartTime = nil
        if let device = connectedDevice {
            centralManager?.cancelPeripheralConnection(device)
            connectedDevice = nil
        }
        delegate?.didConnect(device: nil)
    }

    public func readBattery() {
        if let characteristic = characteristicBattery {
            connectedDevice?.readValue(for: characteristic)
        }
    }

    /// Read data continuously with the given interval
    /// - Parameter interval: Recommended value is 200ms (0.2). Should not be less then 60ms (0.06)
    public func readData(intervalSeconds: Double = 0.2) {
        stopReadData()

        let clampedInterval = max(intervalSeconds, 0.06)

        if let characteristic = characteristicData {
            dataStartTime = DispatchTime.now()
            let queue = DispatchQueue.global()
            dataTimer = DispatchSource.makeTimerSource(queue: queue)
            dataTimer?.schedule(deadline: .now(), repeating: clampedInterval)
            dataTimer?.setEventHandler {
                self.connectedDevice?.readValue(for: characteristic)
            }
            dataTimer?.resume()
        }
    }

    public func stopReadData() {
        dataTimer?.cancel()
        dataTimer = nil
        dataStartTime = nil
    }

    public func isBluetoothAvailable() -> Bool {
        if #available(iOS 13.1, *) {
            return CBCentralManager.authorization == .allowedAlways
        } else if #available(iOS 13.0, *) {
            return CBCentralManager().authorization == .allowedAlways
        } else {
            // Before iOS 13, Bluetooth permissions are not required
            return true
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            centralManager?.scanForPeripherals(
                withServices: nil,
                options: nil
            )
            break
        case .poweredOff, .resetting, .unauthorized, .unsupported, .unknown:
            fallthrough
        @unknown default:
            deviceList.removeAll()
            delegate?.didUpdate(scannedDevices: deviceList)
            break
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        deviceList.append(peripheral)
        delegate?.didUpdate(scannedDevices: deviceList)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices(nil)
        delegate?.didConnect(device: peripheral)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        if let servicePressure = peripheral.services?.first(where: {
            $0.uuid.uuidString == DeepBreath.serviceIdData
        }) {
            peripheral.discoverCharacteristics(nil, for: servicePressure)
        }

        if let serviceBattery = peripheral.services?.first(where: {
            $0.uuid.uuidString == DeepBreath.serviceIdBattery
        }) {
            peripheral.discoverCharacteristics(nil, for: serviceBattery)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {

        if let characteristic = service.characteristics?.first(where: {
            $0.properties.contains(.read)
        }) {
            if service.uuid.uuidString == DeepBreath.serviceIdData {
                characteristicData = characteristic
            }

            if service.uuid.uuidString == DeepBreath.serviceIdBattery {
                characteristicBattery = characteristic
                readBattery()
            }
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("Error reading value: \(error.localizedDescription)")
            return
        }

        guard let value = characteristic.value else {
            print("Error reading value: nil")
            return
        }

        let data = value as Data

        if characteristic == characteristicBattery {
            readBattery(data)
        } else if characteristic == characteristicData {
            readData(data)
        }
    }

    func readBattery(_ data: Data) {
        let batteryMillivolt = data.withUnsafeBytes {
            $0.load(as: Int16.self)
        }
        let batteryVolt = Double(batteryMillivolt) / 1000.0

        // 3.3V = 0%, 4.05V = 100%
        let minBatteryVolt = 3.3
        let maxBatteryVolt = 4.05
        batteryPercent = min(
            max(
                ((100.0 / (maxBatteryVolt - minBatteryVolt))
                    * (batteryVolt - minBatteryVolt)),
                0
            ),
            100
        )
        delegate?.didUpdate(batteryPercent: batteryPercent)
    }

    func readData(_ data: Data) {
        guard let start = dataStartTime else { return }

        let elapsed =
            DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedSeconds = Double(elapsed) / 1_000_000_000

        if let item = TrainingDataItem(
            data: data,
            elapsedSeconds: elapsedSeconds
        ) {
            delegate?.didReadData(item: item)
            print(item.pressure)
            print(item.gyroX)
            print(item.gyroY)
            print(item.gyroZ)
            print(item.elapsedSeconds)
        } else {
            print("Unable to parse data")
        }
    }
}

public struct TrainingDataItem {
    public let pressure: Int16
    public let gyroX: Int16
    public let gyroY: Int16
    public let gyroZ: Int16
    public let elapsedSeconds: Double

    init?(data: Data, elapsedSeconds: Double) {
        guard data.count >= 8 else { return nil }

        self.pressure = data.subdata(in: 0..<2).withUnsafeBytes {
            $0.load(as: Int16.self)
        }
        self.gyroX = data.subdata(in: 2..<4).withUnsafeBytes {
            $0.load(as: Int16.self)
        }
        self.gyroY = data.subdata(in: 4..<6).withUnsafeBytes {
            $0.load(as: Int16.self)
        }
        self.gyroZ = data.subdata(in: 6..<8).withUnsafeBytes {
            $0.load(as: Int16.self)
        }
        self.elapsedSeconds = elapsedSeconds
    }
}
