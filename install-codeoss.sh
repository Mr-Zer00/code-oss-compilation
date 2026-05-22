#!/bin/bash
# ==============================================================================
# Script de Instalação Completa do Code-OSS (Baseado em Debian)
# ------------------------------------------------------------------------------
# Pergunta onde guardar o projeto, instala dependências, clona o repositório,
# compila a última versão estável, empacota, instala e configura o marketplace
# escolhido pelo utilizador.
# Guarda o caminho em ~/.config/code-oss-build.conf para o script de atualização.
# -----------------------------By Mr-Zer00--------------------------------------
# ==============================================================================
set -eo pipefail

# Cores
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERRO]${NC}  $*"; exit 1; }

# --------------------------------------------
# 0. Perguntar e guardar o diretório de trabalho
# --------------------------------------------
CONFIG_FILE="$HOME/.config/code-oss-build.conf"
DEFAULT_DIR="$HOME/Downloads/compilar-code-oss"

if [ -f "$CONFIG_FILE" ]; then
    
    OLD_DIR=$(cat "$CONFIG_FILE")
    echo "Foi encontrada uma configuração anterior: $OLD_DIR"
    read -p "Usar o mesmo diretório? (S/n) " use_old
    if [[ "$use_old" =~ ^[Nn]$ ]]; then
        read -p "Novo diretório de trabalho (padrão: $DEFAULT_DIR): " PROJECT_DIR
        PROJECT_DIR="${PROJECT_DIR:-$DEFAULT_DIR}"
    else
        PROJECT_DIR="$OLD_DIR"
    fi
else
    read -p "Em que diretório quer baixar e compilar o Code-OSS? (padrão: $DEFAULT_DIR): " PROJECT_DIR
    PROJECT_DIR="${PROJECT_DIR:-$DEFAULT_DIR}"
fi

PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
PROJECT_DIR="$(realpath -m "$PROJECT_DIR")"
mkdir -p "$(dirname "$CONFIG_FILE")"
echo "$PROJECT_DIR" > "$CONFIG_FILE"
info "Projeto será guardado em: $PROJECT_DIR"

# --------------------------------------------
# 1. Verificar e instalar dependências de sistema
# --------------------------------------------
info "Verificando dependências de build..."
sudo apt update
sudo apt install -y build-essential g++ libx11-dev libxkbfile-dev \
    libsecret-1-dev libkrb5-dev python-is-python3 fakeroot rpm \
    git curl wget python3

# --------------------------------------------
# 2. Configurar NVM e Node.js 22
# --------------------------------------------
info "Configurando Node.js 22 via NVM..."
export NVM_DIR="$HOME/.nvm"
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
    warn "NVM não encontrado. Instalando..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    source "$NVM_DIR/nvm.sh"
else
    source "$NVM_DIR/nvm.sh"
fi

nvm install 22
nvm use 22

# --------------------------------------------
# 3. Preparar o repositório
# --------------------------------------------
VSCODE_DIR="$PROJECT_DIR/vscode"
if [ -d "$VSCODE_DIR/.git" ]; then
    warn "O repositório já existe em $VSCODE_DIR."
    read -p "Quer apagá‑lo e clonar novamente (s/N)? " choice
    if [[ "$choice" =~ ^[Ss]$ ]]; then
        rm -rf "$VSCODE_DIR"
        info "Repositório apagado."
    else
        error "A instalação requer um diretório limpo. Abortando."
    fi
fi

mkdir -p "$PROJECT_DIR"
info "Clonando repositório oficial do VS Code..."
git clone https://github.com/microsoft/vscode.git "$VSCODE_DIR"
cd "$VSCODE_DIR"

# --------------------------------------------
# 4. Selecionar a última versão estável
# --------------------------------------------
info "Buscando tags mais recentes..."
git fetch --tags
LATEST_TAG=$(git tag -l '1.*' | grep -vE 'rc|insider|nightly' | sort -V | tail -1)
if [ -z "$LATEST_TAG" ]; then
    error "Nenhuma tag de versão estável encontrada."
fi
info "Última versão estável: $LATEST_TAG"

BUILD_BRANCH="build-${LATEST_TAG}"
git checkout tags/"$LATEST_TAG" -b "$BUILD_BRANCH"

# --------------------------------------------
# 5. Instalar dependências Node e compilar
# --------------------------------------------
info "Instalando dependências npm (pode demorar)..."
npm install

info "Compilando o Code-OSS (vscode-linux-x64)..."
npm run gulp vscode-linux-x64

# --------------------------------------------
# 6. Aplicar correções pré‑empacotamento
# --------------------------------------------
info "Aplicando correções conhecidas..."

MUSL_DIR="../VSCode-linux-x64/resources/app/node_modules/@parcel/watcher-linux-x64-musl"
if [ -d "$MUSL_DIR" ]; then
    rm -rf "$MUSL_DIR"
    info "Módulo musl removido."
fi

TUNNEL_BIN="../VSCode-linux-x64/bin/code-tunnel-oss"
if [ ! -f "$TUNNEL_BIN" ]; then
    touch "$TUNNEL_BIN"
    chmod +x "$TUNNEL_BIN"
    info "Binário code-tunnel-oss dummy criado."
fi

DEP_FILE="build/linux/debian/dep-lists.ts"
if [ -f "$DEP_FILE" ]; then
    info "Atualizando automaticamente dep-lists.ts..."
    DEPS_OUTPUT=$(node --experimental-strip-types -e "
        import { getDependencies } from './build/linux/dependencies-generator.ts';
        getDependencies('amd64').then(d => console.log(d.join('\n')));
    " 2>/dev/null || true)
    
    if [ -n "$DEPS_OUTPUT" ]; then
        DEPS_TS=$(echo "$DEPS_OUTPUT" | sed "s/^/        '/; s/$/',/" | sed '$ s/,$//')
        python3 -c "
import re
with open('$DEP_FILE', 'r') as f:
    content = f.read()
new_deps = '''$DEPS_TS'''
content = re.sub(
    r\"'amd64':\s*\[[^\]]*\]\",
    \"'amd64': [\n\" + new_deps + \"\n    ]\",
    content,
    flags=re.DOTALL
)
with open('$DEP_FILE', 'w') as f:
    f.write(content)
" || warn "Falha ao atualizar dep-lists.ts automaticamente — edite manualmente se o prepare‑deb falhar."
    fi
fi

# --------------------------------------------
# 7. Empacotamento e instalação
# --------------------------------------------
info "Preparando pacote Debian (prepare-deb)..."
npm run gulp vscode-linux-x64-prepare-deb

info "Construindo .deb..."
npm run gulp vscode-linux-x64-build-deb

DEB_FILE=$(ls -t ./.build/linux/deb/amd64/deb/code-oss_*.deb 2>/dev/null | head -1)
if [ -z "$DEB_FILE" ]; then
    error "Pacote .deb não encontrado."
fi

info "Instalando $DEB_FILE..."
sudo dpkg -i "$DEB_FILE"
sudo apt install -f -y

# --------------------------------------------
# 8. Escolha do marketplace
# --------------------------------------------
PRODUCT_JSON="/usr/share/code-oss/resources/app/product.json"

echo ""
echo "============================================"
echo " Escolha o marketplace de extensões:"
echo " 1 - Microsoft Marketplace (oficial)"
echo " 2 - Open VSX (open source)"
echo "============================================"
while true; do
    read -p "Digite 1 ou 2: " market_choice
    if [ "$market_choice" == "1" ]; then
        SERVICE_URL="https://marketplace.visualstudio.com/_apis/public/gallery"
        CACHE_URL="https://vscode.blob.core.windows.net/gallery/index"
        ITEM_URL="https://marketplace.visualstudio.com/items"
        MARKET_NAME="Microsoft Marketplace"
        break
    elif [ "$market_choice" == "2" ]; then
        SERVICE_URL="https://open-vsx.org/vscode/gallery"
        CACHE_URL=""
        ITEM_URL="https://open-vsx.org/vscode/item"
        MARKET_NAME="Open VSX"
        break
    else
        warn "Opção inválida. Digite 1 ou 2."
    fi
done

if [ -f "$PRODUCT_JSON" ]; then
    info "Configurando $MARKET_NAME no product.json..."
    if [ -n "$CACHE_URL" ]; then
        sudo python3 -c "
import json
with open('$PRODUCT_JSON', 'r') as f:
    data = json.load(f)
data['extensionsGallery'] = {
    'serviceUrl': '$SERVICE_URL',
    'cacheUrl': '$CACHE_URL',
    'itemUrl': '$ITEM_URL'
}
with open('$PRODUCT_JSON', 'w') as f:
    json.dump(data, f, indent=8, ensure_ascii=False)
"
    else
        sudo python3 -c "
import json
with open('$PRODUCT_JSON', 'r') as f:
    data = json.load(f)
data['extensionsGallery'] = {
    'serviceUrl': '$SERVICE_URL',
    'itemUrl': '$ITEM_URL'
}
with open('$PRODUCT_JSON', 'w') as f:
    json.dump(data, f, indent=8, ensure_ascii=False)
"
    fi
    info "Marketplace configurado com sucesso."
else
    warn "Ficheiro product.json não encontrado em $PRODUCT_JSON."
fi

echo ""
echo "============================================"
echo -e "${GREEN}Code-OSS $LATEST_TAG instalado com sucesso!${NC}"
echo "Execute 'code-oss' para iniciar."
echo ""
echo "Para alterar o marketplace futuramente, edite o arquivo:"
echo "  $PRODUCT_JSON"
echo "============================================"
