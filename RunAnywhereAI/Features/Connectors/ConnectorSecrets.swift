//
//  ConnectorSecrets.swift
//  RunAnywhereAI
//
//  Where a connector's token lives.
//
//  The keychain, except on a locally built Mac app: an ad-hoc signature changes
//  on every rebuild, so the keychain treats each build as a different program
//  and asks for a password per item per launch. The SDK solves this with
//  RUNANYWHERE_SWIFT_SECURE_STORE=file, which `RunAnywhereAIApp.init` sets for
//  macOS DEBUG. This reads the same switch, so app secrets and SDK secrets are
//  never split across two stores.
//

import Foundation
import Security

enum ConnectorSecrets {
    private static let service = "com.runanywhere.RunAnywhereAI.connectors"

    private static var usesFileStore: Bool {
        guard let raw = getenv("RUNANYWHERE_SWIFT_SECURE_STORE") else { return false }
        let mode = String(cString: raw).lowercased()
        return mode == "file" || mode == "filesystem"
    }

    static func read(_ connectorID: String) -> String {
        if usesFileStore {
            guard let url = fileURL(connectorID),
                  let data = try? Data(contentsOf: url) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(connectorID, wantsData: true) as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    static func write(_ secret: String, for connectorID: String) -> Bool {
        guard !secret.isEmpty else { return remove(connectorID) }
        let data = Data(secret.utf8)

        if usesFileStore {
            guard let url = fileURL(connectorID) else { return false }
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: url, options: [.atomic])
                // 0o600 or it is not standing in for the keychain at all. A
                // failure here removes the file rather than leaving a token
                // readable by every account on the machine.
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: url.path
                )
                return true
            } catch {
                try? FileManager.default.removeItem(at: url)
                return false
            }
        }

        var update = SecItemUpdate(
            query(connectorID, wantsData: false) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecItemNotFound {
            var insert = query(connectorID, wantsData: false)
            insert[kSecValueData as String] = data
            update = SecItemAdd(insert as CFDictionary, nil)
        }
        return update == errSecSuccess
    }

    @discardableResult
    static func remove(_ connectorID: String) -> Bool {
        if usesFileStore {
            guard let url = fileURL(connectorID) else { return false }
            try? FileManager.default.removeItem(at: url)
            return true
        }
        let status = SecItemDelete(query(connectorID, wantsData: false) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func query(_ connectorID: String, wantsData: Bool) -> [String: Any] {
        // swiftlint:disable:previous explicit_type_interface
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: connectorID,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        if wantsData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }

    private static func fileURL(_ connectorID: String) -> URL? {
        guard let root = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        // Hex rather than the id itself: an id is caller text, and caller text
        // is not a filename.
        let name = connectorID.utf8.map { String(format: "%02x", $0) }.joined()
        return root
            .appendingPathComponent("RunAnywhere/ConnectorSecrets", isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
    }
}
