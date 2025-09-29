#!/usr/bin/env bash
set -euo pipefail

# installGolang.sh — download and install Go to /usr/local and add to PATH
# - Downloads the official tarball (curl preferred, falls back to wget)
# - Removes any existing /usr/local/go
# - Extracts the tarball to /usr/local
# - Adds /usr/local/go/bin to ~/.profile and ~/.bashrc if missing

log() { printf '%s\n' "$*"; }

DOWNLOAD_DIR="${DOWNLOAD_DIR:-$HOME/Downloads}"
# If VERSION is not set, fetch the latest stable version from go.dev
if [ -z "${VERSION:-}" ]; then
	log "Detecting latest Go version from https://go.dev/VERSION?m=text..."
	# Fetch the VERSION endpoint and keep only the first non-empty line. Some responses may include extra lines (timestamps).
	LATEST_TAG=$(curl -fsS 'https://go.dev/VERSION?m=text' 2>/dev/null || true)
	LATEST_TAG=$(printf '%s' "$LATEST_TAG" | tr -d '\r' | awk 'NF{print; exit}')
	if [ -z "$LATEST_TAG" ]; then
		log "Unable to detect latest Go version; please set VERSION environment variable (example: 1.25.1)"
		exit 2
	fi
	# LATEST_TAG is like "go1.25.1"
	VERSION="${LATEST_TAG#go}"
	log "Latest version: $VERSION"
fi

# Detect OS (map uname -s to Go OS names)
UNAME_S=$(uname -s)
case "$UNAME_S" in
	Linux) OS="linux" ;;
	Darwin) OS="darwin" ;;
	FreeBSD) OS="freebsd" ;;
	MINGW*|MSYS*|CYGWIN*)
		log "Detected Windows-like environment ($UNAME_S). This script is intended for Unix-like systems."
		log "For Windows, download the MSI/ZIP from https://go.dev/dl/ and follow Windows installation instructions."
		exit 4
		;;
	*)
		log "Unsupported operating system: $UNAME_S. Please run this script on Linux, macOS (Darwin) or FreeBSD."
		exit 4
		;;
esac

# Map uname -m to Go architecture names
case "$(uname -m)" in
	x86_64|amd64) ARCH="amd64" ;;
	aarch64|arm64) ARCH="arm64" ;;
	i386|i686) ARCH="386" ;;
	armv7l) ARCH="armv6l" ;;
	*)
		log "Unsupported CPU architecture: $(uname -m). Please set ARCH variable manually."
		exit 3
		;;
esac

FILE="go${VERSION}.${OS}-${ARCH}.tar.gz"
if [ "$OS" = "windows" ]; then
	EXT="zip"
else
	EXT="tar.gz"
fi

FILE="go${VERSION}.${OS}-${ARCH}.${EXT}"
URL="https://go.dev/dl/${FILE}"

cd "$DOWNLOAD_DIR"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

if [ -f "$DOWNLOAD_DIR/$FILE" ]; then
	log "$FILE already exists in $DOWNLOAD_DIR — using that file"
	SRC_FILE="$DOWNLOAD_DIR/$FILE"
else
	log "Downloading $FILE from $URL to $TMPDIR..."
	SRC_FILE="$TMPDIR/$FILE"
	if command -v curl >/dev/null 2>&1; then
		curl -fSL -o "$SRC_FILE" "$URL"
	else
		wget -c "$URL" -O "$SRC_FILE"
	fi
fi

log "Extracting $FILE to temporary location..."
if [ "$EXT" = "tar.gz" ]; then
	tar -xzf "$SRC_FILE" -C "$TMPDIR"
else
	if ! command -v unzip >/dev/null 2>&1; then
		log "unzip is required to extract $FILE but it's not installed. Please install unzip and re-run."
		exit 5
	fi
	unzip -q "$SRC_FILE" -d "$TMPDIR"
fi

# The tarball contains a top-level 'go' directory. Move it atomically into /usr/local
if [ -d /usr/local/go ]; then
	log "Removing existing /usr/local/go (sudo may be required)..."
	sudo rm -rf /usr/local/go
fi

log "Installing Go to /usr/local (sudo may be required)..."
sudo mv "$TMPDIR/go" /usr/local/go

# Add PATH entry to shell profiles if missing
read -r -d '' ADD_PATH_BLOCK <<'EOF' || true
# Go (added by installGolang.sh)
export PATH="$PATH:/usr/local/go/bin"
EOF

for f in "$HOME/.profile" "$HOME/.bashrc"; do
	if [ -f "$f" ]; then
		if grep -q '/usr/local/go/bin' "$f" 2>/dev/null; then
			log "/usr/local/go/bin already in $f"
		else
			printf '%s\n' "$ADD_PATH_BLOCK" >> "$f"
			log "Added PATH entry to $f"
		fi
	fi
done

# Source profile for this session if possible
if [ -f "$HOME/.profile" ]; then
	# shellcheck disable=SC1090
	. "$HOME/.profile" || true
fi

log "--- verification ---"
command -v go && go version || log "go not found in PATH"

exit 0
