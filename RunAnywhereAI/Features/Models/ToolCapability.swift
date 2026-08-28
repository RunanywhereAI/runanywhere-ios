import Foundation

/// Whether a model can be asked to call tools.
///
/// The verified set below was read from each model's own chat template on
/// Hugging Face (`chat_template.jinja`, else `tokenizer_config.json`): a
/// template that never mentions `tools` cannot render a tool schema, so the
/// model is never told the tools exist and the run loop fails.
///
/// Anything outside that set falls back to a size heuristic, because a very
/// small model rarely holds a tool grammar even when its template allows one.
enum ToolCapability {
    /// Confirmed by chat template, 23 models.
    static let verified: Set<String> = [
        "gemma-4-12b-it-q4_k_m",
        "gemma-4-26b-a4b-it-q4_k_xl",
        "gemma-4-31b-it-q4_k_m",
        "gemma-4-e2b-it-q4_k_m",
        "gemma-4-e4b-it-text-q4_k_m",
        "granite-4.1-30b-q4_k_m",
        "granite-4.1-3b-q4_k_m",
        "granite-4.1-8b-q4_k_m",
        "lfm2.5-1.2b-instruct-q4_k_m",
        "lfm2.5-1.2b-thinking-q4_k_m",
        "lfm2.5-2.6b-ane",
        "lfm2.5-2.6b-mlx-4bit",
        "lfm2.5-2.6b-q4-k-m",
        "lfm2.5-230m-ane",
        "lfm2.5-230m-q4_k_m",
        "lfm2.5-350m-ane",
        "maple-preview-tq1_0",
        "qwen3.5-0.8b-q4_k_m",
        "qwen3.5-2b-q4_k_m",
        "qwen3.5-4b-q4_k_m",
        "qwen3.5-9b-q4_k_m",
        "qwen3.6-35b-a3b-q4_k_m",
        "qwen3.8-27b-q4_k_m"
    ]

    /// Families whose templates carry tool support across every size we ship.
    private static let families = ["qwen", "gemma", "granite", "lfm2", "maple", "ministral", "mistral"]

    /// Below this a model is treated as too small to drive a tool loop, unless
    /// its template was verified above.
    static let minimumDownloadBytes: Int64 = 700_000_000

    static func supports(id: String, name: String, downloadBytes: Int64) -> Bool {
        if verified.contains(id) { return true }
        let haystack = "\(id) \(name)".lowercased()
        if families.contains(where: haystack.contains) { return true }
        return downloadBytes >= minimumDownloadBytes
    }
}


/// Vision models known to crash the process rather than fail.
///
/// `mlx-lfm2.5-vl-3b-4bit` used to trap inside MLX-VLM with
/// "Image features and image tokens do not match", because LFM2VLProcessor
/// hardcoded image token 396 while the model ships `<image>` at 124907, so the
/// placeholder was never expanded. Fixed in the mlx-swift-lm fork by resolving
/// the id from the tokenizer; the list is kept for the next one.
enum VisionCompatibility {
    static func blockReason(for id: String, name: String) -> String? {
        nil
    }
}
