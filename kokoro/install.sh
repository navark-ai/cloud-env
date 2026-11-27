#!/usr/bin/env bash
# Install the French TTS runtime while setup can reach the package index and model release.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
runtime="${1:-/opt/kokoro-fr}"
bin_directory="${2:-/usr/local/bin}"
release="https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1"

mkdir -p "$runtime" "$bin_directory"
runtime="$(cd "$runtime" && pwd)"
downloads="$(mktemp -d "$runtime/.download.XXXXXX")"
trap 'rm -rf "$downloads"' EXIT
trap 'exit 1' TERM INT

download() {
    local file="$1" sha256="$2"

    if printf '%s  %s\n' "$sha256" "$runtime/$file" | sha256sum --check --status; then
        return
    fi
    curl -fsSL --connect-timeout 10 --max-time 55 --retry 1 "$release/$file" -o "$downloads/$file"
    printf '%s  %s\n' "$sha256" "$downloads/$file" | sha256sum --check
    mv "$downloads/$file" "$runtime/$file"
}

download kokoro-v1.0.int8.onnx ae315a79b623f244700e4afb9246c46a26066782e049ba174bf3ba433970ee9c
download voices-v1.0.bin bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d

/usr/bin/python3 -I -m venv "$runtime/venv"
"$runtime/venv/bin/python" -I -m pip --isolated install --disable-pip-version-check \
    --no-cache-dir --only-binary=:all: 'kokoro-onnx==0.6.1'

printf '%s\n' '["Bonjour."]' | "$runtime/venv/bin/python" -I "$here/synthesize.py" "$runtime" "$downloads"
cat >"$downloads/kokoro-fr" <<EOF
#!/usr/bin/env bash
exec "$runtime/venv/bin/python" -I "$runtime/synthesize.py" "$runtime" "\$@"
EOF
cp "$here/synthesize.py" "$runtime/synthesize.py"
install -m 755 "$downloads/kokoro-fr" "$bin_directory/kokoro-fr"
