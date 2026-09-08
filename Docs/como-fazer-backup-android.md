### 📱 Como Fazer o Backup do Celular da Sogra (Passo a Passo Prático):

#### Etapa 1: Garantia do WhatsApp (Feito no próprio celular)
1. No celular dela, abra o **WhatsApp**.
2. Toque nos 3 pontinhos > **Configurações > Conversas > Backup de conversas**.
3. Verifique se há uma conta Google associada. Marque se deseja incluir vídeos e toque em **Fazer backup** (espere completar 100%).

#### Etapa 2: Ativar a Depuração USB
1. No celular, vá em **Configurações > Sobre o telefone**.
2. Procure por **Número da Versão** (ou *Versão da Build*) e toque rapidamente **7 vezes seguidas** até aparecer a mensagem *"Você agora é um desenvolvedor!"*.
3. Volte em **Configurações > Opções do desenvolvedor** (ou *Configurações adicionais > Opções do desenvolvedor*).
4. Ative a chave **Depuração USB**.

#### Etapa 3: Conectar no Pop!_OS e Rodar o Utilitário
1. Conecte o celular ao PC com um cabo USB.
2. Na tela do celular aparecerá um pop-up: **"Permitir a depuração USB?"**.
   * Marque a caixinha: ☑️ **"Sempre permitir a partir deste computador"**.
   * Toque em **Permitir**.
3. No terminal do Pop!_OS, basta executar:
   ```bash
   ./util/backup_android.sh
   ```
4. O script identificará o aparelho e puxará automaticamente todos os arquivos para uma pasta nova com data e hora (por padrão em `/mnt/storage_930/Backups_Android/android-backup-...`).

#### Etapa 4: Cuidado Crucial Antes de Resetar o Celular (Evitar Bloqueio FRP)
Antes de ir em *"Restaurar para os padrões de fábrica"*:
1. Acesse **Configurações > Contas e Sincronização** (ou *Gerenciar contas*).
2. Toque na **Conta Google** dela e clique em **Remover conta**.
3. Se for Xiaomi (MIUI/HyperOS): Acesse **Conta Mi** e encerre a sessão (ou saiba a senha da Conta Mi).
*(Isso desativa o bloqueio antifurto de hardware FRP, evitando que o celular trave pedindo senha antiga).*

#### Etapa 5: Como Formatar (Padrões de Fábrica)
* No celular, vá em **Configurações > Sobre o Telefone > Redefinir Dados** (ou *Configurações Adicionais > Redefinir para Configurações Originais*).
* Toque em **Apagar todos os dados**. O celular reiniciará como novo de fábrica.

#### Etapa 6: Restauração Pós-Formatação (Com 1 Comando)
Após iniciar o celular formatado, passar pela tela inicial de boas-vindas do Android e logar na Conta Google:
1. Reative a **Depuração USB** (7 toques na Versão da Build).
2. Conecte ao PC com o cabo USB e execute no Pop!_OS:
   ```bash
   ./util/restore_android.sh
   ```
3. O script listará os backups salvos, você escolhe qual deseja (ou aperta ENTER para o mais recente) e ele enviará de volta fotos, vídeos, músicas, downloads e documentos para a memória do celular!
4. Ao abrir o WhatsApp no celular pela primeira vez, faça login com o número de telefone e selecione **"Restaurar do Google Drive"**. Todas as conversas e mídias voltarão automaticamente.