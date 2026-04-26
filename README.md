# Better-ii-ai — Advanced AI Sidebar for Quickshell

Better-ii-ai is a powerful, multi-provider AI chat extension for the [dots-hyprland](https://github.com/end-4/dots-hyprland) Quickshell configuration. It provides a seamless interface for interacting with various LLMs (Google Gemini, Anthropic Claude, OpenAI GPT, and local Ollama) directly from your desktop sidebar.
    
> [!TIP]
> **Personal Recommendation**: Use **Google Gemini** models (Flash/Pro) whenever possible. They are currently the most stable, cost-effective, and feature-rich options in this suite. Claude models can sometimes experience API issues or higher latency.

---

## ✨ Key Features

| Feature | Description |
|---|---|
| **Multi-Provider** | Support for **Google Gemini**, **Anthropic Claude**, **OpenAI GPT**, and any OpenAI-compatible API. |
| **Local Models** | Automatic detection of **Ollama** models; support for **LM Studio** and **vLLM** via custom endpoints. |
| **Tool Calling** | Native support for **Web Search**, running **Bash commands**, and editing **Shell configuration** files. |
| **Extended Thinking** | Full support for **Anthropic's Thinking Mode** (budget tokens) and **Gemini's Thinking Levels** (Low/Med/High). |
| **Adaptive Context** | Intelligent context compression (summarization) at ~15K tokens to keep conversations fast and cost-effective. |
| **Rich UI** | Smooth animations, syntax-highlighted code blocks, square control buttons, and a scrollable model picker. |
| **File Support** | Attach images, PDFs, or code files via `/attach` (supported by Gemini and Anthropic). |
| **Chat Management** | 5-slot rotating history buffer, persistent chat saving/loading, and Markdown export. |

---

## 🚀 Installation

```bash
git clone https://github.com/flashback7766/better-ii-ai.git
cd better-ii-ai
bash install.sh
```

### What the script does:
1. **Backs up** your current configuration to `~/.config/quickshell/ii/.backup-ai-<timestamp>`.
2. **Installs** all QML components, services, and assets into your Quickshell directory.
3. **Optimizes** the layout for the latest dots-hyprland features.

**To apply changes:** Quickshell should reload and apply changes automatically upon file modification.

---

## ⌨️ Commands

| Command | Usage |
|---|---|
| `/new` | Start a fresh chat (saves current to history buffer). |
| `/clear` | Clear chat immediately without saving to history. |
| `/stop` | Stop all active AI generation and processes. |
| `/model ID` | Switch to a specific model (e.g., `/model claude-sonnet-4-6`). |
| `/tool TOOL` | Set active toolset: `functions`, `search`, or `none`. |
| `/key KEY` | Set the API key for the current provider. |
| `/key get` | Show the API key for the current provider. |
| `/attach PATH` | Attach a file (image/PDF/text) to the next request. |
| `/temp VALUE` | Set generation temperature (0–2). |
| `/addlocal NAME` | Add a local model (Ollama defaults, or provide a URL). |
| `/save NAME` | Save the current session to a named file. |
| `/load NAME` | Load a saved session. |
| `/export` | Export the current chat to Markdown in `~/Downloads`. |

---

## 🛠 Shortcuts

- **Ctrl + 1–9**: Quickly switch between the first 9 models in your list.
- **Ctrl + Shift + O**: Start a new chat immediately.
- **Escape**: Close any open popups or stop current generation.
- **Ctrl + S**: Save changes when editing a message.

---

## 📂 Architecture

- **`Ai.qml`**: Core service managing message state, API keys, and tool execution.
- **`AiChat.qml`**: Main UI container for the chat history and input.
- **`AiMessage.qml`**: Individual message delegate with square control buttons (Regenerate, Copy, Edit, Delete).
- **`ApiStrategies/`**: Specialized handlers for different API formats (Anthropic, Gemini, OpenAI).
- **`MessageBlocks/`**: UI components for rendering Text, Code (syntax-highlighted), and Thinking blocks.

---

## 📝 License

This project is open-source. See the project repository for license details.
