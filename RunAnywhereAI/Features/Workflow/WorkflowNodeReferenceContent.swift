//
//  WorkflowNodeReferenceContent.swift
//  RunAnywhereAI
//
//  One entry per node kind. The dispatch is exhaustive on purpose: a new arm in
//  agent_workflow.proto does not compile until somebody has written down what
//  the node does.
//

import Foundation

extension WorkflowNodeReference {
    static func reference(for kind: WorkflowNodeKind) -> WorkflowNodeReference {
        switch kind {
        case .manualTrigger: manualTrigger
        case .scheduleTrigger: scheduleTrigger
        case .llmGenerate: llmGenerate
        case .llmStructured: llmStructured
        case .vision: vision
        case .embed: embed
        case .rerank: rerank
        case .transcribe: transcribe
        case .speak: speak
        case .detectVoice: detectVoice
        case .diarize: diarize
        case .segment: segment
        case .ragQuery: ragQuery
        case .ragIngest: ragIngest
        case .loadModel: loadModel
        case .condition: condition
        case .filter: filter
        case .loopOverItems: loopOverItems
        case .code: code
        case .setTransform: setTransform
        case .merge: merge
        case .splitOut: splitOut
        case .aggregate: aggregate
        case .wait: wait
        case .toolCall: toolCall
        case .httpRequest: httpRequest
        case .fileRead: fileRead
        case .fileWrite: fileWrite
        case .packNode: packNode
        }
    }
}

// MARK: - Trigger

private extension WorkflowNodeReference {
    static let manualTrigger = WorkflowNodeReference(
        kind: .manualTrigger,
        summary: """
        Starts a run when you press Run, and hands the first node the seed items \
        you typed. A workflow needs exactly one trigger, and this is the one for \
        runs you start yourself.
        """,
        inputPorts: [],
        settings: [
            .init(
                label: "Initial Items",
                detail: """
                A JSON array. Each element becomes one item. A JSON value that is \
                not an array becomes a single item. Left empty, the node emits one \
                item whose body is an empty object, so a workflow that takes no \
                input still runs once.
                """
            )
        ],
        emits: "The seed items, exactly as written.",
        outputPorts: [outPort],
        example: .init(
            caption: "Two items, read downstream as {{ Manual Trigger.city }}.",
            snippet: """
            [{ "city": "Lisbon" }, { "city": "Porto" }]
            """
        ),
        notes: [
            """
            Text that is not valid JSON fails the node before anything else runs.
            """,
            """
            The SDK's run call can pass items that replace these, but the editor's \
            Run button does not, so what you type here is what the run sees.
            """,
            """
            A trigger has no input socket. Nothing can connect into it.
            """
        ]
    )

    static let scheduleTrigger = WorkflowNodeReference(
        kind: .scheduleTrigger,
        summary: """
        Fires the workflow on a timer and seeds the first node the same way Manual \
        Trigger does. The clock belongs to the app, not to the runner.
        """,
        inputPorts: [],
        settings: [
            .init(
                label: "Fires",
                detail: """
                Every interval, daily at a time, or on a cron expression.
                """
            ),
            .init(
                label: "Interval",
                detail: "Seconds between runs, for the interval kind."
            ),
            .init(
                label: "Hour and minute",
                detail: "Local wall clock time to fire at, for the daily kind."
            ),
            .init(
                label: "Cron expression",
                detail: """
                Five fields: minute, hour, day of month, month, day of week, read \
                in this device's time zone. The inspector resolves the next firing \
                as you type, so a bad expression shows up before you save.
                """
            ),
            .init(
                label: "Initial Items",
                detail: "The same seed list Manual Trigger takes, handed over on every firing."
            )
        ],
        emits: "The seed items, exactly as written.",
        outputPorts: [outPort],
        example: .init(
            caption: "Weekday mornings at nine.",
            snippet: "0 9 * * 1-5"
        ),
        notes: [
            """
            Schedules only fire while the app is running. There is no background \
            execution and no catch-up for firings missed while it was closed.
            """,
            """
            A cron expression that can never come round, such as 30 February, is \
            reported when the workflow is saved rather than failing silently at \
            run time.
            """
        ]
    )
}

// MARK: - AI

private extension WorkflowNodeReference {
    static let ignoresIncomingItems = """
    It does not read the incoming items. Fifty items arriving on `in` still \
    produce one item out. To run it once per item, put it in a Loop Over Items \
    body and address the element with {{ item.field }}.
    """

    static let llmGenerate = WorkflowNodeReference(
        kind: .llmGenerate,
        summary: """
        Sends one user turn to a language model and emits the answer as text. The \
        prompt is an expression, so it can quote an earlier node's output.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(
                label: "Prompt",
                detail: """
                The user turn. Required: a prompt that resolves to nothing fails \
                the node.
                """
            ),
            .init(
                label: "Model",
                detail: """
                Left on Automatic, the node uses whichever language model is loaded. \
                Naming one loads it first, unless it is already current.
                """
            ),
            .init(label: "System prompt", detail: "Also an expression, resolved before the call."),
            .init(
                label: "Temperature",
                detail: "Off leaves the model's own default alone. On gives a 0 to 2 slider."
            ),
            .init(label: "Max tokens", detail: "Off leaves the default alone.")
        ],
        emits: "One item: the answer text under `text`, and the model that produced it under `model`.",
        outputPorts: [outPort],
        example: .init(
            caption: "Quoting a Transcribe node upstream.",
            snippet: "Summarise this in one sentence:\n{{ Transcribe.text }}"
        ),
        notes: [
            ignoresIncomingItems,
            """
            An expression that names a node addresses that node's first item only. \
            {{ Split Out.title }} reads the first split item, not all of them.
            """
        ]
    )

    static let llmStructured = WorkflowNodeReference(
        kind: .llmStructured,
        summary: """
        The same call as LLM Generate, with the answer constrained by a JSON \
        Schema and parsed before it leaves the node. The item body is the parsed \
        object, so downstream expressions address its fields directly instead of \
        digging through a wrapper.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Prompt", detail: "The user turn. Required."),
            .init(
                label: "JSON Schema",
                detail: """
                The shape the answer has to satisfy. Required: a node with no \
                schema fails before it calls the model.
                """
            ),
            .init(label: "Model", detail: "A language model, or Automatic for the loaded one."),
            .init(label: "System prompt", detail: "Resolved as an expression."),
            .init(label: "Temperature and max tokens", detail: "Both optional overrides.")
        ],
        emits: "One item whose whole body is the parsed answer.",
        outputPorts: [outPort],
        example: .init(
            caption: "Read the result downstream as {{ Classify.sentiment }}.",
            snippet: """
            {
              "type": "object",
              "properties": {
                "sentiment": { "type": "string" },
                "score": { "type": "number" }
              },
              "required": ["sentiment"]
            }
            """
        ),
        notes: [
            ignoresIncomingItems,
            """
            If the model answers with something that is not valid JSON the node \
            fails rather than passing the raw text along.
            """
        ]
    )

    static let vision = WorkflowNodeReference(
        kind: .vision,
        summary: """
        Asks a vision model a question about an image carried on an incoming item. \
        The image is an attachment, not a field in the item body, so a File Read \
        node in binary mode is the usual source.
        """,
        inputPorts: [
            .init(
                name: "in",
                role: .flow,
                detail: """
                The items to search for the image. The node scans every item and \
                takes the first attachment that matches.
                """
            )
        ],
        settings: [
            .init(label: "Prompt", detail: "The question to ask about the image. Required."),
            .init(
                label: "Image attachment key",
                detail: """
                Which attachment holds the image bytes. Left blank, the node takes \
                the first attachment on the first item that has one.
                """
            ),
            .init(label: "Model", detail: "A vision model, or Automatic for the loaded one."),
            .init(label: "System prompt, temperature, max tokens", detail: "Optional overrides.")
        ],
        emits: "One item: the model's answer under `text`.",
        outputPorts: [outPort],
        example: .init(
            caption: "Reading an image File Read put under the key `data`.",
            snippet: "What is written on this sign?"
        ),
        notes: [
            """
            The attachment needs a MIME type. Without one the runner sniffs the \
            bytes, and it recognises PNG, JPEG and WebP only. Anything else fails \
            with an unrecognisable format.
            """,
            """
            The model list is filtered to the Vision category, but the runner loads \
            whatever you pick under the Multimodal category. A model that appears \
            in the list but is not a vision-language model fails at load.
            """,
            """
            Incoming attachments do not carry through. The node emits a fresh item \
            holding the answer and nothing else.
            """
        ]
    )

    static let embed = WorkflowNodeReference(
        kind: .embed,
        summary: """
        Turns text into a vector with an embedding model. If the expression \
        resolves to a JSON array the whole array is embedded as one batch; \
        anything else is embedded as a single string.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Text expression", detail: "What to embed. Required."),
            .init(label: "Model", detail: "An embedding model, or Automatic for the loaded one.")
        ],
        emits: """
        One item holding `dimension` and `vectors`, a list of lists. When there is \
        exactly one vector it is repeated under `embedding` so a single-text call \
        reads cleanly.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "A literal batch. An expression resolving to a JSON list behaves the same way.",
            snippet: """
            ["first sentence", "second sentence"]
            """
        ),
        notes: [
            ignoresIncomingItems,
            """
            Array elements that are not strings are re-serialised as JSON text \
            before being embedded, so an object embeds as its own JSON.
            """
        ]
    )

    static let rerank = WorkflowNodeReference(
        kind: .rerank,
        summary: """
        Scores a list of documents against a query with a reranking model and \
        emits one item per document, in the order the reranker put them.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Query", detail: "What the documents are being scored against. Required."),
            .init(
                label: "Documents expression",
                detail: """
                Has to resolve to a JSON array. Elements that are not strings are \
                re-serialised as JSON text.
                """
            ),
            .init(label: "Top N", detail: "How many to keep. Zero keeps everything the model returns."),
            .init(
                label: "Model",
                detail: """
                Required, and it has to be downloaded already. Reranking sits \
                outside the category-routed model lifecycle, so this node resolves \
                the model on disk, loads it, scores, and tears it down again.
                """
            )
        ],
        emits: "One item per document, each with `index`, `score` and `text`.",
        outputPorts: [outPort],
        example: .init(
            caption: "Reranking passages an HTTP Request fetched.",
            snippet: "{{ Fetch Docs.body.passages }}"
        ),
        notes: [
            """
            The model dropdown offers Automatic, and Automatic does not work here: \
            a Rerank node with no model fails at run time. Pick one explicitly.
            """,
            ignoresIncomingItems,
            """
            A documents expression that does not resolve to a list fails the node \
            rather than scoring one long string.
            """
        ]
    )
}

// MARK: - Speech

private extension WorkflowNodeReference {
    static let audioAttachmentPort = WorkflowReferencePort(
        name: "in",
        role: .flow,
        detail: """
        The items to search for the audio. The node scans every item and takes the \
        first attachment that matches.
        """
    )

    static let transcribe = WorkflowNodeReference(
        kind: .transcribe,
        summary: """
        Runs speech to text over an audio attachment on an incoming item and emits \
        the transcript.
        """,
        inputPorts: [audioAttachmentPort],
        settings: [
            .init(
                label: "Audio attachment key",
                detail: "Blank takes the first attachment on the first item that has one."
            ),
            .init(
                label: "Language",
                detail: "Blank lets the engine detect it. Otherwise a language code."
            ),
            .init(label: "Model", detail: "A speech recognition model, or Automatic.")
        ],
        emits: "One item with `text`, `duration_ms`, and `language` when the engine reports one.",
        outputPorts: [outPort],
        example: .init(
            caption: "File Read in binary mode under the key `audio`, then Transcribe on the same key.",
            snippet: "audio"
        ),
        notes: [
            """
            A WAV attachment is understood: the runner reads the sample rate and \
            channel count out of its header. Everything else is handed to the \
            engine as raw PCM, so an MP3 or M4A attachment will not transcribe.
            """,
            """
            One transcript comes out however many items went in, and the incoming \
            items' fields do not carry through.
            """
        ]
    )

    static let speak = WorkflowNodeReference(
        kind: .speak,
        summary: """
        Synthesises speech and hands the audio back as an attachment. It never \
        plays it. The runner has no audio output on any platform, so playback is \
        the app's job.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Text expression", detail: "What to say. Required."),
            .init(
                label: "Attachment key",
                detail: "Where the audio lands on the outgoing item. Blank uses `audio`."
            ),
            .init(label: "Voice", detail: "A voice name the model recognises. Blank uses its default."),
            .init(label: "Model", detail: "A speech synthesis model, or Automatic.")
        ],
        emits: """
        One item whose body holds `duration_ms` and `sample_rate`, with the WAV \
        bytes attached under the key you chose.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "Reading a summary aloud, saved under the key `speech`.",
            snippet: "{{ Summarise.text }}"
        ),
        notes: [
            """
            The document format carries a play-through-the-speakers flag. The \
            editor never sets it, and the runner refuses a node that has it set, \
            so play the returned attachment in the app instead.
            """,
            ignoresIncomingItems,
            """
            The outgoing item is fresh, so attachments and fields on the incoming \
            items are dropped. Wire a Set / Transform after it if you need them back.
            """
        ]
    )

    static let detectVoice = WorkflowNodeReference(
        kind: .detectVoice,
        summary: """
        Runs voice activity detection over an audio attachment and reports whether \
        the clip holds speech, with the probability and energy behind the verdict.
        """,
        inputPorts: [audioAttachmentPort],
        settings: [
            .init(label: "Audio attachment key", detail: "Blank takes the first attachment it finds."),
            .init(
                label: "Threshold",
                detail: """
                Off uses the detector's own activation threshold. On gives a 0 to 1 \
                slider: higher is stricter about what counts as speech.
                """
            )
        ],
        emits: "One item with `is_speech`, `probability` and `energy`.",
        outputPorts: [outPort],
        example: .init(
            caption: "Gate a branch on the result with a Condition node.",
            snippet: "{{ Detect Voice.is_speech }} equals true"
        ),
        notes: [
            """
            There is no model to pick. Detection runs on the built-in detector.
            """,
            """
            Mono only. A stereo WAV fails outright.
            """,
            """
            A WAV is stripped to its samples and its own encoding is used. A \
            non-WAV attachment is assumed to be 32-bit float PCM, so 16-bit raw \
            bytes are misread rather than rejected.
            """
        ]
    )

    static let diarize = WorkflowNodeReference(
        kind: .diarize,
        summary: """
        Splits an audio attachment into speaker turns and reports when each \
        speaker was talking.
        """,
        inputPorts: [audioAttachmentPort],
        settings: [
            .init(label: "Audio attachment key", detail: "Blank takes the first attachment it finds."),
            .init(
                label: "Known speaker count",
                detail: """
                Off lets the model decide. On sets a maximum rather than a fixed \
                number, so the model can still find fewer.
                """
            ),
            .init(label: "Model", detail: "A speaker diarization model, or Automatic.")
        ],
        emits: """
        One item with `speaker_count`, `audio_duration_ms`, and `segments`, a list \
        of `start_ms`, `end_ms`, `speaker_index` and `speaker_id`.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "A two-person interview, read downstream through Split Out.",
            snippet: "{{ Diarize.segments }}"
        ),
        notes: [
            """
            Mono only. A stereo WAV fails outright.
            """,
            """
            A WAV is stripped to its samples and its encoding and sample rate are \
            read from the header. A non-WAV attachment goes over with neither \
            declared, so the engine's defaults apply to it.
            """
        ]
    )

    static let segment = WorkflowNodeReference(
        kind: .segment,
        summary: """
        Runs semantic segmentation over an image and reports which classes cover \
        which parts of it. The inspector labels its one field "Text expression", \
        but the runner reads that value as an attachment key: this is an image \
        node, not a text one.
        """,
        inputPorts: [
            .init(
                name: "in",
                role: .flow,
                detail: """
                The item carrying the pixels. Its body also has to hold `width` and \
                `height` as numbers, because the segmentation call takes raw pixels \
                rather than an encoded image.
                """
            )
        ],
        settings: [
            .init(
                label: "Text expression",
                detail: """
                Despite the label, this is the attachment key holding the pixels. \
                Blank takes the first attachment on the first item that has one.
                """
            ),
            .init(label: "Model", detail: "A semantic segmentation model, or Automatic.")
        ],
        emits: """
        One item holding `width`, `height` and `classes`, a list of `class_id`, \
        `label` and `pixel_count`, plus a `mask` attachment of one unsigned 16-bit \
        class id per pixel, little-endian.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "An item whose attachment `pixels` holds 512 by 512 RGBA bytes.",
            snippet: """
            { "width": 512, "height": 512 }
            """
        ),
        notes: [
            """
            The bytes have to be raw RGB8 or RGBA8, and the byte count has to equal \
            width times height times 3 or times 4 exactly. A PNG or JPEG is rejected.
            """,
            """
            No other node in the palette produces a raw pixel buffer. File Read \
            hands over a file's bytes unchanged, and seed items carry JSON only, so \
            in practice this node cannot be fed from inside the editor today.
            """,
            """
            It sits under Speech in the palette because of where its proto arm \
            lands, not because it has anything to do with audio.
            """
        ]
    )
}

// MARK: - Knowledge

private extension WorkflowNodeReference {
    static let ragSessionNote = """
    The index belongs to a session keyed on the pair of model ids, and the session \
    lives as long as the app does. Ingest and Query have to name the same two \
    models to see the same index.
    """

    static let ragQuery = WorkflowNodeReference(
        kind: .ragQuery,
        summary: """
        Asks a question against the RAG index and gets back an answer together with \
        the passages behind it.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Question", detail: "The question to answer. Required."),
            .init(label: "Top K", detail: "How many passages to retrieve before answering."),
            .init(
                label: "Embedding model",
                detail: "Required. Automatic leaves it empty and the node fails at run time."
            ),
            .init(label: "Language model", detail: "The model that writes the answer.")
        ],
        emits: """
        One item with `answer` and `chunks`, a list of `text`, `score` and `source`.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "Feeding the question through from the trigger.",
            snippet: "{{ Manual Trigger.question }}"
        ),
        notes: [
            ragSessionNote,
            """
            The embedding model dropdown offers Automatic, and Automatic does not \
            work here. Pick one explicitly.
            """,
            """
            An SDK built without the RAG backend fails this node outright rather \
            than answering from nothing.
            """
        ]
    )

    static let ragIngest = WorkflowNodeReference(
        kind: .ragIngest,
        summary: """
        Chunks, embeds and indexes a piece of text so a later RAG Query can \
        retrieve it.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Text expression", detail: "The document text. Required."),
            .init(
                label: "Document id",
                detail: "Optional. Names the document in the index so it can be recognised later."
            ),
            .init(
                label: "Embedding model",
                detail: "Required. Automatic leaves it empty and the node fails at run time."
            ),
            .init(label: "Language model", detail: "Part of the session key, alongside the embedding model.")
        ],
        emits: """
        One item with `indexed_documents` and `indexed_chunks`, plus `document_id` \
        when you set one.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "Indexing a file read earlier in the same run.",
            snippet: "{{ File Read.text }}"
        ),
        notes: [
            ragSessionNote,
            ignoresIncomingItems,
            """
            An SDK built without the RAG backend fails this node outright.
            """
        ]
    )
}

// MARK: - Models

private extension WorkflowNodeReference {
    static let loadModel = WorkflowNodeReference(
        kind: .loadModel,
        summary: """
        Brings a model up before a later node needs it, so a long first load is a \
        step you can watch rather than an unexplained pause inside another node. \
        Every node that names a model loads it for itself anyway, so this is about \
        ordering and visibility rather than correctness.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Category", detail: "Which slot the model is being loaded into."),
            .init(
                label: "Model",
                detail: "Required. A Load Model node with nothing chosen fails at run time."
            )
        ],
        emits: "One item with `model_id` and `loaded`.",
        outputPorts: [outPort],
        example: .init(
            caption: "Load a language model first, then leave the LLM nodes below it on Automatic.",
            snippet: "Category: Language"
        ),
        notes: [
            """
            If the named model is already current for that category, nothing is \
            reloaded and the node finishes immediately.
            """,
            ignoresIncomingItems
        ]
    )
}

// MARK: - Logic

private extension WorkflowNodeReference {
    static let comparisonNote = """
    Greater than and less than compare numerically when both sides parse as \
    numbers, and fall back to alphabetical order when either does not. That makes \
    "10" greater than "9", and it also makes "apple" greater than "9".
    """

    static let truePort = WorkflowReferencePort(
        name: "true",
        role: .branch,
        detail: "Items that passed the test."
    )

    static let falsePort = WorkflowReferencePort(
        name: "false",
        role: .branch,
        detail: "Items that did not."
    )

    static let condition = WorkflowNodeReference(
        kind: .condition,
        summary: """
        Compares two values once and sends every incoming item down one of two \
        ports. The whole list goes one way. Nothing is split.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Left value", detail: "An expression, or a literal."),
            .init(
                label: "Comparison",
                detail: """
                Equals, does not equal, contains, is greater than, is less than, or \
                is empty. The right-hand field disappears for is empty.
                """
            ),
            .init(label: "Right value", detail: "The other side of the test.")
        ],
        emits: "The incoming items unchanged, on whichever port the test chose.",
        outputPorts: [truePort, falsePort],
        example: .init(
            caption: "Branch on whether an audio clip held speech.",
            snippet: "{{ Detect Voice.is_speech }}  equals  true"
        ),
        notes: [
            """
            The test runs once for the node, not once per item, so {{ item.field }} \
            is not available here. It exists only inside a loop body and inside \
            Filter. Use Filter to test items individually.
            """,
            comparisonNote,
            """
            Nodes below the branch that was not taken are marked skipped, which is \
            not a failure and does not fail the run.
            """
        ]
    )

    static let filter = WorkflowNodeReference(
        kind: .filter,
        summary: """
        Tests each incoming item on its own and splits the list in two. Matching \
        items leave by true and the rest by false, so nothing is thrown away: both \
        halves are there to wire up.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Left value", detail: "Usually an {{ item.field }} expression."),
            .init(label: "Comparison", detail: "The same six tests Condition offers."),
            .init(label: "Right value", detail: "The other side of the test.")
        ],
        emits: "The matching items on true, and the rest on false.",
        outputPorts: [truePort, falsePort],
        example: .init(
            caption: "Keep only the confident results.",
            snippet: "{{ item.score }}  is greater than  0.8"
        ),
        notes: [
            """
            {{ item.… }} addresses the item under test, which is the reason to \
            reach for Filter over Condition.
            """,
            comparisonNote,
            """
            Unlike Condition, neither branch is treated as untaken, so nodes below \
            both ports run.
            """
        ]
    )

    static let loopOverItems = WorkflowNodeReference(
        kind: .loopOverItems,
        summary: """
        Walks a list and runs a chosen set of nodes once per element. The body \
        nodes stay on the canvas but belong to the loop: they are lifted out of \
        the main run order and only execute inside it.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(
                label: "Items expression",
                detail: "Has to resolve to a JSON array. Anything else fails the node."
            ),
            .init(
                label: "Max iterations",
                detail: "A hard ceiling. Zero means the runner's built-in cap of 1000 applies."
            ),
            .init(
                label: "Body Nodes",
                detail: """
                Which nodes run per element, in the order you ticked them. Triggers \
                and the loop itself are not offered.
                """
            )
        ],
        emits: "Everything the last body node produced, concatenated across all the passes.",
        outputPorts: [outPort],
        example: .init(
            caption: "One LLM call per search result, reading the element with {{ item.title }}.",
            snippet: "{{ Fetch.body.results }}"
        ),
        notes: [
            """
            The body is a straight chain regardless of what is wired on the canvas. \
            Each body node sees the previous one's output, the first sees the \
            current element, and wires drawn between body nodes are ignored.
            """,
            """
            {{ item.… }} is bound here and inside Filter, nowhere else.
            """,
            """
            A body node that fails fails the loop. Cancelling a run stops the loop \
            between iterations.
            """
        ]
    )

    static let code = WorkflowNodeReference(
        kind: .code,
        summary: """
        Runs JavaScript over the incoming items. The runner has no JavaScript \
        engine of its own, so the app evaluates it in JavaScriptCore and hands the \
        result back.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(
                label: "JavaScript",
                detail: """
                `items` is the input list, an array of the incoming items' bodies. \
                Return a value: the source runs inside a wrapper function, so a \
                top-level `return` works.
                """
            )
        ],
        emits: """
        An array becomes one item per element. Any other value becomes a single \
        item. Returning nothing emits an empty list.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "Filter and reshape in one step.",
            snippet: """
            return items
              .filter(i => i.score > 0.5)
              .map(i => ({ title: i.title }));
            """
        ),
        notes: [
            """
            Attachments do not survive. Only the JSON bodies go in and only JSON \
            comes back, so audio and images on the incoming items are lost here.
            """,
            """
            Each run gets a fresh context, so nothing carries between nodes or \
            between runs, and there is no network or filesystem reach from inside.
            """,
            """
            A returned value that JSON.stringify cannot serialise fails the node, \
            as does anything the script throws.
            """
        ]
    )

    static let setTransform = WorkflowNodeReference(
        kind: .setTransform,
        summary: """
        Writes fields onto every incoming item. One item in, one item out, so the \
        list keeps its length and its attachments ride along untouched.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(
                label: "Fields",
                detail: "A field name and an expression per row. Rows keep the order you added them."
            ),
            .init(
                label: "Keep only assigned fields",
                detail: """
                Start each item from an empty body instead of the incoming one. It \
                clears the body, not the attachments.
                """
            )
        ],
        emits: "The same number of items, each with the assigned fields set.",
        outputPorts: [outPort],
        example: .init(
            caption: "Stamp a label from an earlier classification onto every item.",
            snippet: "label  =  {{ Classify.sentiment }}"
        ),
        notes: [
            """
            A resolved value that is itself valid JSON keeps its type: `42` lands as \
            a number, `true` as a boolean, `{\"a\":1}` as an object. Everything else \
            lands as a string. Without that, a number pushed through here would \
            arrive quoted at the next numeric comparison.
            """,
            """
            This is the node to reach for when a later node dropped fields you still \
            need, since it rebuilds a body from expressions rather than from what \
            arrived.
            """
        ]
    )

    static let merge = WorkflowNodeReference(
        kind: .merge,
        summary: """
        The only node with more than one input. It concatenates the branches that \
        reach it, in port order, so a fan-in needs no dummy step.
        """,
        inputPorts: [
            .init(
                name: "in1 … inN",
                role: .flow,
                detail: """
                Numbered sockets, one per declared input. There is no plain `in` \
                port on a Merge node.
                """
            )
        ],
        settings: [
            .init(label: "Inputs", detail: "How many sockets the card shows, from 1 to 8."),
            .init(
                label: "Drop duplicate items",
                detail: "Skip an item whose JSON body has already been seen on an earlier port."
            )
        ],
        emits: "Every item from in1, then every item from in2, and so on.",
        outputPorts: [outPort],
        example: .init(
            caption: "The two sides of a Condition rejoining before a shared File Write.",
            snippet: "in1 ← Condition (true)\nin2 ← Condition (false)"
        ),
        notes: [
            """
            Deduplication compares the JSON body byte for byte, so two items that \
            differ only in the order of their keys both survive.
            """,
            """
            Lowering the input count deletes any connection that landed on a socket \
            that no longer exists.
            """,
            """
            A branch that never ran contributes nothing instead of blocking the \
            merge.
            """
        ]
    )

    static let splitOut = WorkflowNodeReference(
        kind: .splitOut,
        summary: """
        Turns one list into many items, the inverse of Aggregate. It resolves its \
        expression to a JSON array and emits one item per element.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(
                label: "List field",
                detail: """
                An expression, despite the label. It has to resolve to a JSON array.
                """
            )
        ],
        emits: """
        One item per element. An element that is an object becomes that item's \
        whole body.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "Fan out the results of an HTTP call.",
            snippet: "{{ HTTP Request.body.results }}"
        ),
        notes: [
            """
            It does not read the incoming items. The field is resolved against the \
            expression context, so it has to name a node, as in \
            {{ Node Name.list }}. A bare field name with no braces resolves to \
            itself and fails with "did not resolve to a list".
            """,
            """
            An expression that resolves to a single object rather than a list also \
            fails. Use Set / Transform to wrap it first if that is what you meant.
            """
        ]
    )

    static let aggregate = WorkflowNodeReference(
        kind: .aggregate,
        summary: """
        Collapses every incoming item into one, the inverse of Split Out. The new \
        item's body holds a single field with the list of the incoming bodies in it.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(
                label: "Field",
                detail: """
                The name to gather under. Blank uses `items`. It is resolved as an \
                expression, so braces in it are evaluated before use.
                """
            )
        ],
        emits: "Exactly one item, whatever the input length.",
        outputPorts: [outPort],
        example: .init(
            caption: "Gathering under `results`, read downstream as {{ Aggregate.results.0.text }}.",
            snippet: "results"
        ),
        notes: [
            """
            Attachments from every incoming item are merged onto the single output \
            item. Two items using the same attachment key collide, and the last one \
            wins.
            """,
            """
            An empty input still produces one item, holding an empty list.
            """
        ]
    )

    static let wait = WorkflowNodeReference(
        kind: .wait,
        summary: """
        Pauses the run for a fixed number of seconds, then passes its incoming \
        items through unchanged.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Seconds", detail: "How long to wait.")
        ],
        emits: "The incoming items, untouched.",
        outputPorts: [outPort],
        example: .init(
            caption: "Spacing out calls to a rate-limited API.",
            snippet: "30"
        ),
        notes: [
            """
            The runner walks nodes one at a time, so a Wait holds up the whole run \
            rather than only the branch it sits on.
            """,
            """
            Cancelling takes effect within about a twentieth of a second instead of \
            at the end of the wait.
            """
        ]
    )
}

// MARK: - Integration

private extension WorkflowNodeReference {
    static let toolCall = WorkflowNodeReference(
        kind: .toolCall,
        summary: """
        Calls a tool the app has registered, the same registry chat uses. The \
        tool's arguments become sockets on the card, so each one can be wired from \
        another node or typed in by hand.
        """,
        inputPorts: [
            flowPort,
            .init(
                name: "one socket per argument",
                role: .declared,
                detail: """
                Copied into the document when you pick the tool, and marked required \
                or optional from the tool's own schema. Wiring a socket hides its \
                text field.
                """
            )
        ],
        settings: [
            .init(
                label: "Tool",
                detail: """
                Chosen from the registry when the app has one, or typed by name when \
                it does not.
                """
            ),
            .init(
                label: "Argument values",
                detail: """
                A literal or an expression per argument, used for any socket left \
                unconnected.
                """
            )
        ],
        emits: """
        One item whose body is the tool's result, parsed as JSON. A result that is \
        not JSON becomes an empty object.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "A search tool taking its query from the trigger.",
            snippet: "query  =  {{ Manual Trigger.question }}"
        ),
        notes: [
            """
            A wired socket beats a typed value, and the inspector says so instead of \
            leaving a field that would be ignored.
            """,
            """
            A socket fed several items arrives as a JSON array rather than as the \
            first one.
            """,
            """
            A required argument with neither a wire nor a value fails the node.
            """,
            """
            The tool is looked up when the node runs, not when the workflow is \
            saved, so a workflow naming a tool this machine does not register still \
            opens and edits.
            """
        ]
    )

    static let httpRequest = WorkflowNodeReference(
        kind: .httpRequest,
        summary: """
        Sends one HTTP request and emits the response. URL, headers and body are \
        all expressions, so any of them can quote an earlier node.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Method", detail: "GET, POST, PUT, PATCH or DELETE."),
            .init(
                label: "URL",
                detail: "Has to be absolute and start with http:// or https://. Redirects are followed."
            ),
            .init(label: "Timeout", detail: "Milliseconds. Zero uses the transport's default."),
            .init(label: "Headers", detail: "Name and value per row. Values are expressions."),
            .init(
                label: "Authentication",
                detail: """
                A bearer token, a named header, or a query parameter. The secret is \
                taken verbatim and never expression-resolved, so braces in a token \
                cannot be mangled or leak into an error message.
                """
            ),
            .init(label: "Body", detail: "Shown for anything but GET. An expression.")
        ],
        emits: """
        One item with `status` and `body`. The body arrives parsed when the \
        response is JSON, and as raw text otherwise.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "Posting a transcript to an API.",
            snippet: """
            {
              "text": "{{ Transcribe.text }}"
            }
            """
        ),
        notes: [
            """
            A status outside 200 to 299 fails the node. The item is still recorded, \
            so you can read the error body in Last Output, but everything below the \
            node is skipped and the run is reported as failed.
            """,
            """
            The secret is stored in the workflow document in the clear, not in the \
            keychain. Treat a saved workflow the way you would treat a file holding \
            the key itself, and think twice before exporting one as a bundle.
            """,
            ignoresIncomingItems
        ]
    )

    static let fileRead = WorkflowNodeReference(
        kind: .fileRead,
        summary: """
        Reads a file from disk into an item. In text mode the contents land in the \
        body; in binary mode they land as an attachment, which is how audio and \
        images reach the speech and vision nodes.
        """,
        inputPorts: [flowPort],
        settings: [
            .init(label: "Path", detail: "An expression. An empty result fails the node."),
            .init(label: "Read as binary", detail: "Off puts the text in the body. On makes an attachment."),
            .init(label: "Attachment key", detail: "Where the bytes land. Blank uses `data`."),
            .init(
                label: "MIME type",
                detail: "Recorded on the attachment. Worth setting: some nodes read it."
            )
        ],
        emits: """
        Exactly one item. Text mode gives `path` and `text`. Binary mode gives \
        `path` and `size`, plus the attachment, whose file name comes from the path.
        """,
        outputPorts: [outPort],
        example: .init(
            caption: "Reading a recording named by the trigger, for a Transcribe node below.",
            snippet: "/Users/me/Recordings/{{ Manual Trigger.name }}.wav"
        ),
        notes: [
            ignoresIncomingItems,
            """
            Set the MIME type in binary mode. Vision can sniff PNG, JPEG and WebP \
            and nothing else, and Transcribe reads a WAV header rather than the MIME \
            type, so an unlabelled attachment of any other format fails downstream.
            """,
            """
            The read goes through the app's own file access, so the app has to be \
            able to reach that path.
            """
        ]
    )

    static let fileWrite = WorkflowNodeReference(
        kind: .fileWrite,
        summary: """
        Writes text or an attachment to a path on disk, once per run rather than \
        once per item.
        """,
        inputPorts: [
            .init(
                name: "in",
                role: .flow,
                detail: """
                The items to search when an attachment key is set. Ignored otherwise.
                """
            )
        ],
        settings: [
            .init(label: "Path", detail: "An expression. An empty result fails the node."),
            .init(
                label: "Attachment key",
                detail: """
                Names binary data on an incoming item. Set it to write audio or an \
                image rather than text.
                """
            ),
            .init(label: "Append", detail: "Add to the end of an existing file instead of replacing it."),
            .init(
                label: "Content",
                detail: "The text to write. Ignored whenever an attachment key is set."
            )
        ],
        emits: "One item with `path` and `bytes_written`.",
        outputPorts: [outPort],
        example: .init(
            caption: "Appending a summary to a log.",
            snippet: "{{ LLM Generate.text }}"
        ),
        notes: [
            """
            Appending is read, concatenate, write, because there is no append \
            primitive underneath. A file that exists but cannot be read fails the \
            node instead of being overwritten.
            """,
            """
            An attachment key that matches nothing on any incoming item fails the \
            node rather than falling back to the content field.
            """
        ]
    )

    static let packNode = WorkflowNodeReference(
        kind: .packNode,
        summary: """
        An instance of an installed node pack, which is a reusable node somebody \
        built and shared. Its shape is copied from the pack when you drop it, so \
        the card keeps drawing the right sockets even on a machine where the pack \
        is missing.
        """,
        inputPorts: [
            flowPort,
            .init(
                name: "one socket per argument",
                role: .declared,
                detail: """
                Declared by the pack and marked required or optional, exactly the way \
                a tool declares its arguments.
                """
            )
        ],
        settings: [
            .init(
                label: "Argument values",
                detail: "A literal or an expression per argument, used for any socket left unwired."
            )
        ],
        emits: """
        For a script pack, whatever the script returns, under the same rules as a \
        Code node. For a composite pack, the output of its exit node.
        """,
        outputPorts: [
            .init(
                name: "declared by the pack",
                role: .declared,
                detail: """
                A pack that declares no outputs gets the single `out` socket every \
                other node has.
                """
            )
        ],
        example: .init(
            caption: "A pack with a required `text` argument, wired from an LLM Generate node.",
            snippet: "text  ←  LLM Generate (out)"
        ),
        notes: [
            """
            There are two kinds. A composite pack is a subgraph of nodes that \
            already exist, so installing one grants nothing the app could not \
            already do. A script pack carries JavaScript and goes through the same \
            host callback the Code node uses, which is why the importer shows the \
            capabilities it declares before enabling it.
            """,
            """
            A pack that is not installed draws as a placeholder and is reported when \
            the workflow is saved. The document still opens and edits; only running \
            it fails.
            """,
            """
            A pack that reaches itself through its own subgraph is caught, as is \
            nesting deeper than 64 packs.
            """
        ]
    )
}
