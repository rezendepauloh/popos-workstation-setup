# 🖥️ Issue: Porta RDP (3389) Inacessível no Windows 11 Remoto (Edição Home) — ✅ Resolvido

## 📌 Contexto & Sintomas

## 📌 Contexto & Sintomas

- **Cenário:** Acesso remoto do Pop!_OS para o notebook/PC Windows 11 da rede local via `util/remote-devices/win_remote.sh` e aba **Dispositivos (Rede)** do `workstation-hub`.
- **Comportamento Observado:**
  - Ping ICMP e **OpenSSH (porta 22)** funcionam normalmente após definir o perfil de rede como `Private`, configurar `administrators_authorized_keys` com SIDs universais (`*S-1-5-32-544` / `*S-1-5-18`) e liberar a regra no Firewall.
  - Mesmo após habilitar `fDenyTSConnections = 0`, iniciar `TermService` e criar a regra de Firewall para a porta `3389`, a porta **RDP (3389)** permanece fechada/inacessível.

---

## 🔍 Causa Raiz

- Edições **Windows 11 Home** não incluem o servidor nativo de Área de Trabalho Remota (RDP host) ativo para conexões de entrada — o recurso é restrito às edições **Pro / Enterprise**.

---

## ✅ Solução Aplicada (Resolvido)

1. **Manutenção & Limpeza (100% operacional via SSH):**
   - Todas as rotinas de status, disco, limpeza de `%TEMP%`/Lixeira, `winget upgrade` e Wake-on-LAN funcionam normalmente via OpenSSH (porta `22`).
2. **Controle Gráfico de Tela via Sunshine + Moonlight (em uso):**
   - Instalado o **Sunshine** no Windows 11 (`winget install LizardByte.Sunshine`) e o cliente **Moonlight** (`com.moonlight_stream.Moonlight`) no Pop!_OS (integrado ao módulo [`scripts/18_jogos_performance.sh`](../../scripts/18_jogos_performance.sh), ao [`util/remote-devices/win_remote.sh`](../../util/remote-devices/win_remote.sh) com `--moonlight` e ao botão **Abrir Tela (Moonlight)** no `workstation-hub`).
