#!/bin/bash
# En cada arranque baja run.sh y conan-agent desde GitHub si hay update.
cd /home/container || exit 1
export GAME_ID="${GAME_ID:-bedrock}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-.}"
BASE="${AGENT_GITHUB:-https://raw.githubusercontent.com/Jahir5838/clankyhosting/clanky-agent}"
UA="clanky-agent"
mkdir -p .conan-agent

is_linux_bin() {
  [ -s "$1" ] || return 1
  mag=$(dd if="$1" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
  [ "$mag" = "7f454c46" ]
}

read_etag() {
  grep -i '^etag:' "$1" 2>/dev/null | head -n1 | tr -d '\r' | awk '{print $2}' | tr -d '"'
}

fetch_etag() {
  url="$1"
  dest="$2"
  tagf="$3"
  tmp="${dest}.new"
  hdr="${dest}.hdr"
  old=$(cat "$tagf" 2>/dev/null || true)
  if [ -n "$old" ]; then
    code=$(curl -fsSL -A "$UA" -H "If-None-Match: $old" -D "$hdr" -o "$tmp" -w "%{http_code}" "$url" || echo 000)
  else
    code=$(curl -fsSL -A "$UA" -D "$hdr" -o "$tmp" -w "%{http_code}" "$url" || echo 000)
  fi
  if [ "$code" = "304" ]; then
    rm -f "$tmp" "$hdr"
    return 1
  fi
  if [ "$code" = "200" ] && [ -s "$tmp" ]; then
    et=$(read_etag "$hdr")
    [ -n "$et" ] && printf '%s\n' "$et" > "$tagf"
    mv "$tmp" "$dest"
    rm -f "$hdr"
    return 0
  fi
  rm -f "$tmp" "$hdr"
  return 1
}

if [ -z "$CLANKY_BOOTSTRAPPED" ]; then
  if fetch_etag "$BASE/run.sh" ./run.sh .conan-agent/run.sh.etag; then
    chmod +x ./run.sh
    echo "run.sh actualizado desde GitHub."
    export CLANKY_BOOTSTRAPPED=1
    exec ./run.sh
  fi
fi
chmod +x ./run.sh 2>/dev/null || true

echo "Revisando Config Agent en GitHub..."
if fetch_etag "$BASE/conan-agent" ./conan-agent .conan-agent/conan-agent.etag; then
  echo "Config Agent actualizado."
fi
chmod +x ./conan-agent 2>/dev/null || true

if is_linux_bin ./conan-agent; then
  ./conan-agent ensure-token >/dev/null 2>&1 || true
  if [ "$AGENT_BACKGROUND" = "1" ]; then
    ./conan-agent serve >> .conan-agent/agent.log 2>&1 &
    exit 0
  fi
  exec ./conan-agent serve
fi

echo "AVISO: no hay conan-agent Linux. Fuente: $BASE/conan-agent"
if [ "$GAME_ID" = "bedrock" ] && [ -f ./bedrock_server ]; then
  chmod +x ./bedrock_server 2>/dev/null || true
  exec ./bedrock_server
fi
exit 1
