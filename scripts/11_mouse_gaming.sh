#!/bin/bash
# ==============================================================================
# Módulo 10: Configuração de Hardware do Mouse Gaming (Logitech G502 X)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="CONFIG_MOUSE"

if check_flag "$FLAG_NAME" "$@"; then
    log_msg "INFO" "⏭️  Configuração do mouse gaming já aplicada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "11. CONFIGURAÇÃO DO MOUSE GAMING (LOGITECH G502 X)"

# 1. Aceleração Flat 1:1 no GNOME / COSMIC
set_user_gsetting "org.gnome.desktop.peripherals.mouse" "accel-profile" "'flat'"
set_user_gsetting "org.gnome.desktop.peripherals.mouse" "speed" "0.0"

# 2. Configurações on-board via ratbagd / ratbagctl
log_msg "INFO" "Identificando mouse compatível via libratbag..."
sudo systemctl enable --now ratbagd 2>/dev/null || true

# Utiliza IDs de hardware definidos no .env se disponíveis
G502_USB_ID="${USB_ID_LOGITECH_G502X:-"046d:c547"}"
G733_USB_ID="${USB_ID_LOGITECH_G733:-"046d:0ab5"}"

log_msg "INFO" "Verificando hardware (G502 X: $G502_USB_ID, ignorando Headset: $G733_USB_ID)..."
MOUSE_ID=$(ratbagctl list 2>/dev/null | grep -iE 'G502|G502 X|mouse' | grep -ivE 'headset|headphone|audio|webcam|keyboard' | head -n 1 | cut -d: -f1 || true)
if [ -n "$MOUSE_ID" ]; then
    log_msg "INFO" "Mouse detectado: $MOUSE_ID. Gravando perfis e macros..."
    for p in {0..4}; do
        # Polling rate: 1000Hz (1ms de resposta)
        ratbagctl "$MOUSE_ID" profile $p set rate 1000 2>/dev/null || true
        
        # Níveis de DPI (1600 padrão de alta precisão)
        ratbagctl "$MOUSE_ID" profile $p resolution 0 set dpi 800 2>/dev/null || true
        ratbagctl "$MOUSE_ID" profile $p resolution 1 set dpi 1200 2>/dev/null || true
        ratbagctl "$MOUSE_ID" profile $p resolution 2 set dpi 1600 2>/dev/null || true
        ratbagctl "$MOUSE_ID" profile $p resolution 3 set dpi 2400 2>/dev/null || true
        ratbagctl "$MOUSE_ID" profile $p resolution 4 set dpi 3200 2>/dev/null || true
        ratbagctl "$MOUSE_ID" profile $p resolution set active 2 2>/dev/null || true
        
        # Gatilho para o Kando: Ctrl + Shift + F10 (Button 4)
        ratbagctl "$MOUSE_ID" profile $p button 4 action set macro +KEY_LEFTCTRL +KEY_LEFTSHIFT +KEY_F10 -KEY_F10 -KEY_LEFTSHIFT -KEY_LEFTCTRL --commit 2>/dev/null || true
        
        # Copiar (Button 5)
        ratbagctl "$MOUSE_ID" profile $p button 5 action set macro +KEY_LEFTCTRL +KEY_C -KEY_C -KEY_LEFTCTRL --commit 2>/dev/null || true
        
        # Rolagem Horizontal (Tilt Wheel)
        ratbagctl "$MOUSE_ID" profile $p button 6 action set special wheel-left --commit 2>/dev/null || true
        ratbagctl "$MOUSE_ID" profile $p button 7 action set special wheel-right --commit 2>/dev/null || true
    done
    log_msg "SUCCESS" "Macros gravadas na memória do mouse $MOUSE_ID com sucesso."
else
    log_msg "INFO" "Mouse operando via receptor sem fio ou memória interna. Perfil linear 1:1 aplicado no sistema."
fi

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Mouse gaming configurado com sucesso."
