#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  NkapSafe — One-command launcher
#  Run from your project root: /Users/user/nkapsave/
#  Usage: bash run.sh
# ═══════════════════════════════════════════════════════════════

set -e  # stop on any error

FLUTTER_ROOT="/Users/user/nkapsave"
BACKEND_ROOT="/Users/user/nkapsave/backend"
BUILD_WEB="$FLUTTER_ROOT/build/web"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║        NkapSafe Launcher 🚀           ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Flutter dependencies ──────────────────────────────────
echo "📦  Getting Flutter packages..."
cd "$FLUTTER_ROOT"
flutter pub get

# ── 2. Build Flutter Web ─────────────────────────────────────
echo ""
echo "🔨  Building Flutter Web (this takes ~60s)..."
flutter build web --no-tree-shake-icons

# ── 3. Copy build into backend static folder ─────────────────
echo ""
echo "📁  Copying build to backend static folder..."
mkdir -p "$BUILD_WEB"
# Already in place — Flutter builds directly to build/web
# which is what FLUTTER_BUILD points to in main.py ✅

# ── 4. Activate Python venv ──────────────────────────────────
echo ""
echo "🐍  Activating Python virtual environment..."
cd "$BACKEND_ROOT"
source venv/bin/activate

# ── 5. Install backend dependencies ─────────────────────────
echo ""
echo "📦  Installing Python dependencies..."
pip install -r requirements.txt -q

# ── 6. Start FastAPI ─────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅  NkapSafe is running!             ║"
echo "║                                      ║"
echo "║  🌐  App  → http://localhost:8000    ║"
echo "║  📖  Docs → http://localhost:8000/api/docs ║"
echo "║                                      ║"
echo "║  Press Ctrl+C to stop               ║"
echo "╚══════════════════════════════════════╝"
echo ""

uvicorn main:app --host 0.0.0.0 --port 8000 --reload
