#!/usr/bin/env bash
# AgentManager Linux/macOS installer
# Creates a symlink in ~/.local/bin/am pointing at this repo's am.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/am.sh"
BIN_DIR="${HOME}/.local/bin"
DEST="${BIN_DIR}/am"

if [[ ! -f "$SRC" ]]; then
    echo "[오류] am.sh 가 ${SCRIPT_DIR} 에 없습니다."
    exit 1
fi

chmod +x "$SRC"
mkdir -p "$BIN_DIR"

if [[ -e "$DEST" || -L "$DEST" ]]; then
    if [[ -L "$DEST" && "$(readlink "$DEST")" == "$SRC" ]]; then
        echo "[안내] 이미 설치되어 있습니다: $DEST"
    else
        echo "[안내] 기존 ${DEST} 제거 후 재설치합니다."
        rm -f "$DEST"
        ln -s "$SRC" "$DEST"
    fi
else
    ln -s "$SRC" "$DEST"
fi

echo "[완료] 설치됨: $DEST -> $SRC"

case ":${PATH}:" in
    *":${BIN_DIR}:"*)
        echo "[안내] PATH 등록됨. 'am' 명령으로 실행 가능합니다."
        ;;
    *)
        echo ""
        echo "[경고] ${BIN_DIR} 가 PATH 에 없습니다. 셸 rc 파일에 다음을 추가하세요:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    echo ""
    echo "[안내] jq 미설치. am 실행 시 자동 설치를 시도합니다."
fi
