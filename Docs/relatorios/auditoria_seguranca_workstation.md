# 🛡️ Dossiê de Auditoria de Segurança e Hardening (DevSecOps)

> **Escopo:** Auditoria completa de segurança estática (SAST), superfícies de rede, gestão de segredos, escalação de privilégio e higienização de dados sensíveis do repositório `popos-workstation-setup`.  
> **Status:** 100% Remediado e Automatizado via Suíte de Testes (`tests/unit/test_security_audit.py`).

---

## 📊 1. Resumo Executivo

Foi conduzida uma revisão exaustiva linha a linha em todos os **29 módulos Bash (`scripts/00` a `28`)**, **7 daemons Python (`scripts/daemons/`)**, **utilitários de manutenção (`util/`)**, **containerização (`Dockerfile`)** e **documentação (`Docs/`)**.

As vulnerabilidades identificadas foram classificadas segundo severidade (**Crítica**, **Alta**, **Média** e **Baixa**) e integralmente corrigidas sem quebrar a idempotência nem os fluxos nativos Wayland/COSMIC.

---

## 🚨 2. Vulnerabilidades Críticas & Altas Remediadas

### 2.1. Credenciais, Hashes e Identificadores Pessoais Hardcoded (Crítica)
* **Diagnóstico:**
  - Senha real em texto claro (`M!n***`) estava chumbada como fallback em `scripts/26_winapps_office.sh`, `util/winapps/otimizar_winapps_vm.ps1` e `util/winapps/setup_autologon.bat`.
  - Ciphertext 3DES estático do Remmina (`1gm8***==`) estava exposto em `scripts/26_winapps_office.sh`.
  - Endereços MAC Bluetooth reais dos periféricos do usuário (`84:AC:***` e `E0:9F:***`), hostname corporativo (`MPE-***`) e caminhos absolutos de usuário estavam hardcoded em scripts e documentos.
  - Variável desnecessária de alto risco `SUDO_PASS***` constava no template `.env.example`.
* **Correção Aplicada:**
  - Todas as senhas e hashes hardcoded foram erradicados e substituídos por leitura exclusiva de variáveis de ambiente do `.env` (`WINAPPS_RDP_PASSWORD`), abortando operações sensíveis caso a credencial não esteja configurada.
  - Endereços MAC em `scripts/12_wacom_tablet.sh` e `scripts/daemons/bt-audio-switcher.py` agora leem `MAC_WACOM_INTUOS`, `MAC_QCY_H3S` e `BT_AUDIO_DEVICE_NAME` do ambiente, com descoberta dinâmica via BlueZ D-Bus / `bluetoothctl`.
  - Paths fixos em `scripts/09_onlyoffice_padrao.sh` foram parametrizados com `$REAL_HOME`.

---

### 2.2. Execução Remota de Código (RCE) via Injeção em Títulos de Janela e ADB (Crítica)
* **Diagnóstico:**
  - Em `scripts/06_softwares_workflow.sh` (`~/.local/bin/chamar_espanso_acao`), o título da janela em foco no Wayland (`$TARGET_TITLE`, controlável por qualquer página web aberta no navegador ou documento externo) era interpolado diretamente dentro de código Python inline (`target_title = '''$TARGET_TITLE'''`). Um título de página contendo `''' + __import__('os').system('...') + '''` executava comandos arbitrários na sessão do usuário.
  - Em `util/backup_android.sh` e `util/restore_android.sh`, saídas e nomes de pastas do ADB eram interpolados via `'''$raw'''` e `'''$text'''` em chamadas `python3 -c`, além de caminhos não escapados em `adb shell`.
  - Nos módulos `02`, `06`, `13`, `14`, `16` e `26`, variáveis Bash eram interpoladas dentro de strings de código Python ou usavam `os.path.expanduser('~')` sob `sudo` (resolvendo incorretamente para `/root`).
* **Correção Aplicada:**
  - Todas as chamadas `python3 -c` e heredocs Python passaram a usar código estático (aspas simples) recebendo parâmetros estritamente via `sys.argv[1:]`.
  - Caminhos remotos em `adb shell` agora utilizam escape seguro `printf "%q"` e validação estrita por expressão regular (`^[a-zA-Z0-9._]+$`) para nomes de pacotes APK.

---

### 2.3. Exposição de Console Web VNC Sem Senha (`:8006`) e RDP (`:3389`) na Rede (Crítica)
* **Diagnóstico:**
  - Em `scripts/26_winapps_office.sh`, o `docker-compose.yml` do container Windows 11 (`dockurr/windows`) publicava `"8006:8006"` e `"3389:3389"` em todas as interfaces (`0.0.0.0`).
  - Como o Docker manipula a chain `DOCKER` no `iptables`/`nftables` antes das regras de input do UFW, qualquer dispositivo na mesma rede (LAN/Wi-Fi) podia acessar `http://<ip-do-host>:8006` e controlar diretamente a sessão Windows 11 já autenticada (AutoLogon) e com o **OneDrive Corporativo (MPMS)** montado.
* **Correção Aplicada:**
  - Portas do container vinculadas estritamente à interface de loopback: `"127.0.0.1:8006:8006"`, `"127.0.0.1:3389:3389/tcp"` e `"127.0.0.1:3389:3389/udp"`.
  - Aplicado `chmod 600` em `docker-compose.yml` e `setup_autologon.bat`.

---

### 2.4. Escalação de Privilégio Local (`sudoers`), Bypass de Pinning TLS e Vazamento de OTP na VPN (Alta)
* **Diagnóstico:**
  - Em `scripts/23_trabalho_remoto_vpn_rdp.sh`, a regra `/etc/sudoers.d/openfortivpn-mpms` concedia `NOPASSWD: /usr/bin/openfortivpn` irrestrito. Qualquer processo rodando como `$REAL_USER` podia escalar para `root` imediatamente usando `-c /tmp/malicious.conf` ou `--pppd-plugin=/tmp/root.so` (vetor clássico *GTFObins*).
  - O script `vpn-mpms` executava `openssl s_client` a cada conexão e sobrescrevia `--trusted-cert "$LIVE_CERT"`, anulando a proteção contra ataques *Man-in-the-Middle* (MITM) mesmo quando `VPN_TRUSTED_CERT` estava definido no `.env`.
  - O token 2FA (`-o "$VPN_INPUT_OTP"`) e a senha RDP eram passados via linha de comando, ficando visíveis em `/proc/<pid>/cmdline` (`ps aux`).
* **Correção Aplicada:**
  - Criado o wrapper privilegiado `/usr/local/sbin/openfortivpn-mpms-helper` (`root:root`, `chmod 750`), que fixa o arquivo base `/etc/openfortivpn/mpms.conf`, bloqueia argumentos externos e recebe o OTP/senha via `stdin` para um arquivo efêmero `0600` em `/run/openfortivpn-mpms.XXXXXX.conf`.
  - O arquivo `/etc/sudoers.d/openfortivpn-mpms` agora autoriza exclusivamente `/usr/local/sbin/openfortivpn-mpms-helper`.
  - O *Certificate Pinning* (`VPN_TRUSTED_CERT`) do `.env` é estritamente respeitado; a descoberta automática ocorre apenas em modo TOFU (*Trust On First Use*) se o certificado estiver em branco.
  - A senha RDP é transmitida ao script de keyring via variável de ambiente restrita (`RDP_PASSWORD_ENV`) em vez de `sys.argv`.

---

### 2.5. Conta Samba Sem Senha (`smbpasswd -n`) e FUSE `--allow-other` (Alta)
* **Diagnóstico:**
  - `scripts/25_samba_storage.sh` executava `sudo smbpasswd -a -n "$REAL_USER"` quando rodado em modo não interativo sem `SAMBA_PASSWORD`, habilitando acesso sem senha ao share `[Storage700]`.
  - `scripts/05_rclone_storage.sh` habilitava `user_allow_other` em `/etc/fuse.conf` e montava Google Drive, OneDrive e MEGA pessoais com `--allow-other`, expondo arquivos de nuvem pessoal a outros UIDs/containers do sistema.
* **Correção Aplicada:**
  - Removida a flag `-n` do `smbpasswd`: sem senha definida, a conta Samba não é ativada sem autenticação.
  - Removido `--allow-other` das unidades FUSE do Rclone e fixado `--rc-addr 127.0.0.1:5572` no lançador da WebUI do Rclone.

---

### 2.6. Hardening de Firewall UFW, Udev (`0666`), Backups, HTTPS e `.env` (Média)
* **Diagnóstico & Correções:**
  1. **Firewall UFW (`scripts/28_limpeza_otimizacao.sh`):** Removida a regra ampla `ufw allow from 192.168.0.0/24` (que abria todas as portas para a LAN) e restringidas as portas do KDE Connect, LocalSend, Sunshine, Syncthing e servidores Dev (`3000:3010`, `5173`, `8000:8080`) exclusivamente à sub-rede `192.168.0.0/24` (em vez de `0.0.0.0/0`).
  2. **Backup Semanal (`scripts/28_limpeza_otimizacao.sh`):** Adicionado `umask 077`, substituído o fallback inseguro `/tmp/Backups_Workstation` por `$HOME/.local/share/Backups_Workstation` (`0700`) e excluídas chaves privadas SSH (`--exclude='.ssh/id_*'`, `*.pem`, `*.key`) do tarball não criptografado.
  3. **Regras Udev (`scripts/02` e `scripts/22`):** Removido `MODE="0666"` (escrita global em barramentos SMBus/I2C da placa-mãe e USB), substituído por `MODE="0660", GROUP="plugdev"/"i2c", TAG+="uaccess"`.
  4. **Downloads Seguros e Diretórios Temporários (`scripts/06`, `07`, `08`, `10`, `18`, `24`):** URLs `http://archive.ubuntu.com` migradas para `https://mirrors.kernel.org/ubuntu` com validação `dpkg-deb --info`, `-SkipPublisherCheck` removido do PowerShell, e arquivos temporários migrados para diretórios isolados `mktemp -d` (`chmod 700`) com limpeza via `trap EXIT`.
  5. **Proteção de `.env` e Contexto Docker (`scripts/00_comum.sh` & `.dockerignore`):** `00_comum.sh` agora valida que `.env` não é um link simbólico (`! -L`), verifica o UID proprietário e aplica `chmod 600` automaticamente antes do `source`. Criado `.dockerignore` bloqueando o envio de `.env`, `rclone.conf` e chaves SSL para o daemon do Docker.

---

## 🧪 3. Verificação Contínua (`test_security_audit.py`)

Para impedir regressões futuras, foi integrado o módulo [`tests/unit/test_security_audit.py`](../../tests/unit/test_security_audit.py) à suíte principal (`./setup_popos.sh --test`), auditando automaticamente em cada execução:
1. Ausência de senhas, hashes, MACs pessoais ou variáveis proibidas em todo o repositório;
2. Ausência de interpolação insegura `'''$VAR'''` ou `os.path.expanduser('~')` em blocos Python inline;
3. Ausência de regras udev `MODE="0666"`, contas Samba sem senha (`smbpasswd -n`) e FUSE `--allow-other`;
4. Bind estrito em `127.0.0.1` nas portas do container WinApps, wrapper restrito no `sudoers` da VPN e exclusão de chaves privadas no script de backup;
5. Validação anti-symlink do `.env`, existência do `.dockerignore` e ausência de downloads APT via HTTP puro.
