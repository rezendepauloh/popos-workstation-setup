@echo off
:: ==============================================================================
:: Launcher para o script de Otimização e Debloat da VM Windows 11 (WinApps)
:: Solicita elevação de privilégios como Administrador automaticamente
:: ==============================================================================

title Otimizar Windows 11 (WinApps Debloat)

:: Verificar permissões de administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Solicitando privilegios de Administrador...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~dpnx0\"\"' -Verb RunAs"
    exit /b
)

echo ==========================================================
echo   EXECUTANDO OTIMIZACAO DA VM WINDOWS 11 (WINAPPS)
echo ==========================================================
echo.

set SCRIPT_DIR=%~dp0
set PS_SCRIPT=%SCRIPT_DIR%otimizar_winapps_vm.ps1

if not exist "%PS_SCRIPT%" (
    echo [ERRO] O arquivo otimizar_winapps_vm.ps1 nao foi encontrado em %SCRIPT_DIR%
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

echo.
echo ==========================================================
echo Processo finalizado! Pressione qualquer tecla para fechar.
echo ==========================================================
pause >nul

