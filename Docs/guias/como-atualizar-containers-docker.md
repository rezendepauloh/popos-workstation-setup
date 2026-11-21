# 🐳 Guia de Atualização de Containers Docker

Este guia explica como utilizar o utilitário [update_containers.sh](../../util/docker-update/update_containers.sh) para atualizar todos os containers Docker da estação de trabalho (projetos **Docker Compose** e containers **standalone**, como o `dozzle-agent`).

---

## 📋 O que o Script Faz

1. **Projetos Docker Compose (uma stack por vez)**:
   - Descobre automaticamente os arquivos `docker-compose.yml` a partir dos labels dos containers (`com.docker.compose.project.config_files`).
   - No modo `--dry-run`, inspeciona cada container da stack, exibe a imagem, a versão/digest local e compara com o digest remoto via `docker manifest inspect` para indicar o que está atualizado ou prestes a atualizar.
   - Na execução normal, atualiza cada stack sequencialmente (`[i/N]`), executando `docker compose pull --ignore-buildable` e `docker compose up -d` para acompanhar o progresso passo a passo.
2. **Containers Standalone (um por vez)**:
   - Identifica containers sem projeto Compose associado (ex.: `dozzle-agent`).
   - No modo `--dry-run`, exibe a versão/digest local e verifica se há atualização remota disponível.
   - Na execução normal, faz `docker pull` da imagem configurada; se houver nova versão, recria o container preservando nome, portas, volumes, variáveis de ambiente, política de *restart*, rede e comando.
3. **Limpeza**:
   - Remove imagens antigas sem uso (*dangling*) com `docker image prune -f`.

---

## 🚀 Como Executar

### 1. Simulação (Dry-Run)
Para verificar quais projetos e containers seriam analisados sem aplicar alterações:

```bash
./util/docker-update/update_containers.sh --dry-run
```

### 2. Atualização Completa
Para baixar as novas imagens, recriar os containers desatualizados e limpar imagens antigas:

```bash
./util/docker-update/update_containers.sh
```

---

## ⚠️ Observações

- **Tags fixas**: Containers standalone criados com tag fixa (ex.: `amir20/dozzle:v11.4.0`) só são atualizados para novas versões quando usam uma tag móvel como `:latest` (ex.: `amir20/dozzle:latest`).
- **Permissões**: O usuário atual precisa ter acesso ao daemon do Docker (grupo `docker`).

