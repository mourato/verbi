import Foundation
import MeetingAssistantCoreCommon
import MetricKit
import os.log

/// Monitors application performance and reports metrics
/// Note: MetricKit is available on macOS 12+
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

    // MARK: - MXMetricManagerSubscriber

    #if !os(macOS)
        public func didReceive(_ payloads: [MXMetricPayload]) {
            for payload in payloads {
                // Log aggregated metrics
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
            // Log diagnostics (hangs, crashes)
            if let hangs = payload.hangDiagnostics {
                AppLogger.warning("Hang Diagnostics Received: \(hangs.count) hangs", category: .performance)
            }
        }
    }

    // MARK: - Ad-hoc measurement

    /// Report a specific metric event immediately
    public func reportMetric(name: String, value: Double, unit: String) {
        AppLogger.info("Metric [\(name)]: \(value) \(unit)", category: .performance)
    }
}
