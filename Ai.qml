pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai

/**
 * AI chat service for Quickshell desktop. Multi-provider LLM client with:
 * - Providers: Gemini, OpenAI, Anthropic, Groq, xAI, DeepSeek, Ollama, any OpenAI-compatible
 * - Features: streaming, function calling (search, shell commands, config editing),
 *   extended thinking (Anthropic/Gemini), file attachments, chat history,
 *   context compression, export, adaptive UI throttling
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}

    property Component anthropicApiStrategy: AnthropicApiStrategy {}
    GeminiApiStrategy { id: geminiStrategy }
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()

    property bool isGenerating: requester.running || commandExecutionProc.running
    property string previousChatSummary: ""
    property string sessionSummary: "" // Accumulated summary of compressed conversation
    property bool condensing: false // Indicates background summarization is active
    readonly property string summarizerModelId: "gemini-3.1-flash-lite"

    function abortAll() {
        // Kill any running AI processes
        if (commandExecutionProc.running) {
            commandExecutionProc.running = false;
        }
        if (requester.running) {
            requester.running = false;
        }
        // Mark current message as done
        if (requester.message && !requester.message.done) {
            if (requester.message.content.length === 0) {
                requester.message.content = Translation.tr("*[Interrupted]*");
                requester.message.rawContent = Translation.tr("*[Interrupted]*");
            }
            requester.message.thinking = false;
            requester.message.done = true;
        }
        root.postResponseHook = null;
        root.responseFinished();
    }

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5

    // Extended thinking
    property bool thinkingEnabled: Persistent.states?.ai?.thinkingEnabled ?? false
    // Anthropic: used as budget_tokens. Gemini: level 0-3 (off/low/med, max)
    property int thinkingLevel: Persistent.states?.ai?.thinkingLevel ?? 0
    property bool functionsAutoConfirm: Persistent.states?.ai?.functionsAutoConfirm ?? false
    readonly property var geminiThinkingLabels: ["Off", "Low", "Med", "High"]
    function currentModelThinkingStyle() {
        return root.modelThinkingStyles[currentModelId] ?? ""
    }
    property string currentThinkingStyle: {
        const style = root.modelThinkingStyles[root.currentModelId];
        return style ?? "";
    }

    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    // Generation speed & cost tracking
    property real generationStartTime: 0
    property real generationSpeed: 0 // tokens per second
    property real sessionCost: 0 // accumulated $ cost this session

    // Pricing per million tokens: [input, output] — 0 means free
    readonly property var modelPricing: ({
        "gemini-3.1-flash-lite": [0.25, 1.50],
        "gemini-3-flash": [0.50, 3.00],
        "gemini-3.1-pro": [2.00, 12.00],
        "claude-haiku-4-5": [0.80, 4.00],
        "claude-sonnet-4-6": [3.00, 15.00],
        "claude-opus-4-7": [15.00, 75.00],
        "gpt-5.4-nano": [0.20, 1.25],
        "gpt-5.4-mini": [0.75, 4.50],
        "gpt-5.4": [2.50, 15.00],
    })

    // Thinking style per model — "gemini" uses thinking_level, "anthropic" uses budget_tokens
    readonly property var modelThinkingStyles: ({
        "gemini-3-flash": "gemini",
        "gemini-3.1-pro": "gemini",
        "claude-sonnet-4-6": "anthropic",
        "claude-opus-4-7": "anthropic",
    })

    function calculateCost(modelId, inputTokens, outputTokens) {
        const pricing = root.modelPricing[modelId];
        if (!pricing) return 0;
        return (inputTokens * pricing[0] + outputTokens * pricing[1]) / 1000000;
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`,
        "{PREVIOUS_CHAT_CONTEXT}": root.previousChatSummary.length > 0 ? `\n\n## Previous conversation context\n${root.previousChatSummary}` : ""
    }

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "switch_to_search_mode",
                        "description": "Switch to web search mode to look up current information, recent events, prices, documentation, etc. Use whenever the answer might require up-to-date data.",
                        "parameters": {
                            "type": "object",
                            "properties": {}
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {
                            "type": "object",
                            "properties": {}
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [
                {
                    "type": "function",
                    "function": {
                        "name": "web_search_preview",
                        "description": "Search the web for current information. Use for factual queries, recent events, prices, docs, etc.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": "The search query"
                                }
                            },
                            "required": ["query"]
                        }
                    }
                }
            ],
            "none": [],
        },
        "anthropic": {
            "functions": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Switch to web search mode to look up current information, recent events, prices, documentation, etc. Use whenever the answer might require up-to-date data.",
                    "input_schema": {
                        "type": "object",
                        "properties": {}
                    }
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                    "input_schema": {
                        "type": "object",
                        "properties": {}
                    }
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting."
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run"
                            }
                        },
                        "required": ["command"]
                    }
                }
            ],
            "search": [
                {
                    "name": "web_search_preview",
                    "description": "Search the web for current information. Use for factual queries, recent events, prices, docs, etc.",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "The search query"
                            }
                        },
                        "required": ["query"]
                    }
                }
            ],
            "none": [],
        }
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format] ?? root.tools["openai"])
    property var toolDescriptions: {
        "functions": Translation.tr("Shell commands, config editing, web search.\nModel picks the right tool automatically."),
        "search": Translation.tr("Web search only (fastest for lookup tasks)"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - requires_key: Whether the model requires an API key
    // - key_id: The identifier of the API key. Use the same identifier for models that can be accessed with the same key.
    // - key_get_link: Link to get an API key
    // - key_get_description: Description of pricing and how to get an API key
    // - api_format: The API format of the model. Can be "openai" or "gemini". Default is "openai".
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    property var models: Config.options.policies.ai === 2 ? {} : {
        "gemini-3.1-flash-lite": aiModelComponent.createObject(this, {
            "name": "Gemini Flash-Lite",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nFastest & cheapest. Best for high-volume tasks, translation, and simple queries."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:streamGenerateContent",
            "model": "gemini-3.1-flash-lite-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: ~$0.25/M input, ~$1.50/M output\n\n**Instructions**: Log into Google account → AI Studio → Get API key"),
            "api_format": "gemini",
        }),
        "gemini-3-flash": aiModelComponent.createObject(this, {
            "name": "Gemini Flash",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nPro-level intelligence at Flash speed. Great for agentic workflows and coding."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:streamGenerateContent",
            "model": "gemini-3-flash-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: ~$0.50/M input, ~$3/M output\n\n**Instructions**: Log into Google account → AI Studio → Get API key"),
            "api_format": "gemini",
            "thinking_style": "gemini",
        }),
        "gemini-3.1-pro": aiModelComponent.createObject(this, {
            "name": "Gemini Pro",
            "icon": "google-gemini-symbolic",
            "description": Translation.tr("Online | Google's model\nMost advanced reasoning. Excels at complex problems, coding, and research. 1M context."),
            "homepage": "https://aistudio.google.com",
            "endpoint": "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-pro-preview:streamGenerateContent",
            "model": "gemini-3.1-pro-preview",
            "requires_key": true,
            "key_id": "gemini",
            "key_get_link": "https://aistudio.google.com/app/apikey",
            "key_get_description": Translation.tr("**Pricing**: ~$2/M input, ~$12/M output\n\n**Instructions**: Log into Google account → AI Studio → Get API key"),
            "api_format": "gemini",
            "thinking_style": "gemini",
        }),
        "claude-haiku-4-5": aiModelComponent.createObject(this, {
            "name": "Claude Haiku",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Online | Anthropic's model\nFastest Claude model. Great for quick tasks and high-volume use."),
            "homepage": "https://anthropic.com",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-haiku-4-5-20251001",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: ~$0.80/M input, ~$4/M output\n\n**Instructions**: Anthropic Console → API Keys → Create Key"),
            "api_format": "anthropic",
        }),
        "claude-sonnet-4-6": aiModelComponent.createObject(this, {
            "name": "Claude Sonnet",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Online | Anthropic's model\nSmart, efficient. Great at coding, analysis and writing."),
            "homepage": "https://anthropic.com",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-sonnet-4-6",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: ~$3/M input, ~$15/M output\n\n**Instructions**: Anthropic Console → API Keys → Create Key"),
            "api_format": "anthropic",
            "thinking_style": "anthropic",
        }),
        "claude-opus-4-7": aiModelComponent.createObject(this, {
            "name": "Claude Opus",
            "icon": "anthropic-symbolic",
            "description": Translation.tr("Online | Anthropic's model\nMost intelligent Claude. Best for complex reasoning and creative tasks."),
            "homepage": "https://anthropic.com",
            "endpoint": "https://api.anthropic.com/v1/messages",
            "model": "claude-opus-4-7",
            "requires_key": true,
            "key_id": "anthropic",
            "key_get_link": "https://console.anthropic.com/settings/keys",
            "key_get_description": Translation.tr("**Pricing**: ~$15/M input, ~$75/M output\n\n**Instructions**: Anthropic Console → API Keys → Create Key"),
            "api_format": "anthropic",
            "thinking_style": "anthropic",
        }),
        "gpt-5.4-nano": aiModelComponent.createObject(this, {
            "name": "GPT Nano",
            "icon": "openai-symbolic",
            "description": Translation.tr("Online | OpenAI's model\nFastest & cheapest GPT. Best for simple tasks, classification, and data extraction."),
            "homepage": "https://platform.openai.com",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "model": "gpt-5.4-nano",
            "requires_key": true,
            "key_id": "openai",
            "key_get_link": "https://platform.openai.com/api-keys",
            "key_get_description": Translation.tr("**Pricing**: ~$0.20/M input, ~$1.25/M output\n\n**Instructions**: platform.openai.com → API Keys → Create new secret key"),
            "api_format": "openai",
        }),
        "gpt-5.4-mini": aiModelComponent.createObject(this, {
            "name": "GPT Mini",
            "icon": "openai-symbolic",
            "description": Translation.tr("Online | OpenAI's model\nFast & capable. Great balance of speed, quality, and cost."),
            "homepage": "https://platform.openai.com",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "model": "gpt-5.4-mini",
            "requires_key": true,
            "key_id": "openai",
            "key_get_link": "https://platform.openai.com/api-keys",
            "key_get_description": Translation.tr("**Pricing**: ~$0.75/M input, ~$4.50/M output\n\n**Instructions**: platform.openai.com → API Keys → Create new secret key"),
            "api_format": "openai",
        }),
        "gpt-5.4": aiModelComponent.createObject(this, {
            "name": "GPT Standard",
            "icon": "openai-symbolic",
            "description": Translation.tr("Online | OpenAI's model\nFlagship. Best for complex reasoning, coding, and professional work."),
            "homepage": "https://platform.openai.com",
            "endpoint": "https://api.openai.com/v1/chat/completions",
            "model": "gpt-5.4",
            "requires_key": true,
            "key_id": "openai",
            "key_get_link": "https://platform.openai.com/api-keys",
            "key_get_description": Translation.tr("**Pricing**: paid\n\n**Instructions**: platform.openai.com → API Keys → Create new secret key"),
            "api_format": "openai",
        }),
    }
    property var modelList: Object.keys(root.models)
    property var currentModelId: Persistent.states?.ai?.model || modelList[0]
    // Track built-in model IDs so we know which ones are removable
    readonly property var builtinModelIds: [
        "gemini-3.1-flash-lite", "gemini-3-flash", "gemini-3.1-pro",
        "claude-haiku-4-5", "claude-sonnet-4-6", "claude-opus-4-7",
        "gpt-5.4-nano", "gpt-5.4-mini", "gpt-5.4"
    ]

    function isRemovableModel(modelId) {
        return root.builtinModelIds.indexOf(modelId) === -1;
    }

    function removeModel(modelId) {
        if (!root.isRemovableModel(modelId)) return;
        if (root.currentModelId === modelId) {
            root.setModel(root.modelList[0]); // Switch to first model
        }
        const newModels = Object.assign({}, root.models);
        delete newModels[modelId];
        root.models = newModels;
        root.modelList = Object.keys(root.models);
        root.addMessage(Translation.tr("Removed model: %1").arg(modelId), root.interfaceRole);
    }

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "anthropic": anthropicApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    function addUserModels() {
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            const safeModelName = root.safeModelName(model["model"]);
            root.addModel(safeModelName, model)
        });
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
        }
    }

    property string pendingFilePath: ""

    Component.onCompleted: {
        // Ensure temporary directory exists
        CF.FileUtils.createDir(CF.FileUtils.trimFileProtocol(Directories.temp));
        
        // If stored model no longer exists (e.g. ollama model removed), fall back to first
        const storedId = (Persistent.states?.ai?.model ?? "").toLowerCase();
        const resolvedId = (storedId.length > 0 && modelList.indexOf(storedId) !== -1)
            ? storedId
            : modelList[0];
        setModel(resolvedId, false, resolvedId !== storedId);
        root.addUserModels();
        Qt.callLater(root.loadRecentChatSummaries);
    }

    function guessModelLogo(model) {
        if (model.includes("llama")) return "ollama-symbolic";
        if (model.includes("gemma")) return "google-gemini-symbolic";
        if (model.includes("deepseek")) return "deepseek-symbolic";
        if (model.includes("claude")) return "anthropic-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
    }

    /**
     * Add a local model with OpenAI-compatible API (Ollama, LM Studio, vLLM, etc.)
     * @param modelName display name / ID
     * @param endpoint API endpoint (default: http://localhost:11434/v1/chat/completions for Ollama)
     * @param modelString the model string to send in the API request
     */
    function addLocalModel(modelName, endpoint, modelString) {
        if (!modelName || modelName.length === 0) return;
        const safeId = root.safeModelName(modelString || modelName);
        const actualEndpoint = endpoint || "http://localhost:11434/v1/chat/completions";
        const actualModel = modelString || modelName;
        root.addModel(safeId, {
            "name": root.guessModelName(modelName),
            "icon": root.guessModelLogo(modelName),
            "description": Translation.tr("Local model | %1\nEndpoint: %2").arg(actualModel).arg(actualEndpoint),
            "homepage": actualEndpoint,
            "endpoint": actualEndpoint,
            "model": actualModel,
            "requires_key": false,
            "api_format": "openai",
        });
        root.modelList = Object.keys(root.models);
        root.addMessage(Translation.tr("Added local model: **%1**\nEndpoint: `%2`\nModel: `%3`").arg(root.guessModelName(modelName)).arg(actualEndpoint).arg(actualModel), root.interfaceRole);
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                            "api_format": "openai",
                        })
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        const msg = root.messageByID[id];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
        // Destroy the QML object to free memory
        if (msg && msg.destroy) msg.destroy();
    }

    function removeMessageById(id) {
        const index = root.messageIDs.indexOf(id);
        if (index !== -1) {
            root.removeMessage(index);
        }
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"), 
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()
        if (modelList.indexOf(modelId) !== -1) {
            root.currentModelId = modelId
            if (setPersistentState) root.savePersistentState("model", modelId)

            // Reset thinking state if new model doesn't support it
            const newStyle = root.modelThinkingStyles[modelId] ?? "";
            if (newStyle === "") {
                root.thinkingEnabled = false;
                root.thinkingLevel = 0;
            }
            if (feedback) root.addMessage(Translation.tr("Switched to **%1**").arg(models[modelId].name), Ai.interfaceRole);
            const model = models[modelId]
            // See if policy prevents online models
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (model.requires_key) {
                // If key not there show advice
                if (root.apiKeysLoaded && (!root.apiKeys[model.key_id] || root.apiKeys[model.key_id].length === 0)) {
                    root.addApiKeyAdvice(model)
                }
            }
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported:\n```\n") + modelList.join("\n") + "\n```", Ai.interfaceRole)
        }
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (isNaN(value) || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        root.savePersistentState("temperature", value)
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                root.addMessage(Translation.tr("API key:\n\n```txt\n%1\n```").arg(key), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function exportChat() {
        const msgs = root.messageIDs.map(id => root.messageByID[id]).filter(m => m && m.visibleToUser);
        if (msgs.length === 0) {
            root.addMessage(Translation.tr("Nothing to export"), root.interfaceRole);
            return;
        }
        let md = `# AI Chat Export\n**Date:** ${DateTime.time}, ${DateTime.collapsedCalendarFormat}\n**Model:** ${root.models[root.currentModelId]?.name ?? root.currentModelId}\n\n---\n\n`;
        for (const m of msgs) {
            if (m.role === root.interfaceRole) continue;
            const label = m.role === "user" ? "**User**" : `**${root.models[m.model]?.name ?? "Assistant"}**`;
            md += `### ${label}\n\n${m.content}\n\n---\n\n`;
        }
        const exportPath = `${CF.FileUtils.trimFileProtocol(Directories.downloads)}/ai-chat-${Date.now()}.md`;
        chatExportFile.path = Qt.resolvedUrl(exportPath);
        chatExportFile.setText(md);
        root.addMessage(Translation.tr("Chat exported to `%1`").arg(exportPath), root.interfaceRole);
    }

    FileView {
        id: chatExportFile
    }

    property int chatHistorySlots: 5
    property int chatHistoryIndex: Persistent.states?.ai?.historyIndex ?? 0

    /**
     * Start a new chat: save current to rotating buffer, then clear.
     * Buffer: history_0..history_4 (oldest gets overwritten)
     */
    function newChat() {
        // Save current chat to rotating slot (only if there's actual content)
        if (root.messageIDs.length > 1) {
            try {
                const slotName = `history_${root.chatHistoryIndex % root.chatHistorySlots}`;
                root.saveChat(slotName);
                root.chatHistoryIndex = (root.chatHistoryIndex + 1) % root.chatHistorySlots;
                root.savePersistentState("historyIndex", root.chatHistoryIndex)
            } catch (e) {
                console.log("[AI] newChat: could not save to history:", e);
            }
        }
        // Always clear regardless of save success
        // Destroy all message QML objects to free memory
        for (let i = 0; i < root.messageIDs.length; i++) {
            const msg = root.messageByID[root.messageIDs[i]];
            if (msg && msg.destroy) msg.destroy();
        }
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
        root.generationSpeed = 0;
        root.pendingFilePath = "";
        root.sessionSummary = "";
        // Reload summaries from all history slots
        root.loadRecentChatSummaries();
    }

    // Legacy alias
    function clearMessages() {
        root.newChat();
    }

    // Approximate token count for a string (~4 chars per token)
    function estimateTokens(text) {
        return Math.ceil((text?.length ?? 0) / 4);
    }

    // Get total estimated tokens in the current chat
    function estimateChatTokens() {
        let total = estimateTokens(root.systemPrompt);
        for (let i = 0; i < root.messageIDs.length; i++) {
            const msg = root.messageByID[root.messageIDs[i]];
            if (msg) total += estimateTokens(msg.rawContent);
        }
        return total;
    }

    function trimContextIfNeeded(maxTokens) {
        if (maxTokens <= 0) return;
        if (estimateChatTokens() <= maxTokens) return;
        if (root.messageIDs.length <= 8) return; // need enough messages to compress
        if (root.condensing) return; // Only one summarization at a time

        // Collect oldest messages to compress (keep last 4 messages intact)
        const keepCount = 4;
        const compressCount = root.messageIDs.length - keepCount;
        if (compressCount < 4) return;

        let transcript = "";
        if (root.sessionSummary.length > 0) {
            transcript += `Existing Context Summary: ${root.sessionSummary}\n\n`;
        }
        transcript += "Recent interaction to be compressed:\n";
        for (let i = 0; i < compressCount; i++) {
            const msg = root.messageByID[root.messageIDs[i]];
            if (!msg || msg.role === root.interfaceRole) continue;
            const role = msg.role === "user" ? "User" : "Assistant";
            transcript += `${role}: ${msg.rawContent}\n`;
        }

        root.performSemanticSummary(transcript, compressCount);
    }

    function performSemanticSummary(transcript, countToRemove) {
        const model = models[root.summarizerModelId];
        if (!model) {
            console.log("[AI] Summarizer model not found");
            return;
        }

        const prompt = "You are a conversation summarizer. Your task is to condense the provided conversation history into a concise yet comprehensive summary. " +
                       "Maintain critical key points, technical decisions, and important context. If there is an existing summary provided at the start, " +
                       "incorporate the new information into it to create a single updated summary of the entire session so far. " +
                       "Output ONLY the refreshed summary text.";

        const summarizerData = geminiStrategy.buildRequestData(model, [{ role: "user", rawContent: transcript }], prompt, 0.3, [], "", false, 0);
        
        // Non-streaming request via summarizerProc (batch generateContent)
        const endpoint = geminiStrategy.buildEndpoint(model).replace(":streamGenerateContent", ":generateContent");
        const apiKey = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "";
        
        // SECURITY HARDENING: Use in-memory bash heredoc for summarizer to protect API keys.
        const curlCmd = `curl -s "${endpoint}" -H "Content-Type: application/json" --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(summarizerData))}'`;
        const bashCommand = `bash <<'EOP_SUMMARIZER'\nexport ${root.apiKeyEnvVarName}='${apiKey}'\n${curlCmd}\nEOP_SUMMARIZER\n`;
        
        root.condensing = true;
        summarizerProc.countToRemove = countToRemove;
        summarizerProc.command = ["bash", "-c", bashCommand];
        summarizerProc.running = true;
    }

    Process {
        id: summarizerProc
        property int countToRemove: 0
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { summarizerProc.buffer += data; }
        }
        onExited: (exitCode, exitStatus) => {
            root.condensing = false;
            if (exitCode === 0) {
                try {
                    const response = JSON.parse(summarizerProc.buffer);
                    const newSummary = response.candidates[0]?.content?.parts[0]?.text;
                    if (newSummary && newSummary.length > 0) {
                        root.sessionSummary = newSummary.trim();
                        console.log("[AI] Context compressed. New summary length:", root.sessionSummary.length);
                        // Safely remove messages
                        for (let i = summarizerProc.countToRemove - 1; i >= 0; i--) {
                            root.removeMessage(i);
                        }
                    }
                } catch (e) { console.log("[AI] Summarizer parse error:", e); }
            }
            summarizerProc.buffer = "";
        }
    }

    // Summarize a saved chat JSON into a one-liner
    function summarizeSavedChat(chatJson) {
        try {
            const data = JSON.parse(chatJson);
            if (!data || data.length < 2) return "";
            const userMsgs = data.filter(m => m.role === "user");
            const assistantMsgs = data.filter(m => m.role === "assistant");
            const firstUser = userMsgs[0]?.rawContent?.substring(0, 150) ?? "";
            const lastAssistant = assistantMsgs[assistantMsgs.length - 1]?.rawContent?.substring(0, 100) ?? "";
            if (firstUser.length === 0) return "";
            return `- User asked: ${firstUser.replace(/\n/g, " ")}${lastAssistant.length > 0 ? (" → Assistant: " + lastAssistant.replace(/\n/g, " ")) : ""}`;
        } catch (e) {
            return "";
        }
    }

    // Load summaries from the rotating history buffer (history_0..history_4)
    function loadRecentChatSummaries() {
        try {
            let summaries = [];
            for (let i = 0; i < root.chatHistorySlots; i++) {
                try {
                    chatSummaryLoader.path = `${Directories.aiChats}/history_${i}.summary.txt`;
                    chatSummaryLoader.reload();
                    let content = chatSummaryLoader.text();
                    
                    if (content && content.length > 5) {
                        summaries.push(`- ${content.trim()}`);
                    } else {
                        // Fallback to naive JSON parsing
                        chatSummaryLoader.path = `${Directories.aiChats}/history_${i}.json`;
                        chatSummaryLoader.reload();
                        content = chatSummaryLoader.text();
                        if (!content || content.length < 10) continue;
                        const summary = root.summarizeSavedChat(content);
                        if (summary.length > 0) summaries.push(summary);
                    }
                } catch (e) {
                    continue;
                }
            }
            if (summaries.length > 0) {
                root.previousChatSummary = summaries.join("\n").substring(0, 1500);
            } else {
                root.previousChatSummary = "";
            }
        } catch (e) {
            console.log("[AI] Could not load recent chat summaries:", e);
        }
    }

    Process {
        id: backgroundMemoryProc
        property string chatName: ""
        property string buffer: ""
        stdout: SplitParser {
            onRead: data => { backgroundMemoryProc.buffer += data; }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                try {
                    const response = JSON.parse(backgroundMemoryProc.buffer);
                    const newSummary = response.candidates[0]?.content?.parts[0]?.text;
                    if (newSummary && newSummary.length > 0) {
                        const fileContent = newSummary.trim().replace(/'/g, "'\\''");
                        saveSummaryProc.command = ["bash", "-c", `echo '${fileContent}' > ${Directories.aiChats}/${backgroundMemoryProc.chatName}.summary.txt`];
                        saveSummaryProc.running = true;
                    }
                } catch (e) { console.log("[AI] Memory Summarizer parse error:", e); }
            }
            backgroundMemoryProc.buffer = "";
            backgroundMemoryProc.chatName = "";
        }
    }

    Process { id: saveSummaryProc }

    function generateMemorySummary(chatName, transcript) {
        if (backgroundMemoryProc.running) return;
        const model = models[root.summarizerModelId];
        if (!model) return;
        const prompt = "You are a memory module. Summarize the following chat into a very brief, concise bullet point detailing the context, key decisions, and user's intent. Output ONLY the short summary in the same language as the chat, so it can be injected into the next chat session's memory.";
        const requestData = geminiStrategy.buildRequestData(model, [{ role: "user", rawContent: transcript }], prompt, 0.3, [], "", false, 0);
        
        const endpoint = geminiStrategy.buildEndpoint(model).replace(":streamGenerateContent", ":generateContent");
        const apiKey = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : "";
        if (!apiKey) return;
        
        const curlCmd = `curl -s "${endpoint}" -H "Content-Type: application/json" --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(requestData))}'`;
        const bashCommand = `bash <<'EOP_MEMORY'\nexport ${root.apiKeyEnvVarName}='${apiKey}'\n${curlCmd}\nEOP_MEMORY\n`;
        
        backgroundMemoryProc.chatName = chatName;
        backgroundMemoryProc.command = ["bash", "-c", bashCommand];
        backgroundMemoryProc.running = true;
    }

    Timer {
        id: memorySummaryTimer
        interval: 10000 // 10s idle
        onTriggered: {
            if (root.messageIDs.length < 2) return;
            let transcript = "";
            for (let i = 0; i < root.messageIDs.length; i++) {
                const msg = root.messageByID[root.messageIDs[i]];
                if (!msg || msg.role === root.interfaceRole) continue;
                const role = msg.role === "user" ? "User" : "Assistant";
                transcript += `${role}: ${msg.rawContent}\n`;
            }
            if (transcript.length > 50) {
                root.generateMemorySummary(`history_${root.chatHistoryIndex % root.chatHistorySlots}`, transcript);
            }
        }
    }

    FileView {
        id: chatSummaryLoader
        watchChanges: false
        blockLoading: true
    }



    Process {
        id: requester
        property list<string> baseCommand: ["bash", "-c"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            // Reset adaptive flush interval for next message
            streamFlushTimer.interval = 50;
            // If content was truncated for large response, now show full content
            if (requester.message.content !== requester.message.rawContent) {
                requester.message.content = requester.message.rawContent;
            }
            // Calculate generation speed
            if (root.generationStartTime > 0 && root.tokenCount.output > 0) {
                const elapsed = (Date.now() - root.generationStartTime) / 1000;
                root.generationSpeed = elapsed > 0 ? Math.round(root.tokenCount.output / elapsed * 10) / 10 : 0;
            }
            // Calculate session cost
            if (root.tokenCount.input > 0) {
                root.sessionCost += root.calculateCost(root.currentModelId, root.tokenCount.input, root.tokenCount.output);
            }
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null;
            }
            root.saveChat("lastSession")
            memorySummaryTimer.restart()
            root.responseFinished()
        }

        function makeRequest() {
            // Start generation timer
            root.generationStartTime = Date.now();
            root.generationSpeed = 0;

            const model = models[currentModelId];
            if (!model) {
                root.addMessage(Translation.tr("No model selected or model not found. Use /model to pick one."), root.interfaceRole);
                return;
            }

            // Fetch API keys if needed
            if (model.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Auto-trim context if it's getting too large (~800k chars ≈ 200k tokens) */
            root.trimContextIfNeeded(200000);

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            // Filter out null entries and interface messages
            let filteredMessageArray = messageArray.filter(message => message != null && message.role !== Ai.interfaceRole);

            // Inject session summary at the beginning if present
            if (root.sessionSummary.length > 0) {
                const summaryMsg = root.aiMessageComponent.createObject(root, {
                    "role": "user",
                    "rawContent": `[IMPORTANT CONTEXT SUMMARY OF PREVIOUS CONVERSATION PART: ${root.sessionSummary}]`,
                    "visibleToUser": false,
                    "done": true
                });
                filteredMessageArray.unshift(summaryMsg);
            }

            const toolsForFormat = root.tools[model.api_format] ?? root.tools["openai"];
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, toolsForFormat[root.currentTool] ?? [], root.pendingFilePath, root.thinkingEnabled, root.thinkingLevel);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            
            // SECURITY HARDENING: Pass the entire request script through a bash heredoc 
            // to avoid writing sensitive API data to disk.
            const bashCommand = `bash <<'EOP_AI_REQUEST'\n${scriptContent}\nEOP_AI_REQUEST\n`;
            
            requester.command = ["bash", "-c", bashCommand];
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;

                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);

                    if (result.functionCall) {
                        // Flush content immediately before function call
                        streamFlushTimer.flushNow();
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        streamFlushTimer.flushNow();
                        requester.markDone();
                    } else {
                        // Schedule debounced content flush
                        streamFlushTimer.restart();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    streamFlushTimer.restart();
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            streamFlushTimer.flushNow();
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            
            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }

            // Handle curl/network errors
            if (exitCode !== 0 && requester.message.content.length === 0) {
                requester.message.content = Translation.tr("**Connection error** (exit code %1). Check your network and API key.").arg(exitCode);
                requester.message.rawContent = requester.message.content;
            }

            // Clean up fileBase64 to free memory (keep path only)
            for (let i = 0; i < root.messageIDs.length; i++) {
                const msg = root.messageByID[root.messageIDs[i]];
                if (msg && msg.fileBase64 && msg.fileBase64.length > 0 && msg.done) {
                    msg.fileBase64 = ""; // Free memory, base64 data no longer needed
                }
            }
        }
    }

    // Debounced content flush: batches rapid token updates into intervals
    // This prevents re-parsing markdown on every single token
    Timer {
        id: streamFlushTimer
        interval: 50
        repeat: false

        // Thresholds for adaptive rendering
        readonly property int mediumContentThreshold: 12000  // Start mild throttling
        readonly property int largeContentThreshold: 40000   // Heavy throttling

        function flushNow() {
            streamFlushTimer.stop();
            if (!requester.message) return;
            const msg = requester.message;

            // Strip hidden internal markers from UI content
            let cleanContent = msg.rawContent.replace(/\[\[\s*(Function|Output of).*?\s*\]\]\n?/g, "").trim();

            if (msg.contentBeforeCommand && msg.contentBeforeCommand.length > 0) {
                // Check if the model has started sending text after the tool call sequence
                const lastMarkerPos = msg.rawContent.lastIndexOf("]]");
                const hasNewContent = lastMarkerPos !== -1 && msg.rawContent.length > lastMarkerPos + 5;
                
                if (hasNewContent) {
                    msg.contentBeforeCommand = ""; // Resume normal flushing
                } else {
                    return; // Still in command mode / waiting for model to actually start text
                }
            }

            if (msg.content === cleanContent) return;

            const len = cleanContent.length;

            // For large responses during active streaming: throttle hard.
            if (!msg.done && len > largeContentThreshold) {
                const newInterval = Math.min(2000, 80 + Math.floor(len / 1000) * 15);
                if (streamFlushTimer.interval !== newInterval)
                    streamFlushTimer.interval = newInterval;

                const tail = cleanContent.slice(-30000);
                const notice = `> ⚠️ *Large response — showing last 30K of ${Math.round(len/1000)}K chars. Full content sent to model.*\n\n`;
                msg.content = notice + tail;
                return;
            }

            if (!msg.done && len > mediumContentThreshold) {
                const newInterval = Math.min(300, 50 + Math.floor(len / 2000) * 10);
                if (streamFlushTimer.interval !== newInterval)
                    streamFlushTimer.interval = newInterval;
            } else {
                streamFlushTimer.interval = 50;
            }

            msg.content = cleanContent;
        }

        onTriggered: flushNow()
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        root.addMessage(message, "user");
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerateById(id) {
        const messageIndex = root.messageIDs.indexOf(id);
        if (messageIndex === -1) return;
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "visibleToUser": false,
            "thinking": false,
            "done": true,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageByID[id] = aiMessage;
        root.messageIDs = [...root.messageIDs, id];
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false;
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"));
        requester.makeRequest();
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false;

        // Instead of creating a separate function output message,
        // we'll track output directly on the assistant message
        commandExecutionProc.assistantMessage = message;
        commandExecutionProc.outputMessage = createFunctionOutputMessage(message.functionName, "", false);
        const id = idForMessage(commandExecutionProc.outputMessage);
        root.messageByID[id] = commandExecutionProc.outputMessage; // Set object FIRST
        root.messageIDs = [...root.messageIDs, id]; // Then trigger the list update

        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.running = true;
    }

    function isDangerousCommand(cmd) {
        if (!cmd) return false;
        const dangerousPatterns = [
            // Deletion or modification of root/system dirs
            /\brm\s+.*-rf?.*\s+\/(?:bin|boot|dev|etc|home|lib|lib64|lost\+found|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|[^\w\-]|$)/,
            /\bmv\s+.*\s+\/(?:bin|boot|dev|etc|home|lib|lib64|lost\+found|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|[^\w\-]|$)/,
            /\bchmod\s+.*-R.*\s+\/(?:bin|boot|dev|etc|home|lib|lib64|lost\+found|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|[^\w\-]|$)/,
            /\bchown\s+.*-R.*\s+\/(?:bin|boot|dev|etc|home|lib|lib64|lost\+found|mnt|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|[^\w\-]|$)/,
            // Low level disk access
            /dd\s+.*of=\/dev\//,
            /\bmkfs\b/,
            /\bformat\b/,
            // System control
            /\breboot\b/,
            /\bshutdown\b/,
            /\bpoweroff\b/,
            /\bhalt\b/
        ];
        return dangerousPatterns.some(pattern => pattern.test(cmd));
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData assistantMessage
        property AiMessageData outputMessage
        property string collectedOutput: ""
        property int maxOutputChars: 8000 // Truncate command output to prevent huge context
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                // Strip ANSI escape codes (colors, cursor moves, etc)
                const cleanOutput = output.replace(/\u001b\[[0-9;]*[a-zA-Z]/g, "");
                
                commandExecutionProc.collectedOutput += cleanOutput + "\n";
                // Truncate if too large — keep last N chars
                if (commandExecutionProc.collectedOutput.length > commandExecutionProc.maxOutputChars) {
                    commandExecutionProc.collectedOutput = "[...truncated...]\n" + commandExecutionProc.collectedOutput.slice(-commandExecutionProc.maxOutputChars);
                }
                // Update the hidden function output message for API context
                commandExecutionProc.outputMessage.functionResponse = commandExecutionProc.collectedOutput;
                const outputContent = `[[ Output of ${commandExecutionProc.outputMessage.functionName} ]]\n\n<think>\n${commandExecutionProc.collectedOutput}\n</think>`;
                commandExecutionProc.outputMessage.rawContent = outputContent;
                commandExecutionProc.outputMessage.content = outputContent;
                // Update the UI inline: show $ command + last 3 lines of output
                const cmdName = commandExecutionProc.shellCommand;
                const lines = commandExecutionProc.collectedOutput.trim().split("\n");
                const lastLines = lines.slice(-3).join("\n");
                const baseContent = commandExecutionProc.assistantMessage.contentBeforeCommand ?? commandExecutionProc.assistantMessage.content;
                commandExecutionProc.assistantMessage.content = baseContent + `\n\n\`\`\`command\n$ ${cmdName}\n${lastLines}\n\`\`\``;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.outputMessage.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            // Final UI update with exit code
            const cmdName = commandExecutionProc.shellCommand;
            const lines = commandExecutionProc.collectedOutput.trim().split("\n");
            const lastLines = lines.slice(-5).join("\n");
            const exitLabel = exitCode === 0 ? "✓" : `✗ exit ${exitCode}`;
            const baseContent = commandExecutionProc.assistantMessage.contentBeforeCommand ?? commandExecutionProc.assistantMessage.content;
            commandExecutionProc.assistantMessage.content = baseContent + `\n\n\`\`\`command\n$ ${cmdName} ${exitLabel}\n${lastLines}\n\`\`\``;
            commandExecutionProc.collectedOutput = "";
            requester.makeRequest();
        }
    }

    // Web search process for OpenAI web_search_preview tool
    Process {
        id: webSearchProc
        property string query: ""
        property AiMessageData message
        property string functionName: "web_search_preview"
        property string collectedOutput: ""

        stdout: SplitParser {
            onRead: (output) => { webSearchProc.collectedOutput += output; }
        }
        onExited: (exitCode, exitStatus) => {
            const results = webSearchProc.collectedOutput.trim();
            const response = results.length > 0
                ? Translation.tr("Search results for \"%1\":\n\n%2").arg(webSearchProc.query).arg(results)
                : Translation.tr("No results found for \"%1\".").arg(webSearchProc.query);
            root.addFunctionOutputMessage(webSearchProc.functionName, response);
            webSearchProc.collectedOutput = "";
            requester.makeRequest();
        }
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (name === "switch_to_search_mode") {
            root.currentTool = "search";
            root.postResponseHook = () => {
                root.currentTool = Qt.binding(function() { return Config?.options.ai.tool ?? "search"; });
            };
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "web_search_preview") {
            // OpenAI search tool — run a quick web search and return results
            const query = args?.query;
            if (!query || query.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("No query provided."));
                requester.makeRequest();
                return;
            }
            // Notify user a search is happening
            message.content += `\n\n\`\`\`command\n🔍 Searching: ${query}\n\`\`\``;
            // Use xdg-open or a simple curl-based DDG search summary
            webSearchProc.query = query;
            webSearchProc.message = message;
            webSearchProc.functionName = name;
            webSearchProc.command = ["bash", "-c", `curl -s -A 'Mozilla/5.0' 'https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}' | grep -oP '(?<=<a class="result__snippet">)[^<]+' | head -5 | tr '\n' ' '`];
            webSearchProc.running = true;
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                requester.makeRequest();
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
            addFunctionOutputMessage(name, Translation.tr("Config updated: %1 = %2").arg(key).arg(value));
            requester.makeRequest();
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            // Save content state before command for clean inline updates
            message.contentBeforeCommand = message.content;
            // Show command inline in the UI only (content), not rawContent
            message.content += `\n\n\`\`\`command\n$ ${args.command}\n...\n\`\`\``;
            message.functionPending = true;
            message.functionName = name; // Ensure functionName is set for UI usage

            // Logic: Auto-approve only if the switch is ON AND the command is NOT dangerous
            const dangerous = root.isDangerousCommand(args.command);
            if (dangerous) {
                root.addMessage(Translation.tr("⚠️ **Dangerous command detected** — manual approval required:\n```bash\n%1\n```").arg(args.command), root.interfaceRole);
            }
            if (root.functionsAutoConfirm && !dangerous) {
                root.approveCommand(message);
            }
        } else {
            root.addMessage(Translation.tr("Unknown function call: %1").arg(name), root.interfaceRole);
        }
    }

    function chatToJson() {
        return root.messageIDs
            .filter(id => root.messageByID[id] != null)
            .map(id => {
                const message = root.messageByID[id]
                return ({
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "fileTextContent": message.fileTextContent,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": false,
                    "done": true,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionCallParts": message.functionCallParts,
                    "thoughtSignature": message.thoughtSignature,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                })
            })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages()
            const saveIds = saveData.map((_, i) => {
                // Use timestamp+index to avoid collision with live message IDs
                return `loaded_${Date.now()}_${i}`;
            });
            root.messageIDs = saveIds;
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[saveIds[i]] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "fileTextContent": message.fileTextContent ?? "",
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                });
                // Restore Gemini thought signature data (dynamic props, set after creation)
                if (message.functionCallParts) root.messageByID[saveIds[i]].functionCallParts = message.functionCallParts;
                if (message.thoughtSignature) root.messageByID[saveIds[i]].thoughtSignature = message.thoughtSignature;
            }
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }

    function savePersistentState(key, value) {
        if (!Persistent.states) return;
        let ai = Persistent.states.ai || {};
        ai[key] = value;
        Persistent.states = Object.assign({}, Persistent.states, { ai: ai });
    }
}
