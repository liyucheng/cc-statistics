import Foundation
import Network

// MARK: - NotificationServer

/// Lightweight HTTP server on localhost:19852 that accepts notification requests
/// from the Python CLI (notifier.py). Uses Apple's Network framework — no third-party deps.
///
/// Endpoint:
///   POST /notify  { "title": "...", "body": "..." }
///   → 200 OK  on success
///   → 400     on malformed request
final class NotificationServer {

    static let port: UInt16 = 19852

    private var listener: NWListener?

    func start() {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true  // only localhost
        params.requiredInterfaceType = .loopback

        guard let nwPort = NWEndpoint.Port(rawValue: Self.port) else { return }

        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            print("[NotificationServer] failed to create listener: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[NotificationServer] listening on localhost:\(Self.port)")
            case .failed(let error):
                print("[NotificationServer] listener failed: \(error)")
            default:
                break
            }
        }

        listener?.start(queue: .global(qos: .utility))
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        // Read up to 8 KB (more than enough for a notification payload)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
            defer { connection.cancel() }

            guard let data = data, error == nil else {
                Self.sendResponse(connection, status: 400, body: "bad request")
                return
            }

            self.handleRequest(data: data, connection: connection)
        }
    }

    private func handleRequest(data: Data, connection: NWConnection) {
        guard let raw = String(data: data, encoding: .utf8) else {
            Self.sendResponse(connection, status: 400, body: "invalid encoding")
            return
        }

        // Minimal HTTP parsing: find the blank line separating headers from body
        let parts = raw.components(separatedBy: "\r\n\r\n")
        guard parts.count >= 2 else {
            Self.sendResponse(connection, status: 400, body: "malformed http")
            return
        }

        let headerSection = parts[0]
        let bodyString = parts.dropFirst().joined(separator: "\r\n\r\n")

        // Verify it's POST /notify
        let firstLine = headerSection.components(separatedBy: "\r\n").first ?? ""
        guard firstLine.hasPrefix("POST /notify") else {
            Self.sendResponse(connection, status: 404, body: "not found")
            return
        }

        // Parse JSON body
        guard let jsonData = bodyString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let title = json["title"] as? String,
              let body = json["body"] as? String else {
            Self.sendResponse(connection, status: 400, body: "invalid json")
            return
        }

        // Dispatch notification on main actor
        Task { @MainActor in
            NotificationManager.shared.send(title: title, body: body)
        }

        Self.sendResponse(connection, status: 200, body: "ok")
    }

    // MARK: - HTTP Response

    private static func sendResponse(_ connection: NWConnection, status: Int, body: String) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        default:  reason = "Error"
        }

        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
