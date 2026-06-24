#!/bin/bash
# ollama/claude-code-ollama.sh
#
# PURPOSE:
#   Configures Claude Code to use local Ollama (Qwen3:8b) as default
#   for routine tasks, preserving Anthropic API for heavy synthesis.
#
# LLM ROUTING STRATEGY:
#   Local Ollama (Qwen3:8b) -- lightweight, privacy-sensitive, automated:
#     - Scheduled dispatch tasks
#     - Log summarization
#     - Routine code edits
#     - Anything in automated/cron context
#
#   Anthropic API (Claude) -- heavy synthesis, complex reasoning:
#     - Architecture decisions
#     - Multi-file refactors
#     - Interactive development sessions
#     - Anything requiring full context window
#
# USAGE:
#   bash ollama/claude-code-ollama.sh
#   (run as corporatetraveldc)

set -e

echo "=== claude-code-ollama.sh ==="

# Add Ollama host to shell config
BASHRC="$HOME/.bashrc"
if ! grep -q "OLLAMA_HOST" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'EOF'

# Ollama -- local model endpoint (Tailscale-accessible)
export OLLAMA_HOST=http://127.0.0.1:11434
EOF
    echo "[OK]  OLLAMA_HOST added to ~/.bashrc"
else
    echo "[OK]  OLLAMA_HOST already in ~/.bashrc"
fi

echo ""
echo "-- Reload shell: source ~/.bashrc"
echo "-- Test Ollama:  curl http://127.0.0.1:11434/api/tags"
echo "-- Pull model:   ollama pull qwen3:8b"
