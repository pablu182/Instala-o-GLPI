#!/bin/bash
# backup.sh — Backup do GLPI (banco + arquivos)
# Versão 1.0
#
# Uso:
#   ./scripts/backup.sh
#
# Automatizar via cron (roda todo dia às 02:00):
#   0 2 * * * /opt/glpi/scripts/backup.sh >> /opt/glpi/backups/backup.log 2>&1
#
# Requisito: rodar a partir do diretório onde está o docker-compose.yml
#   e com o .env carregado.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Carrega variáveis do .env
if [[ -f "$ROOT_DIR/.env" ]]; then
    set -o allexport
    source "$ROOT_DIR/.env"
    set +o allexport
else
    echo "ERRO: .env não encontrado em $ROOT_DIR" >&2
    exit 1
fi

BACKUP_DIR="$ROOT_DIR/backups"
DATA=$(date +%Y-%m-%d_%H-%M)
RETENCAO=30   # dias para manter backups antigos

mkdir -p "$BACKUP_DIR"

echo "=== Backup GLPI — $DATA ==="

# ── 1. Banco de dados ────────────────────────────────────────────────────────
echo "[1/3] Exportando banco de dados..."
docker exec glpi_db mysqldump \
    -u glpi \
    -p"${MARIADB_PASSWORD}" \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    glpi \
  | gzip > "$BACKUP_DIR/glpi_db_$DATA.sql.gz"

echo "      Banco salvo: glpi_db_$DATA.sql.gz ($(du -sh "$BACKUP_DIR/glpi_db_$DATA.sql.gz" | cut -f1))"

# ── 2. Arquivos do GLPI (uploads, documentos, etc.) ──────────────────────────
echo "[2/3] Exportando arquivos da aplicação..."
docker run --rm \
    --volumes-from glpi_app \
    -v "$BACKUP_DIR:/backup" \
    alpine \
    tar czf "/backup/glpi_files_$DATA.tar.gz" \
        /var/www/html/glpi/files \
        /var/www/html/glpi/config

echo "      Arquivos salvos: glpi_files_$DATA.tar.gz ($(du -sh "$BACKUP_DIR/glpi_files_$DATA.tar.gz" | cut -f1))"

# ── 3. Limpeza de backups antigos ────────────────────────────────────────────
echo "[3/3] Removendo backups com mais de $RETENCAO dias..."
REMOVIDOS=$(find "$BACKUP_DIR" -name "glpi_*.gz" -mtime +$RETENCAO -print -delete | wc -l)
echo "      $REMOVIDOS arquivo(s) removido(s)"

echo "=== Backup concluído ==="
echo "    Localização: $BACKUP_DIR"
echo "    Arquivos disponíveis:"
ls -lh "$BACKUP_DIR"/*.gz 2>/dev/null | awk '{print "    " $9, $5}'
