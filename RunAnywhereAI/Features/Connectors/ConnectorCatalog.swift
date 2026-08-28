//
//  ConnectorCatalog.swift
//  RunAnywhereAI
//
//  The kinds of thing a workflow can be pointed at, and the fields each one
//  needs to be pointed at it.
//
//  Every connector is one metadata record plus a field list, and the editor
//  renders whatever the list says. Adding a connector type is adding a record
//  here; no screen changes.
//

import Foundation

/// One input on a connector's form.
///
/// A tagged union rather than a string-keyed dictionary, so the editor cannot
/// be handed a field it has no control for, and a secret cannot be mistaken for
/// ordinary text on the way to storage.
enum ConnectorField: Identifiable, Hashable {
    case text(key: String, label: String, placeholder: String, isRequired: Bool)
    case secret(key: String, label: String, hint: String)
    case number(key: String, label: String, default: Int)
    case toggle(key: String, label: String, default: Bool)
    case choice(key: String, label: String, options: [String], default: String)

    var id: String { key }

    var key: String {
        switch self {
        case .text(let key, _, _, _),
             .secret(let key, _, _),
             .number(let key, _, _),
             .toggle(let key, _, _),
             .choice(let key, _, _, _):
            key
        }
    }

    var label: String {
        switch self {
        case .text(_, let label, _, _),
             .secret(_, let label, _),
             .number(_, let label, _),
             .toggle(_, let label, _),
             .choice(_, let label, _, _):
            label
        }
    }

    /// True for the one field kind that must never be written anywhere the
    /// ordinary values go.
    var isSecret: Bool {
        if case .secret = self { return true }
        return false
    }

    var isRequired: Bool {
        switch self {
        case .text(_, _, _, let required): required
        case .secret: false
        default: false
        }
    }

    var defaultValue: String? {
        switch self {
        case .number(_, _, let value): String(value)
        case .toggle(_, _, let value): value ? "true" : "false"
        case .choice(_, _, _, let value): value
        default: nil
        }
    }
}

/// What a connector type is and what it needs.
struct ConnectorType: Identifiable, Hashable {
    let id: String
    let displayName: String
    let summary: String
    let symbol: String
    let fields: [ConnectorField]

    var secretFields: [ConnectorField] { fields.filter(\.isSecret) }
}

enum ConnectorCatalog {
    static let all: [ConnectorType] = [restAPI, openAICompatible, webhook, localServer]

    static func type(id: String) -> ConnectorType? {
        all.first { $0.id == id }
    }

    /// Anything that answers HTTP and wants a token. The general case, and the
    /// one every other entry here is a narrowing of.
    static let restAPI = ConnectorType(
        id: "rest",
        displayName: "REST API",
        summary: "A base URL and a token, reused by every request that points at it.",
        symbol: "network",
        fields: [
            .text(key: "baseURL", label: "Base URL", placeholder: "https://api.example.com", isRequired: true),
            .choice(
                key: "auth",
                label: "Authentication",
                options: ["None", "Bearer token", "Header", "Query parameter"],
                default: "Bearer token"
            ),
            .text(key: "authName", label: "Header or parameter name", placeholder: "X-API-Key", isRequired: false),
            .secret(key: "token", label: "Token", hint: "Kept out of the workflow you build, held on this device."),
            .number(key: "timeoutMs", label: "Timeout (ms)", default: 30000)
        ]
    )

    static let openAICompatible = ConnectorType(
        id: "openai",
        displayName: "OpenAI-compatible API",
        summary: "Anything serving the chat-completions shape, including our own Cloud console.",
        symbol: "cpu",
        fields: [
            .text(key: "baseURL", label: "Base URL", placeholder: "https://api.example.com/v1", isRequired: true),
            .secret(key: "token", label: "API key", hint: "Sent as a bearer token."),
            .text(key: "model", label: "Model", placeholder: "qwen3", isRequired: false),
            .number(key: "timeoutMs", label: "Timeout (ms)", default: 60000)
        ]
    )

    static let webhook = ConnectorType(
        id: "webhook",
        displayName: "Webhook",
        summary: "One URL to post results to when a workflow finishes.",
        symbol: "arrow.up.forward.square",
        fields: [
            .text(key: "baseURL", label: "URL", placeholder: "https://hooks.example.com/abc", isRequired: true),
            .choice(key: "method", label: "Method", options: ["POST", "PUT", "PATCH"], default: "POST"),
            .secret(key: "token", label: "Signing secret", hint: "Sent as a bearer token when set."),
            .number(key: "timeoutMs", label: "Timeout (ms)", default: 15000)
        ]
    )

    /// The one that needs no credential, so it is the one to try first — and
    /// the one a script on this machine can answer.
    static let localServer = ConnectorType(
        id: "local",
        displayName: "Local server",
        summary: "Something already running on this machine, on a port you choose.",
        symbol: "desktopcomputer",
        fields: [
            .text(key: "host", label: "Host", placeholder: "127.0.0.1", isRequired: true),
            .number(key: "port", label: "Port", default: 8000),
            .text(key: "path", label: "Path", placeholder: "/health", isRequired: false),
            .toggle(key: "https", label: "Use HTTPS", default: false),
            .number(key: "timeoutMs", label: "Timeout (ms)", default: 5000)
        ]
    )
}
