#!/bin/bash
# Install script for AI sidebar improvements
# Run from the directory containing the downloaded files

set -e

# Auto-detect quickshell config path
QS_BASE="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii"

if [ ! -d "$QS_BASE" ]; then
    echo "❌ Quickshell config not found at $QS_BASE"
    echo "   Set QS_BASE manually: QS_BASE=/path/to/quickshell/ii bash install.sh"
    exit 1
fi

SERVICES="$QS_BASE/services"
AI_DIR="$SERVICES/ai"
SIDEBAR="$QS_BASE/modules/ii/sidebarLeft"
SIDEBAR_AI="$SIDEBAR/aiChat"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backup
BACKUP="$QS_BASE/.backup-ai-$(date +%Y%m%d-%H%M%S)"
echo "📦 Creating backup at $BACKUP"
mkdir -p "$BACKUP/services/ai" "$BACKUP/modules/ii/sidebarLeft/aiChat"
cp "$SERVICES/Ai.qml" "$BACKUP/services/" 2>/dev/null || true
cp "$AI_DIR/AiMessageData.qml" "$BACKUP/services/ai/" 2>/dev/null || true
cp "$AI_DIR/AnthropicApiStrategy.qml" "$BACKUP/services/ai/" 2>/dev/null || true
cp "$AI_DIR/GeminiApiStrategy.qml" "$BACKUP/services/ai/" 2>/dev/null || true
cp "$AI_DIR/OpenAiApiStrategy.qml" "$BACKUP/services/ai/" 2>/dev/null || true
cp "$SIDEBAR/AiChat.qml" "$BACKUP/modules/ii/sidebarLeft/" 2>/dev/null || true
cp "$SIDEBAR_AI/MessageThinkBlock.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/MessageCodeBlock.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/AiMessage.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true

echo "📋 Installing files..."

cp "$SCRIPT_DIR/Ai.qml" "$SERVICES/Ai.qml"
echo "  ✅ services/Ai.qml"

cp "$SCRIPT_DIR/AiMessageData.qml" "$AI_DIR/AiMessageData.qml"
echo "  ✅ services/ai/AiMessageData.qml"

cp "$SCRIPT_DIR/AnthropicApiStrategy.qml" "$AI_DIR/AnthropicApiStrategy.qml"
echo "  ✅ services/ai/AnthropicApiStrategy.qml"

cp "$SCRIPT_DIR/GeminiApiStrategy.qml" "$AI_DIR/GeminiApiStrategy.qml"
echo "  ✅ services/ai/GeminiApiStrategy.qml"

cp "$SCRIPT_DIR/OpenAiApiStrategy.qml" "$AI_DIR/OpenAiApiStrategy.qml"
echo "  ✅ services/ai/OpenAiApiStrategy.qml"

cp "$SCRIPT_DIR/AiChat.qml" "$SIDEBAR/AiChat.qml"
echo "  ✅ modules/ii/sidebarLeft/AiChat.qml"

cp "$SCRIPT_DIR/MessageThinkBlock.qml" "$SIDEBAR_AI/MessageThinkBlock.qml"
echo "  ✅ modules/ii/sidebarLeft/aiChat/MessageThinkBlock.qml"

cp "$SCRIPT_DIR/MessageCodeBlock.qml" "$SIDEBAR_AI/MessageCodeBlock.qml"
echo "  ✅ modules/ii/sidebarLeft/aiChat/MessageCodeBlock.qml"

cp "$SCRIPT_DIR/AiMessage.qml" "$SIDEBAR_AI/AiMessage.qml"
echo "  ✅ modules/ii/sidebarLeft/aiChat/AiMessage.qml"

# Install system prompt if present
if [ -f "$SCRIPT_DIR/ii-Default.md" ]; then
    PROMPTS_DIR="$QS_BASE/defaults/ai/prompts"
    mkdir -p "$PROMPTS_DIR"
    cp "$PROMPTS_DIR/ii-Default.md" "$BACKUP/" 2>/dev/null || true
    cp "$SCRIPT_DIR/ii-Default.md" "$PROMPTS_DIR/ii-Default.md"
    echo "  ✅ defaults/ai/prompts/ii-Default.md"
fi

echo ""
echo "🎉 Done! Restart quickshell to apply changes."
echo ""
echo "📌 Commands:"
echo "   /new            — Save current chat & start fresh"
echo "   /stop           — Stop AI generation"
echo "   /addlocal       — Add local model (Ollama/LM Studio/vLLM)"
echo "   /export         — Export chat to markdown"
echo "   /temp VALUE     — Set temperature (0-2)"
echo "   Escape          — Close popups / stop generation"
echo "   Ctrl+1..9       — Quick model switch"
echo "   Ctrl+Shift+O    — New chat (keybind)"
echo ""
echo "📌 Models: Gemini 3.1 Flash-Lite/Flash/Pro, Claude Haiku/Sonnet/Opus,"
echo "           GPT-5.4 Nano/Mini/Full, Groq Llama/Qwen, Grok 3/4.1,"
echo "           DeepSeek V3/R1 + Ollama auto-detect + /addlocal"
echo ""
echo "📌 Features:"
echo "   • Extended thinking (Anthropic) — toggle in Functions popup"
echo "   • Thinking level (Gemini) — Off/Low/Med/High in Functions popup"
echo "   • Scrollable model picker with smooth animations"
echo "   • Function calling: shell commands, config editing, web search"
echo "   • Auto context trimming at ~200K tokens"
echo "   • Chat history rotation (5 slots)"
echo "   • Session cost tracking"
echo ""
echo "📌 Add {PREVIOUS_CHAT_CONTEXT} to system prompt for cross-chat context"
echo ""
echo "📌 To rollback: cp -r $BACKUP/* $QS_BASE/"
