import Foundation
import MetricKit
import os.log
import VerbiCoreCommon

public final class PerformanceMonitor: NSObject, MXMetricManagerSubscriber, Sendable {
    public static let shared = PerformanceMonitor()

    override private init() {
        super.init()
    }

    public func startMonitoring() {
        let metricManager = MXMetricManager.shared
        metricManager.add(self)
        AppLogger.info("Performance Monitoring Started", category: .performance)
    }

    public func stopMonitoring() {
        let metricManager = MXMetricManager.shared
        metricManager.remove(self)
        AppLogger.info("Performance Monitoring Stopped", category: .performance)
    }

    #if !os(macOS)
        public func didReceive(_ payloads: [MXMetricPayload]) {
            for payload in payloads {
                if let memoryMetrics = payload.memoryMetrics {
                    let peakMemory = memoryMetrics.peakMemoryUsage
                    let averageSuspended = memoryMetrics.averageSuspendedMemory
                    AppLogger.info("Memory Metrics: Peak=\(peakMemory) Average=\(averageSuspended)", category: .performance)
                }

                if let cpuMetrics = payload.cpuMetrics {
                    let cpuTime = cpuMetrics.cumulativeCPUTime
                    AppLogger.info("CPU Metrics: Time=\(cpuTime)", category: .performance)
                }
            }
        }
    #endif

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            if let hangs = payload.hangDiagnostics {
                AppLogger.warning("Hang Diagnostics Received: \(hangs.count) hangs", category: .performance)
            }
        }
    }

    public func reportMetric(name: String, value: Double, unit: String) {
        AppLogger.info("Metric [\(name)]: \(value) \(unit)", category: .performance)
    }
}
