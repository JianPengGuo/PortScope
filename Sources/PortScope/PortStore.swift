import AppKit
import Darwin
import Foundation

struct ListeningPort: Identifiable, Hashable, Sendable {
    let processID: Int32
    let processName: String
    let userID: uid_t
    let endpoint: String
    let port: Int
    var memoryBytes: UInt64? = nil
    var cpuPercent: Double? = nil

    var id: String { "\(processID):\(endpoint)" }
    var isOwnedByCurrentUser: Bool { userID == getuid() }
}

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var ports: [ListeningPort] = []
    @Published var searchText = ""
    @Published var pendingTermination: ListeningPort?
    @Published var errorMessage: String?
    @Published private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
    private var previousUsage: [Int32: TimedProcessUsage] = [:]

    init() {
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var filteredPorts: [ListeningPort] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ports }
        return ports.filter {
            $0.processName.localizedCaseInsensitiveContains(query)
                || $0.endpoint.localizedCaseInsensitiveContains(query)
                || String($0.port).contains(query)
                || String($0.processID).contains(query)
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let latest = await Task.detached(priority: .utility) {
            PortScanner.scan()
        }.value

        let processIDs = Set(latest.map(\.processID))
        let readings = await Task.detached(priority: .utility) {
            ProcessUsageScanner.read(processIDs)
        }.value
        let sampledAt = ProcessInfo.processInfo.systemUptime

        ports = latest.map { port in
            guard let reading = readings[port.processID] else { return port }
            let cpuPercent = previousUsage[port.processID].flatMap { previous -> Double? in
                guard sampledAt > previous.sampledAt,
                      reading.cpuTimeNanoseconds >= previous.cpuTimeNanoseconds else { return nil }
                let elapsed = sampledAt - previous.sampledAt
                let cpuSeconds = Double(reading.cpuTimeNanoseconds - previous.cpuTimeNanoseconds) / 1_000_000_000
                return cpuSeconds / elapsed * 100
            }
            var measuredPort = port
            measuredPort.memoryBytes = reading.memoryBytes
            measuredPort.cpuPercent = cpuPercent
            return measuredPort
        }.sorted {
            let leftMemory = $0.memoryBytes ?? 0
            let rightMemory = $1.memoryBytes ?? 0
            if leftMemory != rightMemory { return leftMemory > rightMemory }

            let leftCPU = $0.cpuPercent ?? 0
            let rightCPU = $1.cpuPercent ?? 0
            if leftCPU != rightCPU { return leftCPU > rightCPU }

            if $0.processName != $1.processName {
                return $0.processName.localizedStandardCompare($1.processName) == .orderedAscending
            }
            return $0.port < $1.port
        }
        previousUsage = readings.mapValues { TimedProcessUsage($0, sampledAt: sampledAt) }
        isRefreshing = false
    }

    func terminate(_ port: ListeningPort) {
        guard port.isOwnedByCurrentUser else {
            errorMessage = "PortScope only signals processes owned by your account."
            return
        }

        // Re-check the PID/endpoint immediately before signaling to reduce the chance
        // of acting on a process that exited and whose PID was subsequently reused.
        let stillListening = PortScanner.scan().contains {
            $0.processID == port.processID && $0.endpoint == port.endpoint
        }
        guard stillListening else {
            errorMessage = "That listener has already exited. The list will refresh shortly."
            return
        }

        guard kill(port.processID, SIGTERM) == 0 else {
            errorMessage = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM).localizedDescription
            return
        }
        pendingTermination = nil
        Task { await refresh() }
    }
}

private struct ProcessUsageReading: Sendable {
    let cpuTimeNanoseconds: UInt64
    let memoryBytes: UInt64
}

private struct TimedProcessUsage: Sendable {
    let cpuTimeNanoseconds: UInt64
    let sampledAt: TimeInterval

    init(_ reading: ProcessUsageReading, sampledAt: TimeInterval) {
        cpuTimeNanoseconds = reading.cpuTimeNanoseconds
        self.sampledAt = sampledAt
    }
}

private enum ProcessUsageScanner {
    static func read(_ processIDs: Set<Int32>) -> [Int32: ProcessUsageReading] {
        Dictionary(uniqueKeysWithValues: processIDs.compactMap { processID in
            var usage = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                proc_pid_rusage(
                    processID,
                    RUSAGE_INFO_V4,
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self)
                )
            }
            guard result == 0 else { return nil }
            return (processID, ProcessUsageReading(
                cpuTimeNanoseconds: usage.ri_user_time &+ usage.ri_system_time,
                memoryBytes: usage.ri_phys_footprint
            ))
        })
    }
}

private enum PortScanner {
    static func scan() -> [ListeningPort] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-Fpcun", "-iTCP", "-sTCP:LISTEN"]
        process.standardError = FileHandle.nullDevice

        let output = Pipe()
        process.standardOutput = output

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return parse(text)
        } catch {
            return []
        }
    }

    private static func parse(_ output: String) -> [ListeningPort] {
        var processID: Int32?
        var processName = "Unknown"
        var userID: uid_t = 0
        var results: [ListeningPort] = []
        var seen = Set<String>()

        for line in output.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                processID = Int32(value)
            case "c":
                processName = value
            case "u":
                userID = uid_t(value) ?? 0
            case "n":
                guard let pid = processID,
                      let number = value.split(separator: ":").last,
                      let port = Int(number), (1...65535).contains(port) else { continue }
                let key = "\(pid):\(value)"
                guard seen.insert(key).inserted else { continue }
                results.append(ListeningPort(
                    processID: pid,
                    processName: processName,
                    userID: userID,
                    endpoint: value,
                    port: port
                ))
            default:
                continue
            }
        }
        return results
    }
}
