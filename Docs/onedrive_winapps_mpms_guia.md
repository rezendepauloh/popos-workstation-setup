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

O módulo [`scripts/26_winapps_office.sh`](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/scripts/26_winapps_office.sh) instala todas as dependências e cria o utilitário `winapps-vm`.

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

## 📂 5. Integrar a Pasta do OneDrive do MPMS ao Nautilus (Linux)

Para você ver e gerenciar os arquivos do OneDrive corporativo diretamente pelo gerenciador de arquivos **Nautilus**:

### Opção A: Pela Pasta Compartilhada Automática (`~/Compartilhado_VM`)
O Docker Compose mapeia automaticamente:
- Host Linux: `~/Compartilhado_VM`
- Windows VM: `C:\shared` (ou drive de rede mapeado)

Você pode salvar qualquer arquivo nessa pasta e ele estará acessível em ambos os sistemas instantaneamente.

### Opção B: Compartilhar a Pasta do OneDrive do Windows via Rede Local
1. No Windows (dentro da VM):
   - Clique com o botão direito na pasta do seu OneDrive (`C:\Users\winapps\OneDrive - Ministério Público do Estado de Mato Grosso do Sul`).
   - Vá em **Propriedades** -> aba **Compartilhamento** -> **Compartilhamento Avançado**.
   - Marque **"Compartilhar esta pasta"** e defina o nome do compartilhamento como `OneDrive-MPMS`.
   - Em **Permissões**, garanta controle total para o usuário `winapps`.
2. No Pop!_OS (Nautilus):
   - Abra o Nautilus (Arquivos).
   - Na barra lateral, clique em **"Outros Locais"**.
   - No campo "Conectar ao Servidor", digite:
     ```text
     smb://127.0.0.1/OneDrive-MPMS
     ```
   - Informe o usuário `winapps` e a senha definida.
   - Marque a opção "Lembrar para sempre".
   - Arraste a pasta conectada para os **Favoritos/Marcadores** do Nautilus (já pré-configurado como `~/OneDrive_MPMS`).

> [!TIP]
> Ao clicar duas vezes em um arquivo `.docx` pelo Nautilus através do compartilhamento, o sistema abrirá o Microsoft Word oficial do WinApps diretamente na sua tela!

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
