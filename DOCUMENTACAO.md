# GLPI — Documentação Operacional

---

## O que está nesta pasta

```
glpi_stack/
├── docker-compose.yml        → Sobe o GLPI completo (MariaDB + aplicação + proxy)
├── .env.example              → Template de senhas (copie para .env e preencha)
├── nginx/glpi.conf           → Configuração do proxy reverso
├── agent/
│   ├── deploy_agent.ps1      → Instala o agente nas estações via GPO
│   └── glpi-agent.cfg        → Configuração padrão do agente Windows
├── scripts/
│   ├── backup.sh             → Backup diário (banco + arquivos)
│   └── update.sh             → Atualização segura com backup automático
└── DOCUMENTACAO.md           → Este arquivo
```

---

## Pré-requisitos

| Item | Requisito | Verificar |
|---|---|---|
| Servidor Linux | Ubuntu 22.04+ ou Debian 12 | `lsb_release -a` |
| Docker Engine | 24.0+ | `docker --version` |
| Docker Compose | plugin v2 | `docker compose version` |
| RAM servidor | mínimo 2GB, recomendado 4GB | `free -h` |
| Disco servidor | mínimo 20GB livres | `df -h` |
| Rede | Estações alcançam o IP do servidor na porta 80 | `ping SERVIDOR-TI` |

**Instalar Docker no Ubuntu (se ainda não tiver):**
```bash
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
# Feche e reabra o terminal
docker --version
```

---

## Instalação do servidor (faça uma vez)

### 1. Copiar os arquivos para o servidor

```bash
# No servidor Linux, como root ou usuário com sudo:
mkdir -p /opt/glpi
cd /opt/glpi
# Copie todos os arquivos desta pasta para /opt/glpi
```

### 2. Configurar as senhas

```bash
cd /opt/glpi
cp .env.example .env
nano .env
```

Edite o `.env` com senhas fortes. **Não use as senhas de exemplo em produção.**

```
MARIADB_ROOT_PASSWORD=Inserir uma nova senha aqui
MARIADB_PASSWORD=Inserir uma nova senha aqui
GLPI_PORT=80
```

Salve com `Ctrl+X → Y → Enter`.

### 3. Subir o stack

```bash
cd /opt/glpi
docker compose up -d
```

Aguarde até 2 minutos na primeira vez (download das imagens).

Verificar se subiu:
```bash
docker compose ps
```
Os três containers (`glpi_db`, `glpi_app`, `glpi_proxy`) devem aparecer com status `Up`.

### 4. Assistente de instalação do GLPI (interface web)

Abra no navegador: `http://IP-DO-SERVIDOR`

O GLPI vai mostrar um assistente de instalação. Siga estes passos:

**Passo 1 — Idioma:** selecione "Português do Brasil"

**Passo 2 — Licença:** clique "OK"

**Passo 3 — Instalação ou atualização:** clique "Instalar"

**Passo 4 — Verificação de extensões:** tudo deve estar verde. Se houver vermelho, pare e chame o analista sênior.

**Passo 5 — Conexão com banco de dados:**
- Servidor SQL: `mariadb`
- Usuário SQL: `glpi`
- Senha SQL: *(a senha que você colocou em MARIADB_PASSWORD no .env)*
- Clique "Continuar"

**Passo 6 — Banco de dados:** selecione `glpi` na lista e clique "Continuar"

**Passo 7 — Inicializar:** clique "Continuar" e aguarde.

**Passo 8 — Configurações adicionais:** clique "Continuar" em tudo.

**Passo 9 — Fim da instalação:** o GLPI mostrará as senhas padrão:

| Usuário | Senha padrão | O que fazer |
|---|---|---|
| glpi | glpi | **Troque imediatamente** |
| tech | tech | Troque |
| normal | normal | Troque |
| post-only | postonly | Troque |

**IMPORTANTE:** após o assistente, delete o arquivo de instalação:
```bash
docker exec glpi_app rm /var/www/html/glpi/install/install.php
```

### 5. Configuração inicial obrigatória

Acesse: `http://IP-DO-SERVIDOR` → login com `glpi` / `glpi`

**Trocar senhas:** Administração → Usuários → clique em cada usuário → edite a senha

**Configurar e-mail de notificações** (opcional mas recomendado):
- Configuração → Notificações → Configuração dos e-mails de envio
- Preencha com os dados do servidor de e-mail da empresa

**Configurar fuso horário:**
- Configuração → Configuração Geral → aba "Geral"
- Fuso horário: America/Sao_Paulo

---

## Implantar o agente nas estações (GPO)

O agente é o programa que roda em cada máquina e envia o inventário para o GLPI. Substitui o script PowerShell que construímos antes.

### Preparar o MSI

1. Baixe o GLPI Agent em: `https://github.com/glpi-project/glpi-agent/releases`
   - Arquivo: `GLPI-Agent-1.9.2-x64.msi` (ou versão mais recente)

2. Crie a pasta no servidor TI:
   ```
   \\SERVIDOR-TI\scripts$\glpi-agent\
   ```
   Copie o MSI para essa pasta.

3. Edite `agent/deploy_agent.ps1`:
   - Linha `$GlpiServer`: coloque o IP real do servidor GLPI
   - Linha `$ShareMsi`: ajuste para o caminho real do share

### Criar o GPO

1. Abra **Group Policy Management** (gpmc.msc)
2. Crie uma nova GPO: `TI - GLPI Agent Deploy`
3. Aplique no OU das estações de trabalho
4. Edite a GPO:
   - **Computer Configuration → Windows Settings → Scripts → Startup**
   - "Add" → clique "Show Files" → copie `deploy_agent.ps1` para a pasta
   - Script Name: `deploy_agent.ps1`
   - Parameters: *(vazio)*
5. **Computer Configuration → Administrative Templates → Windows Components → Windows PowerShell:**
   - "Turn on Script Execution" → Habilitado → "RemoteSigned"
6. OK e feche

O agente será instalado na próxima reinicialização de cada máquina. Na sequência, envia o inventário em até 1 hora.

### Verificar se o agente chegou

No GLPI: **Ativos → Computadores** — as máquinas vão aparecer automaticamente.

Ou pela linha de comando na estação:
```powershell
Get-Service GLPI-Agent   # deve estar Running
# Forçar envio imediato:
& "C:\Program Files\GLPI-Agent\glpi-agent.exe" --server http://IP-GLPI/glpi
```

---

## Uso diário

### Ver o inventário completo

**Ativos → Computadores** — lista todas as estações.

Filtros úteis:
- Por SO: clique no cabeçalho "Sistema operacional"
- Sem contato há X dias: campo "Última atualização"
- Por setor: use "Localização" (configure as localizações primeiro)

### Encontrar uma máquina específica

Barra de busca no topo → nome do computador ou usuário.

Ou: **Ativos → Computadores → Pesquisa** com filtros avançados.

### Ver softwares instalados

No cadastro de qualquer computador, aba **"Softwares"** — lista completa com versões.

Para ver onde um software específico está instalado:
**Ativos → Softwares** → busca pelo nome → clique → aba "Instalações".

### Ver computadores com disco cheio

**Ativos → Computadores → Pesquisa:**
- Adicione filtro: "Disco Rígido → Tamanho livre" → menor que 10 (GB)

Salve essa busca como favorita para acessar diariamente.

### Gerar relatório

**Ferramentas → Relatórios → Inventário:**
- "Relatório de Sistemas Operacionais"
- "Relatório de Softwares por Computador"
- Exporta em CSV para Excel

---

## Configurar localizações e setores

Para organizar o inventário por setor (Expedição, Financeiro, RH...):

1. **Configuração → Localizações → Adicionar**
2. Crie uma hierarquia:
   ```
   EMPRESA
   ├── Planta Gravataí
   │   ├── Expedição
   │   ├── Produção
   │   └── Qualidade
   └── Administrativo
       ├── Financeiro
       ├── RH
       └── TI
   ```

Os agentes podem receber localizações automaticamente por regra de IP:
**Regras → Computadores → Adicionar** → condição: "IP começa com 192.168.10" → ação: "Localização = Expedição"

---

## Backup

### Rodar backup manualmente

```bash
cd /opt/glpi
bash scripts/backup.sh
```

Backups ficam em `/opt/glpi/backups/`. Retidos por 30 dias.

### Automatizar via cron

```bash
crontab -e
```

Adicione esta linha (roda todo dia às 02:00):
```
0 2 * * * cd /opt/glpi && bash scripts/backup.sh >> /opt/glpi/backups/cron.log 2>&1
```

### Restaurar banco de dados

```bash
# Escolha o arquivo de backup
BACKUP=/opt/glpi/backups/glpi_db_2026-08-20_02-00.sql.gz

# Restaura
gunzip -c "$BACKUP" | docker exec -i glpi_db mysql \
    -u glpi -p"SENHA_DO_BANCO" glpi
```

---

## Manutenção

### Verificar status do GLPI

```bash
cd /opt/glpi
docker compose ps
docker compose logs --tail=50 glpi      # logs da aplicação
docker compose logs --tail=50 mariadb   # logs do banco
```

### Reiniciar o GLPI

```bash
cd /opt/glpi
docker compose restart
```

### Parar e subir

```bash
docker compose down      # para tudo (dados preservados nos volumes)
docker compose up -d     # sobe novamente
```

### Atualizar o GLPI

```bash
cd /opt/glpi
bash scripts/update.sh
```

O script faz backup automático antes de qualquer mudança.

---

## Resolução de problemas

### GLPI não abre no navegador

```bash
docker compose ps      # todos os containers estão Up?
docker compose logs glpi_proxy --tail=30   # erro no nginx?
docker compose logs glpi --tail=30         # erro na aplicação?
```

Se algum container está `Exited`:
```bash
docker compose up -d   # tenta subir novamente
```

### Agente instalado mas máquina não aparece no GLPI

1. Verifique conectividade da estação: `curl http://IP-GLPI/glpi`
2. Verifique o log do agente: `C:\ProgramData\GLPI-Agent\glpi-agent.log`
3. Force o envio: rode `glpi-agent.exe --server http://IP-GLPI/glpi` como administrador
4. Verifique se o firewall do servidor libera a porta 80 de dentro da rede

### GLPI lento

```bash
# Ver uso de recursos
docker stats glpi_app glpi_db

# Se o banco estiver sobrecarregado:
docker compose restart mariadb
```

### Banco de dados cheio

```bash
df -h /var/lib/docker    # verificar espaço em disco
docker exec glpi_db mysqlcheck -u root -p"SENHA_ROOT" --optimize glpi
```

### Esqueceu a senha do admin

```bash
# Reseta a senha do usuário 'glpi' para 'glpi' no banco:
docker exec -it glpi_db mysql -u root -p"MARIADB_ROOT_PASSWORD" glpi \
    -e "UPDATE glpi_users SET password=MD5('glpi') WHERE name='glpi';"
# Depois troque imediatamente pela interface
```

---

## Comandos de referência rápida

```bash
# Subir tudo
cd /opt/glpi && docker compose up -d

# Ver status
docker compose ps

# Ver logs em tempo real
docker compose logs -f glpi

# Fazer backup agora
bash scripts/backup.sh

# Atualizar com segurança
bash scripts/update.sh

# Reiniciar tudo
docker compose restart

# Parar tudo (mantém dados)
docker compose down
```

---
