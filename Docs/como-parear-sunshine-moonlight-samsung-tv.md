# 🎮 Guia Completo: Pareamento Sunshine (Workstation) com Moonlight na Smart TV Samsung (Tizen OS)

Este guia orienta a configuração do **Sunshine Game Streamer** na sua Workstation Pop!_OS e a instalação do cliente **Moonlight** na sua **Smart TV Samsung** (sistema Tizen OS 5.5+), permitindo jogar no conforto da sala com latência ultra-baixa via rede local.

---

## ⚠️ A Smart TV Samsung suporta instalação direta via Pen Drive?

> [!IMPORTANT]
> **Diferente de sistemas Android TV (que instalam arquivos `.apk` direto do pen drive), as Smart TVs Samsung com Tizen OS não executam instaladores soltos de pendrive por padrão.**
> 
> As TVs Samsung exigem que o aplicativo esteja empacotado no formato Tizen Widget (`.wgt`), assinado digitalmente com certificado de desenvolvedor e enviado via rede através do **Smart Development Bridge (SDB)** com o **Developer Mode (Modo Desenvolvedor)** ativado na TV.

Para facilitar sua vida, existem **duas formas recomendadas e muito práticas** para instalar o [Moonlight Tizen](https://github.com/brightcraft/moonlight-tizen) na sua TV:
1. **Método 1 (Mais Simples e Rápido):** Utilizar a ferramenta desktop [Apps2Samsung](https://github.com/Apps2Samsung/Apps2Samsung/releases/latest) (disponível para Linux, Windows e Android).
2. **Método 2 (Sem instalar programas extras no PC, via Docker):** Utilizar o contêiner oficial do Moonlight Tizen com Docker e SDB direto no seu terminal.

---

## 🛠️ Passo 1: Preparar a Smart TV Samsung (Ativar o Modo Desenvolvedor)

Antes de qualquer método de instalação, você precisa ativar o modo de desenvolvedor na TV:

1. Ligue a TV e certifique-se de que ela está conectada à **mesma rede local (Wi-Fi ou Cabo)** que sua Workstation Pop!_OS.
2. No menu da TV, abra a aba **Apps (Aplicativos)**.
3. No controle remoto, digite a sequência numérica: `1 2 3 4 5`.
   *(Se o seu controle remoto não tem números físicos, aperte o botão `123` para abrir o teclado virtual na tela e digite `1 2 3 4 5`).*
4. Uma janela pop-up chamada **Developer Mode** será exibida.
5. Mude o interruptor para **ON**.
6. No campo **Host PC IP**, digite o endereço IP local da sua Workstation Pop!_OS (para descobrir seu IP no Pop!_OS, execute `ip a` no terminal, ex: `192.168.1.50`).
7. Clique em **OK**.
8. **Reinicie a TV obrigatoriamente:** Mantenha pressionado o botão **Power** do controle remoto por cerca de 5 segundos até a TV desligar e aparecer a logo *"Smart TV Powered by Tizen"*.
9. Ao abrir a loja de Apps novamente, você verá o aviso discreto `DEVELOP MODE` no topo.

### Descobrir o IP da Smart TV:
* Na TV, vá em **Configurações > Geral > Rede > Status da Rede > Configurações de IP**.
* Anote o **Endereço IP da TV** (ex: `192.168.1.120`).

---

## 📦 Passo 2: Instalar o Moonlight na TV

### Opção A: Via Apps2Samsung (Método Principal & Recomendado)
> [!TIP]
> O utilitário **Apps2Samsung** agora é instalado automaticamente no seu Pop!_OS através do módulo `06_softwares_workflow.sh`. Você também pode abrir digitando `apps2samsung` no terminal ou buscando no menu do sistema.

1. Abra o **Apps2Samsung** no Pop!_OS (ou use o app no celular Android/Windows).
2. O aplicativo detectará a Samsung TV conectada na sua rede local automaticamente.
3. No campo de pacotes, selecione **Moonlight-Tizen** (ou selecione o arquivo `Moonlight.wgt` baixado).
4. Clique em **Download & Install**.
5. Em menos de 1 minuto, o aplicativo do **Moonlight** estará instalado e pronto na sua TV!

### Opção B: Via Docker no Pop!_OS (Linha de Comando Direta)
Se você já tem o Docker configurado no seu sistema:

1. Baixe a imagem pré-compilada do Moonlight Tizen:
   ```bash
   docker pull ghcr.io/brightcraft/moonlight-tizen:master
   ```
2. Inicie o container interativo:
   ```bash
   docker run -it --rm ghcr.io/brightcraft/moonlight-tizen:master
   ```
3. Dentro do container, conecte-se à TV pelo IP dela:
   ```bash
   sdb connect SEU_IP_DA_TV
   ```
   *(Exemplo: `sdb connect 192.168.1.120`)*
4. Confirme a conexão listando os dispositivos:
   ```bash
   sdb devices
   ```
   *(Copie o ID da TV que aparece na última coluna, ex: `UE55AU7172UXXH`)*
5. Instale o pacote na TV:
   ```bash
   tizen install -n Moonlight.wgt -t SEU_DEVICE_ID
   ```
6. O Moonlight aparecerá automaticamente na lista de aplicativos da TV!

---

## 🔗 Passo 3: Configurar e Parear com o Sunshine na Workstation

### 1. Acessar o Painel do Sunshine
O Sunshine já roda como serviço de usuário em segundo plano no Pop!_OS.

1. No navegador da Workstation, abra:
   [https://localhost:47990](https://localhost:47990)
   *(Aceite o aviso de certificado auto-assinado no navegador).*
2. No primeiro acesso, crie um **Usuário e Senha de Administrador** para o Sunshine e faça o login.

### 2. Parear com o Moonlight na TV
1. Na sua Smart TV Samsung, abra o aplicativo **Moonlight**.
2. O Moonlight fará uma varredura na rede e mostrará o ícone da sua Workstation Pop!_OS. Se não aparecer automaticamente, selecione **Add Host manually** e digite o IP da Workstation.
3. Clique no ícone do computador. A TV exibirá um **código PIN de 4 dígitos** na tela (exemplo: `4821`).
4. Volte à Workstation no navegador em [https://localhost:47990](https://localhost:47990):
   - Vá na aba superior **PIN**.
   - Digite o PIN de 4 dígitos exibido na TV.
   - Clique em **Send**.
5. Na TV, o ícone da Workstation mudará para **Conectado** (com cadeado aberto/verde).

---

## 🎮 Passo 4: Jogar e Recomendações de Performance

1. No Moonlight da TV, clique na sua máquina pareada. Você verá opções como **Desktop**, **Steam** ou os jogos cadastrados.
2. **Controles Recomendados:**
   - Pareie seu controle Bluetooth (DualSense, Xbox ou genérico) diretamente no Bluetooth da TV Samsung ou conecte via cabo USB na porta traseira da TV.
   - Alternativamente, se a TV estiver próxima ao quarto/escritório, você pode manter o controle conectado direto no PC.
3. **Ajustes de Qualidade no Moonlight (Configurações do The Freestyle / Smart TV):**
   - **Resolução de Vídeo:** Configure para **1080p (1920x1080)** a **60 FPS** (o projetor Samsung The Freestyle SP-LSP3BLAXZA possui resolução óptica nativa Full HD 1080p).
   - **Bitrate:** Comece entre **20 Mbps e 30 Mbps** para conexões via Wi-Fi 5GHz (evite 2.4GHz para não sofrer engasgos). Se conectado via cabo de rede na TV, utilize de 40 Mbps a 60 Mbps.
   - **Codec de Vídeo:** Deixe em **Automático** ou force **H.264** / **HEVC**.

4. **Monitores Ultrawide (21:9 / 32:9) vs. TV / Projetor (16:9):**
   - Nosso monitor principal é um Ultrawide (3440x1440p / 21:9 ou 32:9). Se transmitir a tela crua para uma TV ou Projetor 16:9, a imagem ficará com barras pretas em cima e embaixo (efeito letterbox).
   - O Sunshine foi configurado para alternar dinamicamente a resolução do monitor para **1920x1080 (16:9)** durante a transmissão de jogos/Steam Big Picture e restaurar automaticamente para **3440x1440** assim que você desconectar!
   - Se quiser usar a área de trabalho sem distorção na TV, selecione a opção **Desktop 1080p (16:9 TV/Projetor)** no menu do Moonlight.

5. **Firewall Liberado (UFW):** O módulo `22_limpeza_otimizacao.sh` já deixa abertas as portas do Sunshine e a comunicação local:
   - `47984:47990/tcp` (Web UI e Handshake HTTPS)
   - `48010/tcp` (RTSP Handshake - essencial para evitar o *error 73*)
   - `47998:48010/udp` (Streaming de Vídeo, Áudio e Controle)
   - Rede Local: Permissão liberada para a faixa `192.168.0.0/24`.

---

## 🛑 Como Encerrar o Streaming no Moonlight (Tizen OS)

> [!IMPORTANT]
> Se você simplesmente pressionar o botão **Home / Casinha** no controle remoto da TV/Projetor, o Tizen apenas minimiza o Moonlight em segundo plano. Com isso, **o Sunshine continua transmitindo** e a resolução do seu computador **não volta** para 3440x1440!

Para encerrar o stream de forma limpa (notificando o Sunshine para executar o `undo` e restaurar o Ultrawide):

1. **Pelo Gamepad / Controle de Jogo (DualSense / Xbox / Genérico):**
   - Segure simultaneamente: **`Select/Back` + `Start/Play` + `L1/LB` + `R1/RB`**.
   - Esse atalho fecha imediatamente a sessão de transmissão e retorna ao menu de jogos do Moonlight.
2. **Pelo Controle Remoto Samsung (The Freestyle / Smart TV):**
   - **Controles com botões coloridos:** Pressione a **tecla Vermelha (A)** para encerrar o stream.
   - **Controle compacto do The Freestyle (Smart Remote branco):**
     - Pressione o botão **123 / Cor** (que abre o teclado numérico virtual / cores na tela).
     - Selecione o botão **Vermelho (Red)** para terminar o stream.
     - Ou pressione duas vezes o botão **Voltar / Return** para abrir o diálogo de confirmação de saída.
3. **Pelo Teclado USB/Bluetooth (se conectado):**
   - Pressione **`Ctrl` + `Alt` + `Shift` + `Q`**.
4. **Pelo Menu do Steam Big Picture:**
   - No menu do Steam Big Picture, vá no ícone de **Energia (Power)** e selecione **Sair do Big Picture** ou **Desconectar**.

---

## 🛠️ Resolução de Problemas Conhecidos

### Erro "handshake RTSP failed (error 73)"
- **Causa:** O cliente Moonlight no Tizen não conseguiu resposta na porta TCP `48010` (tempo limite de conexão / timeout do socket WASM).
- **Solução:** Certifique-se de que a porta `48010/tcp` e a sub-rede local estão liberadas no firewall da Workstation com `sudo ufw allow 48010/tcp && sudo ufw allow from 192.168.0.0/24`.

### Meu computador ficou preso em 1080p após fechar o projetor
- Isso ocorre se o app do Moonlight foi fechado pelo botão Home do projetor sem encerrar a sessão.
- Para voltar manualmente ao Ultrawide no terminal do PC:
  ```bash
  cosmic-randr mode DP-1 3440 1440 --refresh 59.999
  ```

---

Divirta-se jogando seus títulos da Steam, Heroic e emuladores direto na tela grande da sua Smart TV ou Projetor The Freestyle Samsung!
