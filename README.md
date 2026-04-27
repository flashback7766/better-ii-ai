# Better Illogical Impulse AI Sidebar

An agentic AI assistant sidebar for the end-4/dots-hyprland desktop environment. Built with QML and performance in mind, designed to master workflows through tool use.

> [!IMPORTANT]
> **Status: Work In Progress (WIP)**
> Currently, the **Gemini 3.1** model family has the most robust support and is highly recommended for the best experience.

##  Key Features

- **Agentic Workflows (Function Calling)**:
    - **Shell Integration**: Execute commands directly from the chat (with safety manual approval for dangerous commands).
    - **Web Search**: Real-time information retrieval via Google Search (Gemini exclusive).
    - **Context Awareness**: Attach files, read codebases, and interact with your local system.
- **Adaptive Context Management**:
  - **Context Compression**: Automatically sumzmarizes chat history when approaching token limits (~32k tokens) to maintain long-term coherence.
  - **History Rotation**: 5 dynamic slots for chat sessions. (Like gemini.google.com memorizing something for a while and then forgetting it.)
- **Model Picker**: Scrollable, interactive list with quick-switch support.
- **Real-time Streaming**: Optimized rendering for high-speed token output.

## Supported Models

| Provider | Models | Support Level |
|----------|---------|---------------|
| **Google** | Gemini 3.1 (Flash-Lite, Flash, Pro) | **Full (Recommended)** |
| **Anthropic** | Claude 4.7 (Haiku, Sonnet, Opus) | High |
| **OpenAI** | GPT-5.4 (Nano, Mini, Full) | High |
| **Local** | Any LLM Server with OpenAI API endpoint and function calling support | Via `/addlocal` |

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl + 1..9` | Quick-switch between models |
| `Ctrl + Shift + O` | Start new fresh chat |
| `Tab` | Accept command suggestion |
| `Up / Down` | Navigate command history / suggestions |
| `Escape` | Close popups or abort generation |
| `Ctrl + Shift + .` | Emergency abort all processes |

## Commands

- `/new` — Save current chat and start a fresh session.
- `/stop` — Abort current generation.
- `/addlocal` — Add a local provider (Ollama/OpenWebUI).
- `/export` — Export current chat to a Markdown file.
- `/temp [0-2]` — Adjust model temperature (randomness).
- `/attach [path]` — Attach a file to the conversation.
- `/test` — Run a UI rendering test with various markdown elements.

## Installation

Run the provided installation script:
```bash
bash install.sh
```
*The script will automatically back up your existing configuration before applying changes.*

---
*Built with ❤️ for the Quickshell community.*
*If end-4 see this, please contact with me.*
