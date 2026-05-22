#!/bin/bash
# ==============================================================================
# Script de Atualização do Code-OSS (Baseado em Debian)
# ------------------------------------------------------------------------------
# Lê o diretório do projeto do ficheiro de configuração criado pelo script de
# instalação. Se não existir, pergunta ao utilizador e guarda.
# Atualiza o Code-OSS para a última versão estável sem alterar o marketplace.
# -----------------------------By Mr-Zer00--------------------------------------
# ==============================================================================
set -eo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERRO]${NC}  $*"; exit 1; }

# --------------------------------------------
# 1. Obter diretório do projeto (via config)
# --------------------------------------------
CONFIG_FILE="$HOME/.config/code-oss-build.conf"

if [ -f "$CONFIG_FILE" ]; then
    PROJECT_DIR=$(cat "$CONFIG_FILE")
    info "Usando diretório registado: $PROJECT_DIR"
else
    warn "Nenhuma configuração encontrada."
    read -p "Em que diretório está o repositório do Code-OSS? (ex: ~/Downloads/compilar-code-oss/vscode): " PROJECT_DIR
    PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "$PROJECT_DIR" > "$CONFIG_FILE"
    info "Caminho guardado para futuras atualizações."
fi

PROJECT_DIR="$(realpath -m "$PROJECT_DIR")"
VSCODE_DIR="$PROJECT_DIR/vscode"

if [ ! -d "$VSCODE_DIR/.git" ]; then
    error "Repositório não encontrado em $VSCODE_DIR. Execute o script de instalação primeiro."
fi

cd "$VSCODE_DIR"

# --------------------------------------------
# 2. Verificar NVM e Node.js
# --------------------------------------------
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
if ! command -v node &>/dev/null || [ "$(node -v | cut -d'.' -f1-2)" != "v22."* ]; then
    warn "Node.js 22 não ativo. Tentando usar nvm..."
    nvm install 22
    nvm use 22
fi

# --------------------------------------------
# 3. Buscar última tag estável e comparar
# --------------------------------------------
info "Buscando novas tags..."
git fetch --tags

LATEST_TAG=$(git tag -l '1.*' | grep -vE 'rc|insider|nightly' | sort -V | tail -1)
if [ -z "$LATEST_TAG" ]; then
    error "Nenhuma tag estável encontrada."
fi

CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || true)
if [ "$CURRENT_TAG" == "$LATEST_TAG" ]; then
    info "Você já está na versão mais recente ($LATEST_TAG). Nada a fazer."
    exit 0
fi

info "Atualizando de ${CURRENT_TAG:-desconhecida} para $LATEST_TAG..."

# --------------------------------------------
# 4. Mudar para a nova versão e compilar
# --------------------------------------------
BUILD_BRANCH="build-${LATEST_TAG}"
git checkout tags/"$LATEST_TAG" -b "$BUILD_BRANCH"

info "Instalando dependências (npm install)..."
npm install

info "Compilando..."
npm run gulp vscode-linux-x64

# --------------------------------------------
# 5. Correções pré‑empacotamento
# --------------------------------------------
MUSL_DIR="../VSCode-linux-x64/resources/app/node_modules/@parcel/watcher-linux-x64-musl"
[ -d "$MUSL_DIR" ] && rm -rf "$MUSL_DIR" && info "Módulo musl removido."

TUNNEL_BIN="../VSCode-linux-x64/bin/code-tunnel-oss"
[ ! -f "$TUNNEL_BIN" ] && touch "$TUNNEL_BIN" && chmod +x "$TUNNEL_BIN" && info "Túnel dummy criado."

DEP_FILE="build/linux/debian/dep-lists.ts"
if [ -f "$DEP_FILE" ]; then
    info "Atualizando dep-lists.ts..."
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
" || warn "Não foi possível atualizar automaticamente o dep-lists.ts. Poderá ter de editá-lo manualmente."
    fi
fi

# --------------------------------------------
# 6. Empacotar e instalar
# --------------------------------------------
info "Preparando pacote .deb..."
npm run gulp vscode-linux-x64-prepare-deb
npm run gulp vscode-linux-x64-build-deb

DEB_FILE=$(ls -t ./.build/linux/deb/amd64/deb/code-oss_*.deb 2>/dev/null | head -1)
[ -z "$DEB_FILE" ] && error "Pacote .deb não encontrado."

info "Instalando $DEB_FILE..."
sudo dpkg -i "$DEB_FILE"
sudo apt install -f -y

# --------------------------------------------
# 7. Fim (marketplace mantido)
# --------------------------------------------

echo ""
echo "========================================"
echo -e "${GREEN}Code-OSS atualizado para $LATEST_TAG com sucesso!${NC}"
echo "O marketplace permanece da instalação inicial."
echo "========================================"
