# 🌌 Better II AI Sidebar

A premium, agentic AI assistant sidebar for the Quickshell desktop environment. Built with QML and performance in mind, designed to master workflows through autonomous tool use and state-of-the-art reasoning.

> [!IMPORTANT]
> **Status: Work In Progress (WIP)**
> Currently, the **Gemini 3.1** model family has the most robust support and is highly recommended for the best experience.

## ✨ Key Features

- **Invisible Reasoning**: All "thinking" blocks have been removed from the UI for a cleaner experience. Models still reason in the background, but the interface stays focused on the results.
- **Agentic Workflows (Function Calling)**:
  - **Shell Integration**: Execute commands directly from the chat (with safety manual approval for dangerous commands).
  - **Web Search**: Real-time information retrieval via Google Search (Gemini exclusive).
  - **Context Awareness**: Attach files, read codebases, and interact with your local system.
- **Adaptive Context Management**:
  - **Context Compression**: Automatically summarizes chat history when approaching token limits (~32k tokens) to maintain long-term coherence.
  - **History Rotation**: 5 dynamic slots for chat sessions.
- **Premium UI/UX**:
  - **Modern Aesthetics**: Glassmorphism, smooth animations, and a curated dark theme.
  - **Model Picker**: Scrollable, interactive list with quick-switch support.
  - **Real-time Streaming**: Optimized debounced rendering for high-speed token output.

## 🤖 Supported Models

| Provider | Models | Support Level |
|----------|---------|---------------|
| **Google** | Gemini 3.1 (Flash-Lite, Flash, Pro) | **Full (Recommended)** |
| **Anthropic** | Claude 4.5/4.6/4.7 (Haiku, Sonnet, Opus) | High |
| **OpenAI** | GPT-5.4 (Nano, Mini, Full) | High |
| **Local** | Ollama, LM Studio, vLLM | Via `/addlocal` |

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl + 1..9` | Quick-switch between models |
| `Ctrl + Shift + O` | Start new fresh chat |
| `Tab` | Accept command suggestion |
| `Up / Down` | Navigate command history / suggestions |
| `Escape` | Close popups or abort generation |
| `Ctrl + Shift + .` | Emergency abort all processes |

## 🛠 Commands

- `/new` — Save current chat and start a fresh session.
- `/stop` — Abort current generation.
- `/addlocal` — Add a local provider (Ollama/OpenWebUI).
- `/export` — Export current chat to a Markdown file.
- `/temp [0-2]` — Adjust model temperature (randomness).
- `/attach [path]` — Attach a file to the conversation.
- `/test` — Run a UI rendering test with various markdown elements.

## 📦 Installation

Run the provided installation script:
```bash
bash install.sh
```
*The script will automatically back up your existing configuration before applying changes.*

---
*Built with ❤️ for the Quickshell community.*
