# 🔄 Sincronização Diária de Backups do Homelab (umbrelOS -> Pop!_OS)

Este guia documenta o timer e serviço **systemd de usuário** configurados pelo módulo [28_limpeza_otimizacao.sh](../../scripts/28_limpeza_otimizacao.sh) para auditar e sincronizar backups do Homelab (`disk3`) para o Pop!_OS com impacto mínimo no sistema.

---

## ⚙️ Arquivos de Configuração

- **Serviço**: [homelab-backup-sync.service](../../config/systemd/user/homelab-backup-sync.service)
- **Timer**: [homelab-backup-sync.timer](../../config/systemd/user/homelab-backup-sync.timer)
- **Destino no usuário**: `~/.config/systemd/user/`

---

## 📋 Como Funciona

1. **Execução Diária (`homelab-backup-sync.timer`)**:
   - Agenda diária (`OnCalendar=daily`) com `Persistent=true` (executa ao ligar caso o horário tenha passado) e `RandomizedDelaySec=10min`.
2. **Baixo Impacto (`homelab-backup-sync.service`)**:
   - Executa somente após rede ativa (`After=network-online.target`) e se o script existir (`ConditionPathExists=%h/Documentos/DevProjects/Bash/umbrelos-scripts/scripts/utils/homelab_auditar_e_sincronizar_backups.sh`).
   - Roda com prioridade mínima de CPU e disco: `Nice=19`, `IOSchedulingClass=idle`, `CPUQuota=35%` e `/usr/bin/nice -n 19 /usr/bin/ionice -c3`.
   - Passa a flag `--auto` para o script de auditoria e sincronização.
3. **Logs**:
   - Saída padrão e de erro gravadas em `~/.local/state/homelab-backup-sync.log`.

---

## 🛠️ Comandos Úteis

```bash
# Ver status do timer e próximo disparo
systemctl --user list-timers homelab-backup-sync.timer

# Ver status do serviço
systemctl --user status homelab-backup-sync.service

# Executar sincronização manualmente agora
systemctl --user start homelab-backup-sync.service

# Acompanhar o log
tail -f ~/.local/state/homelab-backup-sync.log
```
