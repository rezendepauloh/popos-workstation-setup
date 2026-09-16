# 📁 Guia de Configuração: Nautilus (GNOME Files) como Gerenciador de Arquivos Padrão

Este documento descreve as razões técnicas, os scripts integrados e os comandos necessários para definir o **Nautilus (GNOME Files)** como o gerenciador de arquivos padrão no **Pop!_OS 24.04 (Ambiente COSMIC Desktop)**, substituindo o `COSMIC Files` (`com.system76.CosmicFiles`).

---

## 📌 Motivação da Troca

O `COSMIC Files` ainda está em desenvolvimento ativo e pode apresentar instabilidades no uso diário:
- Falhas/crashes intermitentes ao navegar em diretórios com grande volume de arquivos.
- Limitações na integração com compartilhamentos de rede remotos (Samba/SMB, SSHFS, WebDAV, Google Drive).
- Comportamentos inesperados em drag-and-drop com softwares legados ou Flatpaks.

O **Nautilus**, em conjunto com os backends do `gvfs` (`gvfs-backends`), oferece máxima estabilidade, suporte maduro a montagens de rede, integração sólida com o tema visual do sistema e excelente desempenho.

---

## 🚀 Como Funciona a Integração nos Scripts

A substituição foi incorporada nos seguintes módulos do projeto:

1. **`scripts/04_pacotes_base_dev.sh`**:
   - Adicionados os pacotes essenciais `nautilus` e `gvfs-backends` no `apt install`.
2. **`scripts/09_onlyoffice_padrao.sh`**:
   - Associa o MIME type `inode/directory` diretamente ao `org.gnome.Nautilus.desktop` via:
     - `xdg-mime default org.gnome.Nautilus.desktop inode/directory`
     - `gio mime inode/directory org.gnome.Nautilus.desktop`
     - Gravação persistente nas seções `[Default Applications]` de `~/.config/mimeapps.list` e `~/.config/cosmic-mimeapps.list`.
3. **`scripts/14_cosmic_theme_restore.sh`**:
   - Registra `org.gnome.Nautilus` e `org.gnome.NautilusDialog` nas exceções de tiling do COSMIC (`tiling_exception_custom`), garantindo que janelas de arquivos abram de forma flutuante e suave.
4. **`scripts/15_cosmic_menu_dock.sh`**:
   - Substitui `com.system76.CosmicFiles` por `org.gnome.Nautilus` na Dock do COSMIC (`favorites`).
   - Remove o Nautilus da pasta genérica de utilitários para que fique acessível como aplicativo principal no menu e na barra de favoritos.

---

## 🛠️ Comandos Manuais para Execução Imediata

Caso queira aplicar ou redefinir o Nautilus manualmente sem rodar todo o setup:

### 1. Instalar os pacotes
```bash
sudo apt update && sudo apt install -y nautilus gvfs-backends
```

### 2. Definir como Gerenciador Padrão (MIME inode/directory)
```bash
# Define via XDG MIME
xdg-mime default org.gnome.Nautilus.desktop inode/directory

# Define via GIO (GNOME/GLib)
gio mime inode/directory org.gnome.Nautilus.desktop
```

### 3. Fixar na Dock do COSMIC e atualizar menus
```bash
python3 -c "
import os, re

fav_path = os.path.expanduser('~/.config/cosmic/com.system76.CosmicAppList/v1/favorites')
if os.path.exists(fav_path):
    with open(fav_path, 'r') as f:
        data = f.read()
    if 'com.system76.CosmicFiles' in data:
        data = data.replace('\"com.system76.CosmicFiles\"', '\"org.gnome.Nautilus\"')
    elif '\"org.gnome.Nautilus\"' not in data:
        data = re.sub(r'(\[\s*)', r'\1\"org.gnome.Nautilus\",\n    ', data)
    with open(fav_path, 'w') as f:
        f.write(data)
"

# Recarrega o painel e a biblioteca de apps do COSMIC
pkill -f cosmic-panel 2>/dev/null || true
pkill -f cosmic-app-library 2>/dev/null || true
```

### 4. Verificar se a associação está ativa
```bash
xdg-mime query default inode/directory
# Deve retornar: org.gnome.Nautilus.desktop
```

---

## 🔍 Testando
Abra qualquer diretório via terminal:
```bash
xdg-open ~
```
O diretório Home deverá abrir imediatamente no **Nautilus**.
