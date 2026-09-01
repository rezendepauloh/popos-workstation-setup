# 🐛 Relatório de Diagnóstico & Issue: Inconsistência do NumLock no Boot/Login (COSMIC Desktop / Wayland)

---

## 📌 Informações do Ambiente

* **Sistema Operacional:** Pop!_OS 24.04 LTS x86_64
* **Ambiente Gráfico:** COSMIC Desktop Environment (Alpha/Beta)
* **Servidor de Exibição / Compositor:** Wayland (`cosmic-comp`)
* **Gerenciador de Login:** `cosmic-greeter` / `gdm3`
* **Layout de Teclado:** US-Intl com Cedilha (`'+c = ç`) e teclado numérico físico dedicado

---

## 🔍 Descrição do Problema

O teclado numérico físico (**NumLock**) inicia **desligado** após a inicialização do sistema, tela de login e carregamento da sessão de usuário no COSMIC Desktop, exigindo que o usuário pressione manualmente a tecla `Num Lock` a cada reinicialização ou retorno de suspensão.

### Comportamento Esperado:
O NumLock deve estar automaticamente ativado e com o LED correspondente aceso logo na tela de login e permanecer ativo durante toda a sessão gráfica.

### Comportamento Observado:
Mesmo com serviços do systemd e configurações declarativas aplicadas, o compositor Wayland (`cosmic-comp`) inicializa os teclados com o modificador NumLock inativo.

---

## 🛠️ Diagnóstico Técnico e Métodos Testados

### 1. Incompatibilidade de Ferramentas Legadas (X11 vs Wayland)
* **`numlockx on`:** Não funciona no Wayland, pois depende diretamente do protocolo X11 (`XTEST` / `XKB`) e o servidor XWayland não repassa o estado dos LEDs para o compositor nativo.

### 2. `setleds` nos Consoles Virtuais (TTY)
* Foi criado o serviço systemd `/etc/systemd/system/numlock.service` executando:
  ```bash
  for tty in /dev/tty[1-6]; do
      setleds -D +num < "$tty" 2>/dev/null || true
  done
  ```
* **Resultado:** O NumLock é ligado corretamente nos terminais TTY texto, mas assim que o servidor Wayland (`cosmic-comp` / `cosmic-greeter`) assume o controle dos dispositivos de entrada via `libinput`, o estado do LED é resetado.

### 3. Configuração Declarativa no Compositor COSMIC (`cosmic-comp`)
* Foi gravado o estado booleano nativo do COSMIC em:
  ```bash
  mkdir -p ~/.config/cosmic/com.system76.CosmicComp/v1
  echo "true" > ~/.config/cosmic/com.system76.CosmicComp/v1/numlock_state
  ```
* **Resultado:** Embora a chave seja reconhecida pelo schema do `cosmic-comp`, o compositor nem sempre força a ativação do modificador no hardware durante a enumeração inicial de dispositivos USB no boot ou após acordar de suspensão (*hotplug event*).

### 4. Regras do Udev e Autostart
* Adicionado lançador no autostart do usuário (`~/.config/autostart/numlock.desktop`), porém ferramentas CLI diretas para forçar modificadores de teclado no Wayland sem um cliente de protocolo privilegiado sofrem restrições de segurança do Wayland.

---

## 💡 Sugestões de Melhoria para o Upstream (System76 / COSMIC)

1. **Opção Nativa no `cosmic-settings`:**
   Adicionar uma chave gráfica em *Configurações > Dispositivos de Entrada > Teclado* para **"Ligar NumLock automaticamente na inicialização"**.
2. **Garantia de Estado no `cosmic-comp`:**
   Fazer com que o `cosmic-comp` leia `numlock_state` e execute o *re-assert* do estado do NumLock em todos os eventos `libinput_event_keyboard` e `device_added`.
3. **Persistência no `cosmic-greeter`:**
   Herdar o estado do NumLock definido pelo sistema desde a tela de boas-vindas/login.

---

## 📋 Passos para Reproduzir

1. Conectar um teclado USB ou teclado de laptop com NumPad dedicado.
2. Reiniciar o computador no Pop!_OS 24.04 (COSMIC).
3. Observar que o LED do NumLock está apagado na tela de login e após entrar no desktop.

---

## 📎 Arquivos de Configuração Relacionados no Setup

* [`scripts/02_teclado_cedilha_numlock.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/02_teclado_cedilha_numlock.sh)
* [`scripts/15_cosmic_menu_dock.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/15_cosmic_menu_dock.sh)
* [`scripts/21_autostart_config.sh`](file:///home/rezendepauloh/Documentos/Scripts/scripts/21_autostart_config.sh)
