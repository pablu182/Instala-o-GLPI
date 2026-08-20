#!/bin/bash
# update.sh — Atualização do GLPI com backup automático prévio
# Grupo Inbetta — Versão 1.0
#
# Uso: ./scripts/update.sh
# Sempre faz backup antes de atualizar. Nunca roda em horário de pico.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Atualização GLPI ==="
echo ""
echo "ATENÇÃO: Este script vai:"
echo "  1. Fazer backup completo do banco e arquivos"
echo "  2. Baixar a nova imagem Docker"
echo "  3. Reiniciar os containers"
echo ""
read -p "Continuar? (s/N): " CONFIRMA
if [[ "${CONFIRMA,,}" != "s" ]]; then
    echo "Cancelado."
    exit 0
fi

echo ""
echo "[1/4] Fazendo backup preventivo..."
bash "$SCRIPT_DIR/backup.sh"

echo ""
echo "[2/4] Baixando imagens atualizadas..."
cd "$ROOT_DIR"
docker compose pull

echo ""
echo "[3/4] Reiniciando stack com novas imagens..."
docker compose up -d --remove-orphans

echo ""
echo "[4/4] Verificando status..."
sleep 10
docker compose ps

echo ""
echo "=== Atualização concluída ==="
echo "Acesse o GLPI e verifique se a interface está funcionando."
echo "Se algo quebrou: docker compose down && docker compose up -d"
echo "(isso volta para a configuração anterior sem deletar dados)"
