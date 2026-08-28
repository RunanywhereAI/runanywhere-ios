//
//  Connector.swift
//  RunAnywhereAI
//
//  One configured connection, and the URL it resolves to.
//

import Foundation

/// A saved connector: which type it is, what the reader called it, and the
/// values they filled in.
///
/// Secrets are not in here. `values` is written to disk as it stands, so a
/// field the catalog marked secret is held separately and joined back only when
/// a request is about to be made.
struct Connector: Identifiable, Codable, Hashable {
    let id: String
    var typeID: String
    var name: String
    var values: [String: String]

    var type: ConnectorType? { ConnectorCatalog.type(id: typeID) }

    init(id: String = "conn-" + UUID().uuidString.prefix(8).lowercased(), typeID: String, name: String) {
        self.id = id
        self.typeID = typeID
        self.name = name
        var seeded: [String: String] = [:]
        for field in ConnectorCatalog.type(id: typeID)?.fields ?? [] {
            if let value = field.defaultValue { seeded[field.key] = value }
        }
        values = seeded
    }

    func value(_ key: String) -> String { values[key] ?? "" }

    var timeout: TimeInterval {
        let milliseconds = Int(value("timeoutMs")) ?? 30000
        return TimeInterval(max(milliseconds, 1000)) / 1000
    }

    /// Where this connector points, or nil when what it holds is not a URL yet.
    ///
    /// The local-server arm is assembled from parts rather than typed, because
    /// host-and-port is what the reader knows and `http://127.0.0.1:8000/health`
    /// is what they would otherwise have to get exactly right.
    var url: URL? {
        guard let type else { return nil }
        switch type.id {
        case ConnectorCatalog.localServer.id:
            var components = URLComponents()
            components.scheme = value("https") == "true" ? "https" : "http"
            components.host = value("host").isEmpty ? "127.0.0.1" : value("host")
            components.port = Int(value("port"))
            let path = value("path")
            components.path = path.hasPrefix("/") ? path : (path.isEmpty ? "" : "/" + path)
            return components.url
        default:
            return URL(string: value("baseURL"))
        }
    }

    /// The method a test request should use. Everything but a webhook is read
    /// with a GET; posting to someone's API to see whether it answers is not a
    /// test, it is a side effect.
    var testMethod: String {
        type?.id == ConnectorCatalog.webhook.id ? value("method") : "GET"
    }

    /// The headers this connector contributes, given its secret.
    func headers(secret: String) -> [String: String] {
        guard let type, !secret.isEmpty else { return [:] }
        switch type.id {
        case ConnectorCatalog.restAPI.id:
            switch value("auth") {
            case "Bearer token": return ["Authorization": "Bearer \(secret)"]
            case "Header":
                let name = value("authName")
                return name.isEmpty ? [:] : [name: secret]
            default: return [:]
            }
        case ConnectorCatalog.openAICompatible.id, ConnectorCatalog.webhook.id:
            return ["Authorization": "Bearer \(secret)"]
        default:
            return [:]
        }
    }

    /// Set when a required field is still blank, naming the first one.
    var incompleteField: String? {
        guard let type else { return "Unknown connector type" }
        for field in type.fields where field.isRequired && value(field.key).isEmpty {
            return field.label
        }
        return url == nil ? "A valid URL" : nil
    }
}

/// What came back from pointing at a connector.
enum ConnectorProbe: Equatable {
    case reachable(status: Int, detail: String)
    case refused(status: Int, detail: String)
    case failed(String)

    var isGood: Bool {
        if case .reachable = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case let .reachable(status, detail): "\(status) · \(detail)"
        case let .refused(status, detail): "\(status) · \(detail)"
        case let .failed(message): message
        }
    }
}
