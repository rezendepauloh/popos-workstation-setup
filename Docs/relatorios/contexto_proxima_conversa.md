# 📝 Contexto e Diretrizes para a Próxima Conversa

## 📌 1. Conquistas Recentes (Status: Concluído e Estável)
1. **Reestruturação Arquitetural do Repositório**:
   - `setup_popos_v2.sh` renomeado definitivamente para [`setup_popos.sh`](../../setup_popos.sh).
   - `test_in_docker.sh` movido para [`tests/test_in_docker.sh`](../../tests/test_in_docker.sh).
   - `mpms_ca.crt` movido para [`config/ssl/mpms_ca.crt`](../../config/ssl/mpms_ca.crt).
   - `.setup_progress.log` movido para [`Logs/.setup_progress.log`](../../Logs/.setup_progress.log).
   - `rclone.conf` movido para `config/rclone/rclone.conf`.
   - Criado [`Docs/README.md`](../README.md) como portal centralizador de documentação e links.
   - Atualizado e repaginado [`README.md`](../../README.md) com badges oficiais, tabela open source expandida e árvores de diretórios.
   - Suíte de testes automatizados (`./setup_popos.sh --test`) com **100% de sucesso (22/22 testes passando)**.
2. **Suíte ArtCraft como Padrão de Produtividade**:
   - WordCraft, GridCraft e DeckCraft configurados como manipuladores MIME padrão em `~/.config/mimeapps.list` e `~/.config/cosmic-mimeapps.list`.
3. **OneDrive Corporativo Integrado ao Nautilus & Indicador COSMIC**:
   - Acesso nativo aos arquivos via SMB/GVFS sem dependência de janela da VM Windows.
   - Indicador de status oficial na barra superior via daemon StatusNotifierItem [`scripts/daemons/onedrive-indicator.py`](../../scripts/daemons/onedrive-indicator.py).
   - Permissões Flatpak ajustadas para anexar arquivos no ZapZap sem erro de arquivo vazio.
4. **WinApps & Windows 11 KVM**:
   - AutoLogon configurado (login automático sem prompt de senha).
   - Conexão RDP salva e configurada no Remmina.

---

## 🎯 2. Pauta Prioritária para a Próxima Sessão (Amanhã)

### 🎧 1. Automação de Áudio Inteligente (QCY H3S Bluetooth vs Caixas de Som)
* **Objetivo:**
  - Quando o fone Bluetooth **QCY H3S** for ligado/conectado, o sistema de som deve alternar automaticamente e imediatamente para ele como dispositivo de saída padrão (*Default Audio Sink*).
  - Quando o **QCY H3S** for desligado/desconectado, o sistema de som deve retornar automaticamente para as caixas de som padrão (**Áudio interno Estéreo analógico** ou G733, conforme preferência).
* **Stack Técnica Atual Identificada via `wpctl` / PipeWire / WirePlumber**:
  - Servidor: **PipeWire 1.6.8** com gerenciador de sessão **WirePlumber 1.6.8**.
  - Dispositivo Fone Bluetooth: `QCY H3S` (`bluez5`, MAC configurado via `MAC_QCY_H3S` no `.env`, nó sink `bluez_output.<MAC>.1`).
  - Dispositivo Caixas de Som: `Áudio interno Estéreo analógico` (alsa sink node `alsa_output.pci-0000_00_1f.3.analog-stereo`).
  - Outros sinks presentes: `G733 Gaming Headset`, `HDA NVidia HDMI`.
* **Abordagem Planejada**:
  - Implementar regra de prioridade ou política de comutação no WirePlumber (`~/.config/wireplumber/wireplumber.conf.d/` ou script udev/bluetoothd / `pipewire-pulse`) que conceda prioridade máxima automática a sinks Bluetooth conectados dinamicamente (`bluez_output.*`), garantindo fallback suave e determinístico para o áudio interno analógico ao desconectar.

---

### 🐳 2. Atualização do Contêiner Docker do WinApps (`dockurr/windows`)
* **Objetivo:**
  - O Dozzle acusou que existe uma versão mais recente da imagem Docker `dockurr/windows`.
  - Atualizar a imagem com segurança sem perder dados da VM Windows instalada (preservando o volume persistente do storage/KVM onde residem o Windows 11, o Office e o OneDrive configurados).
* **Ações Técnicas**:
  - Verificar a montagem de volumes do container `winapps-windows`.
  - Fazer pull da imagem atualizada: `docker pull dockurr/windows:latest`.
  - Recriar o container mantendo exatamente os mesmos mapeamentos de portas (`3389`, `8006`), volumes persistentes, variáveis de ambiente e flags KVM (`/dev/kvm`).
  - Validar se o AutoLogon e a inicialização continuam 100% íntegros.
