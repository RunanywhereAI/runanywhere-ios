#!/usr/bin/env bash
# Static functional smoke preflight for the native iOS sample.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${APP_ROOT}"

echo "==> Checking Swift SDK call coverage"
grep -R -E "RunAnywhere\.(initialize|registerModel|downloadModel|loadModel|generateStream|generate\(|transcribe|speak|processImage|processImageStream|detectVoiceActivity|getStorageInfo|clearCache|cleanTempFiles|cancelGeneration|listModels|initializeVoiceAgent|streamVoiceAgent|ragCreatePipeline|ragIngest|ragQuery)" \
    RunAnywhereAI >/dev/null

grep -R -E "Voice|Pipeline|RAG|rag|cancelGeneration" RunAnywhereAI >/dev/null

echo "==> Checking Parakeet CTC catalog policy"
# This check asserts the POLICY, not a snapshot of the current pin.
#
# It used to hardcode the HF revision and the per-file SHA-256 digests. Those
# are exactly the values that change whenever the model is re-exported, so the
# check went red on a legitimate catalog update (and stayed red, because it is
# not wired into CI). It also asserted a `metadataPayload` byte array that no
# longer exists — the metadata_props patching moved server-side into the
# RunAnywhere re-export, so that assertion could never pass again.
#
# What actually matters, and what is checked below:
#   1. the model is still registered under its canonical id;
#   2. it is sourced from the RunAnywhere re-export, NOT the upstream
#      OpenVoiceOS export, which omits three metadata_props entries Sherpa
#      requires and therefore cannot load;
#   3. the source is pinned to an immutable 40-hex commit, never a mutable
#      branch like `main`;
#   4. both required files are declared, each with a size and a SHA-256, so a
#      silent content swap is caught at download time;
#   5. the registration declares a memory requirement and a download size.
catalog_source="RunAnywhereAI/Core/Services/ModelCatalogBootstrap.swift"
parakeet_repo="huggingface.co/runanywhere/sherpa-onnx-nemo-parakeet-ctc-1.1b-int8"

fail() { echo "smoke: $*" >&2; exit 1; }

grep -F -q -- 'id: "sherpa-nemo-parakeet-ctc-1.1b-int8"' "${catalog_source}" ||
    fail "canonical Parakeet CTC model id is no longer registered"

# Every assertion below is scoped to the parakeetCTCSherpaFiles block. Checking
# against the whole file would let another model's pinned revision satisfy the
# check while Parakeet itself sat unpinned.
parakeet_block="$(sed -n '/private static let parakeetCTCSherpaFiles/,/^[[:space:]]*}()/p' "${catalog_source}")"
[ -n "${parakeet_block}" ] || fail "could not locate parakeetCTCSherpaFiles in ${catalog_source}"

printf '%s' "${parakeet_block}" | grep -F -q -- "${parakeet_repo}" ||
    fail "Parakeet CTC no longer points at the patched RunAnywhere re-export (${parakeet_repo})"

# The base URL must end in /resolve/<40-hex>, never /resolve/main.
printf '%s' "${parakeet_block}" | grep -Eq '"[0-9a-f]{40}"' ||
    fail "Parakeet CTC source is not pinned to an immutable 40-hex revision"

for required_file in "model.int8.onnx" "tokens.txt"; do
    printf '%s' "${parakeet_block}" | grep -F -q -- "filename: \"${required_file}\"" ||
        fail "Parakeet CTC no longer declares ${required_file}"
done

checksum_count="$(printf '%s' "${parakeet_block}" | grep -Ec '"[0-9a-f]{64}"' || true)"
[ "${checksum_count}" -ge 2 ] ||
    fail "expected a SHA-256 for each Parakeet CTC file, found ${checksum_count}"

size_count="$(printf '%s' "${parakeet_block}" | grep -Ec 'sizeBytes: [0-9_]+' || true)"
[ "${size_count}" -ge 2 ] ||
    fail "expected a sizeBytes for each Parakeet CTC file, found ${size_count}"

registration="$(sed -n '/id: "sherpa-nemo-parakeet-ctc-1.1b-int8"/,/^[[:space:]]*)$/p' "${catalog_source}")"
printf '%s' "${registration}" | grep -Eq 'memoryRequirement: [0-9_]+' ||
    fail "Parakeet CTC registration is missing memoryRequirement"
printf '%s' "${registration}" | grep -Eq 'downloadSize: [0-9_]+' ||
    fail "Parakeet CTC registration is missing downloadSize"

if [ "${RUN_BUILD_GATES:-0}" = "1" ]; then
    echo "==> Running full iOS verify gates"
    "${SCRIPT_DIR}/verify.sh"
fi

echo "iOS smoke preflight complete"
