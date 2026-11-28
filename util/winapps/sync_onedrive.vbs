' Launcher silencioso (WindowStyle=0) para executar sync_onedrive.ps1 via RemoteApp sem exibir janela
Option Explicit
Dim shell, cmd, rc
Set shell = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""\\host.lan\Data\sync_onedrive.ps1"""
rc = shell.Run(cmd, 0, True)
WScript.Quit rc
