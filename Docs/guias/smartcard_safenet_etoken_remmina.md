# Guia Técnico: Certificado Digital A3 (SafeNet eToken) & Redirecionamento Smartcard no Remmina RDP

Este guia documenta a arquitetura e a configuração idempotente do token USB **SafeNet eToken 5110 SC / Token JC** (`0529:0620`) no **Pop!_OS 24.04 LTS (COSMIC)**, cobrindo tanto o uso local (navegadores e assinadores PKCS#11) quanto o redirecionamento via **Remmina RDP** para a estação Windows do MPMS.

---

## 1. Arquitetura em Camadas

1. **Camada PC/SC + CCID (Host Linux):**
   - Pacotes: `pcscd`, `pcsc-tools`, `libccid`.
   - O driver `libccid` comunica diretamente com o dispositivo USB CCID (`0529:0620` — *Aladdin Knowledge Systems Token JC / eToken 5110 SC*).
   - Os units systemd `pcscd.socket` e `pcscd.service` mantêm o barramento `/run/pcscd/pcscd.comm` ativo sob demanda.
2. **Camada PKCS#11 Local (Navegadores & Assinadores):**
   - Pacotes: `opensc`, `opensc-pkcs11`, `libnss3-tools`, `p11-kit`, `p11-kit-modules`.
   - O módulo `p11-kit-proxy.so` é registrado no cofre NSS do usuário (`~/.pki/nssdb` via `modutil`), permitindo que **Google Chrome** e **Brave** enxerguem automaticamente qualquer provedor PKCS#11 listado no `p11-kit`.
   - Caso algum sistema/assinador local exija o middleware proprietário **SafeNet Authentication Client (SAC)**, basta colocar o pacote `.deb` oficial em `config/safenet/` antes de rodar o módulo 23 (ou instalá-lo normalmente): o script detecta `/usr/lib/libeTPkcs11.so` (ou `libeToken.so`) e registra `/etc/pkcs11/modules/safenet-etoken.module`.
3. **Camada RDP (Remmina + FreeRDP 3):**
   - O perfil RDP corporativo (`group=MPMS`) no Remmina é provisionado com `sharesmartcard=1` e `smartcardname=` (compartilha todos os leitores PC/SC disponíveis).
   - O FreeRDP 3 encaminha os comandos APDU do Windows remoto diretamente para o `pcscd` local; o Windows remoto utiliza seu próprio driver/minidriver SafeNet sem conflito com o host Linux.

---

## 2. Provisionamento Idempotente

O suporte completo é aplicado pelo módulo [23_trabalho_remoto_vpn_rdp.sh](../../scripts/23_trabalho_remoto_vpn_rdp.sh):

```bash
sudo ./scripts/23_trabalho_remoto_vpn_rdp.sh --force
```

---

## 3. Uso Local vs. Redirecionamento Remmina RDP

* **No Remmina RDP (estação Windows remota):** funciona imediatamente apenas com `pcscd` + `libccid`, pois o Windows remoto utiliza o próprio driver SafeNet através do canal PC/SC redirecionado (`sharesmartcard=1`), não exigindo SafeNet Authentication Client no Linux.
* **No Linux local (Chrome, Brave, assinadores):** alguns tokens **eToken 5110 SC** (como `ATR: 3B D5 18 00 81 31 FE 7D 80 73 C8 21 10 F4`) exibem `(token not recognized)` no `opensc-pkcs11`. Nesse caso, utilize o pacote **SafeNet Authentication Client (SAC) 10.9 GA**:
  1. Baixe o pacote oficial pela [base de conhecimento da DigiCert](https://knowledge.digicert.com/general-information/how-to-download-safenet-authentication-client) (link direto: `https://www.digicert.com/StaticFiles/Linux_SAC_10.9_GA.zip`).
  2. Extraia o `.zip` e copie o `.deb` headless (`SAC_10.9 GA/Installation/withoutUI/Ubuntu-2204/safenetauthenticationclient-core_10.9.4723_amd64.deb`) para `config/safenet/` no repositório.
  3. Execute `sudo ./scripts/23_trabalho_remoto_vpn_rdp.sh --force` para instalar o pacote e registrar automaticamente `libeTPkcs11.so` no `p11-kit` (`/etc/pkcs11/modules/safenet-etoken.module`) e no cofre NSS (`~/.pki/nssdb`).

---

## 4. Comandos de Verificação & Testes em Navegador

1. **Detecção física USB:**
   ```bash
   lsusb | grep -i 0529:0620
   ```
2. **Status do serviço PC/SC e leitura do token:**
   ```bash
   systemctl status pcscd.socket pcscd.service
   pcsc_scan -n
   ```
3. **Listagem de módulos e objetos PKCS#11:**
   ```bash
   p11-kit list-modules
   opensc-tool -n
   pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so -L
   ```
4. **Verificação do cofre NSS (Chrome / Brave):**
   ```bash
   modutil -list -dbdir sql:$HOME/.pki/nssdb
   certutil -L -d sql:$HOME/.pki/nssdb -h all
   ```
5. **Teste em navegador / sites ICP-Brasil (após SAC instalado para uso local):**
   * **Chrome / Brave:** acesse `chrome://settings/certificates` (aba *Seus certificados*) para confirmar se o certificado A3 aparece.
   * **Portal gov.br:** `https://sso.acesso.gov.br` (opção *Seu certificado digital*).
   * **e-CAC (Receita Federal):** `https://cav.receita.fazenda.gov.br` (login via certificado digital).
