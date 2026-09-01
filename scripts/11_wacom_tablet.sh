#!/bin/bash
# ==============================================================================
# Módulo 11: Suporte, Drivers e Conexão Bluetooth da Mesa Digitalizadora Wacom (Intuos Pro)
# ==============================================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_comum.sh"

FLAG_NAME="WACOM_TABLET"

if check_flag "$FLAG_NAME"; then
    log_msg "INFO" "⏭️  Mesa Wacom já configurada anteriormente. Pulando..."
    exit 0
fi

log_msg "HEADER" "11. CONFIGURAÇÃO DA MESA DIGITALIZADORA WACOM (INTUOS PRO)"

# 1. Instalação das bibliotecas e utilitários da Wacom
log_msg "INFO" "Instalando utilitários e bibliotecas de suporte da Wacom..."
sudo apt update
sudo apt install -y libwacom-bin libwacom-common libwacom9 xserver-xorg-input-wacom

# 2. Carregamento automático do módulo de kernel 'wacom'
log_msg "INFO" "Garantindo módulo de kernel 'wacom' carregado no boot..."
sudo modprobe wacom 2>/dev/null || true
echo "wacom" | sudo tee /etc/modules-load.d/wacom.conf > /dev/null

# 3. Regras Udev e permissões para dispositivos Wacom e Bluetooth HID
log_msg "INFO" "Configurando regras Udev para permissões de entrada..."
cat << 'EOF' | sudo tee /etc/udev/rules.d/99-wacom.rules > /dev/null
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput", MODE="0660", GROUP="input"
SUBSYSTEM=="input", ATTRS{idVendor}=="056a", MODE="0664", GROUP="input"
SUBSYSTEM=="hidraw", ATTRS{idVendor}=="056a", MODE="0664", GROUP="input"
EOF
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger 2>/dev/null || true

# Adiciona o usuário aos grupos de input se necessário
sudo usermod -aG input "$REAL_USER" 2>/dev/null || true

# 4. Detecção e Emparelhamento Bluetooth Automatizado
log_msg "INFO" "Verificando dispositivos Wacom Bluetooth emparelhados..."
WACOM_MAC=$(bluetoothctl devices 2>/dev/null | grep -iE 'Intuos|Wacom' | head -n 1 | awk '{print $2}' || true)

if [ -n "$WACOM_MAC" ]; then
    log_msg "INFO" "Dispositivo Wacom detectado no Bluetooth: $WACOM_MAC"
    log_msg "INFO" "Definindo dispositivo como confiável (trust) para auto-reconexão..."
    bluetoothctl trust "$WACOM_MAC" 2>/dev/null || true
    
    # Tenta conectar se a mesa estiver ligada
    log_msg "INFO" "Tentando estabelecer conexão Bluetooth..."
    if bluetoothctl connect "$WACOM_MAC" 2>/dev/null; then
        log_msg "SUCCESS" "Mesa Wacom conectada com sucesso via Bluetooth ($WACOM_MAC)!"
    else
        log_msg "INFO" "Mesa Wacom registrada como confiável. Quando ligar a mesa ou colocá-la em modo de pareamento, ela conectará automaticamente."
    fi
else
    log_msg "INFO" "Nenhuma mesa Wacom emparelhada anteriormente no Bluetooth."
    log_msg "INFO" "Dica: Para emparelhar sua Intuos Pro via Bluetooth, segure o botão central do Touch Ring por 3 segundos até o LED azul piscar rapidamente."
fi

# 5. Configurações de Mapeamento 1:1 e Proporção de Tela
set_user_gsetting "org.gnome.desktop.peripherals.tablet" "keep-aspect" "true"
set_user_gsetting "org.gnome.desktop.peripherals.tablet" "left-handed" "false"

set_flag "$FLAG_NAME"
log_msg "SUCCESS" "Suporte à mesa digitalizadora Wacom configurado com sucesso."
