//
//  ConnectorStore.swift
//  RunAnywhereAI
//
//  The saved connectors, and the one request that says whether one works.
//

import Foundation
import Observation
import os

@Observable
@MainActor
final class ConnectorStore {
    private(set) var connectors: [Connector] = []
    /// The last probe per connector id, so a row can show its own result
    /// without the list re-testing everything.
    private(set) var probes: [String: ConnectorProbe] = [:]
    private(set) var probing: Set<String> = []

    private let defaultsKey = "connectors.saved"
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Connectors")

    init() {
        load()
    }

    func save(_ connector: Connector, secret: String?) {
        if let index = connectors.firstIndex(where: { $0.id == connector.id }) {
            connectors[index] = connector
        } else {
            connectors.append(connector)
        }
        connectors.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if let secret {
            ConnectorSecrets.write(secret, for: connector.id)
        }
        persist()
    }

    func delete(_ id: String) {
        connectors.removeAll { $0.id == id }
        probes[id] = nil
        ConnectorSecrets.remove(id)
        persist()
    }

    func secret(for id: String) -> String {
        ConnectorSecrets.read(id)
    }

    // MARK: - Reaching it

    /// One request against the connector, reported in the terms the reader
    /// cares about: it answered, it refused us, or it was not there.
    ///
    /// A 401 or 403 is deliberately not "reachable". The endpoint existing and
    /// the credential working are different questions, and a connector that
    /// says "connected" while the token is wrong is worse than one that says
    /// nothing.
    func probe(_ connector: Connector) async {
        guard !probing.contains(connector.id) else { return }
        probing.insert(connector.id)
        defer { probing.remove(connector.id) }

        if let missing = connector.incompleteField {
            probes[connector.id] = .failed("\(missing) is still empty.")
            return
        }
        guard let url = connector.url else {
            probes[connector.id] = .failed("That is not a URL this can reach.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = connector.testMethod
        request.timeoutInterval = connector.timeout
        for (name, value) in connector.headers(secret: secret(for: connector.id)) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if request.httpMethod != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"probe":true}"#.utf8)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                probes[connector.id] = .failed("The reply was not HTTP.")
                return
            }
            let detail = Self.describe(data)
            switch http.statusCode {
            case 200...299:
                probes[connector.id] = .reachable(status: http.statusCode, detail: detail)
            case 401, 403:
                probes[connector.id] = .refused(
                    status: http.statusCode,
                    detail: "It answered, but rejected the credential."
                )
            default:
                probes[connector.id] = .refused(status: http.statusCode, detail: detail)
            }
        } catch {
            logger.error("connector probe failed: \(error, privacy: .public)")
            probes[connector.id] = .failed(Self.describe(error))
        }
    }

    // MARK: - Storage

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        do {
            connectors = try JSONDecoder().decode([Connector].self, from: data)
        } catch {
            logger.error("could not read saved connectors: \(error, privacy: .public)")
        }
    }

    private func persist() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(connectors), forKey: defaultsKey)
        } catch {
            logger.error("could not save connectors: \(error, privacy: .public)")
        }
    }

    /// The first line of a body, short enough for a row.
    private static func describe(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "\(data.count) bytes"
        }
        let line = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { return "Empty reply" }
        return line.count > 90 ? String(line.prefix(90)) + "…" : line
    }

    /// URLSession's own wording, minus the parts a reader cannot act on.
    private static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .cannotConnectToHost: return "Nothing is listening there."
        case .cannotFindHost: return "That host does not resolve."
        case .timedOut: return "It did not answer in time."
        case .notConnectedToInternet: return "This device is offline."
        case .appTransportSecurityRequiresSecureConnection:
            return "Plain HTTP to that host is blocked by App Transport Security."
        default: return urlError.localizedDescription
        }
    }
}
