@echo off
:: ==============================================================================
:: WinApps AutoLogon & Lock Screen Bypass Setup for Windows 11
:: Configura o login automático e desativa a tela de bloqueio do Windows
:: ==============================================================================

setlocal enabledelayedexpansion
set "LOG_FILE=\\host.lan\Data\autologon_result.log"
echo [%DATE% %TIME%] Iniciando configuracao de AutoLogon... > "%LOG_FILE%"

set "RDP_USER=%~1"
set "RDP_PASS=%~2"
if "%RDP_USER%"=="" set "RDP_USER=winapps"
if "%RDP_PASS%"=="" set "RDP_PASS=%WINAPPS_RDP_PASSWORD%"

:: 1. Credenciais no Winlogon para RDP transparente
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultUserName" /t REG_SZ /d "%RDP_USER%" /f >> "%LOG_FILE%" 2>&1
if not "%RDP_PASS%"=="" (
    reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultPassword" /t REG_SZ /d "%RDP_PASS%" /f >> "%LOG_FILE%" 2>&1
)
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "DefaultDomainName" /t REG_SZ /d "" /f >> "%LOG_FILE%" 2>&1
reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "ForceAutoLogon" /f >> "%LOG_FILE%" 2>&1
reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v "AutoAdminLogon" /t REG_SZ /d "0" /f >> "%LOG_FILE%" 2>&1

:: 2. Desativar Tela de Bloqueio (NoLockScreen)
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v "NoLockScreen" /t REG_DWORD /d 1 /f >> "%LOG_FILE%" 2>&1

:: 3. Desativar solicitacao de senha ao conectar via RDP / Terminal Services
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" /v "fPromptForPassword" /t REG_DWORD /d 0 /f >> "%LOG_FILE%" 2>&1
reg.exe add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v "fPromptForPassword" /t REG_DWORD /d 0 /f >> "%LOG_FILE%" 2>&1

:: 4. Desativar protecao por senha no protetor de tela
reg.exe add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop" /v "ScreenSaverIsSecure" /t REG_SZ /d 0 /f >> "%LOG_FILE%" 2>&1
reg.exe add "HKCU\Control Panel\Desktop" /v "ScreenSaverIsSecure" /t REG_SZ /d 0 /f >> "%LOG_FILE%" 2>&1

:: 5. Desativar suspensao e desligamento de tela via PowerCFG
powercfg.exe -x -monitor-timeout-ac 0 >> "%LOG_FILE%" 2>&1
powercfg.exe -x -standby-timeout-ac 0 >> "%LOG_FILE%" 2>&1
powercfg.exe -h off >> "%LOG_FILE%" 2>&1

:: 6. Impedir expiracao de senha da conta local
net.exe accounts /maxpwage:unlimited >> "%LOG_FILE%" 2>&1

echo [%DATE% %TIME%] AutoLogon configurado com sucesso! >> "%LOG_FILE%"
exit /b 0

