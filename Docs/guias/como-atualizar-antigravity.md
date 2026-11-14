# 🚀 Guia de Atualização do Google Antigravity IDE

Este guia explica como utilizar o utilitário [update_antigravity.sh](../../util/update-antigravity/update_antigravity.sh) para manter o **Google Antigravity IDE** atualizado em `/opt/antigravity`.

---

## 📋 O que o Script Faz

1. **Verificação de Versão**:
   - Lê a versão instalada em `/opt/antigravity/resources/app/package.json`.
   - Consulta a API oficial de releases do Antigravity para obter a última versão estável.
2. **Download e Extração**:
   - Baixa o pacote oficial `.tar.gz` e extrai em `/opt/antigravity`.
   - Ajusta as permissões do `chrome-sandbox` (`chown root:root` e `chmod 4755`).
3. **Preservação de Customizações**:
   - Mantém o wrapper Wayland em `/opt/antigravity/bin/antigravity-ide`.
   - Reaplica o patch binário de cedilha e aspas (`' + c = ç`) no binário Electron (`/opt/antigravity/antigravity-ide`).

---

## 🚀 Como Executar

### 1. Verificar se há atualização disponível
```bash
./util/update-antigravity/update_antigravity.sh --check
```

### 2. Atualizar para a última versão
```bash
./util/update-antigravity/update_antigravity.sh
```

### 3. Forçar reinstalação (mesmo na versão atual)
```bash
./util/update-antigravity/update_antigravity.sh --force
```

---

## ⚠️ Observações

- Após a atualização, **reinicie o Antigravity IDE** para carregar a nova versão.
- O script utiliza `sudo` para extrair em `/opt/antigravity` e aplicar o patch binário.

