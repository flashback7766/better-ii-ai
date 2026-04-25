# Better-ii-ai — AI Sidebar for dots-hyprland

A drop-in multi-provider AI chat sidebar extension for the [dots-hyprland](https://github.com/end-4/dots-hyprland) Quickshell config. Supports streaming, extended thinking, function calling (web search, shell commands, config editing), file attachments, chat history, and more.

---

## Features

| Feature | Details |
|---|---|
| **Providers** | Gemini, OpenAI, Anthropic, Ollama (auto-detect), any OpenAI-compatible endpoint |
| **Streaming** | Adaptive flush throttle — smooth even for very large responses |
| **Extended thinking** | Anthropic `budget_tokens` (toggle on/off) · Gemini `thinking_level` (Off / Low / Med / High) |
| **Function calling** | Web search · run shell commands · read/edit shell config |
| **File attachments** | Images via `/attach PATH` (Gemini & Anthropic) |
| **Chat history** | 5-slot rotating buffer · `/save` / `/load` · Markdown export |
| **Context compression** | Auto-trims at ~200K tokens to prevent context overflow |
| **Cross-chat context** | `{PREVIOUS_CHAT_CONTEXT}` substitution in system prompts |
| **Session stats** | Token counts · generation speed (tok/s) · estimated cost ($) |
| **Keyboard shortcuts** | `Ctrl+1–9` model switch · `Ctrl+Shift+O` new chat · `Escape` close popups |

---

## Requirements

- [Quickshell](https://quickshell.outfoxxed.me/) with the `ii` config at `~/.config/quickshell/ii`
- `curl` (for API requests)
- `base64`, `file` (for image attachments)
- `ollama` (optional, for local models)

---

## Installation

```bash
git clone https://github.com/flashback7766/better-ii-ai.git
cd better-ii-ai
bash install.sh
```

The script will:
1. **Back up** your existing files to `~/.config/quickshell/ii/.backup-ai-<timestamp>`
2. Copy all files into the correct locations
3. Print a summary of available commands

Restart Quickshell to apply:
```bash
pkill quickshell && quickshell & # By default, it should do an auto-reload.
```

To rollback:
```bash
cp -r ~/.config/quickshell/ii/.backup-ai-<timestamp>/* ~/.config/quickshell/ii/
```

---

## API Keys

Set the API key for the currently selected model:
```
/key YOUR_API_KEY
```

View the current key:
```
/key get
```

Keys are stored via `KeyringStorage` (not in plain text files).

---

## Commands

| Command | Description |
|---|---|
| `/new` | Save current chat to history buffer and start fresh |
| `/stop` | Abort all running AI processes |
| `/model MODEL_ID` | Switch model (e.g. `/model gemini-3-flash`) |
| `/key API_KEY` | Set API key for current model |
| `/key get` | Show current model's API key |
| `/tool TOOL` | Set tool: `functions`, `search`, or `none` |
| `/temp VALUE` | Set temperature 0–2 (default 0.5) |
| `/prompt get` | Print current system prompt |
| `/prompt PATH` | Load system prompt from file |
| `/attach PATH` | Attach a file to the next message |
| `/addlocal MODEL [ENDPOINT]` | Add a local model (Ollama / LM Studio / vLLM) |
| `/save NAME` | Save current chat to a named file |
| `/load NAME` | Load a named chat |
| `/export` | Export chat to Markdown in Downloads |
| `/test` | Run a Markdown rendering test |

---

## Models

### Built-in

| ID | Name | Provider |
|---|---|---|
| `gemini-3.1-flash-lite` | Gemini 3.1 Flash-Lite | Google |
| `gemini-3-flash` | Gemini 3 Flash | Google |
| `gemini-3.1-pro` | Gemini 3.1 Pro | Google |
| `claude-haiku-4-5` | Claude Haiku 4.5 | Anthropic |
| `claude-sonnet-4-6` | Claude Sonnet 4.6 | Anthropic |
| `claude-opus-4-7` | Claude Opus 4.7 | Anthropic |
| `gpt-5.4-nano` | GPT-5.4 Nano | OpenAI |
| `gpt-5.4-mini` | GPT-5.4 Mini | OpenAI |
| `gpt-5.4` | GPT-5.4 | OpenAI |

Ollama models are **auto-detected** on startup if Ollama is running.

### Adding a Local Model

```
/addlocal llama3.3                                          # Ollama (default)
/addlocal deepseek-r1:32b                                   # Ollama with tag
/addlocal my-model http://localhost:1234/v1/chat/completions # LM Studio
/addlocal model http://192.168.1.10:8000/v1/chat/completions # Remote vLLM
```

### Adding Models via Config

In your Quickshell config's `ai.extraModels`:
```json
[
  {
    "name": "My Custom Model",
    "model": "my-model-id",
    "endpoint": "https://api.example.com/v1/chat/completions",
    "api_format": "openai",
    "requires_key": true,
    "key_id": "my_provider"
  }
]
```

---

## System Prompt Substitutions

Use these placeholders in your system prompt file:

| Placeholder | Replaced with |
|---|---|
| `{DISTRO}` | Linux distro name |
| `{DATETIME}` | Current date and time |
| `{WINDOWCLASS}` | Active window app ID |
| `{DE}` | Desktop environment + windowing system |
| `{PREVIOUS_CHAT_CONTEXT}` | Summaries of recent chat history slots |

---

## Architecture

```
Ai.qml                  — Singleton service: models, API keys, message state, function dispatch
AiChat.qml              — UI: message list, input bar, model picker, functions popup
AiMessage.qml           — Single message card (header, content blocks, controls)
AiMessageData.qml       — QML object schema for a single message
MessageCodeBlock.qml    — Syntax-highlighted, copyable code block
MessageThinkBlock.qml   — Collapsible thinking / command output block
GeminiApiStrategy.qml   — Gemini API: streaming JSON parser, thinking_level, file upload
AnthropicApiStrategy.qml — Anthropic API: SSE parser, extended thinking, tool use
OpenAiApiStrategy.qml   — OpenAI-compatible API: SSE parser, function calling
install.sh              — Backup + install script
```

---

## License

[MIT](LICENSE) — or whatever license this project uses.
