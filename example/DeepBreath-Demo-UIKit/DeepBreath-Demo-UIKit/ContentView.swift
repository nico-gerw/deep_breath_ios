//
//  ContentView.swift
//  DeepBreath-Demo-UIKit
//
//  Created by Nico Gerwien on 02.07.25.
//

import CoreBluetooth
import SwiftUI
import deep_breath_ios

enum BluetootError: Error {
    case noPermission
}

class DeepBreathAdapter: ObservableObject, DeepBreathDelegate {
    @Published var scannedDevices: [CBPeripheral] = []
    @Published var connectedDevice: CBPeripheral?
    @Published var batteryPercent: Double?
    @Published var trainingDataItems: [deep_breath_ios.TrainingDataItem] = []

    func didUpdate(scannedDevices: [CBPeripheral]) {
        DispatchQueue.main.async {
            self.scannedDevices = scannedDevices
        }
    }

    func didUpdate(batteryPercent: Double?) {
        DispatchQueue.main.async {
            self.batteryPercent = batteryPercent
        }
    }

    func didReadData(item: deep_breath_ios.TrainingDataItem) {
        DispatchQueue.main.async {
            self.trainingDataItems.append(item)
        }
    }

    func didConnect(device: CBPeripheral?) {
        connectedDevice = device
    }
}

struct ContentView: View {
    @StateObject var adapter = DeepBreathAdapter()

    var body: some View {
        VStack {
            if !adapter.trainingDataItems.isEmpty {
                Text(
                    "Pressure: \(adapter.trainingDataItems.last!.pressure)\nGyroX: \(adapter.trainingDataItems.last!.gyroX)\nGyroY: \(adapter.trainingDataItems.last!.gyroY)\nGyroZ: \(adapter.trainingDataItems.last!.gyroZ)\nElapsed Seconds: \(String(format: "%.1f", adapter.trainingDataItems.last!.elapsedSeconds))"
                )
                .padding()
                Button("Stop read") {
                    DeepBreath.shared.stopReadData()
                    adapter.trainingDataItems.removeAll()
                }.padding()
                if let batteryPercent = adapter.batteryPercent {
                    Text("Battery: \(Int(batteryPercent))%").padding()
                }
            } else if let connectedDevice = adapter.connectedDevice {
                Text(
                    "Device connected:\n\(connectedDevice.name ?? "Unknown Device")\n\(connectedDevice.identifier.uuidString)"
                )
                .padding()
                .onAppear {
                    DeepBreath.shared.delegate = adapter
                    DeepBreath.shared.scanForDevices()
                }
                Button("Read data") {
                    DeepBreath.shared.readData()
                }.padding()
                Button("Disconnect Device") {
                    DeepBreath.shared.disconnect()
                }.padding()
                if let batteryPercent = adapter.batteryPercent {
                    Text("Battery: \(Int(batteryPercent))%").padding()
                }
            } else if adapter.scannedDevices.isEmpty {
                Text("Scanning for bluetooth devices")
                    .padding()
                    .onAppear {
                        DeepBreath.shared.delegate = adapter
                        DeepBreath.shared.scanForDevices()
                    }
            } else {
                List(adapter.scannedDevices, id: \.self) { device in
                    Text(
                        "\(device.name ?? "Unkown Device")\n\(device.identifier)"
                    ).onTapGesture {
                        DeepBreath.shared.connect(device: device)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
