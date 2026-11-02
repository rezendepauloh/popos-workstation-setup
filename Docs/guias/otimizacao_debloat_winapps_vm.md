# 🪟 Guia de Otimização e Debloat da VM Windows 11 (WinApps)

Este documento descreve como reduzir o consumo de memória RAM, CPU e I/O de disco da máquina virtual Windows 11 utilizada pelo **WinApps** (`dockurr/windows` via Docker/KVM), removendo telemetrias invasivas, serviços desnecessários e bloatwares UWP da Microsoft sem prejudicar a experiência integrada do **Microsoft 365 (Office)**, **OneDrive** e **RemoteApp/RDP**.

---

## 🎯 1. O Problema: Sobrecarga do Windows 11
Por padrão, uma instalação limpa do Windows 11 executa em segundo plano:
- **Telemetria e Diagnósticos Contínuos** (`DiagTrack`, `dmwappushservice`, `WerSvc`, `CEIP`).
- **SuperFetch / SysMain**: Cache agressivo de memória na RAM que gera leituras/gravações contínuas desnecessárias no disco virtual em SSD do host Linux.
- **Windows Search Indexer (`WSearch`)**: Indexação constante que consome ciclos de CPU na VM.
- **Bloatwares UWP e Xbox Services**: Dezenas de pacotes e daemons em segundo plano (Xbox Gaming Overlay, Bing News, Clima, Clipchamp, TikTok, etc.).
- **Pesquisas da Web (Bing) e Sugestões**: Conexões constantes à nuvem no Menu Iniciar.

Em uma VM dedicada exclusivamente ao WinApps, esses recursos são dispensáveis e apenas degradam a performance do host.

---

## 🛡️ 2. Princípios de Segurança do Script (O que é Preservado)
O script de otimização foi projetado cirurgicamente para **NÃO QUEBRAR** o ecossistema do WinApps:
- ✅ **Microsoft 365 (Word, Excel, PowerPoint, Outlook)**: Totalmente funcional.
- ✅ **OneDrive Corporativo & Pessoal**: Sincronização, montagem e integração intocadas.
- ✅ **Microsoft Edge WebView2 Runtime**: Preservado (obrigatório para autenticação moderna e login em contas Microsoft).
- ✅ **Serviços RDP e RemoteApp**: Registry e conectividade RDP preservados para exibição seamless no Pop!_OS.

---

## 📁 3. Localização dos Scripts no Repositório
Os utilitários estão armazenados em:
```text
util/winapps/
├── otimizar_winapps_vm.cmd   # Launcher em lote com elevação automática de Administrador
└── otimizar_winapps_vm.ps1   # Script PowerShell de debloat e otimização
```

Durante o provisionamento ou uso diário, esses arquivos podem ser copiados para a pasta compartilhada da VM (`~/Compartilhado_VM/`).

---

## 🚀 4. Como Executar na Máquina Virtual Windows

### Passo 1: Garantir que os arquivos estejam na pasta compartilhada
Se os scripts ainda não estiverem em `~/Compartilhado_VM/`, execute no terminal do Pop!_OS:
```bash
cp util/winapps/otimizar_winapps_vm.* ~/Compartilhado_VM/
```

### Passo 2: Acessar a VM Windows
Abra a interface gráfica web da VM:
```bash
winapps-vm web
# Ou acesse no navegador: http://127.0.0.1:8006
```
*(Você também pode acessar via FreeRDP/Remmina se preferir).*

### Passo 3: Executar a Otimização
1. No Windows, abra o **Explorador de Arquivos**.
2. Navegue até o drive da pasta compartilhada (`shared` ou o atalho na rede).
3. Dê **duplo clique** no arquivo:
   ```text
   otimizar_winapps_vm.cmd
   ```
4. Se o Controle de Conta de Usuário (UAC) solicitar permissão, clique em **Sim** (*Yes*).
5. O script abrirá o terminal, aplicará todas as regras em 4 etapas rápidas e exibirá o resumo em verde.
6. Pressione qualquer tecla para fechar a janela ao término.

### Passo 4: Reiniciar a VM
Para que todas as desativações de serviços e tarefas agendadas tenham efeito completo, reinicie a VM:
- Pelo Menu Iniciar do Windows: **Reiniciar**, ou
- No terminal do Pop!_OS:
  ```bash
  winapps-vm restart
  ```

---

## 📊 5. Resultados Esperados
- **Uso de RAM em Idle**: Redução de ~1.5 GB a 2 GB para valores abaixo de 1.8 GB - 2.2 GB.
- **Uso de CPU em Repouso**: Estabilização entre 0% e 2%, eliminando picos causados pelo `DiagTrack` e `WSearch`.
- **I/O de Disco no Host Linux**: Redução drástica de leituras e escritas no arquivo `data.img` do container dockurr/windows.
- **Responsividade do WinApps**: Janelas do Word, Excel e OneDrive abrindo mais rapidamente no Pop!_OS (Wayland).

