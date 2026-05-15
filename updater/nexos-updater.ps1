#Requires -Version 5.1
<#
.SYNOPSIS
    Nexos Chrome Extension Auto-Updater v1.0.0

.DESCRIPTION
    Verifica e aplica atualizações da extensão Nexos de forma silenciosa,
    transacional e sem loops. Projetado para ambientes corporativos restritos.

    Fluxo:
      1. Lê version.lock (versão instalada)
      2. Busca latest.json no servidor remoto (GitHub/Firebase)
      3. Se versão remota > instalada: baixa ZIP, extrai, valida, faz backup,
         substitui arquivos, atualiza version.lock
      4. background.js da extensão detecta a nova versão e dispara chrome.runtime.reload()

    Anti-loop:
      - update.lock impede execuções simultâneas (timeout de 10 min)
      - version.lock isUpdating=false só após conclusão
      - background.js compara manifest.version com latest.json após reload

.PARAMETER InstallPath
    Raiz da instalação. Padrão: %LOCALAPPDATA%\Nexos (sem admin)

.PARAMETER LatestJsonUrl
    URL do arquivo latest.json no servidor de distribuição.
    Padrão: GitHub raw content

.PARAMETER Force
    Aplica atualização mesmo que a versão remota não seja maior.

.PARAMETER DryRun
    Simula o processo sem alterar arquivos (apenas loga).

.EXAMPLE
    .\nexos-updater.ps1
    .\nexos-updater.ps1 -Force
    .\nexos-updater.ps1 -InstallPath "$env:USERPROFILE\Nexos" -DryRun
#>
param(
    [string]$InstallPath   = "$env:LOCALAPPDATA\Nexos",
    [string]$LatestJsonUrl = 'https://raw.githubusercontent.com/TheLeozin/Nexos/main/latest.json',
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURAÇÃO
# ─────────────────────────────────────────────────────────────────────────────
$EXTENSION_DIR  = Join-Path $InstallPath 'extension'
$TEMP_DIR       = Join-Path $InstallPath 'temp'
$BACKUP_DIR     = Join-Path $InstallPath 'backup'
$LOGS_DIR       = Join-Path $InstallPath 'logs'
$VERSION_LOCK   = Join-Path $InstallPath 'version.lock'
$UPDATE_LOCK    = Join-Path $InstallPath 'update.lock'
$LOG_FILE       = Join-Path $LOGS_DIR 'updater.log'
$MAX_LOG_BYTES  = 5MB        # Rotaciona o log quando ultrapassar 5 MB
$MAX_BACKUPS    = 5          # Mantém apenas os últimos N backups
$LOCK_TIMEOUT_S = 600        # Abandona update.lock após 10 min sem atividade
$DOWNLOAD_TIMEOUT_S = 120    # Timeout por tentativa de download (segundos)
$MAX_RETRIES    = 3          # Tentativas de download antes de desistir

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING COM ROTAÇÃO
# ─────────────────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Level, [string]$Message)

    $ts   = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ'
    $line = "[$ts][$Level] $Message"

    Write-Host $line

    try {
        if (-not (Test-Path $LOGS_DIR)) {
            New-Item -ItemType Directory -Path $LOGS_DIR -Force | Out-Null
        }
        # Rotação: se o log ultrapassar MAX_LOG_BYTES, arquiva antes de continuar
        if ((Test-Path $LOG_FILE) -and (Get-Item $LOG_FILE).Length -gt $MAX_LOG_BYTES) {
            $archive = $LOG_FILE -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            Move-Item $LOG_FILE $archive -Force
        }
        Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
    } catch {
        # Log não pode quebrar o updater
    }
}

function Write-Info  { param([string]$m) Write-Log 'INFO ' $m }
function Write-Warn  { param([string]$m) Write-Log 'WARN ' $m }
function Write-Err   { param([string]$m) Write-Log 'ERROR' $m }
function Write-Ok    { param([string]$m) Write-Log 'OK   ' $m }

# ─────────────────────────────────────────────────────────────────────────────
# UPDATE.LOCK — evita execuções simultâneas (múltiplos processos/usuários)
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-AcquireLock {
    if (Test-Path $UPDATE_LOCK) {
        try {
            $lock    = Get-Content $UPDATE_LOCK -Raw | ConvertFrom-Json
            $lockAge = (Get-Date) - [datetime]$lock.timestamp
            if ($lockAge.TotalSeconds -lt $LOCK_TIMEOUT_S) {
                Write-Warn "Lock ativo — PID $($lock.pid), $([math]::Round($lockAge.TotalMinutes, 1)) min. Saindo."
                return $false
            }
            Write-Warn "Lock expirado ($([math]::Round($lockAge.TotalMinutes, 1)) min). Limpando."
        } catch {
            Write-Warn "Lock corrompido. Limpando."
        }
        Remove-Item $UPDATE_LOCK -Force -ErrorAction SilentlyContinue
    }

    [ordered]@{ pid = $PID; timestamp = (Get-Date -Format 'o') } |
        ConvertTo-Json | Set-Content $UPDATE_LOCK -Encoding UTF8
    return $true
}

function Invoke-ReleaseLock {
    if (-not (Test-Path $UPDATE_LOCK)) { return }
    try {
        $lock = Get-Content $UPDATE_LOCK -Raw | ConvertFrom-Json
        if ($lock.pid -eq $PID) {
            Remove-Item $UPDATE_LOCK -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Remove-Item $UPDATE_LOCK -Force -ErrorAction SilentlyContinue
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# VERSION.LOCK — rastreia versão instalada
# ─────────────────────────────────────────────────────────────────────────────
function Read-VersionLock {
    if (-not (Test-Path $VERSION_LOCK)) {
        return [ordered]@{ installed = '0.0.0'; lastCheck = $null; isUpdating = $false; previous = $null; lastUpdated = $null }
    }
    try {
        $data = Get-Content $VERSION_LOCK -Raw | ConvertFrom-Json
        # Garantir campos obrigatórios
        if (-not $data.installed) { $data | Add-Member -MemberType NoteProperty -Name 'installed' -Value '0.0.0' -Force }
        if (-not (Get-Member -InputObject $data -Name 'isUpdating' -MemberType NoteProperty)) {
            $data | Add-Member -MemberType NoteProperty -Name 'isUpdating' -Value $false -Force
        }
        return $data
    } catch {
        Write-Warn "version.lock corrompido — usando padrão."
        return [ordered]@{ installed = '0.0.0'; lastCheck = $null; isUpdating = $false; previous = $null; lastUpdated = $null }
    }
}

function Write-VersionLock {
    param($Data)
    $Data | ConvertTo-Json -Depth 5 | Set-Content $VERSION_LOCK -Encoding UTF8
}

# ─────────────────────────────────────────────────────────────────────────────
# COMPARAÇÃO SEMVER — retorna -1, 0 ou 1
# ─────────────────────────────────────────────────────────────────────────────
function Compare-Versions {
    param([string]$v1, [string]$v2)

    $p1 = ($v1 -split '\.') | ForEach-Object { [int]($_ -replace '[^0-9]') }
    $p2 = ($v2 -split '\.') | ForEach-Object { [int]($_ -replace '[^0-9]') }
    $len = [Math]::Max($p1.Length, $p2.Length)

    for ($i = 0; $i -lt $len; $i++) {
        $a = if ($i -lt $p1.Length) { $p1[$i] } else { 0 }
        $b = if ($i -lt $p2.Length) { $p2[$i] } else { 0 }
        if ($a -lt $b) { return -1 }
        if ($a -gt $b) { return  1 }
    }
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────
# DOWNLOAD COM RETRY E TIMEOUT
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-SafeDownload {
    param(
        [string]$Url,
        [string]$Destination
    )

    for ($attempt = 1; $attempt -le $MAX_RETRIES; $attempt++) {
        try {
            Write-Info "Download tentativa $attempt/$MAX_RETRIES: $Url"

            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add('User-Agent', 'NexosUpdater/1.0')

            # Timeout via proxy assíncrono
            $task    = $wc.DownloadFileTaskAsync($Url, $Destination)
            $timeout = [System.Threading.Tasks.Task]::Delay($DOWNLOAD_TIMEOUT_S * 1000)
            $done    = [System.Threading.Tasks.Task]::WhenAny($task, $timeout).GetAwaiter().GetResult()

            if ($done -eq $timeout) {
                $wc.CancelAsync()
                $wc.Dispose()
                throw "Timeout após ${DOWNLOAD_TIMEOUT_S}s"
            }

            $task.GetAwaiter().GetResult()  # propaga exceção se falhou
            $wc.Dispose()

            if ((Test-Path $Destination) -and (Get-Item $Destination).Length -gt 0) {
                $size = [math]::Round((Get-Item $Destination).Length / 1KB, 1)
                Write-Ok "Download OK: ${size} KB"
                return $true
            }
            Write-Warn "Arquivo baixado está vazio."

        } catch {
            Write-Warn "Tentativa $attempt falhou: $($_.Exception.Message)"
            if (Test-Path $Destination) { Remove-Item $Destination -Force -ErrorAction SilentlyContinue }
            if ($attempt -lt $MAX_RETRIES) {
                $delay = $attempt * 5
                Write-Info "Aguardando ${delay}s antes da próxima tentativa..."
                Start-Sleep -Seconds $delay
            }
        }
    }
    return $false
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDAÇÃO DO CONTEÚDO EXTRAÍDO
# ─────────────────────────────────────────────────────────────────────────────
function Test-ExtractedExtension {
    param(
        [string]$ExtractedPath,
        [string]$ExpectedVersion
    )

    $manifestPath = Join-Path $ExtractedPath 'manifest.json'
    if (-not (Test-Path $manifestPath)) {
        Write-Warn "Validação: manifest.json não encontrado em '$ExtractedPath'"
        return $false
    }

    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.version -ne $ExpectedVersion) {
            Write-Warn "Validação: versão no manifest ($($manifest.version)) ≠ esperada ($ExpectedVersion)"
            return $false
        }
        Write-Ok "Validação OK — manifest.json v$($manifest.version)"
        return $true
    } catch {
        Write-Warn "Validação: manifest.json inválido — $($_.Exception.Message)"
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# BACKUP (mantém $MAX_BACKUPS versões recentes)
# ─────────────────────────────────────────────────────────────────────────────
function New-Backup {
    param([string]$CurrentVersion)

    if (-not (Test-Path $EXTENSION_DIR)) {
        Write-Info "Sem extensão instalada — backup ignorado."
        return $true
    }

    $backupTarget = Join-Path $BACKUP_DIR $CurrentVersion

    try {
        if (Test-Path $backupTarget) { Remove-Item $backupTarget -Recurse -Force }
        New-Item -ItemType Directory -Path $backupTarget -Force | Out-Null
        Copy-Item -Path (Join-Path $EXTENSION_DIR '*') -Destination $backupTarget -Recurse -Force
        Write-Ok "Backup criado: $backupTarget"

        # Limpar backups antigos
        $allBackups = Get-ChildItem $BACKUP_DIR -Directory -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime
        if ($allBackups.Count -gt $MAX_BACKUPS) {
            $toRemove = $allBackups | Select-Object -First ($allBackups.Count - $MAX_BACKUPS)
            foreach ($old in $toRemove) {
                Remove-Item $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Info "Backup antigo removido: $($old.Name)"
            }
        }
        return $true
    } catch {
        Write-Err "Falha ao criar backup: $($_.Exception.Message)"
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ROLLBACK — restaura versão anterior a partir do backup
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-Rollback {
    param([string]$VersionToRestore)

    $backupPath = Join-Path $BACKUP_DIR $VersionToRestore
    if (-not (Test-Path $backupPath)) {
        Write-Err "Rollback impossível: backup da v$VersionToRestore não encontrado."
        return $false
    }

    try {
        Write-Info "Iniciando rollback para v$VersionToRestore..."
        if (Test-Path $EXTENSION_DIR) { Remove-Item $EXTENSION_DIR -Recurse -Force }
        New-Item -ItemType Directory -Path $EXTENSION_DIR -Force | Out-Null
        Copy-Item -Path (Join-Path $backupPath '*') -Destination $EXTENSION_DIR -Recurse -Force
        Write-Ok "Rollback concluído para v$VersionToRestore"
        return $true
    } catch {
        Write-Err "Rollback falhou: $($_.Exception.Message)"
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# SUBSTITUIÇÃO ATÔMICA DE ARQUIVOS (staging → rename)
# ─────────────────────────────────────────────────────────────────────────────
function Install-ExtensionFiles {
    param([string]$SourcePath)

    $stagingNew = Join-Path $TEMP_DIR '_staging_new'
    $stagingOld = Join-Path $TEMP_DIR '_staging_old'

    try {
        # Limpar staging anterior
        foreach ($p in @($stagingNew, $stagingOld)) {
            if (Test-Path $p) { Remove-Item $p -Recurse -Force }
        }

        # Mover novos arquivos para staging
        Move-Item $SourcePath $stagingNew -Force

        # Trocar atomicamente:  extension → staging_old,  staging_new → extension
        if (Test-Path $EXTENSION_DIR) {
            Move-Item $EXTENSION_DIR $stagingOld -Force
        }
        Move-Item $stagingNew $EXTENSION_DIR -Force

        # Limpar staging_old
        if (Test-Path $stagingOld) {
            Remove-Item $stagingOld -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $true

    } catch {
        Write-Err "Substituição de arquivos falhou: $($_.Exception.Message)"

        # Tentar reverter (staging_old → extension)
        if ((Test-Path $stagingOld) -and -not (Test-Path $EXTENSION_DIR)) {
            try {
                Move-Item $stagingOld $EXTENSION_DIR -Force
                Write-Warn "Revertido para versão anterior após falha na instalação."
            } catch {
                Write-Err "Reversão de emergência também falhou: $($_.Exception.Message)"
            }
        }
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# FLUXO PRINCIPAL
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-UpdateCheck {
    $versionLock     = Read-VersionLock
    $currentVersion  = $versionLock.installed

    Write-Info '═══════════════════════════════════════════════'
    Write-Info "Nexos Updater iniciado — instalada: v$currentVersion"
    if ($DryRun) { Write-Info '[DRY RUN] Nenhum arquivo será modificado.' }

    # ── 1. Buscar latest.json ─────────────────────────────────────────────
    $latestJson = $null
    try {
        $resp = Invoke-WebRequest -Uri $LatestJsonUrl `
                    -UseBasicParsing `
                    -TimeoutSec 30 `
                    -Headers @{ 'Cache-Control' = 'no-cache'; 'User-Agent' = 'NexosUpdater/1.0' }
        $latestJson = $resp.Content | ConvertFrom-Json
    } catch {
        Write-Warn "Não foi possível buscar latest.json: $($_.Exception.Message)"
        return
    }

    $remoteVersion = $latestJson.version
    $zipUrl        = $latestJson.url

    if (-not $remoteVersion) { Write-Warn "latest.json sem campo 'version'. Abortando."; return }
    if (-not $zipUrl)        { Write-Warn "latest.json sem campo 'url'. Abortando.";     return }

    Write-Info "Versão remota: v$remoteVersion"

    # Atualizar lastCheck mesmo sem atualização
    try {
        $versionLock.lastCheck = (Get-Date -Format 'o')
        if (-not $DryRun) { Write-VersionLock $versionLock }
    } catch {}

    # ── 2. Comparar versões ───────────────────────────────────────────────
    $cmp = Compare-Versions $remoteVersion $currentVersion
    if ($cmp -le 0 -and -not $Force) {
        Write-Info "Já está na versão mais recente (v$currentVersion). Nenhuma ação."
        return
    }

    Write-Info "→ Nova versão disponível: v$currentVersion → v$remoteVersion"

    if ($DryRun) {
        Write-Info "[DRY RUN] Atualização seria aplicada. Saindo sem modificar arquivos."
        return
    }

    # ── 3. Adquirir lock ──────────────────────────────────────────────────
    if (-not (Invoke-AcquireLock)) { return }

    $zipFile    = Join-Path $TEMP_DIR "nexos-$remoteVersion.zip"
    $extractDir = Join-Path $TEMP_DIR 'extracted'
    $success    = $false

    try {
        # ── 4. Marcar como atualizando ────────────────────────────────────
        $versionLock.isUpdating = $true
        Write-VersionLock $versionLock

        # ── 5. Garantir diretórios ────────────────────────────────────────
        foreach ($dir in @($TEMP_DIR, $BACKUP_DIR, $LOGS_DIR)) {
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        # ── 6. Limpar temp anterior ───────────────────────────────────────
        if (Test-Path $zipFile)    { Remove-Item $zipFile    -Force }
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }

        # ── 7. Download ───────────────────────────────────────────────────
        if (-not (Invoke-SafeDownload -Url $zipUrl -Destination $zipFile)) {
            Write-Err "Download falhou após $MAX_RETRIES tentativas. Abortando."
            return
        }

        # ── 8. Extrair ZIP ────────────────────────────────────────────────
        Write-Info "Extraindo ZIP..."
        try {
            Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force
        } catch {
            Write-Err "Extração falhou: $($_.Exception.Message)"
            return
        }

        # Detectar subpasta raiz (alguns ZIPs encapsulam em pasta)
        $items         = Get-ChildItem $extractDir
        $extensionRoot = $extractDir
        if ($items.Count -eq 1 -and $items[0].PSIsContainer) {
            $extensionRoot = $items[0].FullName
            Write-Info "Subpasta detectada: $($items[0].Name)"
        }

        # ── 9. Validar conteúdo ───────────────────────────────────────────
        if (-not (Test-ExtractedExtension -ExtractedPath $extensionRoot -ExpectedVersion $remoteVersion)) {
            Write-Err "Validação falhou. Atualização abortada para proteção."
            return
        }

        # ── 10. Backup da versão atual ────────────────────────────────────
        if (-not (New-Backup -CurrentVersion $currentVersion)) {
            Write-Warn "Backup falhou. Continuando (rollback manual possível em: $BACKUP_DIR)."
        }

        # ── 11. Substituir arquivos ───────────────────────────────────────
        Write-Info "Instalando v$remoteVersion..."
        if (-not (Install-ExtensionFiles -SourcePath $extensionRoot)) {
            Write-Err "Instalação falhou. Tentando rollback para v$currentVersion..."
            Invoke-Rollback -VersionToRestore $currentVersion
            return
        }

        # ── 12. Atualizar version.lock ────────────────────────────────────
        $newLock = [ordered]@{
            installed   = $remoteVersion
            previous    = $currentVersion
            lastCheck   = (Get-Date -Format 'o')
            lastUpdated = (Get-Date -Format 'o')
            isUpdating  = $false
        }
        Write-VersionLock $newLock

        $success = $true
        Write-Ok '═══════════════════════════════════════════════'
        Write-Ok "Atualização concluída: v$currentVersion → v$remoteVersion"
        Write-Ok "background.js detectará a nova versão e recarregará a extensão."
        Write-Ok '═══════════════════════════════════════════════'

    } finally {
        # ── Limpeza de temp ───────────────────────────────────────────────
        try {
            if (Test-Path $zipFile)    { Remove-Item $zipFile    -Force -ErrorAction SilentlyContinue }
            if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
        } catch {}

        # Garantir que isUpdating=false mesmo em caso de erro
        if (-not $success) {
            try {
                $lock = Read-VersionLock
                $lock.isUpdating = $false
                Write-VersionLock $lock
            } catch {}
        }

        Invoke-ReleaseLock
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
Write-Info "Nexos Updater v1.0.0 — PID: $PID — $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

try {
    Invoke-UpdateCheck
} catch {
    Write-Err "Erro inesperado: $($_.Exception.Message)"
    try { Invoke-ReleaseLock } catch {}
    exit 1
}

Write-Info "Nexos Updater finalizado."
exit 0
