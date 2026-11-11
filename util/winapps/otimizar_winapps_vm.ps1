# ==============================================================================
# Script de Otimização e Debloat Cirúrgico para VM Windows 11 (WinApps)
# Foco: Remover Telemetrias, Bloatware UWP e Serviços Pesados sem quebrar:
#       - Microsoft 365 / Office
#       - OneDrive
#       - RDP / RemoteApp / WinApps Integration
#       - Edge WebView2 / Edge Runtime (necessários para autenticação Microsoft)
# ==============================================================================

# Executar como Administrador se necessário
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Privilégios de Administrador são necessários! Elevando..."
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  INICIANDO OTIMIZAÇÃO & DEBLOAT DO WINDOWS 11 (WINAPPS)  " -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# 1. PARAR E DESATIVAR SERVIÇOS PESADOS E TELEMETRIA
# ------------------------------------------------------------------------------
Write-Host "`n[1/4] Desativando Serviços de Telemetria, Diagnósticos e I/O Desnecessários..." -ForegroundColor Green

$servicesToDisable = @(
    "DiagTrack",                 # Connected User Experiences and Telemetry
    "dmwappushservice",          # Device Management Wireless Application Protocol (WAP) Push
    "WerSvc",                    # Windows Error Reporting Service
    "SysMain",                   # SuperFetch / SysMain (desnecessário e gera I/O pesado em VM/SSD)
    "WSearch",                   # Windows Search Indexer (evita CPU alta constante indexando disco virtual)
    "MapsBroker",                # Downloaded Maps Manager
    "RetailDemo",                # Retail Demo Service
    "TroubleshootingSvc",        # Recommended Troubleshooting Service
    "XblAuthManager",            # Xbox Live Auth
    "XblGameSave",               # Xbox Live Game Save
    "XboxNetApiSvc",             # Xbox Live Networking Service
    "XboxGipSvc"                 # Xbox Accessory Management Service
)

foreach ($svc in $servicesToDisable) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Write-Host "  -> Desativando serviço: $svc" -ForegroundColor Gray
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------------------
# 2. TWEAKS DE REGISTRO (TELEMETRIA, CORTANA, ANÚNCIOS, DICAS)
# ------------------------------------------------------------------------------
Write-Host "`n[2/4] Aplicando Políticas de Registro (Anti-Telemetria, Bing Search, Anúncios)..." -ForegroundColor Green

$registryTweaks = @(
    # Desativar Telemetria Geral
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "MaxTelemetryAllowed"; Value = 0; Type = "DWord" },
    
    # Desativar Cortana e Pesquisa na Web no Menu Iniciar (Bing)
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "AllowCortana"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"; Name = "DisableWebSearch"; Value = 1; Type = "DWord" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"; Name = "BingSearchEnabled"; Value = 0; Type = "DWord" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"; Name = "CortanaConsent"; Value = 0; Type = "DWord" },
    
    # Desativar Sugestões, Anúncios e Conteúdo Promovido no Menu Iniciar
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SystemPaneSuggestionsEnabled"; Value = 0; Type = "DWord" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338388Enabled"; Value = 0; Type = "DWord" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338389Enabled"; Value = 0; Type = "DWord" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SoftLandingEnabled"; Value = 0; Type = "DWord" },
    @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "RotatingLockScreenOverlayEnabled"; Value = 0; Type = "DWord" },
    
    # Desativar Dicas e Sugestões do Windows
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableSoftLanding"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1; Type = "DWord" },
    
    # Desativar GameDVR / GameBar
    @{ Path = "HKCU:\System\GameConfigStore"; Name = "GameDVR_Enabled"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"; Name = "AllowGameDVR"; Value = 0; Type = "DWord" },

    # Otimizar Performance Visual (Reduzir animações desnecessárias para fluidez no RDP)
    @{ Path = "HKCU:\Control Panel\Desktop\WindowMetrics"; Name = "MinAnimate"; Value = "0"; Type = "String" },

    # Configuração de Login Automático Transparente e Sem Tela de Bloqueio (WinApps)
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"; Name = "DefaultUserName"; Value = "winapps"; Type = "String" },
    @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"; Name = "DefaultPassword"; Value = "M!n0t@ur0"; Type = "String" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"; Name = "NoLockScreen"; Value = 1; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name = "fPromptForPassword"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "fPromptForPassword"; Value = 0; Type = "DWord" },
    @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop"; Name = "ScreenSaverIsSecure"; Value = "0"; Type = "String" },
    @{ Path = "HKCU:\Control Panel\Desktop"; Name = "ScreenSaverIsSecure"; Value = "0"; Type = "String" }
)

foreach ($item in $registryTweaks) {
    if (-not (Test-Path $item.Path)) {
        New-Item -Path $item.Path -Force | Out-Null
    }
    Set-ItemProperty -Path $item.Path -Name $item.Name -Value $item.Value -Type $item.Type -Force
}

# ------------------------------------------------------------------------------
# 3. DESATIVAR TAREFAS AGENDADAS INVASIVAS DE TELEMETRIA
# ------------------------------------------------------------------------------
Write-Host "`n[3/4] Desativando Tarefas Agendadas de Coleta de Dados..." -ForegroundColor Green

$tasksToDisable = @(
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Autochk\Proxy",
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
)

foreach ($task in $tasksToDisable) {
    try {
        Disable-ScheduledTask -TaskPath ($task | Split-Path) -TaskName ($task | Split-Path -Leaf) -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  -> Tarefa desativada: $task" -ForegroundColor Gray
    } catch {
        # Silêncio se não existir
    }
}

# ------------------------------------------------------------------------------
# 4. REMOVER BLOATWARE UWP (PRESERVANDO ONEDRIVE E OFFICE)
# ------------------------------------------------------------------------------
Write-Host "`n[4/4] Removendo Aplicativos UWP Pré-instalados e Bloatware..." -ForegroundColor Green

$bloatwareApps = @(
    "*Microsoft.XboxApp*",
    "*Microsoft.XboxGamingOverlay*",
    "*Microsoft.XboxIdentityProvider*",
    "*Microsoft.XboxSpeechToTextOverlay*",
    "*Microsoft.GamingApp*",
    "*Microsoft.BingNews*",
    "*Microsoft.BingWeather*",
    "*Microsoft.GetHelp*",
    "*Microsoft.Getstarted*",
    "*Microsoft.MicrosoftSolitaireCollection*",
    "*Microsoft.People*",
    "*Microsoft.Todos*",
    "*Microsoft.YourPhone*",
    "*Microsoft.ZuneMusic*",
    "*Microsoft.ZuneVideo*",
    "*Clipchamp.Clipchamp*",
    "*SpotifyAB.SpotifyMusic*",
    "*Disney*",
    "*TikTok*",
    "*Facebook*",
    "*Instagram*",
    "*Amazon*",
    "*Netflix*"
)

foreach ($app in $bloatwareApps) {
    # Remove para o usuário atual
    Get-AppxPackage -Name $app -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
    # Remove do provisionamento para novos logins
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $app } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "  OTIMIZAÇÃO CONCLUÍDA COM SUCESSO!                     " -ForegroundColor Green
Write-Host "  Office, OneDrive e suporte a RemoteApp PRESERVADOS!   " -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Recomendado reiniciar a VM Windows quando conveniente." -ForegroundColor Yellow

