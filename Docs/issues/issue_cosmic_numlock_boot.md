# 🐛 Relatório de Diagnóstico & Solução: NumLock no Boot e na Tela de Login (COSMIC Desktop / Wayland)

---

## 📌 Informações do Ambiente

* **Sistema Operacional:** Pop!_OS 24.04 LTS x86_64
* **Ambiente Gráfico:** COSMIC Desktop Environment
* **Servidor de Exibição / Compositor:** Wayland (`cosmic-comp`)
* **Gerenciador de Login:** `cosmic-greeter` / `greetd` (usuário de sistema `cosmic-greeter`, UID 987)
* **Layout de Teclado:** US-Intl com Cedilha (`'+c = ç`) e teclado numérico físico dedicado

---

## 🔍 Causa Raiz Identificada

1. **Separação de Instâncias do Compositor entre Greeter e Usuário:**
   * O `cosmic-greeter` roda sob seu próprio usuário de sistema isolado (`cosmic-greeter`), cujo diretório HOME é `/var/lib/cosmic-greeter`.
   * Quando o computador inicia, o `cosmic-greeter` lança uma instância do `cosmic-comp` na tela de login. Essa instância busca suas preferências em:
     `/var/lib/cosmic-greeter/.config/cosmic/com.system76.CosmicComp/v1/numlock_state`
   * Como esse arquivo não existia por padrão, o greeter inicializava os teclados com o NumLock **desligado**.
   * Ao fazer o login, o estado inativo do hardware herdado da tela de boas-vindas não era restaurado de imediato pelo desktop do usuário.

2. **Soluções Legadas Ineficazes no Wayland:**
   * `numlockx on` atua apenas no X11/XWayland e não controla LEDs ou modificadores do compositor Wayland nativo.
   * `setleds` atua somente nos terminais virtuais TTY de texto (`/dev/tty[1-6]`).

---

## 🛠️ Solução Implementada

Para garantir que o NumLock inicie ativado **desde a tela de login** e permaneça ativo no desktop:

1. **Provisionamento no Diretório do `cosmic-greeter`:**
   * Criação do diretório de configuração do greeter:
     `/var/lib/cosmic-greeter/.config/cosmic/com.system76.CosmicComp/v1/`
   * Gravação de `numlock_state` contendo `true` e espelhamento do layout `xkb_config`.
   * Ajuste de permissões de propriedade para o usuário de sistema `cosmic-greeter:cosmic-greeter`.

2. **Provisionamento no Perfil do Usuário:**
   * Gravação de `true` em `~/.config/cosmic/com.system76.CosmicComp/v1/numlock_state`.

3. **Camadas de Suporte e Hardware:**
   * Serviço do Systemd `/etc/systemd/system/numlock.service` para TTYs e regras Udev `/etc/udev/rules.d/99-numlock.rules` para acendimento de LEDs em hotplug.

---

## 📎 Arquivos de Configuração Relacionados no Setup

* [`scripts/02_teclado_cedilha_numlock.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/02_teclado_cedilha_numlock.sh)
* [`scripts/21_autostart_config.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/21_autostart_config.sh)
* [`README.md`](file:///home/rezendepauloh/Documentos/Scripts/README.md)
