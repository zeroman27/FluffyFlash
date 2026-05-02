//
//  FluffySpeedSparklineView.swift
//  Fluffy Flash
//
//  Tiny "live speed" chart drawn with `Charts`. Maintains a 60-sample ring
//  buffer of aggregated throughput so the user gets a feel for write stability.
//

import Charts
import Combine
import SwiftUI

struct FluffySpeedSparklineView: View {
    @ObservedObject var usbWriter: USBWriterViewModel

    @State private var samples: [Sample] = []
    @State private var nextIndex: Int = 0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let maxSamples = 60

    struct Sample: Identifiable, Equatable {
        let id: Int
        let mbps: Double
    }

    var body: some View {
        Chart(samples) { sample in
            LineMark(
                x: .value("t", sample.id),
                y: .value("MB/s", sample.mbps)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(FluffyColor.purpleGlow)
            .lineStyle(StrokeStyle(lineWidth: 1.6))
            AreaMark(
                x: .value("t", sample.id),
                y: .value("MB/s", sample.mbps)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
                LinearGradient(
                    colors: [FluffyColor.purpleGlow.opacity(0.32), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0 ... max(1, (samples.map(\.mbps).max() ?? 1) * 1.2))
        .frame(height: 56)
        .onReceive(timer) { _ in
            tick()
        }
    }

    private func tick() {
        let mbps = aggregatedMBps()
        let sample = Sample(id: nextIndex, mbps: mbps)
        nextIndex += 1
        samples.append(sample)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
    }

    /// Sum of throughput across all active per-drive progress entries (MB/s).
    private func aggregatedMBps() -> Double {
        let total = usbWriter.perDriveProgress.values
            .map(\.stepBytesPerSecond)
            .reduce(0, +)
        return total / (1024 * 1024)
    }
}
