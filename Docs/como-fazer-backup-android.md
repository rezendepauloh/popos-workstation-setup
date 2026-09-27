### 📱 Guia de Backup e Restauração de Dispositivos Android via ADB

Este guia detalha o fluxo prático e seguro para realizar o backup completo, formatação (restauração aos padrões de fábrica) e restauração de dados para aparelhos Android (Xiaomi/MIUI, Samsung, Motorola, etc.) utilizando os utilitários [backup_android.sh](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/util/backup_android.sh) e [restore_android.sh](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/util/restore_android.sh).

---

#### Etapa 1: Garantia do WhatsApp (Feito no próprio celular)
1. No celular, abra o **WhatsApp**.
2. Toque nos 3 pontinhos > **Configurações > Conversas > Backup de conversas**.
3. Verifique se há uma conta Google associada. Marque se deseja incluir vídeos e toque em **Fazer backup** (aguarde completar 100% no Google Drive).

---

#### Etapa 2: Ativar a Depuração USB no Celular
1. No celular, vá em **Configurações > Sobre o telefone**.
2. Procure por **Número da Versão** (ou *Versão do SO / Versão da MIUI*) e toque rapidamente **7 vezes seguidas** até surgir a mensagem *"Você agora é um desenvolvedor!"*.
3. Volte em **Configurações > Opções do desenvolvedor** (ou *Configurações adicionais > Opções do desenvolvedor*).
4. Ative a chave **Depuração USB**.
   *(Em celulares Xiaomi/MIUI, se for instalar APKs via restore, também é recomendado ativar "Instalar via USB" caso solicite).*

---

#### Etapa 3: Conectar no Pop!_OS e Rodar o Utilitário de Backup
1. Conecte o celular ao PC com um **cabo USB de boa qualidade**.
2. Na tela do celular aparecerá um pop-up: **"Permitir a depuração USB?"**.
   * Marque a caixinha: ☑️ **"Sempre permitir a partir deste computador"**.
   * Toque em **Permitir**.
3. No terminal do Pop!_OS, execute:
   ```bash
   ./util/backup_android.sh
   ```
4. **Comportamento e Recursos do Script de Backup:**
   * **Identificação Automática:** Detecta modelo, fabricante, versão do Android e número de série, gerando o relatório `info_dispositivo.txt`.
   * **Monitoramento e Progresso em Tempo Real:** Possui animação contínua (spinner), cronômetro de tempo decorrido (`[⏱️ Tempo: MM:SS]`) e medidor de tamanho gravado no disco (`[💾 No destino: X.X GB]`), garantindo visibilidade mesmo em diretórios gigantes (como o WhatsApp com dezenas de milhares de arquivos).
   * **Grandezas de Dados Formatadas:** Todas as saídas de transferência são convertidas automaticamente para a grandeza mais próxima e legível (`GB`, `MB`, `KB` ou `bytes`), em vez de exibir números brutos e difíceis de ler (ex: `2.1 GB` em vez de `2248083276 bytes`).
   * **Geração Automática de Logs:** Toda a saída do terminal é salva de forma detalhada e com timestamp no diretório de [Logs](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Logs) (ex: `Logs/backup_android_DD-MM-YYYY_HH-MM-SS.log`).
   * **Mídias e Arquivos:** Cópia de `DCIM` (Câmera/Screenshots), `Pictures`, `Download`, `Documents`, `Movies`, `Music`, `Audiobooks`, `Podcasts`.
   * **Áudios do Sistema e Gravador:** `Recordings`, `VoiceRecorder`, `Sounds`, `Notifications`, `Ringtones`, `Alarms`.
   * **Mensageiros:** `WhatsApp` (legado e moderno `Android/media/com.whatsapp`), `WhatsApp Business` e `Telegram`.
   * **Backups do Sistema:** `MIUI/backup` e `com.xiaomi.bluetooth`.
   * **Aplicativos:** Gera a lista de pacotes instalados (`lista_aplicativos_instalados.txt`) e pergunta se deseja extrair os instaladores reais (`.apk`) de todos os apps de usuário para a pasta `APKs/` (com barra de contagem e progresso).
   * **Destino do Backup:** Salva automaticamente em `/mnt/storage_930/Backups_Android/android-backup-DD-MM-YYYY_HH-MM-SS/` (com fallback inteligente para `/mnt/storage_700`, `/mnt/nvme_01` ou `~/Backups_Android`).

---

#### Etapa 4: Cuidado Crucial Antes de Resetar o Celular (Evitar Bloqueio Antifurto FRP)
> [!CAUTION]
> **NUNCA** formate o celular antes de remover as contas vinculadas, para não cair na trava de hardware FRP (*Factory Reset Protection*):
1. Acesse **Configurações > Contas e Sincronização** (ou *Gerenciar contas*).
2. Toque na **Conta Google** conectada e clique em **Remover conta**.
3. Se for aparelho **Xiaomi**: Acesse **Conta Mi** e encerre a sessão (certifique-se de saber o login/senha caso esteja ativada).
4. Verifique se as senhas de apps essenciais (bancos, e-mails, redes sociais) estão sincronizadas no **Gerenciador de Senhas do Google** ou cofre (ex: Bitwarden).

---

#### Etapa 5: Como Formatar (Padrões de Fábrica)
1. No celular, vá em **Configurações > Sobre o Telefone > Redefinir Dados** (ou *Configurações Adicionais > Redefinir para Configurações Originais*).
2. Toque em **Apagar todos os dados**.
3. Aguarde o aparelho reiniciar completamente e carregar a tela de configuração inicial de fábrica.

---

#### Etapa 6: Restauração Pós-Formatação (Com 1 Comando)
Após iniciar o celular formatado, passar pela configuração inicial do Android e conectar à Conta Google:
1. Reative a **Depuração USB** (7 toques na Versão da Build/MIUI).
2. Conecte ao PC com o cabo USB e execute no Pop!_OS:
   ```bash
   ./util/restore_android.sh
   ```
3. **Recursos do Processo de Restauração:**
   * **Menu Interativo de Backups:** Lista os backups salvos em disco com data, hora e tamanho total formatado em grandezas amigáveis (`GB` / `MB`). Basta pressionar ENTER para selecionar o mais recente.
   * **Monitoramento com Progresso em Tempo Real:** Exibe indicador visual contínuo, cronômetro e tamanho do lote de arquivos que está sendo transmitido para a memória interna.
   * **Pré-criação da Estrutura de Diretórios:** O script pré-cria recursivamente as pastas de destino no Android antes do envio, evitando falhas de permissão ou erros de criação de arquivos pelo subsistema FUSE/MTP do Android (como `remote couldn't create file: No such file or directory` em subpastas ocultas ou de thumbnails).
   * **Registro em Logs:** Salva o relatório e saída completa da restauração em [Logs](file:///home/rezendepauloh/Documentos/DevProjects/Bash/popos-workstation-setup/Logs) (ex: `Logs/restore_android_DD-MM-YYYY_HH-MM-SS.log`).
   * **Restauração de Arquivos e Mensageiros:** Envia de volta todas as pastas para `/sdcard/` e restaura as mídias do WhatsApp, WhatsApp Business e Telegram no caminho padrão do Android 11+ (`Android/media/...`).
   * **Reinstalação Automática de Aplicativos:** Se o backup continha APKs, pergunta se deseja reinstalar todos os apps de uma só vez em lote via ADB.
   * **Reindexador de Mídia (`MediaScanner`):** Executa o scanner interno do Android para que todas as fotos, vídeos, músicas e toques apareçam imediatamente na Galeria e reprodutores sem que seja necessário reiniciar o aparelho!
4. Abra o WhatsApp no celular, autentique com o número e selecione **"Restaurar do Google Drive"**. Todas as conversas e mídias estarão lá prontas para uso.