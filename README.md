# Better Illogical Impulse AI Sidebar

A drop-in replacement for the AI sidebar shipped with [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
(the Illogical Impulse setup, built on [Quickshell](https://quickshell.outfoxxed.me/)). The goal is a
faster, more capable assistant that fits the existing shell without changing the rest of the desktop.

> **Status:** work in progress. Everything in this README is implemented, but expect rough edges.
> Gemini currently has the most complete behaviour and is the recommended default.

## What it does

- **Multi-provider chat** with streaming responses. Built-in support for Google Gemini,
  Anthropic Claude, OpenAI GPT, and any OpenAI-compatible local server (Ollama, LM Studio,
  vLLM, etc.) via `/addlocal`.
- **Function calling** through a single tool layer that all providers share:
  - `run_shell_command` — executes commands locally. A built-in pattern matcher flags
    obviously destructive commands (`rm -rf /`, `dd of=/dev/…`, `curl … | sh`, fork bombs,
    `git push --force`, etc.) and gates them behind explicit user approval. Safe commands
    run automatically.
  - `get_shell_config` / `set_shell_config` — reads and edits the desktop shell config
    so the model can change settings on request.
  - Web search — Google Search grounding for Gemini; for OpenAI/Anthropic the model can
    call a `web_search_preview` tool that scrapes DuckDuckGo HTML for snippets.
- **File attachments.** Images go inline as base64 (all providers). Text/code/PDF source
  is read from disk and sent as a text block — the head of the file (~100 KB) is included
  so the model can analyse it without an upload step.
- **Adaptive context window.** When the running chat goes over ~32 k estimated tokens,
  the oldest messages are condensed by `gemini-3.1-flash-lite` into a 3–4 line semantic
  summary that is reinjected as system context. The most recent four messages are always
  kept verbatim.
- **Rotating chat history.** Five slots (`history_0` … `history_4`) act as a ring buffer.
  Each archived chat gets its own background-generated one-line summary; the summaries
  from all live slots are stitched into the system prompt under `{PREVIOUS_CHAT_HISTORY}`,
  so the assistant carries some memory of what you talked about without dragging the full
  transcripts into every request.
- **Prompt caching for Anthropic.** System prompt, tool schema, and a stable suffix of
  the conversation are tagged with `cache_control: ephemeral` so repeat turns hit the
  Anthropic prompt cache.
- **Cost and speed tracking.** Per-turn input/output token counts, cache-read and
  cache-write tokens, tokens-per-second, and a running session cost estimate based on
  published per-million prices.
- **Adaptive UI throttling.** Token-by-token rendering is debounced; very large
  responses (>40 k characters) switch to tail-only display while still streaming the
  full text into the model context.
- **Persisted state.** The active chat is saved on every change (`lastSession.json`),
  so a Quickshell restart resumes where you left off.

## Supported models

| Provider     | Models                                              | Notes                       |
|--------------|-----------------------------------------------------|-----------------------------|
| Google       | Gemini 3.1 Flash-Lite, Gemini 3 Flash, Gemini 3.1 Pro | Recommended; best tool use  |
| Anthropic    | Claude Haiku 4.5, Claude Sonnet 4.6, Claude Opus 4.7  | Prompt caching enabled      |
| OpenAI       | GPT-5.4 Nano, GPT-5.4 Mini, GPT-5.4                   | Function calling supported  |
| Local (any)  | Anything reachable over an OpenAI-compatible endpoint | Added with `/addlocal`      |

The list of installed Ollama models is auto-discovered at startup.

## Installation

The repository ships drop-in QML files that override the corresponding pieces of the
Illogical Impulse sidebar. Run the installer:

```bash
bash install.sh
```

It backs up the existing files before copying the new ones in place.
And after, set this system prompt to get better expirience
```
/prompt /home/"youruser"/.config/quickshell/ii/defaults/ai/prompts/ii-Default.md 
```

## Keyboard shortcuts

| Shortcut             | Action                                |
|----------------------|---------------------------------------|
| `Ctrl + 1` … `Ctrl + 9` | Quick-switch between models         |
| `Ctrl + Shift + O`   | Start a new chat (saves to history)   |
| `Ctrl + Shift + .`   | Emergency abort (kills all processes) |
| `Tab`                | Accept the current command suggestion |
| `Up` / `Down`        | Navigate history and suggestions      |
| `Esc`                | Close popups, or abort generation     |

## Slash commands

| Command                  | Effect                                                                |
|--------------------------|-----------------------------------------------------------------------|
| `/model NAME`            | Switch active model                                                   |
| `/tool NAME`             | Set the active tool group: `functions`, `search`, or `none`           |
| `/prompt PATH`           | Load a system prompt from a file (`/prompt get` to print the current) |
| `/key VALUE`             | Store an API key for the current provider (`/key get` to print it)    |
| `/temp 0..2`             | Set sampling temperature (`/temp get` to print it)                    |
| `/attach PATH`           | Attach a file to the next user message                                |
| `/addlocal NAME [URL]`   | Register a local OpenAI-compatible model (defaults to Ollama)         |
| `/save NAME`             | Save the current chat under a name                                    |
| `/load NAME`             | Load a saved chat                                                     |
| `/new`                   | Archive the current chat to the rotating buffer and start a new one   |
| `/clear`                 | Clear the chat without archiving                                      |
| `/copy`                  | Copy the last assistant message to the clipboard                      |
| `/stop`                  | Stop every running AI process                                         |
| `/export`                | Export the chat to a Markdown file in `~/Downloads`                   |
| `/test`                  | Render a markdown showcase (debug)                                    |

## Configuration knobs

The relevant fields in the shell config are:

- `ai.systemPrompt` — base system prompt. Supports the substitutions
  `{DISTRO}`, `{DATETIME}`, `{WINDOWCLASS}`, `{DE}`, `{PREVIOUS_CHAT_CONTEXT}`,
  `{PREVIOUS_CHAT_HISTORY}`.
- `ai.tool` — default tool group (`functions` / `search` / `none`).
- `ai.extraModels` — list of additional model definitions (the same shape used by the
  built-ins) loaded on startup.
- `policies.ai` — `2` disables online providers entirely; only local models are reachable.

API keys live in the keyring storage shipped with the rest of Illogical Impulse and are
keyed by provider (`gemini`, `anthropic`, `openai`).

## Acknowledgements

The base shell, sidebar layout, and most of the visual language come from
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland). This project only
re-implements the AI sidebar piece on top of it.
