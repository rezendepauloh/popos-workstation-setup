# 🖥️ Guia de Arquitetura & Operação — Workstation & Homelab Hub (COSMIC GUI)

> Documentação técnica da interface gráfica nativa em **Rust + `libcosmic`** ([`workstation-hub/`](../../workstation-hub)), inspirada na organização modular do projeto `AmbientesHub` e projetada para operar de forma **totalmente desacoplada** dos scripts CLI.

---

## 🎯 1. Princípio de Independência (CLI ↔ GUI)

- **Zero interferência no terminal:** Todos os scripts em [`setup_popos.sh`](../../setup_popos.sh), [`scripts/`](../../scripts), [`util/`](../../util) e `umbrelos-scripts/` continuam funcionando exatamente da mesma forma quando executados manualmente no terminal.
- A GUI atua exclusivamente como **orquestradora visual** sobre os scripts já existentes, sem alterar o comportamento padrão do terminal.
- O único ajuste compartilhado em [`scripts/00_comum.sh`](../../scripts/00_comum.sh) é o suporte adicional a `PKEXEC_UID` como fallback apenas quando `SUDO_USER` estiver vazio (preservando `sudo` e execução normal idênticos).

---

## 🧭 2. Mapa das 7 Abas da Interface

| Aba | Escopo | Funcionalidades Principais |
| :--- | :--- | :--- |
| **🏠 Visão Geral** | Telemetria e atalhos | Progresso (`X/28` módulos), status SSH do Homelab, ADB Android, Docker/WinApps, versão Antigravity e ações rápidas. |
| **🚀 Pós-Formatação** | `scripts/01..28` | Busca, filtros (*Todos/Pendentes/Concluídos*), presets por categoria, `--force`, limpeza de checkpoints e execução em lote com **elevação única `pkexec`**. |
| **🧰 Utilitários** | `util/` + IDEs | Backup/Restore Android (ADB), atualização Docker local (`--dry-run` e deploy), atualização Antigravity IDE, `--repair-ides` e atalho WinApps. |
| **🖥️ Homelab (umbrelOS)** | `umbrelos-scripts` | Status SSH em tempo real (LAN ou Tailscale), seletor Web (DNS `*.pk.local` ou IP), 22 WebUIs, atalho SSH no `cosmic-term`, utilitários remotos, rollback e módulos `setup/01..07`. |
| **🌐 Dispositivos (Rede)** | `util/remote-devices/` | Controle remoto de Windows 11 (SSH/RDP/WoL/limpeza), Android (ADB Wi-Fi/trim-caches/scrcpy), Smart TV & Projetor Samsung (Tizen/WoL), scanner de rede e Alexa via Home Assistant. |
| **🔐 VPN** | MPMS & Tailscale | Conexão VPN corporativa MPMS com input de Token 2FA (`cosmic-term`) e controle rápido do Tailscale (`pkexec`). |
| **🧪 Testes** | `tests/` + `cargo test` | Dispara `popos-workstation-setup/tests/run_all.py`, `tests/test_in_docker.sh`, `cargo test` (Rust) e `umbrelos-scripts/tests/run_all.py` (Tudo, `--unit`, `--integration`). |
| **📜 Console & Logs** | PTY + `Logs/` + rotativo | Saída em tempo real ANSI, entrada interativa `stdin`, indicador visual de execução, altura ajustável, rotatividade `3 MB × 3`, paginação e prévia colorida. |
| **⚙️ Configurações** | `.env` & `config.env` | Configuração dos caminhos dos repositórios (`0600`) e editor seguro de `.env` / `config.env` com mascaramento de segredos e merge automático de novas chaves do `.example`. |

---

## 🛡️ 3. Segurança & Hardening

1. **Zero dados sensíveis hardcoded:** Todos os endereços de Homelab, usuários, tokens e senhas são lidos dinamicamente de `config.env` / `.env` em tempo de execução.
2. **Validação Fail-Closed ([`input_validator.rs`](../../workstation-hub/src/services/input_validator.rs)):**
   - Módulos validados contra padrão `^[0-9]{2}_[A-Za-z0-9_]+\.sh$`.
   - Caminhos de scripts canonicalizados (`canonicalize()`) garantindo que estejam estritamente dentro da raiz do repositório correspondente.
   - Invocação de processos via arrays de argumentos (`CommandBuilder` / `Command::args`), bloqueando injeção de shell.
3. **Proteção de Arquivos `.env` / `config.env` ([`env_service.rs`](../../workstation-hub/src/services/env_service.rs)):**
   - Recusa leitura ou gravação se o alvo for um link simbólico (`!is_symlink()`).
   - Rejeita quebras de linha/bytes nulos em valores.
   - Grava atomicamente via arquivo temporário com `chmod 0600` antes do `rename`.
4. **Execução Administrativa em Lote (`pkexec`):**
   - Ao rodar vários módulos marcados, gera um script temporário `0700` dentro de `$XDG_RUNTIME_DIR` contendo apenas caminhos canônicos validados e o remove imediatamente ao término da execução.

---

## 🔨 4. Compilação e Instalação

Consulte o guia dedicado passo a passo em:
👉 [`Docs/guias/compilar_e_instalar_workstation_hub.md`](compilar_e_instalar_workstation_hub.md)
