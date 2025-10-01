#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required commands
check_requirements() {
    log_info "Checking required commands..."
    
    local required_commands=("git" "curl" "wget")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "The following commands are not installed: ${missing_commands[*]}"
        log_info "You can install them with:"
        echo "  sudo apt-get install -y ${missing_commands[*]}"
        exit 1
    fi
    
    # Check for yq (YAML parser)
    if ! command -v yq &> /dev/null; then
        log_warning "yq is not installed. Attempting to install..."
        install_yq
    fi
    
    log_success "All required commands are available"
}

# Install yq
install_yq() {
    log_info "Installing yq..."
    
    local YQ_VERSION="v4.35.1"
    local YQ_BINARY="yq_linux_amd64"
    
    wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq
    
    if [ $? -eq 0 ]; then
        sudo chmod +x /tmp/yq
        sudo mv /tmp/yq /usr/local/bin/yq
        log_success "yq installation completed"
    else
        log_error "Failed to install yq"
        log_info "Will parse YAML using alternative method"
    fi
}

# Create directory structure
create_directory_structure() {
    log_info "Creating directory structure..."
    
    mkdir -p Tools
    mkdir -p Tools/Windows-Weapons
    mkdir -p Tools/Linux-Weapons
    
    log_success "Directory structure creation completed"
}

# Clone Git repository
clone_repository() {
    local name=$1
    local url=$2
    local directory=$3
    
    local target_path="${directory}/${name}"
    
    if [ -d "$target_path" ]; then
        log_warning "${name} already exists. Skipping"
        return 0
    fi
    
    log_info "Cloning: ${name} -> ${target_path}"
    
    git clone --depth 1 "$url" "$target_path" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Cloning ${name} completed"
        return 0
    else
        log_error "Failed to clone ${name}"
        return 1
    fi
}

# Direct file download
download_file() {
    local name=$1
    local url=$2
    local directory=$3
    
    local target_path="${directory}/${name}"
    
    if [ -f "$target_path" ]; then
        log_warning "${name} already exists. Skipping"
        return 0
    fi
    
    log_info "Downloading: ${name} -> ${target_path}"
    
    wget -q --show-progress "$url" -O "$target_path"
    
    if [ $? -eq 0 ]; then
        chmod +x "$target_path" 2>/dev/null
        log_success "Download of ${name} completed"
        return 0
    else
        log_error "Failed to download ${name}"
        return 1
    fi
}

# Process YAML file using yq
install_from_yaml_with_yq() {
    local yaml_file=$1
    
    log_info "Installing general tools from YAML file..."
    local tools_count=$(yq eval '.tools | length' "$yaml_file")
    for ((i=0; i<$tools_count; i++)); do
        local name=$(yq eval ".tools[$i].name" "$yaml_file")
        local url=$(yq eval ".tools[$i].url" "$yaml_file")
        clone_repository "$name" "$url" "Tools"
    done
    
    log_info "Installing Linux-Weapons from YAML file..."
    local linux_count=$(yq eval '.linux_weapons | length' "$yaml_file")
    for ((i=0; i<$linux_count; i++)); do
        local name=$(yq eval ".linux_weapons[$i].name" "$yaml_file")
        local url=$(yq eval ".linux_weapons[$i].url" "$yaml_file")
        clone_repository "$name" "$url" "Tools/Linux-Weapons"
    done
    
    log_info "Installing Windows-Weapons from YAML file..."
    local windows_count=$(yq eval '.windows_weapons | length' "$yaml_file")
    for ((i=0; i<$windows_count; i++)); do
        local name=$(yq eval ".windows_weapons[$i].name" "$yaml_file")
        local url=$(yq eval ".windows_weapons[$i].url" "$yaml_file")
        clone_repository "$name" "$url" "Tools/Windows-Weapons"
    done
    
    log_info "Fetching direct download files..."
    local direct_tools_count=$(yq eval '.direct_downloads.tools | length' "$yaml_file")
    for ((i=0; i<$direct_tools_count; i++)); do
        local name=$(yq eval ".direct_downloads.tools[$i].name" "$yaml_file")
        local url=$(yq eval ".direct_downloads.tools[$i].url" "$yaml_file")
        
        # Download only if URL is a direct file link
        if [[ "$url" == *.exe ]] || [[ "$url" == *.ps1 ]] || [[ "$url" == *.sh ]]; then
            download_file "$name" "$url" "Tools"
        else
            log_warning "${name} is a link to release page. Please download manually: $url"
        fi
    done
    
    local direct_windows_count=$(yq eval '.direct_downloads.windows_weapons | length' "$yaml_file")
    for ((i=0; i<$direct_windows_count; i++)); do
        local name=$(yq eval ".direct_downloads.windows_weapons[$i].name" "$yaml_file")
        local url=$(yq eval ".direct_downloads.windows_weapons[$i].url" "$yaml_file")
        
        if [[ "$url" == *.exe ]] || [[ "$url" == *.zip ]]; then
            download_file "$name" "$url" "Tools/Windows-Weapons"
        else
            log_warning "${name} is a link to release page. Please download manually: $url"
        fi
    done
    
    log_info "Executing special installations..."
    local special_count=$(yq eval '.special_installs | length' "$yaml_file")
    for ((i=0; i<$special_count; i++)); do
        local name=$(yq eval ".special_installs[$i].name" "$yaml_file")
        local url=$(yq eval ".special_installs[$i].url" "$yaml_file" 2>/dev/null)
        local command=$(yq eval ".special_installs[$i].command" "$yaml_file" 2>/dev/null)
        local directory=$(yq eval ".special_installs[$i].directory" "$yaml_file")
        
        if [ "$url" != "null" ]; then
            download_file "$name" "$url" "$directory"
        elif [ "$command" != "null" ]; then
            log_info "Executing special command: ${name}"
            eval "$command" > "${directory}/${name}"
            chmod +x "${directory}/${name}"
            log_success "Successfully retrieved ${name}"
        fi
    done
}

# Fallback when yq is not available (basic list only)
install_from_yaml_fallback() {
    log_warning "yq is not available, will clone repositories manually"
    log_info "This process may take some time..."
    
    # Use hardcoded list (minimal)
    log_info "Installing essential tools only..."
    
    # Tools directory
    declare -A tools_repos=(
        ["BloodHound.py"]="https://github.com/dirkjanm/BloodHound.py"
        ["chisel"]="https://github.com/jpillora/chisel"
        ["impacket"]="https://github.com/ropnop/impacket_static_binaries"
        ["mimikatz"]="https://github.com/ParrotSec/mimikatz"
        ["ligolo-ng"]="https://github.com/nicocha30/ligolo-ng"
    )
    
    for name in "${!tools_repos[@]}"; do
        clone_repository "$name" "${tools_repos[$name]}" "Tools"
    done
    
    # Linux-Weapons
    declare -A linux_repos=(
        ["LinPEAS"]="https://github.com/peass-ng/PEASS-ng"
        ["pspy"]="https://github.com/DominicBreuker/pspy"
        ["PwnKit"]="https://github.com/ly4k/PwnKit"
    )
    
    for name in "${!linux_repos[@]}"; do
        clone_repository "$name" "${linux_repos[$name]}" "Tools/Linux-Weapons"
    done
    
    # Windows-Weapons
    declare -A windows_repos=(
        ["winPEAS"]="https://github.com/peass-ng/PEASS-ng"
        ["mimikatz"]="https://github.com/ParrotSec/mimikatz"
        ["SharpHound"]="https://github.com/SpecterOps/SharpHound"
    )
    
    for name in "${!windows_repos[@]}"; do
        clone_repository "$name" "${windows_repos[$name]}" "Tools/Windows-Weapons"
    done
    
    log_warning "To perform a complete installation, install yq and re-run the script"
}

# Main process
main() {
    echo "=========================================="
    echo "  Security Tools Auto Installer"
    echo "=========================================="
    echo ""
    
    local yaml_file="tools_config.yaml"
    
    # Requirements check
    check_requirements
    
    # Create directories
    create_directory_structure
    
    # Check YAML file existence
    if [ ! -f "$yaml_file" ]; then
        log_error "YAML file '$yaml_file' not found"
        log_info "Please place tools_config.yaml in the same directory"
        exit 1
    fi
    
    # Start installation
    log_info "Starting installation..."
    echo ""
    
    if command -v yq &> /dev/null; then
        install_from_yaml_with_yq "$yaml_file"
    else
        install_from_yaml_fallback
    fi
    
    echo ""
    log_success "All installations completed!"
    echo ""
    log_info "Installation directories:"
    echo "  - Tools/"
    echo "  - Tools/Linux-Weapons/"
    echo "  - Tools/Windows-Weapons/"
    echo ""
    log_warning "Note: Some tools require manual download from release pages"
}

# Execute script
main "$@"
