#!/bin/bash

# ==================== CONFIGURATION ====================
SCRIPT_NAME="bounty-vps-setup"
SCRIPT_VERSION="2.0"
LOG_FILE="/tmp/$SCRIPT_NAME-$(date +%Y%m%d-%H%M%S).log"
INSTALL_DIR="$HOME/tools"
WORDLISTS_DIR="$HOME/wordlists"
GO_VERSION="1.25.6"
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
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [$level] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log_message "INFO" "${CYAN}$1${NL}"
}

log_success() {
    log_message "SUCCESS" "${GR}$1${NL}"
}

log_warning() {
    log_message "WARNING" "${YELLOW}$1${NL}"
}

log_error() {
    log_message "ERROR" "${RED}$1${NL}"
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
            dpkg -l | grep -q "$tool" 2>/dev/null || command_exists "$tool"
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
    
    # Add local bin to PATH if not already
    if [[ ":$PATH:" != *":$INSTALL_DIR/bin:"* ]]; then
        echo "export PATH=\"\$PATH:$INSTALL_DIR/bin\"" >> ~/.bashrc
        export PATH="$PATH:$INSTALL_DIR/bin"
        log_success "Added $INSTALL_DIR/bin to PATH"
    fi
}

# ==================== GO SETUP ====================
setup_go_environment() {
    log_info "Setting up Go environment..."
    
    # Check if Go is already installed
    if command_exists go; then
        CURRENT_GO_VERSION=$(go version | awk '{print $3}')
        log_info "Go already installed: $CURRENT_GO_VERSION"
        
        if [[ "$CURRENT_GO_VERSION" == *"$GO_VERSION"* ]]; then
            log_success "Correct Go version already installed"
            return 0
        else
            log_warning "Different Go version found. Consider upgrading."
        fi
    else
        log_info "Installing Go $GO_VERSION..."
        
        # Download and install Go
        cd /tmp
        if ! wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"; then
            log_error "Failed to download Go"
            return 1
        fi
        
        if ! sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"; then
            log_error "Failed to extract Go"
            return 1
        fi
        
        rm -f "go${GO_VERSION}.linux-amd64.tar.gz"
    fi
    
    # Setup Go environment variables
    local go_env="
    # Go Environment
    export GOROOT=\"$GO_INSTALL_DIR\"
    export GOPATH=\"\$HOME/go\"
    export GOBIN=\"\$GOPATH/bin\"
    export PATH=\"\$PATH:\$GOROOT/bin:\$GOBIN\"
    "
        
        # Add to bashrc if not already present
        # Detect current shell
    LOGIN_SHELL="$(basename "$SHELL")"

    case "$LOGIN_SHELL" in
        bash)
            SHELL_RC="$HOME/.bashrc"
            ;;
        zsh)
            SHELL_RC="$HOME/.zshrc"
            ;;
        fish)
            SHELL_RC="$HOME/.config/fish/config.fish"
            ;;
        *)
            SHELL_RC="$HOME/.profile"
            ;;
    esac

    # Create if missing
    touch "$SHELL_RC"

    # Add Go env if not present
    if ! grep -q "GOROOT=" "$SHELL_RC" 2>/dev/null; then
        echo "$go_env" >> "$SHELL_RC"
        log_success "Added Go environment to $SHELL_RC"
    else
        log_info "Go environment already present in $SHELL_RC"
    fi


    
    # Export for current session
    export GOROOT="$GO_INSTALL_DIR"
    export GOPATH="$HOME/go"
    export GOBIN="$GOPATH/bin"
    export PATH="$PATH:$GOROOT/bin:$GOBIN"
    
    # Create Go directories
    mkdir -p "$GOPATH"/{src,bin,pkg}
    
    # Verify installation
    if command_exists go; then
        log_success "Go installed successfully: $(go version)"
        return 0
    else
        log_error "Go installation failed"
        return 1
    fi
}

install_go_tool() {
    local tool_name=$1
    local tool_path=$2
    local install_cmd=$3
    
    log_info "Checking: $tool_name"
    
    # Check if already installed
    if command_exists "$tool_name"; then
        log_info "$tool_name already installed"
        return 0
    fi
    
    # Try to install
    log_info "Installing $tool_name..."
    
    if eval "$install_cmd" >> "$LOG_FILE" 2>&1; then
        # Verify installation
        if command_exists "$tool_name"; then
            log_success "Installed $tool_name successfully"
            return 0
        else
            # Try alternative paths
            if [ -f "$GOBIN/$tool_name" ]; then
                sudo ln -sf "$GOBIN/$tool_name" "/usr/local/bin/$tool_name" 2>/dev/null
                log_success "Installed $tool_name (linked from GOBIN)"
                return 0
            fi
            log_warning "$tool_name installed but not in PATH"
            return 1
        fi
    else
        log_error "Failed to install $tool_name"
        return 1
    fi
}

install_go_tools() {
    log_info "Installing Go tools..."
    
    # Ensure Go environment is set
    if ! command_exists go; then
        log_error "Go not found in PATH. Please install Go first."
        return 1
    fi
    
    # Array of tools with their installation commands
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
    )
    
    local installed_count=0
    local failed_count=0
    
    for tool in "${!go_tools[@]}"; do
        if install_go_tool "$tool" "" "${go_tools[$tool]}"; then
            ((installed_count++))
        else
            ((failed_count++))
        fi
    done
    
    log_success "Go tools: $installed_count installed, $failed_count failed"
    
    # Install tool configurations
    if command_exists gf; then
        log_info "Setting up gf patterns..."
        mkdir -p ~/.gf
        git clone https://github.com/tomnomnom/gf.git /tmp/gf-patterns 2>/dev/null && \
            cp -r /tmp/gf-patterns/examples/* ~/.gf/ 2>/dev/null && \
            log_success "GF patterns installed"
    fi
}

# ==================== PYTHON SETUP ====================
setup_python_environment() {
    log_info "Setting up Python environment..."

    # Ensure system dependencies
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip python3-dev

    PY_VENV="$INSTALL_DIR/python/venv"

    # Create venv if missing
    if [ ! -d "$PY_VENV" ]; then
        python3 -m venv "$PY_VENV"
        log_success "Python virtual environment created at $PY_VENV"
    else
        log_info "Python virtual environment already exists"
    fi

    # Upgrade pip inside venv
    source "$PY_VENV/bin/activate"
    pip install --upgrade pip setuptools wheel
    deactivate

    # Add venv bin to PATH (shell-aware)
    LOGIN_SHELL="$(basename "$SHELL")"
    case "$LOGIN_SHELL" in
        bash) SHELL_RC="$HOME/.bashrc" ;;
        zsh)  SHELL_RC="$HOME/.zshrc" ;;
        fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)    SHELL_RC="$HOME/.profile" ;;
    esac

    touch "$SHELL_RC"

    if ! grep -q "$PY_VENV/bin" "$SHELL_RC" 2>/dev/null; then
        echo "export PATH=\"$PY_VENV/bin:\$PATH\"" >> "$SHELL_RC"
        log_success "Added Python venv to PATH in $SHELL_RC"
    else
        log_info "Python venv already in PATH"
    fi

    log_success "Python environment ready"
}


install_python_tools() {
    log_info "Installing Python tools..."
    PY_VENV="$INSTALL_DIR/python/venv"
    source "$PY_VENV/bin/activate"
    
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
    
    # Install from GitHub repositories
    install_from_github() {
        local repo=$1
        local tool_name=$2
        local install_path=$3
        
        log_info "Installing $tool_name from GitHub..."
        
        if [ -d "/tmp/$tool_name" ]; then
            rm -rf "/tmp/$tool_name"
        fi
        
        if git clone "https://github.com/$repo.git" "/tmp/$tool_name" 2>> "$LOG_FILE"; then
            cd "/tmp/$tool_name"
            
            # Install requirements if they exist
            if [ -f "requirements.txt" ]; then
                pip3 install -r requirements.txt 2>> "$LOG_FILE"
            fi
            
            # Setup tool
            sudo mkdir -p "$install_path"
            local py_file=$(find . -name "*.py" -type f | head -1)
            if [ -n "$py_file" ]; then
                sudo cp "$py_file" "$install_path/$tool_name.py"
                sudo chmod +x "$install_path/$tool_name.py"
                echo "alias $tool_name='python3 $install_path/$tool_name.py'" >> ~/.bashrc
                log_success "Installed $tool_name"
                return 0
            fi
        fi
        
        log_error "Failed to install $tool_name"
        return 1
    }
    
    # Install specific GitHub tools
    install_from_github "0xRyuk/crtsh" "crtsh" "/opt/crtsh"
    install_from_github "m4ll0k/SecretFinder" "secretfinder" "/opt/secretfinder"
    install_from_github "GerbenJavado/LinkFinder" "linkfinder" "/opt/linkfinder"
    
    log_success "Python tools: $installed_count installed, $failed_count failed"
}

# ==================== SYSTEM TOOLS ====================
install_system_tools() {
    log_info "Installing system tools..."
    
    # Update package list
    sudo apt update
    
    # Essential tools
    local essential_tools=(
        "curl" "wget" "git" "jq" "unzip" "build-essential"
        "libssl-dev" "libffi-dev" "python3-dev" "ruby"
        "nmap" "masscan" "netcat" "socat" "tcpdump"
        "whois" "dnsutils" "net-tools" "htop" "tmux"
        "zsh" "vim" "nano" "tree" "rsync" "ssh"
    )
    
    # Security tools
    local security_tools=(
        "sqlmap" "nikto" "dirb" "gobuster" "whatweb"
        "hydra" "john" "hashcat" "aircrack-ng"
        "binwalk" "exiftool" "strings" "file"
        "radare2" "binutils" "gdb" "arjun"
    )
    
    local installed_count=0
    local failed_count=0
    
    # Install essential tools
    for tool in "${essential_tools[@]}"; do
        log_info "Checking: $tool"
        if is_installed "$tool" "system"; then
            log_info "$tool already installed"
            continue
        fi
        
        log_info "Installing $tool..."
        if sudo apt install -y "$tool" 2>> "$LOG_FILE"; then
            log_success "Installed $tool"
            ((installed_count++))
        else
            log_warning "Failed to install $tool"
            ((failed_count++))
        fi
    done
    
    log_success "System tools: $installed_count installed, $failed_count failed"
}

# ==================== WORDLISTS ====================
setup_wordlists() {
    log_info "Setting up wordlists..."
    
    if [ ! -d "$WORDLISTS_DIR" ]; then
        mkdir -p "$WORDLISTS_DIR"
    fi
    
    cd "$WORDLISTS_DIR"
    
    # Common wordlists
    declare -A wordlists=(
        ["/usr/share/wordlists/rockyou.txt"]="sudo apt install -y wordlists 2>/dev/null || true"
        ["$WORDLISTS_DIR/common.txt"]="wget -q https://gist.githubusercontent.com/jhaddix/86a06c5dc309d08580a018c66354a056/raw/96f4e51d96b2203f19f6381c8c545b278eaa0837/all.txt -O common.txt"
        ["$WORDLISTS_DIR/subdomains.txt"]="wget -q https://wordlists-cdn.assetnote.io/data/manual/best-dns-wordlist.txt -O subdomains.txt"
        ["$WORDLISTS_DIR/directory-list.txt"]="wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/common.txt -O directory-list.txt"
        ["$WORDLISTS_DIR/parameters.txt"]="wget -q https://raw.githubusercontent.com/danielmiessler/SecLists/master/Discovery/Web-Content/burp-parameter-names.txt -O parameters.txt"
    )
    
    for wordlist in "${!wordlists[@]}"; do
        local filename=$(basename "$wordlist")
        
        if [ -f "$wordlist" ] || [ -f "$WORDLISTS_DIR/$filename" ]; then
            log_info "Wordlist exists: $filename"
            continue
        fi
        
        log_info "Downloading: $filename"
        eval "${wordlists[$wordlist]}" 2>> "$LOG_FILE"
        
        if [ -f "$filename" ]; then
            log_success "Downloaded $filename"
        else
            log_warning "Failed to download $filename"
        fi
    done
    
    # Clone SecLists if not present
    if [ ! -d "$WORDLISTS_DIR/SecLists" ]; then
        log_info "Cloning SecLists..."
        git clone --depth 1 https://github.com/danielmiessler/SecLists.git 2>> "$LOG_FILE" && \
            log_success "Cloned SecLists"
    fi
    
    log_success "Wordlists setup complete"
}

# ==================== POST INSTALL ====================
post_install_setup() {
    log_info "Running post-install setup..."
    
    # Update alternatives
    sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 1
    
    # Setup massdns for puredns
    if command_exists puredns && [ ! -f "/usr/local/bin/massdns" ]; then
        log_info "Setting up massdns for puredns..."
        cd /tmp
        git clone https://github.com/blechschmidt/massdns.git
        cd massdns
        make
        sudo cp bin/massdns /usr/local/bin/
        log_success "Installed massdns"
    fi
    
    # Setup resolvers
    if [ ! -f "$HOME/resolvers.txt" ]; then
        log_info "Downloading resolvers..."
        wget -q https://raw.githubusercontent.com/projectdiscovery/dnsx/main/scripts/resolvers.txt -O "$HOME/resolvers.txt"
        log_success "Downloaded resolvers"
    fi
    
    # Source bashrc
    source ~/.bashrc
    
    # Verify key tools
    log_info "Verifying key installations..."
    
    declare -A key_tools=(
        ["nmap"]="nmap --version"
        ["go"]="go version"
        ["python3"]="python3 --version"
        ["git"]="git --version"
        ["subfinder"]="subfinder -version"
        ["httpx"]="httpx -version"
        ["nuclei"]="nuclei -version"
    )
    
    for tool in "${!key_tools[@]}"; do
        if command_exists "$tool"; then
            log_success "$tool is installed"
        else
            log_warning "$tool is NOT installed"
        fi
    done
}

# ==================== MAIN EXECUTION ====================
main() {
    clear
    
    # Banner
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
    
    # Initial checks
    check_sudo
    check_internet
    
    # Create log header
    echo "=== Bounty VPS Setup Log ===" > "$LOG_FILE"
    echo "Start time: $(date)" >> "$LOG_FILE"
    echo "User: $(whoami)" >> "$LOG_FILE"
    echo "System: $(uname -a)" >> "$LOG_FILE"
    
    # Setup
    setup_directories
    install_system_tools
    setup_go_environment
    install_go_tools
    setup_python_environment
    install_python_tools
    setup_wordlists
    post_install_setup

    LOGIN_SHELL="$(basename "$SHELL")"

    case "$LOGIN_SHELL" in
        bash)
            SHELL_RC="$HOME/.bashrc"
            ;;
        zsh)
            SHELL_RC="$HOME/.zshrc"
            ;;
        fish)
            SHELL_RC="$HOME/.config/fish/config.fish"
            ;;
        *)
            SHELL_RC="$HOME/.profile"
            ;;
    esac

    
    # Final message
    echo -e "\n${GR}===============================================${NL}"
    echo -e "${GR}          SETUP COMPLETE! 🎉${NL}"
    echo -e "===============================================${NL}"
    echo -e "\n${WH}Next steps:${NL}"
    echo -e "1. ${CYAN}Reload your shell:${NL}   ${WH}source $SHELL_RC${NL}"
    echo -e "2. ${CYAN}Activate Python venv:${NL}   ${WH}bounty-venv${NL}"
    echo -e "3. ${CYAN}Update nuclei templates:${NL}   ${WH}nuclei -ut${NL}"
    echo -e "4. ${CYAN}Configure API keys for:${NL}   ${WH}- GitHub Token${NL}   ${WH}- Chaos API${NL}   ${WH}- Shodan API${NL}"
    echo -e "\n${YELLOW}Log file saved at: $LOG_FILE${NL}"
    echo -e "\n${BL}Happy Hunting! 🔍${NL}"
}

# Trap errors
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main
main "$@"
