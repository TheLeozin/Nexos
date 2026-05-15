#Requires -Version 5.1
<#
.SYNOPSIS
    Nexos Torre - Instalador Visual v2
    Design profissional: sidebar escura + area de conteudo clara.
    Executar sempre em modo STA:
        powershell.exe -sta -noprofile -executionpolicy bypass -file nexos-installer.ps1
#>
param(
    [string]$InstallPath = "$env:LOCALAPPDATA\Nexos",
    [switch]$Force
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- URLs ------------------------------------------------------------------
$RAW       = 'https://raw.githubusercontent.com/TheLeozin/Nexos/main'
$UPD_URL   = "$RAW/updater/nexos-updater.ps1"
$TASK_URL  = "$RAW/updater/install-task.ps1"
$LOGO_URL  = "$RAW/images/logo_nome.png"

# --- CAMINHOS --------------------------------------------------------------
$UPD_DIR   = Join-Path $InstallPath 'updater'
$EXT_DIR   = Join-Path $InstallPath 'extension'
$UPD_FILE  = Join-Path $UPD_DIR 'nexos-updater.ps1'
$TASK_FILE = Join-Path $UPD_DIR 'install-task.ps1'
$VER_LOCK  = Join-Path $InstallPath 'version.lock'

# --- PALETA ----------------------------------------------------------------
function rgb($r,$g,$b) { [System.Drawing.Color]::FromArgb($r,$g,$b) }
function rgba($a,$r,$g,$b) { [System.Drawing.Color]::FromArgb($a,$r,$g,$b) }

$C_SIDE    = rgb  18  30  66    # sidebar azul-marinho profundo
$C_SIDE2   = rgb  24  40  85    # sidebar hover/hover
$C_ACCENT  = rgb  26 143 214    # azul acao (linha e botao)
$C_ACCENT2 = rgb  16 110 178    # azul acao darker
$C_WHITE   = [System.Drawing.Color]::White
$C_BG      = rgb 246 248 252    # fundo principal off-white
$C_CARD    = rgb 255 255 255    # card branco
$C_GREEN   = rgb  34 168 110    # verde OK
$C_RED     = rgb 210  50  50    # erro
$C_ORANGE  = rgb 220 130   0    # aviso
$C_GRAY    = rgb 185 195 215    # pendente
$C_TEXT    = rgb  20  28  48    # texto principal escuro
$C_MUTED   = rgb 100 115 145    # texto secundario
$C_BORDER  = rgb 220 228 240    # bordas suaves
$C_LOGBG   = rgb 238 243 252    # fundo log

# ============================================================
#  FORM PRINCIPAL  560 x 620
# ============================================================
$F = New-Object System.Windows.Forms.Form
$F.Text            = 'Nexos Torre - Instalador'
$F.ClientSize      = New-Object System.Drawing.Size(620, 620)
$F.MinimumSize     = $F.Size
$F.MaximumSize     = $F.Size
$F.StartPosition   = 'CenterScreen'
$F.FormBorderStyle = 'FixedSingle'
$F.MaximizeBox     = $false
$F.BackColor       = $C_BG
$F.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

# ============================================================
#  SIDEBAR ESQUERDA  (180px)
# ============================================================
$SIDE = New-Object System.Windows.Forms.Panel
$SIDE.Location  = New-Object System.Drawing.Point(0, 0)
$SIDE.Size      = New-Object System.Drawing.Size(180, 620)
$SIDE.BackColor = $C_SIDE
$F.Controls.Add($SIDE)

# Logo na sidebar
$PIC = New-Object System.Windows.Forms.PictureBox
$PIC.Location  = New-Object System.Drawing.Point(22, 28)
$PIC.Size      = New-Object System.Drawing.Size(136, 90)
$PIC.SizeMode  = 'Zoom'
$PIC.BackColor = $C_SIDE
$SIDE.Controls.Add($PIC)

# Linha separadora sob o logo
$SIDE_LINE = New-Object System.Windows.Forms.Panel
$SIDE_LINE.Location  = New-Object System.Drawing.Point(22, 126)
$SIDE_LINE.Size      = New-Object System.Drawing.Size(136, 1)
$SIDE_LINE.BackColor = rgb 40 60 120
$SIDE.Controls.Add($SIDE_LINE)

# Versao na sidebar
$LBL_VER = New-Object System.Windows.Forms.Label
$LBL_VER.Text      = 'v3.0.1'
$LBL_VER.Location  = New-Object System.Drawing.Point(22, 134)
$LBL_VER.Size      = New-Object System.Drawing.Size(136, 18)
$LBL_VER.ForeColor = rgb 80 110 180
$LBL_VER.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
$LBL_VER.TextAlign = 'MiddleCenter'
$SIDE.Controls.Add($LBL_VER)

# Titulo na sidebar
$LBL_PROD = New-Object System.Windows.Forms.Label
$LBL_PROD.Text      = 'Torre de'
$LBL_PROD.Location  = New-Object System.Drawing.Point(22, 162)
$LBL_PROD.Size      = New-Object System.Drawing.Size(136, 20)
$LBL_PROD.ForeColor = rgb 180 200 235
$LBL_PROD.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$LBL_PROD.TextAlign = 'MiddleCenter'
$SIDE.Controls.Add($LBL_PROD)

$LBL_PROD2 = New-Object System.Windows.Forms.Label
$LBL_PROD2.Text      = 'Controle GPA'
$LBL_PROD2.Location  = New-Object System.Drawing.Point(22, 182)
$LBL_PROD2.Size      = New-Object System.Drawing.Size(136, 20)
$LBL_PROD2.ForeColor = rgb 180 200 235
$LBL_PROD2.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$LBL_PROD2.TextAlign = 'MiddleCenter'
$SIDE.Controls.Add($LBL_PROD2)

# Steps na sidebar (indicadores laterais)
$STEP_DEFS = @(
    'Pastas'
    'Atualizador'
    'Baixando'
    'Instalando'
    'Auto-update'
)

$SC = @()
$sideY = 230

foreach ($i in 0..($STEP_DEFS.Count - 1)) {
    # Icone circulo numerado
    $SIC = New-Object System.Windows.Forms.Label
    $SIC.Location  = New-Object System.Drawing.Point(22, $sideY)
    $SIC.Size      = New-Object System.Drawing.Size(24, 24)
    $SIC.BackColor = $C_GRAY
    $SIC.ForeColor = $C_WHITE
    $SIC.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
    $SIC.TextAlign = 'MiddleCenter'
    $SIC.Text      = ($i + 1).ToString()
    $SIDE.Controls.Add($SIC)

    # Label do step
    $SLT = New-Object System.Windows.Forms.Label
    $SLT.Location  = New-Object System.Drawing.Point(54, $sideY)
    $SLT.Size      = New-Object System.Drawing.Size(110, 24)
    $SLT.Text      = $STEP_DEFS[$i]
    $SLT.ForeColor = rgb 130 150 190
    $SLT.Font      = New-Object System.Drawing.Font('Segoe UI', 8.5)
    $SLT.TextAlign = 'MiddleLeft'
    $SIDE.Controls.Add($SLT)

    $SC += @{ Ic = $SIC; Lt = $SLT }
    $sideY += 36
}

# Rodape sidebar
$LBL_COPY = New-Object System.Windows.Forms.Label
$LBL_COPY.Text      = 'GPA  |  2026'
$LBL_COPY.Location  = New-Object System.Drawing.Point(22, 590)
$LBL_COPY.Size      = New-Object System.Drawing.Size(136, 18)
$LBL_COPY.ForeColor = rgb 50 70 120
$LBL_COPY.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5)
$LBL_COPY.TextAlign = 'MiddleCenter'
$SIDE.Controls.Add($LBL_COPY)

# ============================================================
#  AREA PRINCIPAL (direita, x=180)
# ============================================================
$W = 440   # largura da area principal

# Titulo topo
$LBL_TITLE = New-Object System.Windows.Forms.Label
$LBL_TITLE.Text      = 'Instalacao do Nexos Torre'
$LBL_TITLE.Location  = New-Object System.Drawing.Point(196, 26)
$LBL_TITLE.Size      = New-Object System.Drawing.Size(400, 34)
$LBL_TITLE.ForeColor = $C_TEXT
$LBL_TITLE.Font      = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$F.Controls.Add($LBL_TITLE)

$LBL_SUB = New-Object System.Windows.Forms.Label
$LBL_SUB.Text      = 'Configurando sua estacao de trabalho...'
$LBL_SUB.Location  = New-Object System.Drawing.Point(196, 62)
$LBL_SUB.Size      = New-Object System.Drawing.Size(400, 20)
$LBL_SUB.ForeColor = $C_MUTED
$LBL_SUB.Font      = New-Object System.Drawing.Font('Segoe UI', 9)
$F.Controls.Add($LBL_SUB)

# Linha decorativa sob o titulo
$TITLE_LINE = New-Object System.Windows.Forms.Panel
$TITLE_LINE.Location  = New-Object System.Drawing.Point(196, 88)
$TITLE_LINE.Size      = New-Object System.Drawing.Size(400, 2)
$TITLE_LINE.BackColor = $C_BORDER
$F.Controls.Add($TITLE_LINE)

# Linha de acento colorida
$TITLE_ACCENT = New-Object System.Windows.Forms.Panel
$TITLE_ACCENT.Location  = New-Object System.Drawing.Point(196, 88)
$TITLE_ACCENT.Size      = New-Object System.Drawing.Size(60, 2)
$TITLE_ACCENT.BackColor = $C_ACCENT
$F.Controls.Add($TITLE_ACCENT)

# ---- BARRA DE PROGRESSO (abaixo do titulo) ----
$PB = New-Object System.Windows.Forms.ProgressBar
$PB.Location = New-Object System.Drawing.Point(196, 100)
$PB.Size     = New-Object System.Drawing.Size(400, 6)
$PB.Minimum  = 0
$PB.Maximum  = 100
$PB.Value    = 0
$PB.Style    = 'Continuous'
$F.Controls.Add($PB)

# ---- STATUS (abaixo da barra) ----
$STAT = New-Object System.Windows.Forms.Label
$STAT.Location  = New-Object System.Drawing.Point(196, 112)
$STAT.Size      = New-Object System.Drawing.Size(400, 18)
$STAT.Text      = 'Aguardando inicio...'
$STAT.Font      = New-Object System.Drawing.Font('Segoe UI', 8)
$STAT.ForeColor = $C_MUTED
$F.Controls.Add($STAT)

# ---- LOG (caixa de texto) ----
$LOG = New-Object System.Windows.Forms.RichTextBox
$LOG.Location    = New-Object System.Drawing.Point(196, 136)
$LOG.Size        = New-Object System.Drawing.Size(400, 360)
$LOG.BackColor   = $C_LOGBG
$LOG.ForeColor   = $C_MUTED
$LOG.Font        = New-Object System.Drawing.Font('Consolas', 8)
$LOG.ReadOnly    = $true
$LOG.ScrollBars  = 'Vertical'
$LOG.BorderStyle = 'None'
$F.Controls.Add($LOG)

# ---- BOTAO FINAL ----
$BTN = New-Object System.Windows.Forms.Button
$BTN.Location  = New-Object System.Drawing.Point(196, 508)
$BTN.Size      = New-Object System.Drawing.Size(400, 52)
$BTN.Text      = 'Instalando, aguarde...'
$BTN.Font      = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$BTN.BackColor = $C_GRAY
$BTN.ForeColor = $C_WHITE
$BTN.FlatStyle = 'Flat'
$BTN.FlatAppearance.BorderSize = 0
$BTN.Enabled   = $false
$F.Controls.Add($BTN)

# Nota sobre caminho (abaixo do botao)
$LBL_NOTE = New-Object System.Windows.Forms.Label
$LBL_NOTE.Location  = New-Object System.Drawing.Point(196, 566)
$LBL_NOTE.Size      = New-Object System.Drawing.Size(400, 36)
$LBL_NOTE.Text      = "Local de instalacao:`r`n$InstallPath"
$LBL_NOTE.Font      = New-Object System.Drawing.Font('Segoe UI', 7.5)
$LBL_NOTE.ForeColor = $C_MUTED
$F.Controls.Add($LBL_NOTE)

# ============================================================
#  HELPERS DE UI
# ============================================================
function DoUI { [System.Windows.Forms.Application]::DoEvents() }

function Set-Step([int]$i, [string]$state) {
    $c = $SC[$i]
    switch ($state) {
        'active' {
            $c.Ic.BackColor = $C_ACCENT
            $c.Ic.Text      = '...'
            $c.Lt.ForeColor = $C_WHITE
            $c.Lt.Font      = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Bold)
        }
        'done' {
            $c.Ic.BackColor = $C_GREEN
            $c.Ic.Text      = 'v'
            $c.Lt.ForeColor = rgb 200 220 255
            $c.Lt.Font      = New-Object System.Drawing.Font('Segoe UI', 8.5)
        }
        'warn' {
            $c.Ic.BackColor = $C_ORANGE
            $c.Ic.Text      = '!'
            $c.Lt.ForeColor = rgb 220 200 100
        }
        'error' {
            $c.Ic.BackColor = $C_RED
            $c.Ic.Text      = 'X'
            $c.Lt.ForeColor = rgb 255 140 140
        }
    }
    DoUI
}

function Add-Log([string]$msg) {
    $ts = Get-Date -Format 'HH:mm:ss'
    $LOG.AppendText("[$ts] $msg`n")
    try { $LOG.ScrollToCaret() } catch {}
    DoUI
}

function Set-Status([string]$msg, $col = $null) {
    $STAT.Text = $msg
    if ($col) { $STAT.ForeColor = $col } else { $STAT.ForeColor = $C_MUTED }
    DoUI
}

function Set-Progress([int]$v) {
    $PB.Value = [Math]::Min(100, [Math]::Max(0, $v))
    DoUI
}

function Update-Subtitle([string]$msg) {
    $LBL_SUB.Text = $msg
    DoUI
}

function Load-Logo {
    $localLogo = Join-Path $EXT_DIR 'images\logo_nome.png'
    try {
        if (Test-Path $localLogo) {
            $PIC.Image    = [System.Drawing.Image]::FromFile($localLogo)
            $PIC.BackColor = $C_SIDE
        } else {
            $tmp = "$env:TEMP\_nexos_logo_$PID.png"
            (New-Object System.Net.WebClient).DownloadFile($LOGO_URL, $tmp)
            $PIC.Image    = [System.Drawing.Image]::FromFile($tmp)
            $PIC.BackColor = $C_SIDE
        }
    } catch {}
    DoUI
}

# ============================================================
#  INSTALACAO
# ============================================================
function Start-Install {

    # Verificar se ja instalado
    if ((Test-Path $VER_LOCK) -and -not $Force) {
        try {
            $vl = Get-Content $VER_LOCK -Raw | ConvertFrom-Json
            if ($vl.installed -and $vl.installed -ne '0.0.0') {
                Show-AlreadyInstalled $vl.installed
                return
            }
        } catch {}
    }

    # -- STEP 0: Criar pastas -----------------------------------------------
    Set-Step 0 'active'
    Update-Subtitle 'Criando estrutura de pastas...'
    Add-Log "Destino: $InstallPath"

    foreach ($d in @(
        $InstallPath, $UPD_DIR, $EXT_DIR,
        (Join-Path $InstallPath 'backup'),
        (Join-Path $InstallPath 'logs'),
        (Join-Path $InstallPath 'temp')
    )) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Add-Log "  OK: $(Split-Path $d -Leaf)"
    }

    Set-Progress 8
    Set-Step 0 'done'

    # -- STEP 1: Baixar scripts ----------------------------------------------
    Set-Step 1 'active'
    Update-Subtitle 'Baixando scripts do servidor Nexos...'

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'NexosInstaller/3.0')
        $wc.Headers.Add('Cache-Control', 'no-cache')

        Add-Log "Baixando nexos-updater.ps1..."
        $wc.DownloadFile($UPD_URL, $UPD_FILE)
        Add-Log "  OK ($([math]::Round((Get-Item $UPD_FILE).Length/1KB,1)) KB)"

        Add-Log "Baixando install-task.ps1..."
        $wc.DownloadFile($TASK_URL, $TASK_FILE)
        Add-Log "  OK ($([math]::Round((Get-Item $TASK_FILE).Length/1KB,1)) KB)"

        $wc.Dispose()
        Set-Progress 20
        Set-Step 1 'done'
    } catch {
        try { $wc.Dispose() } catch {}
        Add-Log "ERRO: $($_.Exception.Message)"
        Set-Step 1 'error'
        Set-Status 'Falha no download de scripts.' $C_RED
        Show-Error; return
    }

    # -- STEP 2: Baixar extensao --------------------------------------------
    Set-Step 2 'active'
    Update-Subtitle 'Consultando versao disponivel...'

    try {
        $wc2 = New-Object System.Net.WebClient
        $wc2.Headers.Add('User-Agent', 'NexosInstaller/3.0')
        $wc2.Headers.Add('Cache-Control', 'no-cache')

        Add-Log "Lendo latest.json..."
        $latest   = $wc2.DownloadString("$RAW/latest.json") | ConvertFrom-Json
        $zipUrl   = $latest.url
        $ver      = $latest.version
        $expHash  = ($latest.hash -replace 'sha256:', '').ToUpper()
        Add-Log "  Versao disponivel: v$ver"
        $LBL_VER.Text = "v$ver"

        $tempDir = Join-Path $InstallPath 'temp'
        $zipFile = Join-Path $tempDir "nexos-$ver.zip"

        Add-Log "Baixando $zipUrl..."
        Update-Subtitle "Baixando Nexos Torre v$ver..."
        Set-Progress 30
        DoUI

        $wc2.DownloadFile($zipUrl, $zipFile)
        $wc2.Dispose()
        $sizeMB = [math]::Round((Get-Item $zipFile).Length / 1MB, 2)
        Add-Log "  Download OK ($sizeMB MB)"
        Set-Progress 55
        Set-Step 2 'done'
    } catch {
        try { $wc2.Dispose() } catch {}
        Add-Log "ERRO: $($_.Exception.Message)"
        Set-Step 2 'error'
        Set-Status 'Falha no download da extensao.' $C_RED
        Show-Error; return
    }

    # -- STEP 3: Instalar extensao ------------------------------------------
    Set-Step 3 'active'
    Update-Subtitle 'Validando e instalando a extensao...'
    Set-Progress 60

    try {
        Add-Log "Validando SHA-256..."
        $actualHash = (Get-FileHash $zipFile -Algorithm SHA256).Hash.ToUpper()
        if ($expHash -and ($actualHash -ne $expHash)) {
            Add-Log "ERRO: hash invalido!"
            Add-Log "  Esperado: $expHash"
            Add-Log "  Obtido:   $actualHash"
            Set-Step 3 'error'
            Set-Status 'Arquivo corrompido. Tente novamente.' $C_RED
            Show-Error; return
        }
        Add-Log "  Hash OK"
        Set-Progress 68

        if (Test-Path $EXT_DIR) { Remove-Item $EXT_DIR -Recurse -Force -ErrorAction SilentlyContinue }
        Add-Log "Extraindo arquivos para $EXT_DIR..."
        Expand-Archive -Path $zipFile -DestinationPath $EXT_DIR -Force
        Set-Progress 78
        Add-Log "  Extracao OK"

        @{ installed = $ver; date = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ') } |
            ConvertTo-Json | Set-Content -Path $VER_LOCK -Encoding UTF8
        Add-Log "  version.lock: v$ver"

        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Set-Step 3 'done'
    } catch {
        Add-Log "ERRO: $($_.Exception.Message)"
        Set-Step 3 'error'
        Set-Status 'Falha na instalacao.' $C_RED
        Show-Error; return
    }

    # -- STEP 4: Tarefa agendada --------------------------------------------
    Set-Step 4 'active'
    Update-Subtitle 'Registrando tarefa de auto-atualizacao...'
    Set-Progress 86

    $taskOk = $false
    if (Test-Path $TASK_FILE) {
        try {
            Add-Log "Criando tarefa NexosUpdater..."
            $p = Start-Process 'powershell.exe' -ArgumentList "-noprofile -executionpolicy bypass -file `"$TASK_FILE`" -InstallPath `"$InstallPath`"" -Wait -PassThru -WindowStyle Hidden
            $taskOk = ($p.ExitCode -eq 0)
            if ($taskOk) { Add-Log "  Tarefa criada" } else { Add-Log "  Aviso: cod $($p.ExitCode)" }
        } catch { Add-Log "  Aviso: $($_.Exception.Message)" }
    }

    if ($taskOk) { Set-Step 4 'done' } else { Set-Step 4 'warn' }

    # -- FINAL --------------------------------------------------------------
    $verFinal = '?'
    try { $verFinal = (Get-Content $VER_LOCK -Raw | ConvertFrom-Json).installed } catch {}
    $LBL_VER.Text = "v$verFinal"

    Load-Logo
    Set-Progress 100
    Update-Subtitle "Nexos Torre v$verFinal instalado com sucesso!"
    Set-Status "Instalacao concluida!" $C_GREEN

    Add-Log ""
    Add-Log "============================================"
    Add-Log "  PROXIMO PASSO: ativar no Chrome / Edge"
    Add-Log "============================================"
    Add-Log "  1. Clique no botao abaixo para abrir"
    Add-Log "     chrome://extensions"
    Add-Log "  2. Ative 'Modo do desenvolvedor'"
    Add-Log "  3. Clique 'Carregar sem compactacao'"
    Add-Log "  4. Cole o caminho (ja na area de transfer.):"
    Add-Log "     $EXT_DIR"
    Add-Log "============================================"

    try { $EXT_DIR | clip } catch {}

    $BTN.Text      = "  Abrir chrome://extensions     (caminho ja copiado!)"
    $BTN.BackColor = $C_ACCENT
    $BTN.Enabled   = $true

    $capturedDir = $EXT_DIR
    $BTN.Add_Click({
        try { $capturedDir | clip } catch {}
        $launched = $false
        foreach ($cp in @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
        )) {
            if (Test-Path $cp) {
                if ($cp -like '*Edge*') { $ext = 'edge://extensions/' } else { $ext = 'chrome://extensions/' }
                Start-Process $cp "--new-window $ext"
                $launched = $true
                break
            }
        }
        if (-not $launched) {
            $msg = "Abra o Chrome/Edge e acesse:`n  chrome://extensions`n`nDepois:`n  1. Ative Modo do desenvolvedor`n  2. Carregar sem compactacao`n  3. Selecione (Ctrl+V):`n     $capturedDir"
            [System.Windows.Forms.MessageBox]::Show($msg, 'Nexos Torre - Passo Final', 'OK', 'Information') | Out-Null
        }
    }.GetNewClosure())
}

# ============================================================
#  JA INSTALADO
# ============================================================
function Show-AlreadyInstalled([string]$ver) {
    for ($i = 0; $i -lt $SC.Count; $i++) { Set-Step $i 'done' }
    Load-Logo
    Set-Progress 100
    Update-Subtitle "Nexos Torre v$ver ja esta instalado."
    Set-Status "Instalacao detectada: v$ver" $C_GREEN
    Add-Log "Instalacao existente: v$ver"
    Add-Log "Caminho: $EXT_DIR"
    try { $EXT_DIR | clip } catch {}

    $capturedDir = $EXT_DIR
    $BTN.Text      = "  Abrir chrome://extensions     (caminho ja copiado!)"
    $BTN.BackColor = $C_GREEN
    $BTN.Enabled   = $true
    $BTN.Add_Click({
        try { $capturedDir | clip } catch {}
        foreach ($cp in @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
        )) {
            if (Test-Path $cp) {
                if ($cp -like '*Edge*') { $ext = 'edge://extensions/' } else { $ext = 'chrome://extensions/' }
                Start-Process $cp "--new-window $ext"; break
            }
        }
    }.GetNewClosure())
}

# ============================================================
#  ERRO
# ============================================================
function Show-Error {
    $BTN.Text      = '  Instalacao falhou  |  Clique para fechar'
    $BTN.BackColor = $C_RED
    $BTN.Enabled   = $true
    $BTN.Add_Click({ $F.Close() })
    Set-Progress 0
}

# ============================================================
#  INICIAR
# ============================================================
$F.Add_Shown({
    Load-Logo
    DoUI
    Start-Install
})

[void]$F.ShowDialog()