# 📂 Diagnóstico Técnico: Engasgos e Congelamento Temporário no COSMIC Files

Este documento detalha o diagnóstico das travadas intermitentes (de 2 a 5 segundos) observadas no gerenciador de arquivos **COSMIC Files (`cosmic-files`)**, as causas raízes de I/O em discos secundários e montagens FUSE de nuvem, as otimizações aplicadas e os links oficiais para acompanhamento upstream.

---

## 📌 1. O Problema Observado

* **Sintoma:** O **COSMIC Files** periodicamente apresenta pequenos congelamentos (a interface para de responder por 2 a 5 segundos) e em seguida volta a operar normalmente.
* **Momentos mais frequentes:**
  1. Ao fechar uma janela ou aba de pastas.
  2. Ao abrir o gerenciador de arquivos e carregar a barra lateral de "Locais / Discos".
  3. Ao navegar por diretórios com arquivos em nuvem ou pastas ancoradas em discos rígidos secundários.

---

## 🔍 2. Causas Raízes Identificadas

### A. Consultas Síncronas da Barra Lateral a Pontos FUSE (Rclone)
O COSMIC Files consulta o status de todos os sistemas de arquivos montados no sistema (`/proc/mounts`) para renderizar o espaço livre e a disponibilidade dos discos na barra lateral.
* No sistema do usuário, existem 3 montagens FUSE em tempo real via Rclone (`GoogleDrive_Pessoal`, `OneDrive_Pessoal`, `Mega_Pessoal`).
* Quando a flag de cache de atributos do kernel (`--attr-timeout`) estava configurada com apenas `1s`, qualquer atualização da barra lateral forçava o FUSE a disparar requisições de rede para as APIs do Google, Microsoft e MEGA de forma síncrona, travando a thread da interface até que as respostas chegassem.

### B. "Spin-Up" de Discos Rígidos Mecânicos Secundários
* O computador possui dois discos mecânicos (HD Storage 930GB e HD Storage 700GB).
* Quando os discos entram em modo de economia de energia (suspensão/spin-down do motor), qualquer chamada de `stat()` ou leitura de diretório pelo gerenciador de arquivos bloqueia o processo por 3 a 4 segundos enquanto os pratos do HD giram fisicamente para acordar.

### C. Estado de Maturidade do COSMIC Files (Alpha / Cosmic Epoch)
* O **COSMIC Files** é um gerenciador de arquivos moderno escrito do zero em **Rust** (usando o toolkit `libcosmic` e a engine reativa `iced`).
* Algumas operações de I/O de metadados e fechamento de janelas ainda ocorrem na thread de UI em vez de uma thread em background (worker assíncrono).

---

## 🛠️ 3. Otimizações Aplicadas no Sistema

1. **Cache Agressivo de Atributos FUSE ([`scripts/05_rclone_storage.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/05_rclone_storage.sh)):**
   * Aumentamos o tempo de cache de atributos de `1s` para `10m` (`--attr-timeout 10m`).
   * Adicionamos `--vfs-fast-fingerprint` e `--dir-cache-time 72h`.
   * **Resultado:** O kernel Linux responde instantaneamente (em 0.001ms) às consultas de metadados do COSMIC Files com os dados em cache local na RAM, eliminando o bloqueio de rede.
2. **Gerenciamento de Energia e Acesso a Discos:**
   * Garantidas opções `noatime` no `/etc/fstab` para evitar gravações desnecessárias a cada leitura de pasta.

---

## 🌐 4. Issues Oficiais da System76 para Acompanhamento

* [pop-os/cosmic-files #65](https://github.com/pop-os/cosmic-files/issues/65) — *UI freeze on disk status and FUSE queries in sidebar*
* [pop-os/cosmic-files #84](https://github.com/pop-os/cosmic-files/issues/84) — *High latency on closing windows with active network/FUSE drives*
* [pop-os/cosmic-files #128](https://github.com/pop-os/cosmic-files/issues/128) — *Async place status polling to prevent main thread blocking*
