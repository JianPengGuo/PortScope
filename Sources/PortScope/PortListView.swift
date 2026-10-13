import AppKit
import SwiftUI

struct PortListView: View {
    @ObservedObject var store: PortStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.filteredPorts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(store.ports.isEmpty ? "No listening ports" : "No matches")
                        .font(.headline)
                    Text(store.ports.isEmpty
                        ? "TCP listeners will appear here."
                        : "Try another process name or port number.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.filteredPorts) { port in
                            PortRow(port: port) {
                                store.pendingTermination = port
                            }
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }

            Divider()
            footer
        }
        .frame(width: 390, height: 470)
        .confirmationDialog(
            "Stop \(store.pendingTermination?.processName ?? "process")?",
            isPresented: Binding(
                get: { store.pendingTermination != nil },
                set: { if !$0 { store.pendingTermination = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let port = store.pendingTermination {
                Button("Stop listener on port \(port.port)", role: .destructive) {
                    store.terminate(port)
                }
            }
            Button("Cancel", role: .cancel) { store.pendingTermination = nil }
        } message: {
            if let port = store.pendingTermination {
                Text("Sends a normal termination signal to PID \(port.processID).")
            }
        }
        .alert("Couldn’t stop process", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PortScope")
                        .font(.headline)
                    Text("\(store.ports.count) TCP listeners")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isRefreshing ? 180 : 0))
                }
                .buttonStyle(.borderless)
                .help("Refresh ports")
            }

            TextField("Search process, port, or PID", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield")
            Text("Stops processes with confirmation · no admin access")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct PortRow: View {
    let port: ListeningPort
    let onTerminate: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(port.processName)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .lineLimit(1)
                    Text(":\(port.port)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                Text("PID \(port.processID)  ·  \(port.endpoint)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button(action: onTerminate) {
                Image(systemName: "stop.circle")
                    .font(.title3)
                    .foregroundStyle(port.isOwnedByCurrentUser ? .red : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!port.isOwnedByCurrentUser)
            .help(port.isOwnedByCurrentUser ? "Stop process" : "Owned by another user")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contextMenu {
            Button("Copy endpoint") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(port.endpoint, forType: .string)
            }
            Button("Copy localhost URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("http://localhost:\(port.port)", forType: .string)
            }
            if port.isOwnedByCurrentUser {
                Button("Stop process…", role: .destructive, action: onTerminate)
            }
        }
    }
}
