#!/bin/bash

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
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

# 必要なコマンドのチェック
check_requirements() {
    log_info "必要なコマンドをチェック中..."
    
    local required_commands=("git" "curl" "wget")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -ne 0 ]; then
        log_error "以下のコマンドがインストールされていません: ${missing_commands[*]}"
        log_info "以下のコマンドでインストールできます:"
        echo "  sudo apt-get install -y ${missing_commands[*]}"
        exit 1
    fi
    
    # yqのチェック（YAMLパーサー）
    if ! command -v yq &> /dev/null; then
        log_warning "yqがインストールされていません。インストールを試みます..."
        install_yq
    fi
    
    log_success "すべての必要なコマンドが利用可能です"
}

# yqのインストール
install_yq() {
    log_info "yqをインストール中..."
    
    local YQ_VERSION="v4.35.1"
    local YQ_BINARY="yq_linux_amd64"
    
    wget -q "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}" -O /tmp/yq
    
    if [ $? -eq 0 ]; then
        sudo chmod +x /tmp/yq
        sudo mv /tmp/yq /usr/local/bin/yq
        log_success "yqのインストールが完了しました"
    else
        log_error "yqのインストールに失敗しました"
        log_info "代替方法でYAMLを解析します"
    fi
}

# ディレクトリ構造の作成
create_directory_structure() {
    log_info "ディレクトリ構造を作成中..."
    
    mkdir -p Tools
    mkdir -p Tools/Windows-Weapons
    mkdir -p Tools/Linux-Weapons
    
    log_success "ディレクトリ構造の作成が完了しました"
}

# Gitリポジトリのクローン
clone_repository() {
    local name=$1
    local url=$2
    local directory=$3
    
    local target_path="${directory}/${name}"
    
    if [ -d "$target_path" ]; then
        log_warning "${name} は既に存在します。スキップします"
        return 0
    fi
    
    log_info "クローン中: ${name} -> ${target_path}"
    
    git clone --depth 1 "$url" "$target_path" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "${name} のクローンが完了しました"
        return 0
    else
        log_error "${name} のクローンに失敗しました"
        return 1
    fi
}

# ファイルの直接ダウンロード
download_file() {
    local name=$1
    local url=$2
    local directory=$3
    
    local target_path="${directory}/${name}"
    
    if [ -f "$target_path" ]; then
        log_warning "${name} は既に存在します。スキップします"
        return 0
    fi
    
    log_info "ダウンロード中: ${name} -> ${target_path}"
    
    wget -q --show-progress "$url" -O "$target_path"
    
    if [ $? -eq 0 ]; then
        chmod +x "$target_path" 2>/dev/null
        log_success "${name} のダウンロードが完了しました"
        return 0
    else
        log_error "${name} のダウンロードに失敗しました"
        return 1
    fi
}

# YAMLファイルが存在する場合の処理（yqを使用）
install_from_yaml_with_yq() {
    local yaml_file=$1
    
    log_info "YAMLファイルから一般ツールをインストール中..."
    local tools_count=$(yq eval '.tools | length' "$yaml_file")
    for ((i=0; i<$tools_count; i++)); do
        local name=$(yq eval ".tools[$i].name" "$yaml_file")
        local url=$(yq eval ".tools[$i].url" "$yaml_file")
        clone_repository "$name" "$url" "Tools"
    done
    
    log_info "YAMLファイルからLinux-Weaponsをインストール中..."
    local linux_count=$(yq eval '.linux_weapons | length' "$yaml_file")
    for ((i=0; i<$linux_count; i++)); do
        local name=$(yq eval ".linux_weapons[$i].name" "$yaml_file")
        local url=$(yq eval ".linux_weapons[$i].url" "$yaml_file")
        clone_repository "$name" "$url" "Tools/Linux-Weapons"
    done
    
    log_info "YAMLファイルからWindows-Weaponsをインストール中..."
    local windows_count=$(yq eval '.windows_weapons | length' "$yaml_file")
    for ((i=0; i<$windows_count; i++)); do
        local name=$(yq eval ".windows_weapons[$i].name" "$yaml_file")
        local url=$(yq eval ".windows_weapons[$i].url" "$yaml_file")
        clone_repository "$name" "$url" "Tools/Windows-Weapons"
    done
    
    log_info "直接ダウンロードファイルを取得中..."
    local direct_tools_count=$(yq eval '.direct_downloads.tools | length' "$yaml_file")
    for ((i=0; i<$direct_tools_count; i++)); do
        local name=$(yq eval ".direct_downloads.tools[$i].name" "$yaml_file")
        local url=$(yq eval ".direct_downloads.tools[$i].url" "$yaml_file")
        
        # URLが実際のファイルへの直接リンクの場合のみダウンロード
        if [[ "$url" == *.exe ]] || [[ "$url" == *.ps1 ]] || [[ "$url" == *.sh ]]; then
            download_file "$name" "$url" "Tools"
        else
            log_warning "${name} はリリースページへのリンクです。手動でダウンロードしてください: $url"
        fi
    done
    
    local direct_windows_count=$(yq eval '.direct_downloads.windows_weapons | length' "$yaml_file")
    for ((i=0; i<$direct_windows_count; i++)); do
        local name=$(yq eval ".direct_downloads.windows_weapons[$i].name" "$yaml_file")
        local url=$(yq eval ".direct_downloads.windows_weapons[$i].url" "$yaml_file")
        
        if [[ "$url" == *.exe ]] || [[ "$url" == *.zip ]]; then
            download_file "$name" "$url" "Tools/Windows-Weapons"
        else
            log_warning "${name} はリリースページへのリンクです。手動でダウンロードしてください: $url"
        fi
    done
    
    log_info "特殊なインストールを実行中..."
    local special_count=$(yq eval '.special_installs | length' "$yaml_file")
    for ((i=0; i<$special_count; i++)); do
        local name=$(yq eval ".special_installs[$i].name" "$yaml_file")
        local url=$(yq eval ".special_installs[$i].url" "$yaml_file" 2>/dev/null)
        local command=$(yq eval ".special_installs[$i].command" "$yaml_file" 2>/dev/null)
        local directory=$(yq eval ".special_installs[$i].directory" "$yaml_file")
        
        if [ "$url" != "null" ]; then
            download_file "$name" "$url" "$directory"
        elif [ "$command" != "null" ]; then
            log_info "特殊コマンドを実行: ${name}"
            eval "$command" > "${directory}/${name}"
            chmod +x "${directory}/${name}"
            log_success "${name} の取得が完了しました"
        fi
    done
}

# yqが利用できない場合の代替処理（基本的なリストのみ）
install_from_yaml_fallback() {
    log_warning "yqが利用できないため、手動でリポジトリをクローンします"
    log_info "この処理には時間がかかる場合があります..."
    
    # ここにハードコードされたリストを使用（最小限）
    log_info "主要なツールのみをインストールします..."
    
    # Tools ディレクトリ
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
    
    log_warning "完全なインストールを行うには、yqをインストールしてスクリプトを再実行してください"
}

# メイン処理
main() {
    echo "=========================================="
    echo "  Tools for RedTeam Pentesters"
    echo "=========================================="
    echo ""
    
    local yaml_file="tools_config.yaml"
    
    # 要件チェック
    check_requirements
    
    # ディレクトリ作成
    create_directory_structure
    
    # YAMLファイルの存在確認
    if [ ! -f "$yaml_file" ]; then
        log_error "YAMLファイル '$yaml_file' が見つかりません"
        log_info "tools_config.yaml を同じディレクトリに配置してください"
        exit 1
    fi
    
    # インストール開始
    log_info "インストールを開始します..."
    echo ""
    
    if command -v yq &> /dev/null; then
        install_from_yaml_with_yq "$yaml_file"
    else
        install_from_yaml_fallback
    fi
    
    echo ""
    log_success "すべてのインストールが完了しました！"
    echo ""
    log_info "インストール先:"
    echo "  - Tools/"
    echo "  - Tools/Linux-Weapons/"
    echo "  - Tools/Windows-Weapons/"
    echo ""
    log_warning "注意: 一部のツールはリリースページからの手動ダウンロードが必要です"
}

# スクリプト実行
main "$@"
