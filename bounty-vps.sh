#!/bin/bash

# ==================== CONFIGURATION ====================
SCRIPT_NAME="bounty-vps-setup"
SCRIPT_VERSION="2.2"
LOG_FILE="/tmp/$SCRIPT_NAME-$(date +%Y%m%d-%H%M%S).log"
INSTALL_DIR="$HOME/tools"
WORDLISTS_DIR="$HOME/wordlists"
GO_VERSION="1.22.4"
GO_INSTALL_DIR="/usr/local/go"

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
log_message() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [$level] ${message}" | tee -a "$LOG_FILE"
}

log_info()    { log_message "INFO"    "${CYAN}$1${NL}"; }
log_success() { log_message "SUCCESS" "${GR}$1${NL}"; }
log_warning() { log_message "WARNING" "${YELLOW}$1${NL}"; }
log_error()   { log_message "ERROR"   "${RED}$1${NL}"; }

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

    if [[ ":$PATH:" != *":$INSTALL_DIR/bin:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR/bin\"" >> "$shell_rc"
        export PATH="$PATH:$INSTALL_DIR/bin"
        log_success "Added $INSTALL_DIR/bin to PATH"
    fi
}

# ==================== GO SETUP ====================
setup_go_environment() {
    log_info "Setting up Go environment..."

    if command_exists go; then
        local current_go_version
        current_go_version=$(go version | awk '{print $3}')
        log_info "Go already installed: $current_go_version"

        if [[ "$current_go_version" == *"$GO_VERSION"* ]]; then
            log_success "Correct Go version already installed"
        else
            log_warning "Different Go version found ($current_go_version). Continuing with existing version."
        fi
    else
        log_info "Installing Go $GO_VERSION..."
        cd /tmp || exit 1

        local go_archive="go${GO_VERSION}.linux-amd64.tar.gz"

        if ! wget -q --server-response "https://go.dev/dl/${go_archive}" -O "$go_archive" 2>&1 | grep -q "200 OK"; then
            if ! wget -q "https://go.dev/dl/${go_archive}"; then
                log_error "Failed to download Go $GO_VERSION — check the version string"
                return 1
            fi
        fi

        if ! sudo tar -C /usr/local -xzf "$go_archive"; then
            log_error "Failed to extract Go"
            rm -f "$go_archive"
            return 1
        fi

        rm -f "$go_archive"
    fi

    local go_env
    go_env="
# Go Environment
export GOROOT=\"$GO_INSTALL_DIR\"
export GOPATH=\"\$HOME/go\"
export GOBIN=\"\$GOPATH/bin\"
export PATH=\"\$PATH:\$GOROOT/bin:\$GOBIN\"
"

    local shell_rc
    shell_rc="$(get_shell_rc)"
    touch "$shell_rc"

    if ! grep -q "GOROOT=" "$shell_rc" 2>/dev/null; then
        echo "$go_env" >> "$shell_rc"
        log_success "Added Go environment to $shell_rc"
    else
        log_info "Go environment already present in $shell_rc"
    fi

    export GOROOT="$GO_INSTALL_DIR"
    export GOPATH="$HOME/go"
    export GOBIN="$GOPATH/bin"
    export PATH="$PATH:$GOROOT/bin:$GOBIN"

    mkdir -p "$GOPATH"/{src,bin,pkg}

    if command_exists go; then
        log_success "Go ready: $(go version)"
        return 0
    else
        log_error "Go installation failed"
        return 1
    fi
}

# ==================== GO TOOLS ====================
install_go_tool() {
    local tool_name=$1
    local install_cmd=$2

    log_info "Checking: $tool_name"

    if command_exists "$tool_name" || [ -f "$GOBIN/$tool_name" ]; then
        log_info "$tool_name already installed"
        return 0
    fi

    log_info "Installing $tool_name..."

    # Explicitly carry Go env into the subshell — don't trust inherited PATH alone
    local err_out
    err_out=$(env GOROOT="$GOROOT" GOPATH="$GOPATH" GOBIN="$GOBIN" \
        PATH="$PATH:$GOROOT/bin:$GOBIN" \
        bash -c "$install_cmd" 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to install $tool_name"
        echo "$err_out" >> "$LOG_FILE"
        # Surface first meaningful error line to terminal
        echo "$err_out" | grep -E "^(go:|error:|#|cannot|dial|timeout|no required)" | head -3 | \
            while IFS= read -r line; do log_warning "  ↳ $line"; done
        return 1
    fi

    if command_exists "$tool_name"; then
        log_success "Installed $tool_name"
        return 0
    elif [ -f "$GOBIN/$tool_name" ]; then
        sudo ln -sf "$GOBIN/$tool_name" "/usr/local/bin/$tool_name" 2>/dev/null
        log_success "Installed $tool_name (linked from GOBIN)"
        return 0
    fi

    log_warning "$tool_name build succeeded but binary not found — may need shell reload"
    return 1
}

install_go_tools() {
    log_info "Installing Go tools..."

    if ! command_exists go; then
        log_error "Go not found in PATH. Please install Go first."
        return 1
    fi

    # Re-export explicitly so all subshells spawned by install_go_tool see these
    export GOROOT="${GOROOT:-$GO_INSTALL_DIR}"
    export GOPATH="${GOPATH:-$HOME/go}"
    export GOBIN="${GOBIN:-$GOPATH/bin}"
    export PATH="$PATH:$GOROOT/bin:$GOBIN"
    mkdir -p "$GOBIN"

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

    local installed_count=0
    local failed_count=0

    for tool in "${!go_tools[@]}"; do
        if install_go_tool "$tool" "${go_tools[$tool]}"; then
            ((installed_count++))
        else
            ((failed_count++))
        fi
    done

    log_success "Go tools: $installed_count installed, $failed_count failed"

    if command_exists gf; then
        log_info "Setting up gf patterns..."
        mkdir -p ~/.gf
        if git clone --depth 1 https://github.com/tomnomnom/gf.git /tmp/gf-patterns 2>/dev/null; then
            cp -r /tmp/gf-patterns/examples/* ~/.gf/ 2>/dev/null
            log_success "GF base patterns installed"
        fi
        if git clone --depth 1 https://github.com/1ndex-g0d/GF-Patterns.git /tmp/gf-extra 2>/dev/null; then
            cp -r /tmp/gf-extra/*.json ~/.gf/ 2>/dev/null
            log_success "GF extra patterns installed"
        fi
    fi
}

# ==================== PYTHON SETUP ====================
setup_python_environment() {
    log_info "Setting up Python environment..."

    sudo apt update -qq
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

    if ! grep -q "$py_venv/bin" "$shell_rc" 2>/dev/null; then
        echo "export PATH=\"$py_venv/bin:\$PATH\"" >> "$shell_rc"
        log_success "Added Python venv to PATH in $shell_rc"
    fi

    if ! grep -q "alias bounty-venv" "$shell_rc" 2>/dev/null; then
        echo "alias bounty-venv='source $py_venv/bin/activate'" >> "$shell_rc"
        log_success "Created bounty-venv alias in $shell_rc"
    fi

    log_success "Python environment ready"
}

install_python_tool() {
    local tool=$1
    log_info "Checking Python package: $tool"

    if pip show "$tool" >/dev/null 2>&1; then
        log_info "$tool already installed"
        return 0
    fi

    log_info "Installing Python package: $tool..."
    if pip install "$tool" >> "$LOG_FILE" 2>&1; then
        log_success "Installed Python package: $tool"
        return 0
    else
        log_error "Failed to install Python package: $tool"
        return 1
    fi
}

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

    local installed_count=0
    local failed_count=0

    for tool in "${python_tools[@]}"; do
        if install_python_tool "$tool"; then
            ((installed_count++))
        else
            ((failed_count++))
        fi
    done

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

        sudo mkdir -p "$install_path"

        if [ -n "$main_script" ] && [ -f "$main_script" ]; then
            local py_file="$main_script"
        elif [ -f "setup.py" ]; then
            pip install . >> "$LOG_FILE" 2>&1
            log_success "Installed $tool_name via setup.py"
            cd /tmp || true
            return 0
        else
            local py_file
            py_file=$(find . -maxdepth 2 -name "${tool_name}.py" -type f | head -1)
            if [ -z "$py_file" ]; then
                py_file=$(find . -maxdepth 1 -name "*.py" -type f | head -1)
            fi
        fi

        if [ -n "$py_file" ]; then
            sudo cp "$py_file" "$install_path/$tool_name.py"
            sudo chmod +x "$install_path/$tool_name.py"
            local shell_rc
            shell_rc="$(get_shell_rc)"
            if ! grep -q "alias $tool_name=" "$shell_rc"; then
                echo "alias $tool_name='python3 $install_path/$tool_name.py'" >> "$shell_rc"
            fi
            log_success "Installed $tool_name"
            cd /tmp || true
            return 0
        fi

        log_error "Could not find a main script for $tool_name"
        cd /tmp || true
        return 1
    }

    install_from_github "0xRyuk/crtsh"               "crtsh"        "/opt/crtsh"                                "crtsh.py"
    install_from_github "m4ll0k/SecretFinder"         "secretfinder" "$INSTALL_DIR/python/secretfinder"         "SecretFinder.py"
    install_from_github "GerbenJavado/LinkFinder"     "linkfinder"   "$INSTALL_DIR/python/linkfinder"           "linkfinder.py"
    install_from_github "WangYihang/GitHacker"        "githacker"    "$INSTALL_DIR/python/GitHacker"            "GitHacker.py"
    install_from_github "s0md3v/uro"                  "uro"          "$INSTALL_DIR/python/uro"                  ""

    deactivate

    log_success "Python tools: $installed_count installed, $failed_count failed"
}

# ==================== SYSTEM TOOLS ====================
install_system_tools() {
    log_info "Installing system tools..."

    sudo apt update -qq

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

    local installed_count=0
    local failed_count=0

    for tool in "${essential_tools[@]}"; do
        log_info "Checking: $tool"
        if is_installed "$tool" "system"; then
            log_info "$tool already installed"
            continue
        fi

        log_info "Installing $tool..."
        if sudo apt install -y "$tool" >> "$LOG_FILE" 2>&1; then
            log_success "Installed $tool"
            ((installed_count++))
        else
            log_warning "Failed to install $tool (may not exist in repos)"
            ((failed_count++))
        fi
    done

    log_success "System tools: $installed_count installed, $failed_count failed"
}

# ==================== WORDLISTS ====================

# Search for an existing copy of a file anywhere on disk before downloading
find_existing_file() {
    local filename=$1
    find /usr/share/wordlists /usr/share /opt /home /root /data /mnt \
        -maxdepth 6 -name "$filename" -type f 2>/dev/null | head -1
}

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

    for filename in "${!url_wordlists[@]}"; do
        # Already in target dir (real file or symlink)
        if [ -f "$WORDLISTS_DIR/$filename" ]; then
            log_info "Wordlist exists: $filename"
            continue
        fi

        # Search system for an existing copy — symlink instead of re-downloading
        local existing
        existing=$(find_existing_file "$filename")
        if [ -n "$existing" ]; then
            ln -sf "$existing" "$WORDLISTS_DIR/$filename"
            log_success "Symlinked existing $filename → $existing"
            continue
        fi

        # Not found anywhere — download
        log_info "Downloading: $filename"
        if wget -q "${url_wordlists[$filename]}" -O "$WORDLISTS_DIR/$filename"; then
            log_success "Downloaded $filename"
        else
            log_warning "Failed to download $filename"
            rm -f "$WORDLISTS_DIR/$filename"
        fi
    done

    # SecLists
    if [ ! -d "$WORDLISTS_DIR/SecLists" ]; then
        local existing_seclists
        existing_seclists=$(find /usr/share/wordlists /opt /home /root -maxdepth 4 \
            -name "SecLists" -type d 2>/dev/null | head -1)
        if [ -n "$existing_seclists" ]; then
            ln -sf "$existing_seclists" "$WORDLISTS_DIR/SecLists"
            log_success "Symlinked existing SecLists → $existing_seclists"
        else
            log_info "Cloning SecLists (shallow)..."
            git clone --depth 1 https://github.com/danielmiessler/SecLists.git \
                "$WORDLISTS_DIR/SecLists" >> "$LOG_FILE" 2>&1 && \
                log_success "Cloned SecLists" || log_warning "SecLists clone failed"
        fi
    else
        log_info "SecLists already present"
    fi

    # Assetnote wordlists
    if [ ! -d "$WORDLISTS_DIR/assetnote" ]; then
        mkdir -p "$WORDLISTS_DIR/assetnote"

        for wl_name in "aspx.txt" "apiroutes.txt"; do
            local existing_wl
            existing_wl=$(find_existing_file "$wl_name")
            if [ -n "$existing_wl" ]; then
                ln -sf "$existing_wl" "$WORDLISTS_DIR/assetnote/$wl_name"
                log_success "Symlinked existing $wl_name → $existing_wl"
            fi
        done

        [ ! -f "$WORDLISTS_DIR/assetnote/aspx.txt" ] && \
            wget -q "https://wordlists-cdn.assetnote.io/data/manual/aspx.txt" \
                -O "$WORDLISTS_DIR/assetnote/aspx.txt" && \
            log_success "Downloaded aspx.txt"

        [ ! -f "$WORDLISTS_DIR/assetnote/apiroutes.txt" ] && \
            wget -q "https://wordlists-cdn.assetnote.io/data/automated/httparchive_apiroutes_2024.01.28.txt" \
                -O "$WORDLISTS_DIR/assetnote/apiroutes.txt" && \
            log_success "Downloaded apiroutes.txt"
    else
        log_info "Assetnote wordlists already present"
    fi

    log_success "Wordlists setup complete"
}

# ==================== POST INSTALL ====================
post_install_setup() {
    log_info "Running post-install setup..."

    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1 2>/dev/null || true

    # Build massdns if puredns is present and massdns is missing
    if command_exists puredns && ! command_exists massdns; then
        log_info "Building massdns (required by puredns)..."
        cd /tmp || exit 1
        rm -rf massdns
        if git clone --depth 1 https://github.com/blechschmidt/massdns.git >> "$LOG_FILE" 2>&1; then
            cd massdns && make >> "$LOG_FILE" 2>&1
            sudo cp bin/massdns /usr/local/bin/
            log_success "Installed massdns"
        else
            log_warning "Failed to build massdns"
        fi
    fi

    # Re-export Go env explicitly (source ~/.bashrc is a no-op in non-interactive subshell)
    export GOROOT="${GOROOT:-$GO_INSTALL_DIR}"
    export GOPATH="${GOPATH:-$HOME/go}"
    export GOBIN="${GOBIN:-$GOPATH/bin}"
    export PATH="$PATH:$GOROOT/bin:$GOBIN:$INSTALL_DIR/python/venv/bin"

    # Update nuclei templates
    if command_exists nuclei; then
        log_info "Updating nuclei templates..."
        nuclei -ut >> "$LOG_FILE" 2>&1 && log_success "Nuclei templates updated"
    fi

    # Verify key installations
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
    echo -e "Made with ${RED}❤${NL} by ${GR}@sudosuraj${NL}"
    echo -e "${BL}===============================================${NL}"

    check_sudo
    check_internet

    echo "=== Bounty VPS Setup Log ===" > "$LOG_FILE"
    echo "Start time: $(date)"        >> "$LOG_FILE"
    echo "User: $(whoami)"            >> "$LOG_FILE"
    echo "System: $(uname -a)"        >> "$LOG_FILE"

    setup_directories
    install_system_tools
    setup_go_environment
    install_go_tools
    setup_python_environment
    install_python_tools
    setup_wordlists
    post_install_setup

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

trap 'log_error "Script interrupted at line $LINENO"; exit 1' INT TERM

main "$@"
