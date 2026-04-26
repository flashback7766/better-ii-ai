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
WIDGETS_DIR="$QS_BASE/modules/common/widgets"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Backup
BACKUP="$QS_BASE/.backup-ai-$(date +%Y%m%d-%H%M%S)"
echo "📦 Creating backup at $BACKUP"
mkdir -p "$BACKUP/services/ai" "$BACKUP/modules/ii/sidebarLeft/aiChat" "$BACKUP/modules/common/widgets"
cp "$SERVICES/Ai.qml" "$BACKUP/services/" 2>/dev/null || true
cp "$AI_DIR/AiMessageData.qml" "$BACKUP/services/ai/" 2>/dev/null || true
cp "$AI_DIR/AnthropicApiStrategy.qml" "$BACKUP/services/ai/" 2>/dev/null || true
cp "$AI_DIR/GeminiApiStrategy.qml" "$BACKUP/services/ai/" 2>/dev/null || true
cp "$AI_DIR/OpenAiApiStrategy.qml" "$BACKUP/services/ai/" 2>/dev/null || true
cp "$SIDEBAR/AiChat.qml" "$BACKUP/modules/ii/sidebarLeft/" 2>/dev/null || true
cp "$SIDEBAR_AI/MessageThinkBlock.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/MessageCodeBlock.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/AiMessage.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/AiMessageControlButton.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/AnnotationSourceButton.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/AttachedFileIndicator.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/MessageTextBlock.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$SIDEBAR_AI/SearchQueryButton.qml" "$BACKUP/modules/ii/sidebarLeft/aiChat/" 2>/dev/null || true
cp "$WIDGETS_DIR/GroupButton.qml" "$BACKUP/modules/common/widgets/" 2>/dev/null || true
cp "$WIDGETS_DIR/RippleButton.qml" "$BACKUP/modules/common/widgets/" 2>/dev/null || true

echo "📋 Installing files..."
echo ""

cp "$SCRIPT_DIR/Ai.qml" "$SERVICES/Ai.qml"
echo "  ✅ Ai.qml              → $SERVICES/Ai.qml"

cp "$SCRIPT_DIR/AiMessageData.qml" "$AI_DIR/AiMessageData.qml"
echo "  ✅ AiMessageData.qml   → $AI_DIR/AiMessageData.qml"

cp "$SCRIPT_DIR/AnthropicApiStrategy.qml" "$AI_DIR/AnthropicApiStrategy.qml"
echo "  ✅ AnthropicApiStrategy.qml → $AI_DIR/AnthropicApiStrategy.qml"

cp "$SCRIPT_DIR/GeminiApiStrategy.qml" "$AI_DIR/GeminiApiStrategy.qml"
echo "  ✅ GeminiApiStrategy.qml    → $AI_DIR/GeminiApiStrategy.qml"

cp "$SCRIPT_DIR/OpenAiApiStrategy.qml" "$AI_DIR/OpenAiApiStrategy.qml"
echo "  ✅ OpenAiApiStrategy.qml    → $AI_DIR/OpenAiApiStrategy.qml"

cp "$SCRIPT_DIR/AiChat.qml" "$SIDEBAR/AiChat.qml"
echo "  ✅ AiChat.qml          → $SIDEBAR/AiChat.qml"

cp "$SCRIPT_DIR/MessageThinkBlock.qml" "$SIDEBAR_AI/MessageThinkBlock.qml"
echo "  ✅ MessageThinkBlock.qml → $SIDEBAR_AI/MessageThinkBlock.qml"

cp "$SCRIPT_DIR/MessageCodeBlock.qml" "$SIDEBAR_AI/MessageCodeBlock.qml"
echo "  ✅ MessageCodeBlock.qml  → $SIDEBAR_AI/MessageCodeBlock.qml"

cp "$SCRIPT_DIR/AiMessage.qml" "$SIDEBAR_AI/AiMessage.qml"
echo "  ✅ AiMessage.qml       → $SIDEBAR_AI/AiMessage.qml"

cp "$SCRIPT_DIR/AiMessageControlButton.qml" "$SIDEBAR_AI/AiMessageControlButton.qml"
echo "  ✅ AiMessageControlButton.qml → $SIDEBAR_AI/AiMessageControlButton.qml"

cp "$SCRIPT_DIR/AnnotationSourceButton.qml" "$SIDEBAR_AI/AnnotationSourceButton.qml"
echo "  ✅ AnnotationSourceButton.qml → $SIDEBAR_AI/AnnotationSourceButton.qml"

cp "$SCRIPT_DIR/AttachedFileIndicator.qml" "$SIDEBAR_AI/AttachedFileIndicator.qml"
echo "  ✅ AttachedFileIndicator.qml → $SIDEBAR_AI/AttachedFileIndicator.qml"

cp "$SCRIPT_DIR/MessageTextBlock.qml" "$SIDEBAR_AI/MessageTextBlock.qml"
echo "  ✅ MessageTextBlock.qml → $SIDEBAR_AI/MessageTextBlock.qml"

cp "$SCRIPT_DIR/SearchQueryButton.qml" "$SIDEBAR_AI/SearchQueryButton.qml"
echo "  ✅ SearchQueryButton.qml → $SIDEBAR_AI/SearchQueryButton.qml"

mkdir -p "$WIDGETS_DIR"
cp "$SCRIPT_DIR/GroupButton.qml" "$WIDGETS_DIR/GroupButton.qml"
echo "  ✅ GroupButton.qml     → $WIDGETS_DIR/GroupButton.qml"

cp "$SCRIPT_DIR/RippleButton.qml" "$WIDGETS_DIR/RippleButton.qml"
echo "  ✅ RippleButton.qml    → $WIDGETS_DIR/RippleButton.qml"

# Install system prompt if present
if [ -f "$SCRIPT_DIR/ii-Default.md" ]; then
    PROMPTS_DIR="$QS_BASE/defaults/ai/prompts"
    mkdir -p "$PROMPTS_DIR"
    cp "$PROMPTS_DIR/ii-Default.md" "$BACKUP/" 2>/dev/null || true
    cp "$SCRIPT_DIR/ii-Default.md" "$PROMPTS_DIR/ii-Default.md"
    echo "  ✅ ii-Default.md       → $PROMPTS_DIR/ii-Default.md"
fi

# Install custom icons
ICONS_DIR="$QS_BASE/assets/icons"
mkdir -p "$ICONS_DIR"
if [ -f "$SCRIPT_DIR/anthropic-symbolic.svg" ]; then
    cp "$SCRIPT_DIR/anthropic-symbolic.svg" "$ICONS_DIR/"
    echo "  ✅ anthropic-symbolic.svg → $ICONS_DIR/anthropic-symbolic.svg"
fi

echo ""
echo "🎉 Done! Changes should be applied automatically."
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
echo "📌 Models: Gemini 3.1 Flash-Lite/Flash/Pro, Claude Haiku/Sonnet/Opus 4.7,"
echo "           GPT-5.4 Nano/Mini/Full + Ollama auto-detect + /addlocal"
echo ""
echo "💡 Recommendation: Gemini models are highly recommended for the best experience!"
echo ""
echo "📌 Features:"
echo "   • Extended thinking (Anthropic) — toggle in Functions popup"
echo "   • Thinking level (Gemini) — Off/Low/Med/High in Functions popup"
echo "   • Scrollable model picker with smooth animations"
echo "   • Function calling: shell commands, config editing, web search"
echo "   • Auto context trimming at ~15K tokens (adaptive for Claude)"
echo "   • Chat history rotation (5 slots)"
echo "   • Session cost tracking"
echo ""
echo "📌 Add {PREVIOUS_CHAT_CONTEXT} to system prompt for cross-chat context"
echo ""
echo "📌 To rollback: cp -r $BACKUP/* $QS_BASE/"
