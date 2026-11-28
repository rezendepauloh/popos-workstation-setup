# ==============================================================================
# sync_onedrive.ps1
# Dispara e acompanha a sincronização do Microsoft OneDrive (MPMS) dentro da VM
# Windows 11 (WinApps) de forma silenciosa, reportando o progresso para o host
# Linux via \\host.lan\Data\onedrive_sync_status.json.
# ==============================================================================

param(
    [int]$InitialWaitSeconds = 12,
    [int]$MaxWaitSeconds = 120,
    [int]$PollIntervalSeconds = 3
)

$ErrorActionPreference = "SilentlyContinue"

$ShareDir = "\\host.lan\Data"
$StatusFile = Join-Path $ShareDir "onedrive_sync_status.json"
$LogFile = Join-Path $ShareDir "onedrive_sync.log"

function Write-SyncLog {
    param([string]$Message)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    try {
        Add-Content -Path $LogFile -Value "[$ts] $Message" -Encoding UTF8
    } catch {}
}

function Write-SyncStatus {
    param(
        [string]$State,
        [string]$Message,
        [int]$FilesToUpload = 0,
        [int]$FilesToDownload = 0
    )
    $payload = [ordered]@{
        state             = $State
        message           = $Message
        timestamp         = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
        pid               = $PID
        files_to_upload   = $FilesToUpload
        files_to_download = $FilesToDownload
    }
    try {
        $json = $payload | ConvertTo-Json -Compress
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($StatusFile, $json, $utf8NoBom)
    } catch {}
}

function Find-OneDriveExe {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\OneDrive.exe"),
        (Join-Path $env:ProgramFiles "Microsoft OneDrive\OneDrive.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft OneDrive\OneDrive.exe")
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }
    return $null
}

function Get-OneDriveDiagnostics {
    $result = @{
        Found           = $false
        FilesToUpload   = 0
        FilesToDownload = 0
        SyncProgress    = -1
        LastWriteUtc    = [DateTime]::MinValue
    }

    $logsBase = Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\logs"
    if (-not (Test-Path -LiteralPath $logsBase)) {
        return $result
    }

    $diagFiles = Get-ChildItem -Path $logsBase -Filter "SyncDiagnostics.log" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending

    if (-not $diagFiles -or $diagFiles.Count -eq 0) {
        return $result
    }

    $diagFile = $diagFiles[0]
    $result.Found = $true
    $result.LastWriteUtc = $diagFile.LastWriteTimeUtc

    try {
        $lines = Get-Content -LiteralPath $diagFile.FullName -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '^FilesToUpload\s*=\s*(\d+)') {
                $result.FilesToUpload = [int]$Matches[1]
            } elseif ($line -match '^FilesToDownload\s*=\s*(\d+)') {
                $result.FilesToDownload = [int]$Matches[1]
            } elseif ($line -match '^SyncProgressState\s*=\s*(\d+)') {
                $result.SyncProgress = [int]$Matches[1]
            }
        }
    } catch {}

    return $result
}

function Get-LatestOdlWriteUtc {
    $logsBase = Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive\logs"
    if (-not (Test-Path -LiteralPath $logsBase)) {
        return [DateTime]::MinValue
    }
    $latest = Get-ChildItem -Path $logsBase -Filter "*.odl" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($latest) {
        return $latest.LastWriteTimeUtc
    }
    return [DateTime]::MinValue
}

# 1. Início
Write-SyncLog "Iniciando sincronização silenciosa do OneDrive MPMS..."
Write-SyncStatus -State "starting" -Message "Localizando OneDrive na VM..."

$oneDriveExe = Find-OneDriveExe
if (-not $oneDriveExe) {
    Write-SyncLog "ERRO: OneDrive.exe não encontrado."
    Write-SyncStatus -State "error" -Message "OneDrive.exe não encontrado na VM Windows."
    exit 1
}

# 2. Se já estiver rodando, reinicia suavemente para forçar varredura delta imediata
$existing = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
if ($existing) {
    Write-SyncLog "OneDrive já em execução (PID(s): $(($existing | Select-Object -ExpandProperty Id) -join ',')). Reiniciando para forçar varredura delta..."
    Write-SyncStatus -State "starting" -Message "Reiniciando OneDrive para forçar sincronização..."
    try {
        Start-Process -FilePath $oneDriveExe -ArgumentList "/shutdown" -WindowStyle Hidden -Wait
    } catch {}
    $waitStop = 0
    while ((Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue) -and ($waitStop -lt 10)) {
        Start-Sleep -Seconds 1
        $waitStop++
    }
}

# 3. Inicia OneDrive em modo background
Write-SyncLog "Iniciando OneDrive em segundo plano: $oneDriveExe /background"
Write-SyncStatus -State "syncing" -Message "Iniciando OneDrive e verificando alterações..."
Start-Process -FilePath $oneDriveExe -ArgumentList "/background" -WindowStyle Hidden

# Aguarda inicialização do SyncEngine e autenticação M365
Start-Sleep -Seconds $InitialWaitSeconds

# 4. Loop de monitoramento até estabilizar (idle) ou atingir MaxWaitSeconds
$startTime = Get-Date
$idleChecks = 0
$lastCpu = 0.0

$proc = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($proc) {
    $lastCpu = [double]$proc.CPU
}

while (((Get-Date) - $startTime).TotalSeconds -lt $MaxWaitSeconds) {
    $proc = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Write-SyncLog "OneDrive.exe encerrou inesperadamente; tentando relançar..."
        Start-Process -FilePath $oneDriveExe -ArgumentList "/background" -WindowStyle Hidden
        Start-Sleep -Seconds 5
        continue
    }

    $currCpu = [double]$proc.CPU
    $cpuDelta = $currCpu - $lastCpu
    $lastCpu = $currCpu

    $diag = Get-OneDriveDiagnostics
    $odlWrite = Get-LatestOdlWriteUtc
    $odlAge = ([DateTime]::UtcNow - $odlWrite).TotalSeconds

    $pendingUp = $diag.FilesToUpload
    $pendingDown = $diag.FilesToDownload

    if ($pendingUp -gt 0 -or $pendingDown -gt 0) {
        $idleChecks = 0
        $msg = "Sincronizando arquivos (enviando: $pendingUp, baixando: $pendingDown)..."
        Write-SyncStatus -State "syncing" -Message $msg -FilesToUpload $pendingUp -FilesToDownload $pendingDown
        Write-SyncLog $msg
    } else {
        # Considera ocioso quando não há arquivos pendentes, CPU baixa e sem escrita recente intensa
        $isLowCpu = ($cpuDelta -lt 0.35)
        $isOdlQuiet = ($odlAge -gt 6)

        if ($isLowCpu -and ($isOdlQuiet -or $diag.Found)) {
            $idleChecks++
            Write-SyncStatus -State "syncing" -Message "Finalizando verificação de sincronização..."
            if ($idleChecks -ge 3) {
                Write-SyncLog "Sincronização estabilizada (ocioso por 3 ciclos consecutivos)."
                break
            }
        } else {
            $idleChecks = 0
            Write-SyncStatus -State "syncing" -Message "Processando alterações na nuvem..."
        }
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}

$elapsed = [int](((Get-Date) - $startTime).TotalSeconds + $InitialWaitSeconds)
Write-SyncLog "Sincronização concluída em ${elapsed}s."
Write-SyncStatus -State "completed" -Message "Sincronização concluída (${elapsed}s)."
exit 0
