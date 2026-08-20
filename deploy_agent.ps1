#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy do GLPI Agent via GPO — Grupo Inbetta
.DESCRIPTION
    Baixa o MSI do share de TI, instala silenciosamente e configura o agente
    para enviar inventário ao servidor GLPI. Seguro para re-execução: se a
    versão correta já estiver instalada, sai sem fazer nada.
.NOTES
    Versão  : 1.0 — Agosto 2026
    GPO     : Computer Configuration → Windows Settings → Scripts → Startup
    Contexto: SYSTEM (a máquina precisa acessar o share abaixo)
#>

# ── CONFIGURAÇÃO — edite estas duas linhas ───────────────────────────────────
$GlpiServer    = "http://192.168.1.10/glpi"         # URL do servidor GLPI
$ShareMsi      = "\\SERVIDOR-TI\scripts$\glpi-agent" # pasta no servidor TI com o MSI
# ─────────────────────────────────────────────────────────────────────────────

$AgentVersion  = "1.9.2"
$AgentMsi      = "GLPI-Agent-$AgentVersion-x64.msi"
$LogFile       = "C:\ProgramData\GLPI-Agent\deploy.log"
$ServiceName   = "GLPI-Agent"

function Write-Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts  [$Level]  $Msg"
    $null = New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Output $line
}

# ── 1. Verifica se a versão correta já está instalada ───────────────────────
$installed = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "GLPI Agent*" -and
                   $_.DisplayVersion -eq $AgentVersion }

if ($installed) {
    Write-Log "GLPI Agent $AgentVersion já instalado em $env:COMPUTERNAME. Nada a fazer."
    exit 0
}

Write-Log "Iniciando deploy do GLPI Agent $AgentVersion em $env:COMPUTERNAME"

# ── 2. Copia o MSI do share para temp local ──────────────────────────────────
$MsiLocal = "$env:TEMP\$AgentMsi"
try {
    if (-not (Test-Path "$ShareMsi\$AgentMsi")) {
        throw "MSI não encontrado em $ShareMsi\$AgentMsi"
    }
    Copy-Item "$ShareMsi\$AgentMsi" -Destination $MsiLocal -Force -ErrorAction Stop
    Write-Log "MSI copiado: $MsiLocal"
} catch {
    Write-Log "ERRO ao copiar MSI: $_" -Level "ERRO"
    exit 1
}

# ── 3. Remove versão antiga se existir ──────────────────────────────────────
$old = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "GLPI Agent*" }

if ($old) {
    Write-Log "Removendo versão anterior: $($old.DisplayVersion)"
    $null = Start-Process msiexec -ArgumentList "/x `"$($old.PSChildName)`" /qn" -Wait -PassThru
}

# ── 4. Instalação silenciosa ─────────────────────────────────────────────────
$msiArgs = @(
    "/i",  $MsiLocal,
    "/qn",
    "/log", "$env:TEMP\glpi-agent-msi.log",
    "SERVER=$GlpiServer",
    "RUNNOW=1",           # Roda inventário imediatamente após instalar
    "TAG=Inbetta",        # Tag visível no GLPI para filtrar por empresa
    "ADDLOCAL=ALL"        # Instala todos os módulos (Network, Deploy, etc.)
)

Write-Log "Executando msiexec..."
$proc = Start-Process msiexec -ArgumentList $msiArgs -Wait -PassThru

if ($proc.ExitCode -ne 0) {
    Write-Log "ERRO: msiexec saiu com código $($proc.ExitCode)" -Level "ERRO"
    Write-Log "Log do MSI: $env:TEMP\glpi-agent-msi.log" -Level "ERRO"
    exit 1
}

# ── 5. Confirma que o serviço subiu ─────────────────────────────────────────
Start-Sleep -Seconds 5
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Log "Serviço $ServiceName em execução. Deploy concluído."
} else {
    Write-Log "AVISO: Serviço $ServiceName não encontrado ou não está rodando." -Level "AVISO"
    Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
}

# ── 6. Limpeza ──────────────────────────────────────────────────────────────
Remove-Item $MsiLocal -Force -ErrorAction SilentlyContinue
Write-Log "Deploy finalizado em $env:COMPUTERNAME"
