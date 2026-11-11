# 📘 Guia Prático: WinApps (Microsoft 365) & Integração do OneDrive MPMS (Files On-Demand) no Pop!_OS

Este documento descreve como funciona a arquitetura do **WinApps** via Docker (`dockurr/windows`), como provisionar o Windows 11 sem necessidade de baixar ISO manualmente, e como integrar o **OneDrive Corporativo do MPMS** ao Nautilus com o recurso **Arquivos sob Demanda (Files On-Demand)**.

---

## 🏗️ 1. Como Funciona a Arquitetura

```
+-------------------------------------------------------------------------+
|                         Pop!_OS 24.04 (COSMIC Desktop)                  |
|                                                                         |
|  [COSMIC Launcher] ---> Clica no "Microsoft Word" / "Excel"            |
|         |                                                               |
|         v                                                               |
|   FreeRDP (RDP Seamless)                                                |
|         ^                                                               |
|         | Porta 3389 / RDP                                              |
|         v                                                               |
|  +-------------------------------------------------------------------+  |
|  | Container Docker (dockurr/windows) - Windows 11 (KVM acelerado)   |  |
|  | - Microsoft Office 365 instalado                                  |  |
|  | - OneDrive Corporativo (MPMS) com "Files On-Demand"               |  |
|  | - Compartilhamento Samba local (\shared e drive mapeado)          |  |
|  +-------------------------------------------------------------------+  |
|                                                                         |
|  [Nautilus] <========== Samba / CIFS ===========> Pasta OneDrive MPMS    |
|   (Acessa arquivos sob demanda do MPMS)                                 |
+-------------------------------------------------------------------------+
```

1. O **dockurr/windows** roda uma VM Windows 11 com aceleração de hardware nativa (`/dev/kvm`).
2. Ele baixa automaticamente a ISO oficial da Microsoft em segundo plano, instala sem perguntas, aplica bypass de TPM e prepara o RDP.
3. O **WinApps** conecta via FreeRDP diretamente ao Windows e renderiza as janelas do Word/Excel como se fossem programas nativos do Linux.
4. O **OneDrive Corporativo** roda com todas as políticas do Azure AD / Intune satisfeitas (pois identifica um Windows legítimo).

---

## 🚀 2. Passo a Passo Inicial: Subir o Windows

O módulo [`scripts/26_winapps_office.sh`](scripts/26_winapps_office.sh) instala todas as dependências e cria o utilitário `winapps-vm`.

### 2.1. Iniciar o container Windows
No terminal, execute:
```bash
winapps-vm start
```

### 2.2. Acompanhar a instalação automática
Abra o navegador no Pop!_OS e acesse a interface web VNC do container:
```text
http://127.0.0.1:8006
```
> [!NOTE]
> Na primeira execução, o container fará o download da imagem oficial da Microsoft e concluirá a instalação de forma autônoma. Isso leva cerca de 10 a 15 minutos dependendo da sua conexão.

Quando o Windows inicializar no desktop padrão, o usuário e senha serão os definidos no seu `.env` (ou o padrão `winapps` / `winapps`).

---

## 📦 3. Instalar o Microsoft Office 365 e o OneDrive

1. Pelo próprio navegador na interface web (`http://127.0.0.1:8006`) ou conectando via RDP:
   - Abra o Microsoft Edge no Windows.
   - Acesse [portal.office.com](https://portal.office.com) e faça login com sua conta institucional `@mpms.mp.br`.
   - Clique em **"Instalar aplicativos"** -> **"Aplicativos do Microsoft 365"** e execute o instalador.
2. **Login no OneDrive do MPMS:**
   - Abra o aplicativo do OneDrive no Windows.
   - Conecte sua conta do MPMS.
   - Nas configurações do OneDrive -> aba **Sincronização e backup** -> **Configurações avançadas**:
     - Garanta que a opção **"Arquivos sob Demanda" (Files On-Demand)** esteja **ATIVADA**.
     - *(Isso garante que arquivos só ocupem espaço quando você abri-los).*

---

## ⚡ 4. Exportar os Atalhos para o Menu do COSMIC (WinApps)

Dentro da VM Windows, o WinApps precisa habilitar o suporte a RemoteApps e preparar o RDP:

### Método Direto (Recomendado via Pasta Compartilhada):
Como mapeamos automaticamente a pasta `~/Compartilhado_VM` para a Área de Trabalho do Windows (atalho `Shared` no Desktop ou drive `D:` / `C:\shared`):
1. No Windows, abra o PowerShell ou Prompt de Comando (CMD) como Administrador e execute:
   ```cmd
   \\host.lan\Data\install.bat
   ```
   *(ou simplesmente abra o atalho **Shared** que está na Área de Trabalho do Windows e clique duas vezes com o botão direito em **`install.bat`** -> **"Executar como Administrador"**)*.

### Método Alternativo via One-liner Oficial:
Se preferir rodar direto no PowerShell como Administrador:
```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/winapps-org/winapps/main/oem/install.bat")))
```
ou simplesmente:
```powershell
cd C:\shared; .\install.bat
```
2. No Pop!_OS, execute o detector de aplicativos:
   ```bash
   winapps-vm setup-apps
   ```
   *(Ou execute `cd ~/.local/share/winapps && ./setup.sh --user`)*.
3. O WinApps escaneará o Windows, encontrará o Word, Excel, PowerPoint e OneDrive, e criará os atalhos `.desktop` automaticamente em `~/.local/share/applications/`.
4. Esses ícones aparecerão imediatamente na categoria **"Escritório & Trabalho Remoto"** do seu COSMIC App Library!

---

## 🔑 4.1. Login Automático Transparente (Sem Senha ou Tela de Bloqueio)

Para que os aplicativos do WinApps (Word, Excel, etc.) e as sessões RDP abram instantaneamente sem pedir senha nem exibir a tela de bloqueio do Windows:

1. O script de provisionamento gera automaticamente o script `\\host.lan\Data\setup_autologon.bat`.
2. Para aplicar ou revalidar a qualquer momento a partir do Pop!_OS:
   ```bash
   winapps-vm fix-autologon
   ```
3. O comando configura no Registro do Windows:
   - `AutoAdminLogon = 1` com as credenciais do seu `.env`
   - `NoLockScreen = 1` (desativa tela de bloqueio com relógio)
   - `fPromptForPassword = 0` (impede solicitações repetitivas de senha no RDP)
   - `powercfg -x -monitor-timeout-ac 0` (impede suspensão ou desligamento de tela)

---

## 📂 5. Integrar a Pasta do OneDrive do MPMS ao Nautilus (Linux)

Os arquivos do OneDrive corporativo podem ser acessados diretamente no Linux sem precisar abrir a área de trabalho ou a janela do Windows:

### 5.1. Acesso com Um Clique pelo Menu ou Terminal
- **Pelo Menu de Aplicativos do COSMIC:** Clique no lançador **"Microsoft OneDrive (MPMS)"**. Ele abre diretamente a pasta corporativa no Nautilus via GVFS SMB (`smb://172.20.0.2/onedrive-mpms`).
- **Pelo Terminal ou Atalho do Nautilus:** Acesse a pasta amigável:
  ```bash
  cd ~/OneDrive_MPMS
  # ou via helper:
  winapps-vm onedrive
  ```
  O serviço de usuário `winapps-smb-sync.service` mantém o link simbólico `~/OneDrive_MPMS` apontando dinamicamente para o ponto de montagem GVFS sempre que a VM estiver ativa.

### 5.2. Como o Compartilhamento SMB Funciona
1. O container `dockurr/windows` expõe o Windows na rede interna Docker (`172.20.0.2`).
2. O daemon `winapps-smb-sync.sh` desbloqueia as portas SMB (139/445) no firewall do container e efetua o `gio mount` no usuário.
3. Se precisar remontar manualmente:
   ```bash
   winapps-vm fix-smb
   ```

> [!TIP]
> Ao clicar duas vezes em um arquivo `.docx` pelo Nautilus através do compartilhamento, o sistema abrirá o Microsoft Word oficial do WinApps diretamente na sua tela!

> [!IMPORTANT]
> **Atenção ao Recurso "Arquivos sob Demanda" (Files On-Demand) via SMB:**
> Se um arquivo estiver apenas como ponteiro na nuvem no Windows (ícone de nuvenzinha azul, atributos `OrsA` / *Cloud Placeholder*), o protocolo SMB não consegue disparar o download sob demanda em tempo real para o Linux, retornando `Erro de entrada/saída` ou `Argumento inválido` (código NT `0xc000cf01 - STATUS_CLOUD_FILE_PROVIDER_NOT_RUNNING`).
> 
> **Como resolver para os arquivos/pastas que você usa no dia a dia:**
> 1. Acesse o Windows (pelo navegador em `http://127.0.0.1:8006` ou via `winapps windows`).
> 2. No Explorador de Arquivos do Windows, vá na pasta do seu OneDrive (`OneDrive - Ministério Público...`).
> 3. Clique com o botão direito nas pastas ou arquivos desejados (ex: `Documents`, `Aulas`, etc.).
> 4. Clique em **"Sempre manter neste dispositivo"** (*Always keep on this device*).
> 5. Assim que o ícone mudar para o círculo verde com visto (arquivo baixado localmente no Windows), o Linux conseguirá ler, abrir com o Visualizador de Documentos ou qualquer app nativo instantaneamente sem qualquer erro.

---

## ☁️ 5. Acesso Direto ao OneDrive no Linux & Indicador de Bandeja

Para evitar ter que abrir a VM ou janelas do Windows apenas para acessar arquivos ou verificar sincronização, a estação conta com três camadas de integração nativa:

1. **Lançador Desktop com Ícone Oficial da Nuvem (`onedrive-x86.desktop`):**
   - No menu de aplicativos (Biblioteca de Aplicativos do COSMIC) e fixado na Dock de favoritos (`~/.config/cosmic/com.system76.CosmicAppList/v1/favorites`).
   - Exibe o ícone em vetor SVG oficial da Microsoft Fluent Cloud (`Icon=onedrive`).
   - Clicar nele abre instantaneamente a pasta `~/OneDrive_MPMS` no Nautilus.
2. **Indicador Nativo no Painel Superior (Bandeja / StatusArea):**
   - O daemon [`scripts/daemons/onedrive-indicator.py`](scripts/daemons/onedrive-indicator.py) opera via protocolo nativo Wayland **StatusNotifierItem** (`AyatanaAppIndicator3`), residindo no canto superior direito do painel COSMIC (`com.system76.CosmicAppletStatusArea`).
   - Gerenciado pelo serviço systemd de usuário `onedrive-indicator.service` (`systemctl --user`).
   - Apresenta status em tempo real (`● OneDrive MPMS: Conectado` / `○ Desconectado`).
   - Menu com ações rápidas com 1 clique:
     - 📂 **Abrir Pasta Local (`~/OneDrive_MPMS`)** no Nautilus
     - 🔄 **Remontar / Sincronizar Compartilhamento SMB**
     - 🌐 **Abrir OneDrive na Web (M365 Corporativo):** utiliza a URL oficial SSO multi-tenant `https://www.office.com/launch/onedrive?auth=2`, evitando falhas de locatário Azure AD do SharePoint.
     - 🖥️ **Abrir Windows 11 no Remmina:** conecta diretamente pelo perfil salvo `winapps_windows11.remmina` (Console VNC ou RDP), com a mesma praticidade do perfil corporativo MPE-80703.
     - 🖥️ **Abrir Console Web da VM (`:8006`):** acesso rápido via navegador ao painel do container.
     - ⚙️ **Reiniciar Container Windows**
3. **Perfis Nativos Salvos no Remmina (`~/.local/share/remmina`):**
   - Salvos automaticamente sob o grupo **`WinApps`**:
     - `Windows 11 (WinApps VM)`: conexão direta de console VNC (`172.20.0.2:5900`), imune a desconexões por limite de sessão RDP ou colisões de logon.
     - `Windows 11 (WinApps VM - RDP)`: conexão de área de trabalho remota RDP (`127.0.0.1:3389`) com senha e compartilhamento de área de transferência.
4. **Marcador Fixo no Nautilus (GTK Bookmarks):**
   - Marcador `OneDrive-MPMS` na barra lateral esquerda do gerenciador de arquivos.

---

## 🛠️ 6. Comandos Úteis do Helper (`winapps-vm`)

| Comando | Descrição |
| :--- | :--- |
| `winapps-vm start` | Inicia o container Windows em segundo plano com suporte a KVM. |
| `winapps-vm stop` | Desliga o container Windows com segurança. |
| `winapps-vm status` | Mostra se a VM está rodando, portas e consumo. |
| `winapps-vm web` | Abre a interface de visualização da VM no navegador (`http://127.0.0.1:8006`). |
| `winapps-vm logs` | Exibe os logs do container Windows em tempo real. |
| `winapps-vm setup-apps` | Roda a detecção do WinApps e atualiza os atalhos no COSMIC. |
| `winapps-vm fix-smb` | Reajusta imediatamente as regras do iptables no container e remonta no Nautilus. |
| `winapps-vm fix-autologon` | Aplica o AutoLogon sem senha e desativa a tela de bloqueio da VM via RemoteApp. |
| `winapps-vm onedrive` | Abre diretamente a pasta corporativa do OneDrive (MPMS) no Nautilus. |

> [!NOTE]
> **Inicialização Automática com o Sistema:**
> O container `winapps-windows` está configurado com `restart: unless-stopped` e sobe automaticamente na inicialização do Docker / boot do sistema. O serviço de usuário `winapps-smb-sync.service` (`systemctl --user`) é acionado no login para desobstruir as regras do firewall QEMU (portas SMB 139/445) e garantir que a montagem no Nautilus esteja pronta para uso.

---

## ⚠️ 7. Issues Mapeadas & Próximos Passos (Acompanhamento)

### 📌 Issue: Comportamento Anômalo / Congelamento da Janela ao Clicar nos WinApps
* **Sintoma:** Ao disparar o Word ou Excel pelo atalho `(WinApp)` no COSMIC Launcher, surge a tela inicial (Splash Screen) ou uma moldura que congela/trava na área de trabalho, interferindo na sessão.
* **Causas Prováveis Investigadas:**
  1. **Compositor Wayland vs FreeRDP 3 (RAIL / RemoteApp):**
     - O FreeRDP 3 com flags `/app` (RemoteApp) sob Wayland nativo às vezes tenta criar superfícies `xf_UnmapWindowForSurface` e repassar eventos de foco antes do handshake completo da janela principal do Office.
  2. **Interação com Pop Shell / COSMIC Window Management:**
     - Falta de regra de exceção para janelas flutuantes (`Floating window exception`) no COSMIC para classes de janela do FreeRDP (`StartupWMClass=Microsoft Word`, `Microsoft Excel`, etc.), fazendo o compositor tentar ladrilhar (tile) uma janela remota sem suporte a redimensionamento dinâmico.
  3. **Flags de RDP a Testar na Próxima Sessão:**
     - Testar uso do backend Wayland nativo do FreeRDP (`wlfreerdp3`) vs cliente XWayland (`xfreerdp3` com `/gdi:hw` ou `/gfx:avc420`).
     - Avaliar adição de `/network:auto` e desativação temporária de redirecionamento de áudio/clipboard (`/clipboard` ou `/sound`) para isolar se é contenção de canal virtual.
* **Status:** Mapeado para depuração e refinamento na próxima sessão.
