#!/usr/bin/env bash
# ==================================================
# Author: securekim (https://securekim.com)
# License: MIT License
# 자유롭게 수정·사용 가능. 원본 표기만 남겨주세요.
# Linux port of c.bat
# ==================================================
set -u

VERSION="1.1.17"

# 스크립트 위치 기준 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
CONFIG_BASE_DIR="${SCRIPT_DIR}/claude_configs"
mkdir -p "${CONFIG_BASE_DIR}"
GLOBAL_PATH_FILE="${CONFIG_BASE_DIR}/last_path.txt"
LAST_ALIAS_FILE="${CONFIG_BASE_DIR}/last_alias.txt"
PATH_ALIAS_FILE="${CONFIG_BASE_DIR}/path_aliases.txt"

# 예약어 (계정/경로 alias 로 사용 불가)
RESERVED_WORDS="login copy reset logout remove delete remote close account alias version path help install uninstall"

is_reserved() {
    local w="$1"
    [[ -z "$w" ]] && return 1
    case " $RESERVED_WORDS " in
        *" $w "*) return 0 ;;
    esac
    case "$w" in
        -h|--help) return 0 ;;
    esac
    return 1
}

# 경로 alias 조회: 성공시 stdout 으로 경로 출력
get_path_alias() {
    local name="$1"
    [[ -z "$name" || ! -f "$PATH_ALIAS_FILE" ]] && return 1
    local k v
    while IFS='=' read -r k v; do
        if [[ "$k" == "$name" ]]; then
            printf '%s' "$v"
            return 0
        fi
    done < "$PATH_ALIAS_FILE"
    return 1
}

ARG1="${1:-}"
ARG2="${2:-}"
ARG3="${3:-}"
NEW_PATH=""
TARGET_ALIAS=""

# jq 의존성 자동 설치
install_jq() {
    echo "[안내] jq 미설치. 자동 설치 시도..."
    local SUDO=""
    if [[ "$(id -u 2>/dev/null || echo 1000)" != "0" ]] && command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    fi

    # 1) OS 패키지 매니저 우선
    if command -v apt-get >/dev/null 2>&1; then
        $SUDO apt-get update -y && $SUDO apt-get install -y jq && return 0
    elif command -v dnf >/dev/null 2>&1; then
        $SUDO dnf install -y jq && return 0
    elif command -v yum >/dev/null 2>&1; then
        $SUDO yum install -y jq && return 0
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm jq && return 0
    elif command -v zypper >/dev/null 2>&1; then
        $SUDO zypper install -y jq && return 0
    elif command -v apk >/dev/null 2>&1; then
        $SUDO apk add --no-cache jq && return 0
    elif command -v brew >/dev/null 2>&1; then
        brew install jq && return 0
    fi

    # 2) Fallback: GitHub release 정적 바이너리 (jq 1.7.1)
    echo "[안내] 패키지 매니저 없음. 정적 바이너리 다운로드 시도..."
    local DOWNLOADER ARCH OS_NAME URL DEST_DIR DEST
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl -fsSL -o"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget -qO"
    else
        echo "[오류] curl/wget 없음. 자동 설치 불가."
        return 1
    fi
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l|armhf) ARCH="armhf" ;;
        i386|i686) ARCH="i386" ;;
        *) echo "[오류] 미지원 아키텍처: $(uname -m)"; return 1 ;;
    esac
    case "$(uname -s)" in
        Linux) OS_NAME="linux" ;;
        Darwin) OS_NAME="macos"; ARCH="$(uname -m | sed 's/x86_64/amd64/;s/arm64/arm64/')" ;;
        *) echo "[오류] 미지원 OS: $(uname -s)"; return 1 ;;
    esac
    URL="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-${OS_NAME}-${ARCH}"

    DEST_DIR="${HOME}/.local/bin"
    mkdir -p "$DEST_DIR"
    DEST="${DEST_DIR}/jq"
    echo "[다운로드] ${URL}"
    if ! $DOWNLOADER "$DEST" "$URL"; then
        echo "[오류] 다운로드 실패: $URL"
        return 1
    fi
    chmod +x "$DEST"
    case ":$PATH:" in
        *":${DEST_DIR}:"*) ;;
        *) export PATH="${DEST_DIR}:${PATH}"
           echo "[안내] PATH에 ${DEST_DIR} 추가됨 (영구 적용은 셸 rc에 export 필요)" ;;
    esac
}

if ! command -v jq >/dev/null 2>&1; then
    install_jq || { echo "[오류] jq 설치 실패. 수동 설치 필요: https://jqlang.github.io/jq/download/"; exit 1; }
    if ! command -v jq >/dev/null 2>&1; then
        echo "[오류] jq 설치 후에도 인식 불가. PATH 확인 필요."
        exit 1
    fi
    echo "[안내] jq 설치 완료: $(command -v jq)"
fi

# ---------- 세션 정보 추출 함수 ----------
# get_session <ConfigDir> <CurrentPath> [MaxSessions]
# stdout: KEY=VALUE 라인
get_session() {
    local config_dir="$1"
    local current_path="${2:-}"
    local max_sessions="${3:-1}"
    [[ -z "$max_sessions" ]] && max_sessions=1

    local claude_file="${config_dir}/.claude.json"
    local cred_file="${config_dir}/.credentials.json"
    local acc_name="" acc_email="" global_session_id=""

    if [[ -f "$claude_file" ]]; then
        acc_name=$(jq -r '.oauthAccount.displayName // ""' "$claude_file" 2>/dev/null || echo "")
        acc_email=$(jq -r '.oauthAccount.emailAddress // ""' "$claude_file" 2>/dev/null || echo "")
    fi
    if [[ -f "$cred_file" ]]; then
        global_session_id=$(jq -r '.sessionId // ""' "$cred_file" 2>/dev/null || echo "")
    fi
    echo "ACC_NAME=${acc_name}"
    echo "ACC_EMAIL=${acc_email}"

    # jsonl 파일 수집 (수정시간 내림차순, 최대 30개)
    local all_files=()
    if [[ -d "$config_dir" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" ]] && all_files+=("$f")
        done < <(find "$config_dir" -type f -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null \
                    | sort -rn | head -30 | awk '{ $1=""; sub(/^ /,""); print }')
    fi

    # current_path 정규화
    local norm_curr=""
    if [[ -n "$current_path" ]]; then
        norm_curr="${current_path//\\/\/}"
        norm_curr="${norm_curr%/}"
    fi

    local matched_files=()
    local file
    for file in "${all_files[@]}"; do
        [[ ${#matched_files[@]} -ge $max_sessions ]] && break
        if [[ -z "$current_path" ]]; then
            matched_files+=("$file")
            continue
        fi
        local file_cwd=""
        # 첫 20줄 안에서 cwd 추출 (jq 1회 호출)
        file_cwd=$(head -20 "$file" 2>/dev/null \
                    | jq -r 'select(.cwd) | .cwd' 2>/dev/null | head -1)
        local norm_file_cwd="${file_cwd//\\/\/}"
        norm_file_cwd="${norm_file_cwd%/}"
        if [[ "$norm_file_cwd" == "$norm_curr" ]]; then
            matched_files+=("$file")
        fi
    done

    # 프로젝트 lastSessionId
    local project_session_id=""
    if [[ -n "$current_path" && -f "$claude_file" ]]; then
        project_session_id=$(jq -r --arg p "$norm_curr" '
            (.projects // {}) | to_entries[]
            | select((.key | gsub("\\\\"; "/") | sub("/$"; "")) == $p)
            | .value.lastSessionId // empty
        ' "$claude_file" 2>/dev/null | head -1)
    fi

    local primary_session_id=""
    if [[ -n "$project_session_id" ]]; then
        # Validate: lastSessionId from .claude.json may be stale (file deleted).
        # Confirm the jsonl exists in matched_files before trusting it.
        local lastid_exists=0
        local mf
        for mf in "${matched_files[@]}"; do
            if [[ "$(basename "$mf" .jsonl)" == "$project_session_id" ]]; then
                lastid_exists=1
                break
            fi
        done
        # Broader check: even if not in matched_files (older than top-30 window),
        # the file might still exist on disk under any project subdir.
        if [[ $lastid_exists -eq 0 ]]; then
            if find "$config_dir" -type f -name "${project_session_id}.jsonl" -print -quit 2>/dev/null | grep -q .; then
                lastid_exists=1
            fi
        fi
        if [[ $lastid_exists -eq 1 ]]; then
            primary_session_id="$project_session_id"
        elif [[ ${#matched_files[@]} -gt 0 ]]; then
            primary_session_id="$(basename "${matched_files[0]}" .jsonl)"
        fi
    elif [[ ${#matched_files[@]} -gt 0 ]]; then
        primary_session_id="$(basename "${matched_files[0]}" .jsonl)"
    elif [[ -z "$current_path" ]]; then
        primary_session_id="$global_session_id"
    fi

    if [[ -z "$primary_session_id" ]]; then
        echo "S_COUNT=0"
        return
    fi

    # 첫 매칭 파일 요약
    local cwd="알 수 없음" branch="알 수 없음" time="알 수 없음"
    local user_msg="알 수 없음" assistant_msg="알 수 없음"
    if [[ ${#matched_files[@]} -gt 0 ]]; then
        local summary
        summary=$(jq -rs '
            reduce .[] as $o ({cwd:"", branch:"", time:"", user:"", assistant:""};
                .cwd = (if $o.cwd then $o.cwd else .cwd end)
              | .branch = (if $o.gitBranch then $o.gitBranch else .branch end)
              | .time = (if $o.timestamp then $o.timestamp else .time end)
              | .user = (if ($o.type=="last-prompt" and $o.lastPrompt) then $o.lastPrompt else .user end)
              | .assistant = (if ($o.type=="assistant" and $o.message.content) then ($o.message.content|tostring) else .assistant end)
            )
            | [.cwd, .branch, .time, .user, .assistant] | @tsv
        ' "${matched_files[0]}" 2>/dev/null || echo "")
        if [[ -n "$summary" ]]; then
            IFS=$'\t' read -r c1 c2 c3 c4 c5 <<< "$summary"
            [[ -n "$c1" ]] && cwd="$c1"
            [[ -n "$c2" ]] && branch="$c2"
            [[ -n "$c3" ]] && time="$c3"
            [[ -n "$c4" ]] && user_msg="$c4"
            [[ -n "$c5" ]] && assistant_msg="$c5"
        fi
    fi

    user_msg=$(printf '%s' "$user_msg" | tr '\r\n' '  ')
    assistant_msg=$(printf '%s' "$assistant_msg" | tr '\r\n' '  ')
    user_msg="${user_msg:0:47}..."
    assistant_msg="${assistant_msg:0:47}..."

    echo "S_ID=${primary_session_id}"
    echo "S_PATH=${cwd}"
    echo "S_BRANCH=${branch}"
    echo "S_TIME=${time}"
    echo "S_USER=${user_msg}"
    echo "S_ASSISTANT=${assistant_msg}"

    local count=0
    for file in "${matched_files[@]}"; do
        count=$((count+1))
        local fcwd="알 수 없음" fbranch="알 수 없음" ftime="알 수 없음"
        local fuser="알 수 없음" fasst="알 수 없음"
        local summary2
        summary2=$(jq -rs '
            reduce .[] as $o ({cwd:"", branch:"", time:"", user:"", assistant:""};
                .cwd = (if $o.cwd then $o.cwd else .cwd end)
              | .branch = (if $o.gitBranch then $o.gitBranch else .branch end)
              | .time = (if $o.timestamp then $o.timestamp else .time end)
              | .user = (if ($o.type=="last-prompt" and $o.lastPrompt) then $o.lastPrompt else .user end)
              | .assistant = (if ($o.type=="assistant" and $o.message.content) then ($o.message.content|tostring) else .assistant end)
            )
            | [.cwd, .branch, .time, .user, .assistant] | @tsv
        ' "$file" 2>/dev/null || echo "")
        if [[ -n "$summary2" ]]; then
            IFS=$'\t' read -r c1 c2 c3 c4 c5 <<< "$summary2"
            [[ -n "$c1" ]] && fcwd="$c1"
            [[ -n "$c2" ]] && fbranch="$c2"
            [[ -n "$c3" ]] && ftime="$c3"
            [[ -n "$c4" ]] && fuser="$c4"
            [[ -n "$c5" ]] && fasst="$c5"
        fi
        fuser=$(printf '%s' "$fuser" | tr '\r\n' '  ')
        fasst=$(printf '%s' "$fasst" | tr '\r\n' '  ')
        fuser="${fuser:0:47}..."
        fasst="${fasst:0:47}..."

        echo "S_ID_${count}=$(basename "$file" .jsonl)"
        echo "S_PATH_${count}=${fcwd}"
        echo "S_BRANCH_${count}=${fbranch}"
        echo "S_TIME_${count}=${ftime}"
        echo "S_USER_${count}=${fuser}"
        echo "S_ASSISTANT_${count}=${fasst}"
    done
    echo "S_COUNT=${count}"
}

# settings.json 의 일부 키만 글로벌->alias 로 머지
merge_settings() {
    local alias_dir="$1"
    local global_dir="$2"
    local g="${global_dir}/settings.json"
    local a="${alias_dir}/settings.json"
    [[ -f "$g" ]] || return 0
    local gjson ajson merged
    gjson=$(cat "$g" 2>/dev/null) || return 0
    if [[ -f "$a" ]]; then
        ajson=$(cat "$a" 2>/dev/null) || ajson="{}"
    else
        ajson="{}"
    fi
    merged=$(jq -n --argjson g "$gjson" --argjson a "$ajson" '
        $a as $base
        | reduce ["hooks","statusLine","extraKnownMarketplaces","enabledPlugins"][] as $k ($base;
            if ($g|has($k)) then .[$k] = $g[$k] else . end
          )
    ' 2>/dev/null) || return 0
    [[ -n "$merged" ]] && printf '%s\n' "$merged" > "$a"
}

# ---------- 명령어 함수 ----------
do_version() {
    echo "Agent Manager: ${VERSION}"
}

_pick_rc_file() {
    local shell_name="${SHELL##*/}"
    case "$shell_name" in
        zsh)  printf '%s' "${HOME}/.zshrc" ;;
        bash) printf '%s' "${HOME}/.bashrc" ;;
        *)    printf '%s' "${HOME}/.profile" ;;
    esac
}

_install_marker() {
    printf '# Added by %s install (do not edit this line)' "$SCRIPT_NAME"
}

_add_path_to_rc() {
    local rc_file; rc_file="$(_pick_rc_file)"
    local marker; marker="$(_install_marker)"
    local export_line='export PATH="$HOME/.local/bin:$PATH"'

    touch "$rc_file"
    if grep -qF "$marker" "$rc_file" 2>/dev/null; then
        echo "[안내] ${rc_file} 에 이미 ${SCRIPT_NAME} install 항목이 있습니다."
    else
        printf '\n%s\n%s\n' "$marker" "$export_line" >> "$rc_file"
        echo "[완료] ${rc_file} 에 PATH 설정 추가됨."
    fi
    echo "[안내] 현재 셸에 즉시 적용: source ${rc_file}"
    echo "[안내] 또는 새 터미널에서 '${SCRIPT_NAME}' 실행."
}

_remove_path_from_rc() {
    local rc_file; rc_file="$(_pick_rc_file)"
    local marker; marker="$(_install_marker)"
    [[ -f "$rc_file" ]] || return 0
    grep -qF "$marker" "$rc_file" 2>/dev/null || return 0
    local tmp="${rc_file}.am.tmp.$$"
    awk -v m="$marker" '
        $0 == m { skip = 1; next }
        skip == 1 { skip = 0; next }
        { print }
    ' "$rc_file" > "$tmp" && mv "$tmp" "$rc_file"
    echo "[안내] ${rc_file} 에서 ${SCRIPT_NAME} install PATH 설정 제거됨."
}

do_install() {
    local bin_dir="${HOME}/.local/bin"
    local src="${SCRIPT_DIR}/${SCRIPT_NAME}.sh"
    local dest="${bin_dir}/${SCRIPT_NAME}"

    if [[ ! -f "$src" ]]; then
        echo "[오류] ${src} 파일을 찾을 수 없습니다."
        return 1
    fi
    chmod +x "$src"
    mkdir -p "$bin_dir"

    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
        echo "[안내] 이미 설치되어 있습니다: ${dest}"
    else
        [[ -e "$dest" || -L "$dest" ]] && rm -f "$dest"
        ln -s "$src" "$dest"
        echo "[완료] 설치됨: ${dest} -> ${src}"
    fi

    case ":${PATH}:" in
        *":${bin_dir}:"*)
            echo "[안내] PATH 등록됨. '${SCRIPT_NAME}' 명령으로 실행 가능합니다."
            ;;
        *)
            echo ""
            echo "[경고] ${bin_dir} 가 현재 PATH 에 없습니다. 셸 rc 파일에 자동 추가합니다."
            _add_path_to_rc
            ;;
    esac
}

do_uninstall() {
    local dest="${HOME}/.local/bin/${SCRIPT_NAME}"
    if [[ -L "$dest" || -e "$dest" ]]; then
        rm -f "$dest"
        echo "[완료] 제거됨: ${dest}"
    else
        echo "[안내] 설치되어 있지 않습니다: ${dest}"
    fi
    _remove_path_from_rc
}

check_install_hint() {
    # Already resolvable as a command on PATH? No hint needed.
    command -v "$SCRIPT_NAME" >/dev/null 2>&1 && return
    echo "[안내] '${SCRIPT_NAME}' 명령이 설치되지 않았습니다. 'bash ${SCRIPT_NAME}.sh install' 로 설치하면 어디서나 '${SCRIPT_NAME}' 명령으로 실행 가능합니다."
}

do_login() {
    NEW_ALIAS="$ARG2"
    [[ -z "$NEW_ALIAS" ]] && read -r -p "로그인할 계정 Alias를 입력하세요: " NEW_ALIAS
    [[ -z "$NEW_ALIAS" ]] && { echo "[오류] Alias가 비어있습니다."; return; }
    if is_reserved "$NEW_ALIAS"; then
        echo "[오류] '${NEW_ALIAS}'은(는) 예약어이므로 계정 Alias로 사용할 수 없습니다."
        return
    fi
    if get_path_alias "$NEW_ALIAS" >/dev/null; then
        echo "[오류] '${NEW_ALIAS}'은(는) 이미 경로 Alias로 등록되어 있습니다."
        return
    fi
    mkdir -p "${CONFIG_BASE_DIR}/${NEW_ALIAS}"
    export CLAUDE_CONFIG_DIR="${CONFIG_BASE_DIR}/${NEW_ALIAS}"
    printf '%s' "$NEW_ALIAS" > "$LAST_ALIAS_FILE"
    echo "[안내] '${NEW_ALIAS}' 계정 Alias 프로파일 환경에서 로그인을 진행합니다."
    claude login
}

do_copy() {
    local SRC_ALIAS="$ARG2" NEW_ALIAS="$ARG3"
    [[ -z "$SRC_ALIAS" ]] && read -r -p "원본 계정 Alias를 입력하세요: " SRC_ALIAS
    [[ -z "$NEW_ALIAS" ]] && read -r -p "복제할 신규 계정 Alias를 입력하세요: " NEW_ALIAS
    if is_reserved "$NEW_ALIAS"; then
        echo "[오류] '${NEW_ALIAS}'은(는) 예약어이므로 계정 Alias로 사용할 수 없습니다."
        return
    fi
    if get_path_alias "$NEW_ALIAS" >/dev/null; then
        echo "[오류] '${NEW_ALIAS}'은(는) 이미 경로 Alias로 등록되어 있습니다."
        return
    fi
    if [[ ! -d "${CONFIG_BASE_DIR}/${SRC_ALIAS}" ]]; then
        echo "[오류] 원본 계정 '${SRC_ALIAS}'이(가) 존재하지 않습니다."
        return
    fi
    if [[ -e "${CONFIG_BASE_DIR}/${NEW_ALIAS}" ]]; then
        echo "[오류] '${NEW_ALIAS}'은(는) 이미 계정 Alias로 등록되어 있습니다."
        return
    fi
    mkdir -p "${CONFIG_BASE_DIR}/${NEW_ALIAS}"
    local f
    for f in "${CONFIG_BASE_DIR}/${SRC_ALIAS}/"*; do
        [[ -e "$f" ]] || continue
        local bn; bn="$(basename "$f")"
        [[ "$bn" == "last_path.txt" ]] && continue
        cp -a "$f" "${CONFIG_BASE_DIR}/${NEW_ALIAS}/" 2>/dev/null
    done
    export CLAUDE_CONFIG_DIR="${CONFIG_BASE_DIR}/${NEW_ALIAS}"
    printf '%s' "$NEW_ALIAS" > "$LAST_ALIAS_FILE"
    echo "[안내] '${SRC_ALIAS}' 계정의 설정 파일을 복제하여 프로파일 분 계정 '${NEW_ALIAS}'을 생성했습니다."
}

do_reset() {
    echo "claude_configs 폴더의 모든 데이터를 초기화합니다."
    [[ -d "$CONFIG_BASE_DIR" ]] && rm -rf "$CONFIG_BASE_DIR"
    mkdir -p "$CONFIG_BASE_DIR"
    echo "초기화 완료."
}

do_logout() {
    local LOGOUT_ALIAS="$ARG2"
    if [[ -z "$LOGOUT_ALIAS" ]]; then
        echo "[오류] 로그아웃할 계정 Alias를 입력하세요. 예: ${SCRIPT_NAME} logout a"
        return
    fi
    if [[ -d "${CONFIG_BASE_DIR}/${LOGOUT_ALIAS}" ]]; then
        rm -rf "${CONFIG_BASE_DIR}/${LOGOUT_ALIAS}"
        echo "[안내] '${LOGOUT_ALIAS}' 계정 정보가 삭제되었습니다."
        if [[ -f "$LAST_ALIAS_FILE" ]]; then
            local cur; cur="$(cat "$LAST_ALIAS_FILE" 2>/dev/null || true)"
            [[ "$cur" == "$LOGOUT_ALIAS" ]] && rm -f "$LAST_ALIAS_FILE"
        fi
    else
        echo "[오류] '${LOGOUT_ALIAS}' 계정 Alias를 찾을 수 없습니다."
    fi
}

do_remove() {
    local target="$ARG2"
    if [[ -z "$target" ]]; then
        echo "[오류] 삭제할 대상(계정/경로 Alias)을 입력하세요. 예: ${SCRIPT_NAME} remove a"
        return 1
    fi
    local removed=0
    # 계정 Alias 삭제 (claude_configs/<alias> 디렉터리)
    if [[ -d "${CONFIG_BASE_DIR}/${target}" ]]; then
        rm -rf "${CONFIG_BASE_DIR}/${target}"
        echo "[안내] '${target}' 계정 Alias가 삭제되었습니다."
        if [[ -f "$LAST_ALIAS_FILE" ]]; then
            local cur; cur="$(cat "$LAST_ALIAS_FILE" 2>/dev/null || true)"
            [[ "$cur" == "$target" ]] && rm -f "$LAST_ALIAS_FILE"
        fi
        removed=1
    fi
    # 경로 Alias 삭제 (이름 또는 실제 경로가 일치하는 항목)
    if [[ -f "$PATH_ALIAS_FILE" ]]; then
        local tmp="${PATH_ALIAS_FILE}.tmp.$$"
        if awk -v n="$target" '
                { i=index($0,"="); k=substr($0,1,i-1); v=substr($0,i+1);
                  if (i>0 && (k==n || v==n)) { hit=1; next }
                  print }
                END { exit (hit?0:1) }
            ' "$PATH_ALIAS_FILE" > "$tmp"; then
            mv "$tmp" "$PATH_ALIAS_FILE"
            echo "[안내] '${target}' 경로 Alias가 삭제되었습니다."
            removed=1
        else
            rm -f "$tmp"
        fi
    fi
    if [[ $removed -eq 0 ]]; then
        echo "[오류] '${target}'에 해당하는 계정/경로 Alias를 찾을 수 없습니다."
        return 1
    fi
}

do_remote() {
    local REMOTE_ALIAS="$ARG2"
    local REMOTE_PATH="$ARG3"
    if [[ -z "$REMOTE_ALIAS" ]]; then
        if ! command -v tmux >/dev/null 2>&1; then
            echo "[오류] tmux 미설치."
            return 1
        fi
        local sessions
        sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -F 'claude-remote-' || true)
        if [[ -z "$sessions" ]]; then
            echo "[안내] 열려있는 remote 세션 없음."
            return 0
        fi
        echo "=================================================="
        echo "              열려있는 remote 세션"
        echo "=================================================="
        local s rest alias_part folder_part
        while IFS= read -r s; do
            [[ -z "$s" ]] && continue
            rest="${s#claude-remote-}"
            alias_part="${rest%%-*}"
            folder_part="${rest#*-}"
            echo "  계정: ${alias_part}  폴더: ${folder_part}  세션: ${s}"
        done <<< "$sessions"
        echo "=================================================="
        return 0
    fi
    if [[ ! -d "${CONFIG_BASE_DIR}/${REMOTE_ALIAS}" ]]; then
        echo "[오류] '${REMOTE_ALIAS}' 프로파일 없음. ${SCRIPT_NAME} login 으로 먼저 생성하세요."
        return 1
    fi
    export CLAUDE_CONFIG_DIR="${CONFIG_BASE_DIR}/${REMOTE_ALIAS}"
    printf '%s' "$REMOTE_ALIAS" > "$LAST_ALIAS_FILE"

    # 글로벌 plugins/hooks 링크 + mcp.json 동기화 (일반 실행과 동일하게)
    local GLOBAL_CLAUDE_DIR="${HOME}/.claude"
    mkdir -p "${GLOBAL_CLAUDE_DIR}/plugins" "${GLOBAL_CLAUDE_DIR}/hooks" "${GLOBAL_CLAUDE_DIR}/skills" "${GLOBAL_CLAUDE_DIR}/agents"
    local sub target
    for sub in plugins hooks skills agents; do
        target="${CLAUDE_CONFIG_DIR}/${sub}"
        if [[ -L "$target" ]]; then
            :
        elif [[ -d "$target" ]]; then
            cp -an "${target}/." "${GLOBAL_CLAUDE_DIR}/${sub}/" 2>/dev/null || true
            rm -rf "$target"
            ln -s "${GLOBAL_CLAUDE_DIR}/${sub}" "$target"
        else
            ln -s "${GLOBAL_CLAUDE_DIR}/${sub}" "$target"
        fi
    done
    [[ -f "${GLOBAL_CLAUDE_DIR}/mcp.json" ]] && cp -f "${GLOBAL_CLAUDE_DIR}/mcp.json" "${CLAUDE_CONFIG_DIR}/mcp.json" 2>/dev/null || true
    merge_settings "$CLAUDE_CONFIG_DIR" "$GLOBAL_CLAUDE_DIR"

    # 경로 결정
    local PROFILE_PATH_FILE="${CLAUDE_CONFIG_DIR}/last_path.txt"
    local target_path=""
    if [[ -n "$REMOTE_PATH" && -d "$REMOTE_PATH" ]]; then
        target_path="$REMOTE_PATH"
    else
        [[ -f "$PROFILE_PATH_FILE" ]] && target_path="$(cat "$PROFILE_PATH_FILE" 2>/dev/null | tr -d '\r\n' || true)"
        if [[ -z "$target_path" && -f "$GLOBAL_PATH_FILE" ]]; then
            target_path="$(cat "$GLOBAL_PATH_FILE" 2>/dev/null | tr -d '\r\n' || true)"
        fi
    fi
    if [[ -z "$target_path" || ! -d "$target_path" ]]; then
        echo "[오류] 유효한 경로 없음. 인자로 경로 주거나 먼저 일반 실행으로 경로 등록하세요."
        return 1
    fi
    printf '%s' "$target_path" > "$PROFILE_PATH_FILE"
    printf '%s' "$target_path" > "$GLOBAL_PATH_FILE"

    if ! command -v tmux >/dev/null 2>&1; then
        echo "[오류] tmux 미설치. apt-get install tmux 등으로 설치하세요."
        return 1
    fi

    local folder; folder="$(basename "$target_path")"
    local raw_session="claude-remote-${REMOTE_ALIAS}-${folder}"
    local session_name="${raw_session//[^A-Za-z0-9_-]/_}"

    # 기존 동명 세션 정리
    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo "[안내] 기존 tmux 세션 '${session_name}' 종료 후 재생성."
        tmux kill-session -t "$session_name" 2>/dev/null || true
    fi

    # Login shell PATH check (where claude is normally installed via nvm/npm).
    if ! bash -lc 'command -v claude >/dev/null 2>&1'; then
        echo "[오류] login shell PATH 에 'claude' 명령 없음."
        echo "[안내] 'bash -l -c \"command -v claude\"' 결과 확인 후 PATH 설정 보완."
        return 1
    fi

    local log_file="${CONFIG_BASE_DIR}/remote-${session_name}.log"
    local launch_script="${CONFIG_BASE_DIR}/.launch-${session_name}.sh"
    # No stdout/stderr pipe in this script -- claude must see a real TTY
    # (tmux pane) or it falls back to --print mode and exits with the
    # "Input must be provided" error.
    cat > "$launch_script" <<EOF
#!/usr/bin/env bash
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR}"
cd "${target_path}" || exit 1
echo "[am remote] start \$(date -Iseconds 2>/dev/null || date)"
echo "[am remote] alias: ${REMOTE_ALIAS}"
echo "[am remote] folder: ${folder}"
echo "[am remote] CLAUDE_CONFIG_DIR: \$CLAUDE_CONFIG_DIR"
echo "[am remote] claude: \$(command -v claude || echo NOT-FOUND)"
echo "[am remote] claude --version: \$(claude --version 2>&1 || echo FAILED)"
echo "[am remote] launching: claude --remote-control ${folder}"
echo
claude --remote-control "${folder}"
rc=\$?
echo
echo "[am remote] claude exited rc=\$rc at \$(date -Iseconds 2>/dev/null || date)"
echo "[am remote] tmux session stays alive — Ctrl+D to close, or run: ${SCRIPT_NAME} close ${REMOTE_ALIAS}"
exec bash -l
EOF
    chmod +x "$launch_script"

    echo "[원격] alias='${REMOTE_ALIAS}' path='${target_path}' folder='${folder}'"
    echo "[원격] tmux session='${session_name}'"
    echo "[원격] CLAUDE_CONFIG_DIR='${CLAUDE_CONFIG_DIR}'"
    echo "[원격] log file='${log_file}'"

    tmux new-session -d -s "$session_name" "bash -l '${launch_script}'"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "[오류] tmux new-session 실패 (rc=${rc})."
        return $rc
    fi
    # Capture pane output to log via tmux pipe-pane so claude's stdout
    # stays attached to the PTY and TTY detection succeeds.
    tmux pipe-pane -t "$session_name" -o "cat >> '${log_file}'" 2>/dev/null || true
    echo "[완료] tmux 백그라운드 시작. https://claude.ai/code 에서 원격 제어 가능 (등록 성공 시)."
    echo "[안내] 로그 확인 (실시간): tail -f ${log_file}"
    echo "[안내] 부착 (디버깅용): tmux attach -t ${session_name}"
    echo "[안내] 종료: ${SCRIPT_NAME} close ${REMOTE_ALIAS}"
}

do_close() {
    local close_alias="$ARG2"
    if [[ -z "$close_alias" ]]; then
        echo "[오류] 계정 Alias 필수. 예: ${SCRIPT_NAME} close a"
        return 1
    fi
    if ! command -v tmux >/dev/null 2>&1; then
        echo "[오류] tmux 미설치."
        return 1
    fi
    local prefix="claude-remote-${close_alias}-"
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -F "$prefix" || true)
    if [[ -z "$sessions" ]]; then
        echo "[안내] '${close_alias}' alias 로 열려있는 remote 세션 없음."
        return 0
    fi
    local s killed=0
    while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        if tmux kill-session -t "$s" 2>/dev/null; then
            echo "[완료] tmux 세션 종료: $s"
            killed=$((killed+1))
        fi
    done <<< "$sessions"
    echo "[완료] 총 ${killed}개 세션 종료됨."
}

do_path() {
    local name="$ARG2" dir="$ARG3"
    if [[ -z "$name" ]]; then
        echo "=================================================="
        echo "              등록된 경로 Alias 목록"
        echo "=================================================="
        if [[ ! -f "$PATH_ALIAS_FILE" ]]; then
            echo "등록된 경로 Alias가 없습니다."
            echo "예: ${SCRIPT_NAME} path tabmerge /path/to/TabMerge"
            return
        fi
        local k v
        while IFS='=' read -r k v; do
            [[ -n "$k" ]] && echo "  ${k} -> ${v}"
        done < "$PATH_ALIAS_FILE"
        echo "=================================================="
        return
    fi
    if is_reserved "$name"; then
        echo "[오류] '${name}'은(는) 예약어이므로 경로 Alias로 사용할 수 없습니다."
        return 1
    fi
    if [[ "$name" == *"/"* || "$name" == *"\\"* ]]; then
        echo "[오류] 경로 Alias '${name}' 에 '/' 또는 '\\' 사용 불가."
        return 1
    fi
    if [[ -d "${CONFIG_BASE_DIR}/${name}" ]]; then
        echo "[오류] '${name}'은(는) 이미 계정 Alias로 등록되어 있습니다."
        return 1
    fi
    if get_path_alias "$name" >/dev/null; then
        echo "[오류] '${name}'은(는) 이미 경로 Alias로 등록되어 있습니다."
        return 1
    fi
    if [[ -z "$dir" ]]; then
        echo "[오류] 경로가 필요합니다. 예: ${SCRIPT_NAME} path <path alias> <real path>"
        return 1
    fi
    if [[ ! -d "$dir" ]]; then
        echo "[오류] 경로 '${dir}'가 존재하지 않습니다."
        return 1
    fi
    local abs_dir
    abs_dir="$(cd "$dir" 2>/dev/null && pwd)" || abs_dir="$dir"
    echo "${name}=${abs_dir}" >> "$PATH_ALIAS_FILE"
    echo "[안내] 경로 Alias '${name}' -> '${abs_dir}' 등록 완료."
}

do_alias() {
    echo "=================================================="
    echo "                  등록된 Alias 목록"
    echo "=================================================="
    echo "[계정 Alias]"
    local found=0 d name
    if [[ -d "$CONFIG_BASE_DIR" ]]; then
        for d in "${CONFIG_BASE_DIR}"/*/; do
            [[ -d "$d" ]] || continue
            name="$(basename "$d")"
            [[ "$name" == "shared" ]] && continue
            echo "  ${name}"
            found=1
        done
    fi
    [[ $found -eq 0 ]] && echo "  (없음)"
    echo
    echo "[경로 Alias]"
    if [[ ! -f "$PATH_ALIAS_FILE" ]]; then
        echo "  (없음)"
    else
        local k v has=0
        while IFS='=' read -r k v; do
            if [[ -n "$k" ]]; then
                echo "  ${k} -> ${v}"
                has=1
            fi
        done < "$PATH_ALIAS_FILE"
        [[ $has -eq 0 ]] && echo "  (없음)"
    fi
    echo "=================================================="
}

do_account() {
    echo "=================================================="
    echo "             사용자 계정 정보 목록"
    echo "=================================================="
    if [[ ! -d "$CONFIG_BASE_DIR" ]]; then
        echo "사용자 계정 정보가 없습니다."
        return
    fi
    local GLOBAL_LAST_PATH=""
    [[ -f "$GLOBAL_PATH_FILE" ]] && GLOBAL_LAST_PATH="$(cat "$GLOBAL_PATH_FILE")"
    if [[ -n "$GLOBAL_LAST_PATH" ]]; then
        echo "[전역 마지막 경로]: ${GLOBAL_LAST_PATH}"
        echo "--------------------------------------------------"
    fi
    local d
    for d in "${CONFIG_BASE_DIR}"/*/; do
        [[ -d "$d" ]] || continue
        local name; name="$(basename "$d")"
        [[ "$name" == "shared" ]] && continue
        local A_NAME="Unknown" A_EMAIL="Unknown" A_PATH="설정되지 않음" SI=""
        while IFS='=' read -r k v; do
            case "$k" in
                ACC_NAME) [[ -n "$v" ]] && A_NAME="$v" ;;
                ACC_EMAIL) [[ -n "$v" ]] && A_EMAIL="$v" ;;
                S_ID) [[ -n "$v" ]] && SI="${v:0:36}" ;;
            esac
        done < <(get_session "${d%/}" "")
        [[ -f "${d}last_path.txt" ]] && A_PATH="$(cat "${d}last_path.txt")"
        echo "[계정 Alias: ${name}] ${A_NAME} - ${A_EMAIL}"
        echo " - 경로: ${A_PATH}"
        if [[ -z "$SI" ]]; then
            echo " - 세션: 알 수 없음"
        else
            echo " - 세션: ${SI}"
        fi
        echo
    done
    echo "=================================================="
}

show_help() {
    cat <<EOF
==================================================
             Agent Manager v${VERSION}
==================================================
[사용법]
 ${SCRIPT_NAME}                          : 마지막 사용 프로파일·경로에서 실행
 ${SCRIPT_NAME} login [Alias]            : 새로운 계정 프로파일 생성 및 로그인 (Alias 생략 시 입력 프롬프트)
 ${SCRIPT_NAME} copy [원본Alias] [신규Alias] : 기존 계정 설정을 복제하여 신규 계정 생성
 ${SCRIPT_NAME} logout [Alias]           : 특정 계정 Alias 삭제
 ${SCRIPT_NAME} remove [Alias]           : 계정 Alias 또는 경로 Alias(이름/실제경로) 삭제 (delete 동일)
 ${SCRIPT_NAME} delete [Alias]           : remove 와 동일
 ${SCRIPT_NAME} reset                    : 모든 계정·경로·설정 초기화
 ${SCRIPT_NAME} remote [Alias] [경로]    : alias 프로파일로 tmux 백그라운드 'claude --remote-control' 실행 (claude.ai/code 원격 제어용)
 ${SCRIPT_NAME} close [Alias]            : 해당 alias 로 열려있는 remote tmux 세션 모두 종료
 ${SCRIPT_NAME} account                  : 사용자 계정 및 세션 정보 출력
 ${SCRIPT_NAME} alias                    : 등록된 계정/경로 Alias 목록 출력
 ${SCRIPT_NAME} version                  : 도구 버전 출력
 ${SCRIPT_NAME} path                     : 등록된 경로 Alias 목록 출력
 ${SCRIPT_NAME} path [경로Alias] [실제경로] : 경로 Alias 등록 (예: ${SCRIPT_NAME} path tabmerge /path/to/TabMerge)
 ${SCRIPT_NAME} [계정 Alias]             : 해당 프로파일로 마지막 경로에서 실행
 ${SCRIPT_NAME} [경로|경로Alias]         : 마지막 프로파일로 지정 경로/경로Alias 에서 실행
 ${SCRIPT_NAME} [계정 Alias] [경로|경로Alias] : 지정 프로파일에서 경로/경로Alias 로 실행
 ${SCRIPT_NAME} install                  : ~/.local/bin/${SCRIPT_NAME} 심볼릭 링크 생성 (PATH 등록)
 ${SCRIPT_NAME} uninstall                : ~/.local/bin/${SCRIPT_NAME} 심볼릭 링크 제거
 ${SCRIPT_NAME} -h, --help               : 도움말

[예약어 - 계정/경로 Alias 로 사용 불가]
 login, copy, reset, logout, remove, delete, remote, close, account, alias, version, path, install, uninstall, help, -h, --help

[환경 변수]
 - CLAUDE_CONFIG_DIR : 활성 프로파일 디렉터리로 설정됨

[예시]
 ${SCRIPT_NAME} login a                  -> 계정 Alias a 로 로그인
 ${SCRIPT_NAME} copy a a1                -> a 설정 복제, a1 생성
 ${SCRIPT_NAME} a ~/workspace            -> a 프로파일로 ~/workspace 작업
 ${SCRIPT_NAME} path tabmerge ~/src/TabMerge -> 경로 Alias 등록
 ${SCRIPT_NAME} a tabmerge               -> a 프로파일로 tabmerge 경로 Alias 위치에서 실행
 ${SCRIPT_NAME} remote a tabmerge        -> a 프로파일로 tabmerge 위치에서 원격 제어용 백그라운드 실행
 ${SCRIPT_NAME} logout a1                -> a1 계정 삭제
==================================================
EOF
}

# ---------- 0. 설치 안내 ----------
case "$ARG1" in
    install|uninstall|version|-h|--help) ;;
    *) check_install_hint ;;
esac

# ---------- 1. 특수 명령어 분기 ----------
case "$ARG1" in
    "" )      : ;;
    -h|--help) show_help; exit 0 ;;
    login)    do_login; exit 0 ;;
    copy)     do_copy; exit 0 ;;
    reset)    do_reset; exit 0 ;;
    logout)   do_logout; exit 0 ;;
    remove|delete) do_remove; exit 0 ;;
    remote)   do_remote; exit 0 ;;
    close)    do_close; exit 0 ;;
    account)  do_account; exit 0 ;;
    version)  do_version; exit 0 ;;
    path)     do_path; exit 0 ;;
    alias)    do_alias; exit 0 ;;
    install)  do_install; exit 0 ;;
    uninstall) do_uninstall; exit 0 ;;
esac

# ---------- 2. 인자 분석: alias / path / path-alias ----------
if [[ -n "$ARG1" ]]; then
    if [[ -d "$ARG1" ]]; then
        NEW_PATH="$ARG1"
    elif [[ ! -d "${CONFIG_BASE_DIR}/${ARG1}" ]] && _resolved=$(get_path_alias "$ARG1") && [[ -n "$_resolved" && -d "$_resolved" ]]; then
        # ARG1 이 계정 alias 가 아니고 path alias 인 경우: 마지막 계정 사용
        NEW_PATH="$_resolved"
    else
        TARGET_ALIAS="$ARG1"
        if [[ -n "$ARG2" ]]; then
            if [[ -d "$ARG2" ]]; then
                NEW_PATH="$ARG2"
            else
                _resolved=$(get_path_alias "$ARG2") || _resolved=""
                if [[ -n "$_resolved" && -d "$_resolved" ]]; then
                    NEW_PATH="$_resolved"
                else
                    echo "[오류] '${ARG2}' 은(는) 등록된 경로 Alias도 아니고 존재하는 경로도 아닙니다."
                    echo "[안내] 경로 Alias 등록: ${SCRIPT_NAME} path <경로Alias> <실제경로>"
                    exit 1
                fi
            fi
        fi
    fi
fi

# ---------- 3. 프로파일 결정 ----------
if [[ -z "$TARGET_ALIAS" && -f "$LAST_ALIAS_FILE" ]]; then
    TARGET_ALIAS="$(cat "$LAST_ALIAS_FILE" 2>/dev/null | tr -d '\r\n' || true)"
fi

if [[ -n "$TARGET_ALIAS" ]]; then
    if [[ -d "${CONFIG_BASE_DIR}/${TARGET_ALIAS}" ]]; then
        export CLAUDE_CONFIG_DIR="${CONFIG_BASE_DIR}/${TARGET_ALIAS}"
        printf '%s' "$TARGET_ALIAS" > "$LAST_ALIAS_FILE"
        echo "[프로필 적용] 계정 Alias '${TARGET_ALIAS}' 프로파일로 실행합니다."
    else
        echo "[오류] '${TARGET_ALIAS}' 계정 Alias에 해당하는 프로파일이 없습니다. ${SCRIPT_NAME} login 으로 먼저 생성하세요."
        exit 1
    fi
else
    echo "[오류] 사용할 프로파일이 없습니다. ${SCRIPT_NAME} login 으로 먼저 생성하세요."
    exit 1
fi

# ---------- 전역 .claude 의 plugins/hooks/skills/agents 를 심볼릭 링크로 공유 ----------
GLOBAL_CLAUDE_DIR="${HOME}/.claude"
mkdir -p "${GLOBAL_CLAUDE_DIR}/plugins" "${GLOBAL_CLAUDE_DIR}/hooks" "${GLOBAL_CLAUDE_DIR}/skills" "${GLOBAL_CLAUDE_DIR}/agents"

for sub in plugins hooks skills agents; do
    target="${CLAUDE_CONFIG_DIR}/${sub}"
    if [[ -L "$target" ]]; then
        # 이미 심볼릭 링크면 그대로 둠
        :
    elif [[ -d "$target" ]]; then
        # 실제 디렉터리면 글로벌로 옮긴 후 링크
        cp -an "${target}/." "${GLOBAL_CLAUDE_DIR}/${sub}/" 2>/dev/null || true
        rm -rf "$target"
        ln -s "${GLOBAL_CLAUDE_DIR}/${sub}" "$target"
    else
        ln -s "${GLOBAL_CLAUDE_DIR}/${sub}" "$target"
    fi
done

# MCP 설정 파일 동기화 (global -> alias)
if [[ -f "${GLOBAL_CLAUDE_DIR}/mcp.json" ]]; then
    cp -f "${GLOBAL_CLAUDE_DIR}/mcp.json" "${CLAUDE_CONFIG_DIR}/mcp.json" 2>/dev/null || true
fi

# settings.json 머지 (global -> alias)
merge_settings "$CLAUDE_CONFIG_DIR" "$GLOBAL_CLAUDE_DIR"

# ---------- 4. 경로 처리 ----------
PROFILE_PATH_FILE="${CLAUDE_CONFIG_DIR}/last_path.txt"
if [[ -n "$NEW_PATH" ]]; then
    printf '%s' "$NEW_PATH" > "$PROFILE_PATH_FILE"
    printf '%s' "$NEW_PATH" > "$GLOBAL_PATH_FILE"
fi

LAST_PATH=""
[[ -f "$PROFILE_PATH_FILE" ]] && LAST_PATH="$(cat "$PROFILE_PATH_FILE" 2>/dev/null | tr -d '\r\n' || true)"
if [[ -z "$LAST_PATH" && -f "$GLOBAL_PATH_FILE" ]]; then
    LAST_PATH="$(cat "$GLOBAL_PATH_FILE" 2>/dev/null | tr -d '\r\n' || true)"
fi
if [[ -z "$LAST_PATH" ]]; then
    echo
    read -r -p "이동할 경로를 입력하세요: " LAST_PATH
    printf '%s' "$LAST_PATH" > "$PROFILE_PATH_FILE"
    printf '%s' "$LAST_PATH" > "$GLOBAL_PATH_FILE"
fi

# ---------- 5. 자동 세션 감지 ----------
RESUME_ARG=()
TEMP_SESSION="${CONFIG_BASE_DIR}/temp_session.txt"
get_session "$CLAUDE_CONFIG_DIR" "$LAST_PATH" > "$TEMP_SESSION"

S_ID=""; S_PATH=""; S_BRANCH=""; S_TIME=""; S_USER=""
while IFS='=' read -r k v; do
    case "$k" in
        S_ID)     S_ID="${v:0:36}" ;;
        S_PATH)   S_PATH="$v" ;;
        S_BRANCH) S_BRANCH="$v" ;;
        S_TIME)   S_TIME="$v" ;;
        S_USER)   S_USER="$v" ;;
    esac
done < "$TEMP_SESSION"

run_claude() {
    rm -f "$TEMP_SESSION" 2>/dev/null
    echo
    echo "\"${LAST_PATH}\" 위치에서 Claude를 실행합니다..."
    echo
    cd "$LAST_PATH" || { echo "[오류] 경로 이동 실패: ${LAST_PATH}"; exit 1; }
    claude "${RESUME_ARG[@]}"
    # 종료 후 alias 쪽 mcp.json 을 글로벌로 역동기화
    if [[ -f "${CLAUDE_CONFIG_DIR}/mcp.json" ]]; then
        cp -f "${CLAUDE_CONFIG_DIR}/mcp.json" "${GLOBAL_CLAUDE_DIR}/mcp.json" 2>/dev/null || true
    fi
}

if [[ -n "$S_ID" ]]; then
    echo "--------------------------------------------------"
    echo "[최근 세션 정보]"
    echo " - 작업 위치: ${S_PATH}"
    echo " - 마지막 시각: ${S_TIME}"
    echo " - 최근 입력: ${S_USER}"
    echo "--------------------------------------------------"

    while true; do
        read -r -p "최근 세션을 이어서 진행할까요? (y/n) 또는 검색할 세션 개수 입력(숫자): " USE_SESSION
        case "$USE_SESSION" in
            y|Y) RESUME_ARG=(--resume "$S_ID"); run_claude; exit 0 ;;
            n|N) run_claude; exit 0 ;;
            "")  continue ;;
        esac
        # 숫자 입력 처리
        if [[ "$USE_SESSION" =~ ^[1-9][0-9]*$ ]]; then
            echo "최근 ${USE_SESSION}개 세션을 검색합니다..."
            FOUND_COUNT=0
            declare -A M_ID M_PATH M_BRANCH M_TIME M_USER M_ASSISTANT
            while IFS='=' read -r k v; do
                case "$k" in
                    S_COUNT) FOUND_COUNT="$v" ;;
                    S_ID_*)        M_ID[${k#S_ID_}]="${v:0:36}" ;;
                    S_PATH_*)      M_PATH[${k#S_PATH_}]="$v" ;;
                    S_BRANCH_*)    M_BRANCH[${k#S_BRANCH_}]="$v" ;;
                    S_TIME_*)      M_TIME[${k#S_TIME_}]="$v" ;;
                    S_USER_*)      M_USER[${k#S_USER_}]="$v" ;;
                    S_ASSISTANT_*) M_ASSISTANT[${k#S_ASSISTANT_}]="$v" ;;
                esac
            done < <(get_session "$CLAUDE_CONFIG_DIR" "$LAST_PATH" "$USE_SESSION")

            if [[ "$FOUND_COUNT" == "0" ]]; then
                echo "검색 결과가 없습니다."
                continue
            fi
            echo "--------------------------------------------------"
            for ((i=1; i<=FOUND_COUNT; i++)); do
                echo "[${i}] 시간: ${M_TIME[$i]:-} | 입력: ${M_USER[$i]:-} | 응답: ${M_ASSISTANT[$i]:-}"
                [[ $i -lt $FOUND_COUNT ]] && echo
            done
            echo "--------------------------------------------------"
            while true; do
                read -r -p "이어서 진행할 번호를 입력하세요 (취소: c): " SEL_INDEX
                if [[ "$SEL_INDEX" == "c" || "$SEL_INDEX" == "C" ]]; then
                    break
                fi
                if [[ -n "${M_ID[$SEL_INDEX]:-}" ]]; then
                    RESUME_ARG=(--resume "${M_ID[$SEL_INDEX]}")
                    run_claude
                    exit 0
                fi
                echo "잘못된 번호입니다."
            done
        fi
    done
else
    echo "[안내] 발견된 세션 정보 없음."
    run_claude
fi
