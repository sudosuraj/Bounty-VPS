#!/bin/bash

# ==================== CONFIGURATION ====================
SCRIPT_NAME="bounty-vps-setup"
SCRIPT_VERSION="2.4"
LOG_FILE="/tmp/$SCRIPT_NAME-$(date +%Y%m%d-%H%M%S).log"
INSTALL_DIR="$HOME/tools"
WORDLISTS_DIR="$HOME/wordlists"
GO_VERSION="1.22.4"
GO_INSTALL_DIR="/usr/local/go"

# Two separate concurrency caps, because network-bound work (downloads,
# release-asset fetches) and CPU-bound work (compiling) behave very
# differently:
#   - MAX_PARALLEL_NET:   used for downloads / GitHub release fetches /
#                          `go install` fallback for tools without binaries.
#                          These mostly wait on network I/O, so it's fine
#                          (and much faster) to run far more of these at once
#                          than you have cores.
#   - MAX_PARALLEL_BUILD: used for actual local compilation (make, go build
#                          fallback compiling from source). Capped at core
#                          count since compiling is CPU-bound.
# Override with: MAX_PARALLEL_NET=N MAX_PARALLEL_BUILD=N ./bounty-vps-setup.sh
MAX_PARALLEL_NET="${MAX_PARALLEL_NET:-15}"
MAX_PARALLEL_BUILD="${MAX_PARALLEL_BUILD:-$(nproc 2>/dev/null || echo 4)}"
[ "$MAX_PARALLEL_BUILD" -lt 2 ] 2>/dev/null && MAX_PARALLEL_BUILD=4
# Kept for backward-compat with any code below that doesn't care which kind
MAX_PARALLEL="$MAX_PARALLEL_NET"

# ==================== COLOR SETUP ====================
OR='\e[38;5;202m'
GR='\e[32m'
NL='\e[0m'
WH='\e[97m'
BL='\e[34m'
RED='\e[31m'
CYAN='\e[36m'
YELLOW='\e[33m'

# ==================== LOGGING FUNCTIONS ====================
# NOTE: log_message uses flock around the tee/append so concurrent background
# jobs writing to the same LOG_FILE don't interleave/corrupt each other.
log_message() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    (
        flock -w 5 200
        echo -e "${timestamp} [$level] ${message}" | tee -a "$LOG_FILE" >/dev/null
        echo -e "${timestamp} [$level] ${message}"
    ) 200>>"$LOG_FILE.lock"
}

log_info()    { log_message "INFO"    "${CYAN}$1${NL}"; }
log_success() { log_message "SUCCESS" "${GR}$1${NL}"; }
log_warning() { log_message "WARNING" "${YELLOW}$1${NL}"; }
log_error()   { log_message "ERROR"   "${RED}$1${NL}"; }

# ==================== JOB POOL HELPER ====================
# Simple bounded-parallelism helper: call `pool_wait_for_slot [limit]` before
# backgrounding a new job to block until fewer than `limit` jobs of this
# script are running (defaults to MAX_PARALLEL_NET). Works on bash 4.3+
# (uses wait -n).
pool_wait_for_slot() {
    local limit="${1:-$MAX_PARALLEL_NET}"
    while [ "$(jobs -rp | wc -l)" -ge "$limit" ]; do
        wait -n 2>/dev/null || sleep 0.2
    done
}

# ==================== UTILITY FUNCTIONS ====================
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_installed() {
    local tool=$1
    local type=$2

    case "$type" in
        "go")
            command_exists "$tool" || [ -f "$HOME/go/bin/$tool" ] || [ -f "/usr/local/bin/$tool" ]
            ;;
        "python")
            pip3 show "$tool" >/dev/null 2>&1 || command_exists "$tool"
            ;;
        "system")
            dpkg -l | awk '{print $2}' | grep -qw "$tool" 2>/dev/null || command_exists "$tool"
            ;;
        *)
            command_exists "$tool"
            ;;
    esac
}

check_sudo() {
    if [ "$EUID" -eq 0 ]; then
        log_error "Do not run as root! Use sudo when needed."
        exit 1
    fi

    if ! sudo -v; then
        log_error "User does not have sudo privileges"
        exit 1
    fi

    # Keep sudo alive in the background for the duration of the script so
    # long parallel sections don't hit a sudo timeout halfway through.
    # IMPORTANT: disown it immediately — otherwise it's an infinite background
    # job that any later bare `wait` (or `jobs -rp` count in pool_wait_for_slot)
    # would also wait on/count, since it never exits on its own. That was
    # causing the script to hang forever after all real work finished.
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    disown "$SUDO_KEEPALIVE_PID" 2>/dev/null
}

check_internet() {
    if ! curl -s --connect-timeout 10 https://github.com > /dev/null; then
        log_error "No internet connection. Please check your network."
        exit 1
    fi
}

get_shell_rc() {
    local login_shell
    login_shell="$(basename "$SHELL")"
    case "$login_shell" in
        bash) echo "$HOME/.bashrc" ;;
        zsh)  echo "$HOME/.zshrc" ;;
        fish) echo "$HOME/.config/fish/config.fish" ;;
        *)    echo "$HOME/.profile" ;;
    esac
}

# Append a line to shell_rc only if an equivalent line isn't already present.
# Uses fixed-string matching so special characters (like $ in PATH exports) are safe.
# flock-protected since multiple parallel installers may call this concurrently
# (e.g. github tool installers each adding an alias line).
append_once() {
    local file=$1
    local line=$2
    (
        flock -w 5 201
        if ! grep -qF -- "$line" "$file" 2>/dev/null; then
            echo "$line" >> "$file"
            exit 0
        fi
        exit 1
    ) 201>>"$file.lock"
}

setup_directories() {
    log_info "Setting up directories..."

    for dir in "$INSTALL_DIR" "$WORDLISTS_DIR" "$INSTALL_DIR/go" "$INSTALL_DIR/python" "$INSTALL_DIR/bin"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_success "Created directory: $dir"
        else
            log_info "Directory exists: $dir"
        fi
    done

    local shell_rc
    shell_rc="$(get_shell_rc)"
    touch "$shell_rc"

    # IMPORTANT: check the shell_rc FILE for an existing entry, not the live $PATH.
    # Checking $PATH was the cause of duplicate entries on every run, since a
    # non-interactive script invocation doesn't necessarily inherit a PATH that
    # already includes lines appended to ~/.zshrc in a previous run.
    if append_once "$shell_rc" "export PATH=\"\$PATH:$INSTALL_DIR/bin\""; then
        log_success "Added $INSTALL_DIR/bin to PATH in $shell_rc"
    else
        log_info "$INSTALL_DIR/bin already present in $shell_rc"
    fi

    export PATH="$PATH:$INSTALL_DIR/bin"
}

# ==================== GO SETUP ====================
setup_go_environment() {
    log_info "Setting up Go environment..."

    local detected_goroot=""

    if command_exists go; then
        if go version >/dev/null 2>&1; then
            detected_goroot=$(go env GOROOT 2>/dev/null)
            local current_go_version
            current_go_version=$(go version | awk '{print $3}')
            log_info "Go already installed: $current_go_version (GOROOT: $detected_goroot)"

            if [[ "$current_go_version" == *"$GO_VERSION"* ]]; then
                log_success "Correct Go version already installed"
            else
                log_warning "Different Go version found ($current_go_version). Continuing with existing version."
            fi

            if [ -z "$detected_goroot" ] || [ ! -d "$detected_goroot" ] || [ ! -x "$detected_goroot/bin/go" ]; then
                log_warning "Detected GOROOT ('$detected_goroot') looks broken or missing — will reinstall Go"
                detected_goroot=""
            fi
        else
            log_warning "A 'go' binary is on PATH but is not functional — will reinstall Go"
        fi
    fi

    if [ -z "$detected_goroot" ]; then
        log_info "Installing Go $GO_VERSION..."
        cd /tmp || exit 1

        local go_archive="go${GO_VERSION}.linux-amd64.tar.gz"

        if ! wget -q --server-response "https://go.dev/dl/${go_archive}" -O "$go_archive" 2>&1 | grep -q "200 OK"; then
            if ! wget -q "https://go.dev/dl/${go_archive}"; then
                log_error "Failed to download Go $GO_VERSION — check the version string"
                return 1
            fi
        fi

        sudo rm -rf "$GO_INSTALL_DIR"

        if ! sudo tar -C /usr/local -xzf "$go_archive"; then
            log_error "Failed to extract Go"
            rm -f "$go_archive"
            return 1
        fi

        rm -f "$go_archive"
        detected_goroot="$GO_INSTALL_DIR"
    fi

    GO_INSTALL_DIR="$detected_goroot"

    local go_env
    go_env="
# Go Environment
export GOROOT=\"$GO_INSTALL_DIR\"
export GOPATH=\"\$HOME/go\"
export GOBIN=\"\$GOPATH/bin\"
export PATH=\"\$PATH:\$GOROOT/bin:\$GOBIN\"
# Speed: skip the sumdb network round-trip per dependency, use module proxy
export GOPROXY=\"https://proxy.golang.org,direct\"
export GOSUMDB=\"off\"
export GOFLAGS=\"-mod=mod\"
"

    local shell_rc
    shell_rc="$(get_shell_rc)"
    touch "$shell_rc"

    if grep -q "# Go Environment" "$shell_rc" 2>/dev/null; then
        if grep -qF "GOROOT=\"$GO_INSTALL_DIR\"" "$shell_rc" 2>/dev/null; then
            log_info "Go environment already correctly configured in $shell_rc"
        else
            log_warning "Go environment block in $shell_rc is stale — refreshing it"
            sed -i '/# Go Environment/,/^export GOFLAGS="-mod=mod"$/d' "$shell_rc"
            echo "$go_env" >> "$shell_rc"
            log_success "Refreshed Go environment in $shell_rc"
        fi
    else
        echo "$go_env" >> "$shell_rc"
        log_success "Added Go environment to $shell_rc"
    fi

    export GOROOT="$GO_INSTALL_DIR"
    export GOPATH="$HOME/go"
    export GOBIN="$GOPATH/bin"
    export PATH="$PATH:$GOROOT/bin:$GOBIN"
    export GOPROXY="https://proxy.golang.org,direct"
    export GOSUMDB="off"
    export GOFLAGS="-mod=mod"

    mkdir -p "$GOPATH"/{src,bin,pkg}

    if command_exists go; then
        local verify_goroot
        verify_goroot=$(go env GOROOT 2>/dev/null)
        if [ -n "$verify_goroot" ] && [ "$verify_goroot" != "$GOROOT" ]; then
            log_warning "GOROOT mismatch detected (shell=$GOROOT, go reports=$verify_goroot) — using go's reported value"
            export GOROOT="$verify_goroot"
        fi
        log_success "Go ready: $(go version) [GOROOT=$GOROOT]"
        return 0
    else
        log_error "Go installation failed"
        return 1
    fi
}

# ==================== GO TOOLS (RELEASE-BINARY-FIRST, PARALLEL) ====================
# The real bottleneck in the old version wasn't lack of parallelism — it was
# `go install ...@latest` compiling each tool FROM SOURCE every run, which
# means: resolving the whole module graph, downloading every transitive
# dependency, then compiling. For the projectdiscovery suite, ffuf, dalfox,
# gowitness, amass, and puredns, the upstream project already publishes a
# prebuilt linux_amd64 binary as a GitHub release. Grabbing that asset is a
# single small download — typically 5-20x faster than a from-source build.
#
# Strategy per tool:
#   1. If a GitHub repo is known for this tool, try to fetch its latest
#      release and pull down a linux/amd64 binary asset (no compiling).
#   2. If that fails (no matching asset, rate-limited, API error, etc.),
#      fall back to the original `go install` command.
# Release-fetch attempts run in the larger network pool (MAX_PARALLEL_NET);
# `go install` fallback work runs in the smaller build pool
# (MAX_PARALLEL_BUILD) since it's CPU-bound compilation.

# Repos that publish prebuilt linux/amd64 release binaries.
declare -A GO_TOOL_RELEASE_REPOS=(
    ["subfinder"]="projectdiscovery/subfinder"
    ["katana"]="projectdiscovery/katana"
    ["httpx"]="projectdiscovery/httpx"
    ["nuclei"]="projectdiscovery/nuclei"
    ["naabu"]="projectdiscovery/naabu"
    ["dnsx"]="projectdiscovery/dnsx"
    ["notify"]="projectdiscovery/notify"
    ["mapcidr"]="projectdiscovery/mapcidr"
    ["interactsh-client"]="projectdiscovery/interactsh"
    ["tlsx"]="projectdiscovery/tlsx"
    ["alterx"]="projectdiscovery/alterx"
    ["asnmap"]="projectdiscovery/asnmap"
    ["shuffledns"]="projectdiscovery/shuffledns"
    ["cdncheck"]="projectdiscovery/cdncheck"
    ["urlfinder"]="projectdiscovery/urlfinder"
    ["uncover"]="projectdiscovery/uncover"
    ["ffuf"]="ffuf/ffuf"
    ["dalfox"]="hahwul/dalfox"
    ["gowitness"]="sensepost/gowitness"
    ["amass"]="owasp-amass/amass"
    ["puredns"]="d3mondev/puredns"
)

# Try to install $tool_name from its latest GitHub release binary.
# Returns 0 on success (binary placed at $GOBIN/$tool_name), 1 otherwise —
# caller should fall back to `go install` on failure.
try_install_go_tool_from_release() {
    local tool_name=$1
    local repo=$2

    local release_json
    release_json=$(curl -sf --connect-timeout 10 --max-time 20 \
        "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)
    [ -z "$release_json" ] && return 1

    # Pick a linux/amd64 (or x86_64) asset, excluding checksums/sboms/arm builds.
    local asset_url
    asset_url=$(echo "$release_json" \
        | grep -oE '"browser_download_url" *: *"[^"]*"' \
        | cut -d'"' -f4 \
        | grep -iE '(linux)' \
        | grep -iE '(amd64|x86_64|x86-64)' \
        | grep -viE '(arm|aarch64|\.sha256|\.sbom|checksums|\.sig|\.pem)' \
        | head -1)
    [ -z "$asset_url" ] && return 1

    local tmp_dir
    tmp_dir=$(mktemp -d "/tmp/${tool_name}-release.XXXXXX")
    local asset_file="$tmp_dir/$(basename "$asset_url")"

    if ! curl -sfL --connect-timeout 15 --max-time 60 "$asset_url" -o "$asset_file" 2>/dev/null; then
        rm -rf "$tmp_dir"
        return 1
    fi

    case "$asset_file" in
        *.zip)
            unzip -oq "$asset_file" -d "$tmp_dir" 2>/dev/null
            ;;
        *.tar.gz | *.tgz)
            tar -xzf "$asset_file" -C "$tmp_dir" 2>/dev/null
            ;;
        *) : ;; # raw binary asset, nothing to extract
    esac

    # Find the extracted binary: prefer an exact name match, else the only
    # executable file that isn't a doc/license/checksum.
    local bin_path
    bin_path=$(find "$tmp_dir" -maxdepth 2 -type f -name "$tool_name" 2>/dev/null | head -1)
    if [ -z "$bin_path" ]; then
        bin_path=$(find "$tmp_dir" -maxdepth 2 -type f \
            ! -iname "*.md" ! -iname "LICENSE*" ! -iname "*.txt" ! -iname "*.zip" ! -iname "*.tar.gz" \
            -perm -u+r 2>/dev/null | head -1)
    fi
    # Raw single-file binary asset case (no archive at all)
    if [ -z "$bin_path" ] && [[ "$asset_file" != *.zip && "$asset_file" != *.tar.gz && "$asset_file" != *.tgz ]]; then
        bin_path="$asset_file"
    fi

    if [ -z "$bin_path" ] || [ ! -f "$bin_path" ]; then
        rm -rf "$tmp_dir"
        return 1
    fi

    mkdir -p "$GOBIN"
    chmod +x "$bin_path"
    cp "$bin_path" "$GOBIN/$tool_name"
    rm -rf "$tmp_dir"
    return 0
}

install_go_tool_job() {
    local tool_name=$1
    local install_cmd=$2
    local status_dir=$3

    if command_exists "$tool_name" || [ -f "$GOBIN/$tool_name" ]; then
        log_info "$tool_name already installed"
        echo "skip" > "$status_dir/$tool_name"
        return 0
    fi

    local repo="${GO_TOOL_RELEASE_REPOS[$tool_name]:-}"
    if [ -n "$repo" ]; then
        log_info "Fetching $tool_name release binary from $repo..."
        if try_install_go_tool_from_release "$tool_name" "$repo"; then
            sudo -n ln -sf "$GOBIN/$tool_name" "/usr/local/bin/$tool_name" 2>/dev/null
            log_success "Installed $tool_name (prebuilt release binary)"
            echo "ok" > "$status_dir/$tool_name"
            return 0
        fi
        log_warning "$tool_name: no usable release binary found — falling back to source build"
    fi

    log_info "Building $tool_name from source..."

    local err_out
    err_out=$(env GOROOT="$GOROOT" GOPATH="$GOPATH" GOBIN="$GOBIN" \
        GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}" GOSUMDB="${GOSUMDB:-off}" \
        PATH="$PATH:$GOROOT/bin:$GOBIN" \
        timeout 180 bash -c "$install_cmd" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 124 ]; then
        log_error "$tool_name: build timed out after 180s — skipping"
        echo "$err_out" >> "$LOG_FILE"
        echo "fail" > "$status_dir/$tool_name"
        return 1
    fi

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to install $tool_name"
        echo "$err_out" >> "$LOG_FILE"
        echo "$err_out" | grep -E "^(go:|error:|#|cannot|dial|timeout|no required)" | head -3 | \
            while IFS= read -r line; do log_warning "  ↳ $line"; done
        echo "fail" > "$status_dir/$tool_name"
        return 1
    fi

    if command_exists "$tool_name"; then
        log_success "Installed $tool_name (built from source)"
        echo "ok" > "$status_dir/$tool_name"
        return 0
    elif [ -f "$GOBIN/$tool_name" ]; then
        sudo -n ln -sf "$GOBIN/$tool_name" "/usr/local/bin/$tool_name" 2>/dev/null
        log_success "Installed $tool_name (built from source, linked from GOBIN)"
        echo "ok" > "$status_dir/$tool_name"
        return 0
    fi

    log_warning "$tool_name build succeeded but binary not found — may need shell reload"
    echo "warn" > "$status_dir/$tool_name"
    return 1
}

install_go_tools() {
    log_info "Installing Go tools (release binaries where available, source build fallback)..."
    log_info "Network pool: $MAX_PARALLEL_NET parallel | Build pool: $MAX_PARALLEL_BUILD parallel"

    if ! command_exists go; then
        log_error "Go not found in PATH. Please install Go first."
        return 1
    fi

    export GOROOT="${GOROOT:-$GO_INSTALL_DIR}"
    export GOPATH="${GOPATH:-$HOME/go}"
    export GOBIN="${GOBIN:-$GOPATH/bin}"
    export PATH="$PATH:$GOROOT/bin:$GOBIN"
    export GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"
    export GOSUMDB="${GOSUMDB:-off}"
    mkdir -p "$GOBIN"

    if [ ! -x "$GOROOT/bin/go" ]; then
        log_error "GOROOT ($GOROOT) does not contain a valid go binary — aborting Go tools install"
        log_error "Try re-running the script; setup_go_environment should repair this on the next pass"
        return 1
    fi

    declare -A go_tools=(
        ["subfinder"]="go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        ["anew"]="go install -v github.com/tomnomnom/anew@latest"
        ["assetfinder"]="go install github.com/tomnomnom/assetfinder@latest"
        ["katana"]="go install github.com/projectdiscovery/katana/cmd/katana@latest"
        ["waybackurls"]="go install github.com/tomnomnom/waybackurls@latest"
        ["httpx"]="go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest"
        ["nuclei"]="go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
        ["naabu"]="go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
        ["dnsx"]="go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
        ["notify"]="go install -v github.com/projectdiscovery/notify/cmd/notify@latest"
        ["mapcidr"]="go install -v github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest"
        ["interactsh-client"]="go install -v github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest"
        ["tlsx"]="go install -v github.com/projectdiscovery/tlsx/cmd/tlsx@latest"
        ["alterx"]="go install -v github.com/projectdiscovery/alterx/cmd/alterx@latest"
        ["asnmap"]="go install -v github.com/projectdiscovery/asnmap/cmd/asnmap@latest"
        ["shuffledns"]="go install -v github.com/projectdiscovery/shuffledns/cmd/shuffledns@latest"
        ["puredns"]="go install github.com/d3mondev/puredns/v2@latest"
        ["ffuf"]="go install github.com/ffuf/ffuf@latest"
        ["gau"]="go install github.com/lc/gau/v2/cmd/gau@latest"
        ["hakrawler"]="go install github.com/hakluke/hakrawler@latest"
        ["gowitness"]="go install github.com/sensepost/gowitness@latest"
        ["gospider"]="go install github.com/jaeles-project/gospider@latest"
        ["dalfox"]="go install -v github.com/hahwul/dalfox/v2@latest"
        ["amass"]="go install -v github.com/owasp-amass/amass/v4/...@master"
        ["gf"]="go install github.com/tomnomnom/gf@latest"
        ["qsreplace"]="go install github.com/tomnomnom/qsreplace@latest"
        ["unfurl"]="go install github.com/tomnomnom/unfurl@latest"
        ["gron"]="go install github.com/tomnomnom/gron@latest"
        ["cdncheck"]="go install -v github.com/projectdiscovery/cdncheck/cmd/cdncheck@latest"
        ["urlfinder"]="go install -v github.com/projectdiscovery/urlfinder/cmd/urlfinder@latest"
        ["uncover"]="go install -v github.com/projectdiscovery/uncover/cmd/uncover@latest"
    )

    local status_dir
    status_dir=$(mktemp -d /tmp/go-tools-status.XXXXXX)

    # Tools with a known release repo get the large network-bound pool since
    # they're just doing an API call + a small download. Tools that are
    # going straight to `go install` (no release repo known) get the smaller
    # build pool since they'll actually compile.
    local job_pids=()
    for tool in "${!go_tools[@]}"; do
        if [ -n "${GO_TOOL_RELEASE_REPOS[$tool]:-}" ]; then
            pool_wait_for_slot "$MAX_PARALLEL_NET"
        else
            pool_wait_for_slot "$MAX_PARALLEL_BUILD"
        fi
        install_go_tool_job "$tool" "${go_tools[$tool]}" "$status_dir" &
        job_pids+=("$!")
    done
    wait "${job_pids[@]}" 2>/dev/null

    local installed_count=0 failed_count=0 skipped_count=0
    for f in "$status_dir"/*; do
        case "$(cat "$f" 2>/dev/null)" in
            ok)   ((installed_count++)) ;;
            skip) ((skipped_count++)) ;;
            *)    ((failed_count++)) ;;
        esac
    done
    rm -rf "$status_dir"

    log_success "Go tools: $installed_count installed, $skipped_count already present, $failed_count failed"

    if command_exists gf; then
        log_info "Setting up gf patterns..."
        mkdir -p ~/.gf
        # Tarball download instead of git clone — skips git's object
        # negotiation overhead for what's just a couple of small dirs.
        (
            curl -sfL --connect-timeout 10 --max-time 30 \
                "https://github.com/tomnomnom/gf/archive/refs/heads/master.tar.gz" \
                -o /tmp/gf-base.tar.gz 2>/dev/null &&
            tar -xzf /tmp/gf-base.tar.gz -C /tmp 2>/dev/null &&
            cp -r /tmp/gf-master/examples/* ~/.gf/ 2>/dev/null &&
            log_success "GF base patterns installed"
        ) &
        (
            curl -sfL --connect-timeout 10 --max-time 30 \
                "https://github.com/1ndex-g0d/GF-Patterns/archive/refs/heads/main.tar.gz" \
                -o /tmp/gf-extra.tar.gz 2>/dev/null &&
            tar -xzf /tmp/gf-extra.tar.gz -C /tmp 2>/dev/null &&
            cp -r /tmp/GF-Patterns-main/*.json ~/.gf/ 2>/dev/null &&
            log_success "GF extra patterns installed"
        ) &
        wait
    fi
}


# ==================== PYTHON SETUP ====================
setup_python_environment() {
    log_info "Setting up Python environment..."

    # apt update already ran in install_system_tools(); no need to repeat it.
    sudo apt install -y python3 python3-venv python3-pip python3-dev

    local py_venv="$INSTALL_DIR/python/venv"

    if [ ! -d "$py_venv" ]; then
        python3 -m venv "$py_venv"
        log_success "Python virtual environment created at $py_venv"
    else
        log_info "Python virtual environment already exists"
    fi

    source "$py_venv/bin/activate"
    pip install --upgrade pip setuptools wheel >> "$LOG_FILE" 2>&1
    deactivate

    local shell_rc
    shell_rc="$(get_shell_rc)"
    touch "$shell_rc"

    if append_once "$shell_rc" "export PATH=\"$py_venv/bin:\$PATH\""; then
        log_success "Added Python venv to PATH in $shell_rc"
    else
        log_info "Python venv PATH entry already present in $shell_rc"
    fi

    if append_once "$shell_rc" "alias bounty-venv='source $py_venv/bin/activate'"; then
        log_success "Created bounty-venv alias in $shell_rc"
    else
        log_info "bounty-venv alias already present in $shell_rc"
    fi

    log_success "Python environment ready"
}

# ==================== PYTHON TOOLS (PARALLEL) ====================
install_python_tools() {
    log_info "Installing Python tools..."

    local py_venv="$INSTALL_DIR/python/venv"
    source "$py_venv/bin/activate"

    local python_tools=(
        "arjun"
        "jsbeautifier"
        "lxml"
        "requests"
        "beautifulsoup4"
        "urllib3"
        "colorama"
        "pyyaml"
        "tldextract"
        "dnspython"
        "shodan"
        "censys"
        "paramspider"
    )

    # Single batched pip install instead of N separate pip invocations.
    # pip resolves the whole set together and reuses its HTTP connection /
    # wheel cache, which is dramatically faster than looping pip per-package.
    # First figure out which ones are already installed so we don't even
    # send those to the resolver.
    local to_install=()
    for tool in "${python_tools[@]}"; do
        if pip show "$tool" >/dev/null 2>&1; then
            log_info "$tool already installed"
        else
            to_install+=("$tool")
        fi
    done

    local installed_count=$(( ${#python_tools[@]} - ${#to_install[@]} ))
    local failed_count=0

    if [ "${#to_install[@]}" -gt 0 ]; then
        log_info "Installing ${#to_install[@]} Python packages in one batch: ${to_install[*]}"
        if pip install "${to_install[@]}" >> "$LOG_FILE" 2>&1; then
            for tool in "${to_install[@]}"; do
                log_success "Installed Python package: $tool"
            done
            ((installed_count+=${#to_install[@]}))
        else
            # Batch failed (one bad package can sink the whole batch) — fall
            # back to per-package installs so one failure doesn't block the rest,
            # but still run them in parallel.
            log_warning "Batched pip install failed — falling back to parallel per-package installs"
            local status_dir
            status_dir=$(mktemp -d /tmp/pip-tools-status.XXXXXX)
            for tool in "${to_install[@]}"; do
                pool_wait_for_slot
                (
                    if pip install "$tool" >> "$LOG_FILE" 2>&1; then
                        log_success "Installed Python package: $tool"
                        echo ok > "$status_dir/$tool"
                    else
                        log_error "Failed to install Python package: $tool"
                        echo fail > "$status_dir/$tool"
                    fi
                ) &
            done
            wait
            for f in "$status_dir"/*; do
                [ "$(cat "$f" 2>/dev/null)" = "ok" ] && ((installed_count++)) || ((failed_count++))
            done
            rm -rf "$status_dir"
        fi
    fi

    install_from_github() {
        local repo=$1
        local tool_name=$2
        local install_path=$3
        local main_script=${4:-}

        log_info "Installing $tool_name from GitHub..."

        rm -rf "/tmp/$tool_name"

        if ! git clone --depth 1 "https://github.com/$repo.git" "/tmp/$tool_name" 2>> "$LOG_FILE"; then
            log_error "Failed to clone $repo"
            return 1
        fi

        cd "/tmp/$tool_name" || return 1

        if [ -f "requirements.txt" ]; then
            pip install -r requirements.txt >> "$LOG_FILE" 2>&1
        fi

        sudo -n mkdir -p "$install_path"

        local py_file=""
        if [ -n "$main_script" ] && [ -f "$main_script" ]; then
            py_file="$main_script"
        elif [ -f "setup.py" ]; then
            pip install . >> "$LOG_FILE" 2>&1
            log_success "Installed $tool_name via setup.py"
            return 0
        else
            py_file=$(find . -maxdepth 2 -name "${tool_name}.py" -type f | head -1)
            if [ -z "$py_file" ]; then
                py_file=$(find . -maxdepth 1 -name "*.py" -type f | head -1)
            fi
        fi

        if [ -n "$py_file" ]; then
            sudo -n cp "$py_file" "$install_path/$tool_name.py"
            sudo -n chmod +x "$install_path/$tool_name.py"
            local shell_rc
            shell_rc="$(get_shell_rc)"
            append_once "$shell_rc" "alias $tool_name='python3 $install_path/$tool_name.py'" >/dev/null
            log_success "Installed $tool_name"
            return 0
        fi

        log_error "Could not find a main script for $tool_name"
        return 1
    }
    export -f install_from_github
    export -f log_info log_success log_warning log_error log_message append_once get_shell_rc

    # Run the GitHub-based python tool installs in parallel — each clones into
    # its own /tmp/<tool_name> dir so there's no path collision between jobs.
    (install_from_github "0xRyuk/crtsh"           "crtsh"        "/opt/crtsh"                        "crtsh.py")        &
    (install_from_github "m4ll0k/SecretFinder"    "secretfinder" "$INSTALL_DIR/python/secretfinder"  "SecretFinder.py") &
    (install_from_github "GerbenJavado/LinkFinder" "linkfinder"  "$INSTALL_DIR/python/linkfinder"    "linkfinder.py")   &
    (install_from_github "WangYihang/GitHacker"   "githacker"    "$INSTALL_DIR/python/GitHacker"     "GitHacker.py")    &
    (install_from_github "s0md3v/uro"             "uro"          "$INSTALL_DIR/python/uro"           "")                &
    wait

    deactivate

    log_success "Python tools: $installed_count installed, $failed_count failed"
}

# ==================== SYSTEM TOOLS ====================
# apt itself doesn't meaningfully parallelize across separate invocations
# (it serializes on the dpkg lock anyway), so the real win here is replacing
# N sequential `apt install` calls (each with its own dependency resolution
# and lock acquisition) with a single batched call for everything that's
# actually missing. We also enable apt's parallel package *download* via
# acquire::queue-mode, which does help on multi-package transactions.
install_system_tools() {
    log_info "Installing system tools..."

    sudo apt update -qq

    # Allow apt to download multiple packages concurrently (doesn't affect
    # the dpkg install step itself, but cuts fetch time noticeably).
    echo 'Acquire::Queue-Mode "host"; Acquire::Retries "3";' | \
        sudo tee /etc/apt/apt.conf.d/99parallel-fetch >/dev/null 2>&1

    local essential_tools=(
        "curl" "wget" "git" "jq" "unzip" "build-essential"
        "libssl-dev" "libffi-dev" "python3-dev" "ruby"
        "nmap" "masscan" "ncat" "socat" "tcpdump"
        "whois" "dnsutils" "net-tools" "htop" "tmux"
        "zsh" "vim" "nano" "tree" "rsync" "openssh-client"
        "sqlmap" "nikto" "gobuster" "whatweb"
        "hydra" "john" "hashcat"
        "binwalk" "exiftool"
        "radare2" "gdb"
        "chromium-browser"
        "parallel"
        "proxychains4"
    )

    local to_install=()
    for tool in "${essential_tools[@]}"; do
        log_info "Checking: $tool"
        if is_installed "$tool" "system"; then
            log_info "$tool already installed"
        else
            to_install+=("$tool")
        fi
    done

    local installed_count=0
    local failed_count=0

    if [ "${#to_install[@]}" -gt 0 ]; then
        log_info "Installing ${#to_install[@]} packages in a single apt transaction: ${to_install[*]}"
        if sudo apt install -y "${to_install[@]}" >> "$LOG_FILE" 2>&1; then
            for tool in "${to_install[@]}"; do
                log_success "Installed $tool"
            done
            installed_count=${#to_install[@]}
        else
            # If the batch fails (e.g. one package name doesn't exist in repos,
            # such as chromium-browser on some distros), fall back to
            # installing each individually so one bad name doesn't block the rest.
            log_warning "Batched apt install hit an error — retrying packages individually"
            for tool in "${to_install[@]}"; do
                if sudo apt install -y "$tool" >> "$LOG_FILE" 2>&1; then
                    log_success "Installed $tool"
                    ((installed_count++))
                else
                    log_warning "Failed to install $tool (may not exist in repos)"
                    ((failed_count++))
                fi
            done
        fi
    fi

    log_success "System tools: $installed_count installed, $failed_count failed"
}

# ==================== WORDLISTS (PARALLEL DOWNLOADS) ====================

find_existing_file() {
    local filename=$1
    find /usr/share/wordlists /usr/share /opt /home /root /data /mnt \
        -maxdepth 6 -name "$filename" -type f 2>/dev/null | head -1
}
export -f find_existing_file

setup_wordlists() {
    log_info "Setting up wordlists..."
    mkdir -p "$WORDLISTS_DIR"
    cd "$WORDLISTS_DIR" || exit 1

    # rockyou
    if [ ! -f "/usr/share/wordlists/rockyou.txt" ] && [ ! -f "/usr/share/wordlists/rockyou.txt.gz" ]; then
        local existing_rockyou
        existing_rockyou=$(find_existing_file "rockyou.txt")
        if [ -n "$existing_rockyou" ]; then
            ln -sf "$existing_rockyou" "$WORDLISTS_DIR/rockyou.txt"
            log_success "Symlinked existing rockyou → $existing_rockyou"
        else
            sudo apt install -y wordlists >> "$LOG_FILE" 2>&1 && \
                log_success "Installed rockyou via apt" || \
                log_warning "wordlists package not available"
        fi
    else
        log_info "rockyou already present"
    fi

    declare -A url_wordlists=(
        ["common.txt"]="https://gist.githubusercontent.com/jhaddix/86a06c5dc309d08580a018c66354a056/raw/96f4e51d96b2203f19f6381c8c545b278eaa0837/all.txt"
        ["subdomains-best.txt"]="https://wordlists-cdn.assetnote.io/data/manual/best-dns-wordlist.txt"
        ["directory-list.txt"]="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/common.txt"
        ["parameters.txt"]="https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/burp-parameter-names.txt"
        ["resolvers.txt"]="https://raw.githubusercontent.com/projectdiscovery/dnsx/main/scripts/resolvers.txt"
    )

    # Fire off all wordlist downloads/symlinks in parallel (bounded), each
    # independent of the others, then wait for the whole batch.
    for filename in "${!url_wordlists[@]}"; do
        if [ -f "$WORDLISTS_DIR/$filename" ]; then
            log_info "Wordlist exists: $filename"
            continue
        fi

        pool_wait_for_slot
        (
            local existing
            existing=$(find_existing_file "$filename")
            if [ -n "$existing" ]; then
                ln -sf "$existing" "$WORDLISTS_DIR/$filename"
                log_success "Symlinked existing $filename → $existing"
                exit 0
            fi

            log_info "Downloading: $filename"
            if wget -q "${url_wordlists[$filename]}" -O "$WORDLISTS_DIR/$filename"; then
                log_success "Downloaded $filename"
            else
                log_warning "Failed to download $filename"
                rm -f "$WORDLISTS_DIR/$filename"
            fi
        ) &
    done

    # SecLists (large clone) and Assetnote wordlists run concurrently with
    # the small downloads above rather than waiting for them first.
    if [ ! -d "$WORDLISTS_DIR/SecLists" ]; then
        pool_wait_for_slot
        (
            local existing_seclists
            existing_seclists=$(find /usr/share/wordlists /opt /home /root -maxdepth 4 \
                -name "SecLists" -type d 2>/dev/null | head -1)
            if [ -n "$existing_seclists" ]; then
                ln -sf "$existing_seclists" "$WORDLISTS_DIR/SecLists"
                log_success "Symlinked existing SecLists → $existing_seclists"
            else
                log_info "Downloading SecLists (tarball, faster than git clone)..."
                if curl -sfL --connect-timeout 15 --max-time 300 \
                        "https://github.com/danielmiessler/SecLists/archive/refs/heads/master.tar.gz" \
                        -o /tmp/seclists.tar.gz 2>/dev/null \
                    && mkdir -p "$WORDLISTS_DIR/SecLists" \
                    && tar -xzf /tmp/seclists.tar.gz -C "$WORDLISTS_DIR/SecLists" --strip-components=1 2>/dev/null; then
                    log_success "Downloaded SecLists"
                    rm -f /tmp/seclists.tar.gz
                else
                    log_warning "SecLists tarball download failed — falling back to git clone"
                    rm -rf "$WORDLISTS_DIR/SecLists" /tmp/seclists.tar.gz
                    git clone --depth 1 https://github.com/danielmiessler/SecLists.git \
                        "$WORDLISTS_DIR/SecLists" >> "$LOG_FILE" 2>&1 && \
                        log_success "Cloned SecLists" || log_warning "SecLists clone failed"
                fi
            fi
        ) &
    else
        log_info "SecLists already present"
    fi

    if [ ! -d "$WORDLISTS_DIR/assetnote" ]; then
        pool_wait_for_slot
        (
            mkdir -p "$WORDLISTS_DIR/assetnote"

            for wl_name in "aspx.txt" "apiroutes.txt"; do
                existing_wl=$(find_existing_file "$wl_name")
                if [ -n "$existing_wl" ]; then
                    ln -sf "$existing_wl" "$WORDLISTS_DIR/assetnote/$wl_name"
                    log_success "Symlinked existing $wl_name → $existing_wl"
                fi
            done

            if [ ! -f "$WORDLISTS_DIR/assetnote/aspx.txt" ]; then
                wget -q "https://wordlists-cdn.assetnote.io/data/manual/aspx.txt" \
                    -O "$WORDLISTS_DIR/assetnote/aspx.txt" && \
                    log_success "Downloaded aspx.txt"
            fi

            if [ ! -f "$WORDLISTS_DIR/assetnote/apiroutes.txt" ]; then
                wget -q "https://wordlists-cdn.assetnote.io/data/automated/httparchive_apiroutes_2024.01.28.txt" \
                    -O "$WORDLISTS_DIR/assetnote/apiroutes.txt" && \
                    log_success "Downloaded apiroutes.txt"
            fi
        ) &
    else
        log_info "Assetnote wordlists already present"
    fi

    wait
    log_success "Wordlists setup complete"
}

# ==================== POST INSTALL ====================
post_install_setup() {
    log_info "Running post-install setup..."

    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || true

    if command_exists puredns && ! command_exists massdns; then
        log_info "Building massdns (required by puredns)..."
        cd /tmp || exit 1
        rm -rf massdns
        if git clone --depth 1 https://github.com/blechschmidt/massdns.git >> "$LOG_FILE" 2>&1; then
            cd massdns && make -j"$MAX_PARALLEL_BUILD" >> "$LOG_FILE" 2>&1
            sudo -n cp bin/massdns /usr/local/bin/
            log_success "Installed massdns"
        else
            log_warning "Failed to build massdns"
        fi
    fi

    export GOROOT="${GOROOT:-$GO_INSTALL_DIR}"
    export GOPATH="${GOPATH:-$HOME/go}"
    export GOBIN="${GOBIN:-$GOPATH/bin}"
    export PATH="$PATH:$GOROOT/bin:$GOBIN:$INSTALL_DIR/python/venv/bin"

    if command_exists nuclei; then
        log_info "Updating nuclei templates..."
        nuclei -ut >> "$LOG_FILE" 2>&1 && log_success "Nuclei templates updated"
    fi

    log_info "Verifying key installations..."

    local key_tools=("nmap" "go" "python3" "git" "subfinder" "httpx" "nuclei" "ffuf" "dalfox" "puredns")

    for tool in "${key_tools[@]}"; do
        if command_exists "$tool" || [ -f "$GOBIN/$tool" ]; then
            log_success "✓ $tool"
        else
            log_warning "✗ $tool not found in PATH"
        fi
    done
}

# ==================== MAIN EXECUTION ====================
main() {
    clear

    echo -e "${OR}
    ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
    ██▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██
    ██╔════════════════════════════════╗██
    ██║    Bounty VPS Setup Script     ║██
    ██║         Version $SCRIPT_VERSION            ║██
    ██╚════════════════════════════════╝██
    ██▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██
    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${NL}"

    echo -e "Log file: ${WH}$LOG_FILE${NL}"
    echo -e "Parallel jobs: ${WH}net=$MAX_PARALLEL_NET build=$MAX_PARALLEL_BUILD${NL}"
    echo -e "Made with ${RED}❤${NL} by ${GR}@sudosuraj${NL}"
    echo -e "${BL}===============================================${NL}"

    check_sudo
    check_internet

    echo "=== Bounty VPS Setup Log ===" > "$LOG_FILE"
    echo "Start time: $(date)"        >> "$LOG_FILE"
    echo "User: $(whoami)"            >> "$LOG_FILE"
    echo "System: $(uname -a)"        >> "$LOG_FILE"
    echo "Max parallel (net/build): $MAX_PARALLEL_NET / $MAX_PARALLEL_BUILD" >> "$LOG_FILE"

    setup_directories
    install_system_tools
    setup_go_environment
    install_go_tools
    setup_python_environment
    install_python_tools
    setup_wordlists
    post_install_setup

    [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null

    local shell_rc
    shell_rc="$(get_shell_rc)"

    echo -e "\n${GR}===============================================${NL}"
    echo -e "${GR}          SETUP COMPLETE! 🎉${NL}"
    echo -e "===============================================${NL}"
    echo -e "\n${WH}Next steps:${NL}"
    echo -e "1. ${CYAN}Reload your shell:${NL}          ${WH}source $shell_rc${NL}"
    echo -e "2. ${CYAN}Activate Python venv:${NL}       ${WH}bounty-venv${NL}"
    echo -e "3. ${CYAN}Nuclei templates already updated during setup${NL}"
    echo -e "4. ${CYAN}Configure API keys for:${NL}     ${WH}~/.config/subfinder/provider-config.yaml${NL}"
    echo -e "   ${WH}  - GitHub Token (subfinder, amass)${NL}"
    echo -e "   ${WH}  - Chaos API    (subfinder)${NL}"
    echo -e "   ${WH}  - Shodan API   (uncover, shodan python lib)${NL}"
    echo -e "   ${WH}  - Censys API   (uncover, censys python lib)${NL}"
    echo -e "5. ${CYAN}Wordlists are at:${NL}           ${WH}$WORDLISTS_DIR${NL}"
    echo -e "\n${YELLOW}Log file saved at: $LOG_FILE${NL}"
    echo -e "\n${BL}Happy Hunting! 🔍${NL}"
}

trap 'log_error "Script interrupted at line $LINENO"; [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; exit 1' INT TERM

main "$@"
