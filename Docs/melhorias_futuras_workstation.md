# 🚀 Roadmap de Melhorias & Otimizações Futuras (Pop!_OS Workstation)

Este documento reúne uma análise abrangente de melhorias técnicas recomendadas para a workstation, divididas por categorias (Performance, Áudio/Multimídia, Backup, Dev & Contêineres, Segurança e Armazenamento). 

São sugestões de alto valor prático para serem avaliadas e implementadas futuramente sob demanda.

---

## ⚡ 1. Performance de Kernel, Memória & I/O

### 🔹 A. ZRAM com Compressão Zstandard (`systemd-zram-generator`)
* **O que é:** Cria um dispositivo de swap compactado dinamicamente na própria memória RAM usando o algoritmo ultrarrápido **zstd**.
* **Benefício:** Reduz drasticamente a escrita de swap no SSD NVMe, aumenta a vida útil dos discos e evita travamentos quando múltiplos ambientes pesados estão abertos simultaneamente (Antigravity IDE + VS Code + Docker + modelos de IA/NLP do spaCy).
* **Como implementar:**
  ```bash
  sudo apt install -y systemd-zram-generator
  # Configurar em /etc/systemd/zram-generator.conf
  ```

### 🔹 B. Elevação dos Limites de Inotify e File Descriptors (`sysctl.d`)
* **O que é:** Limites do kernel para monitoramento de arquivos em tempo real.
* **Benefício:** Evita erros como *"ENOSPC: System limit for number of file watchers reached"* comuns no VS Code, Antigravity, Espanso, Vite/Node.js e Rust Analyzer em projetos com muitos arquivos.
* **Valores sugeridos (`/etc/sysctl.d/99-dev-limits.conf`):**
  ```ini
  fs.inotify.max_user_watches = 524288
  fs.inotify.max_user_instances = 1024
  fs.file-max = 2097152
  vm.dirty_ratio = 10
  vm.dirty_background_ratio = 5
  ```

---

## 🎧 2. Áudio de Baixa Latência & Bluetooth de Alta Fidelidade (PipeWire)

### 🔹 A. Ajuste de Quantum do PipeWire
* **O que é:** Otimização do buffer de áudio do servidor PipeWire.
* **Benefício:** Reduz a latência de áudio para menos de 10ms em jogos, chamadas e reprodução de mídia, eliminando micro-estalos (*pops/crackles*).
* **Configuração:** Ajustar `default.clock.quantum = 512` em `~/.config/pipewire/pipewire.conf.d/latency.conf`.

### 🔹 B. Codecs Bluetooth Audiófilos (LDAC / AAC / aptX HD)
* **O que é:** Habilitação completa de codecs de alta definição no módulo `libspa-0.2-bluetooth`.
* **Benefício:** Qualidade máxima de som ao conectar fones e caixas de som Bluetooth modernos.

---

## 🛡️ 3. Segurança, Firewall & Rede Local

### 🔹 A. Ativação do UFW (Firewall do Sistema)
* **O que é:** Ativação do firewall nativo do Linux com regras controladas.
* **Benefício:** Protege a máquina contra varreduras de portas em redes Wi-Fi públicas/externas sem bloquear conexões essenciais de desenvolvimento local:
  * Permitir: Rede local privada, Jellyfin (`8096`), KDE Connect (`1714:1764`), portas de desenvolvimento (`3000`, `5173`, `8000`, `8080`).
  * Bloquear: Todas as demais entradas externas não solicitadas.

---

## 🐳 4. Dev, Docker & Manutenção de Contêineres

### 🔹 B. Ativação sob Demanda do Daemon do Docker (`docker.socket`)
* **O que é:** Configurar o systemd para iniciar o daemon pesado do Docker apenas quando o primeiro comando `docker` ou `docker compose` for executado no terminal.
* **Benefício:** Economiza até 500MB de RAM e ciclos de CPU durante a inicialização do sistema, acelerando ainda mais o login.

### 🔹 C. Rotina de Limpeza de Imagens Órfãs
* **O que é:** Integrar ao script `22_limpeza_otimizacao.sh` um comando `docker system prune -f --volumes` (com confirmação ou verificação) para evitar acúmulo de gigabytes de camadas e imagens antigas no SSD.

---

## 💾 5. Automação de Backup das Configurações (Dotfiles & Automações)

### 🔹 A. Script de Backup Agendado para Nuvem / HD Storage
* **O que é:** Um script simples executado semanalmente via Systemd Timer para compactar e enviar um snapshot criptografado das pastas vitais:
  * `~/.config/espanso/` (Automações STI e scripts)
  * `~/.config/copyq/` (Histórico de transferências)
  * `~/.config/kando/` (Menus radiais)
  * `~/Documentos/Scripts/` (Suíte de pós-instalação)
  * Chaves SSH e GPG (`~/.ssh`)
* **Destino:** Enviar automaticamente para `~/GoogleDrive_Pessoal/Backups_Workstation/` ou `/mnt/storage_930/Backups/`.

---

## 📊 6. Tabela Resumo de Implementação

Todas as melhorias abaixo foram integradas de forma nativa e declarativa no módulo [`scripts/22_limpeza_otimizacao.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/22_limpeza_otimizacao.sh):

| Melhoria Implementada | Status | Local da Configuração |
| :--- | :---: | :--- |
| **ZRAM (Compressão de Memória)** | ✅ Ativo | Pacote nativo do Pop!_OS (`zstd`, 16GB em RAM) |
| **Limites de Inotify / File Watchers** | ✅ Integrado | `/etc/sysctl.d/99-dev-limits.conf` (`524288` watches, dirty ratios) |
| **Docker Socket sob Demanda** | ✅ Integrado | `systemctl enable docker.socket` (daemon dorme até ser chamado) |
| **Backup Automático de Dotfiles** | ✅ Integrado | `/usr/local/bin/backup-workstation` + `backup-workstation.timer` semanal |
| **UFW (Firewall com Regras Dev)** | ✅ Integrado | UFW com portas locais liberadas (Jellyfin, KDE Connect, Dev 3000/5173/8080) |
| **Otimização de Buffers PipeWire** | ✅ Integrado | `~/.config/pipewire/pipewire.conf.d/99-low-latency.conf` (quantum 512) |
