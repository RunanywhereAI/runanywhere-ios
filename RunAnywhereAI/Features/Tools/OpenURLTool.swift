//
//  OpenURLTool.swift
//  RunAnywhereAI
//
//  open_url — hands a web address to the system default browser. The scheme
//  is restricted to http/https so a model cannot reach arbitrary URL handlers
//  (file:, tel:, another app's custom scheme).
//

import Foundation
import RunAnywhere
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum OpenURLTool {
    static var definition: ToolDefinition {
        ToolDefinition(
            name: "open_url",
            description: """
                Opens a web page in the user's default browser. Use only when the user \
                explicitly asks to open, visit, or go to a site — never open a URL as a \
                side effect of answering a question. Pass a complete http:// or https:// \
                address; any other scheme is rejected. This does not fetch or read the \
                page, so do not claim to know what it says. Only say the page was opened \
                if the result has opened = true.
                """,
            parameters: [
                ToolParameter(
                    name: "url",
                    type: .string,
                    description: "Full web address to open, e.g. \"https://www.example.com/page\"."
                )
            ],
            category: "System"
        )
    }

    static var executor: ToolExecutor {
        { args in
            guard let raw = args["url"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else {
                return ["error": RAToolValue("Missing required \"url\" argument")]
            }
            guard let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = url.host, !host.isEmpty else {
                return [
                    "error": RAToolValue(
                        "Invalid URL \"\(raw)\" — only complete http:// or https:// web addresses can be opened"
                    ),
                    "opened": RAToolValue(false)
                ]
            }

            #if os(macOS)
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            #else
            let opened = await UIApplication.shared.open(url)
            #endif

            guard opened else {
                return [
                    "error": RAToolValue("The system could not open \(url.absoluteString)"),
                    "opened": RAToolValue(false)
                ]
            }
            return [
                "opened": RAToolValue(true),
                "url": RAToolValue(url.absoluteString)
            ]
        }
    }
}
