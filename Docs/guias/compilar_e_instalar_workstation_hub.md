# 🛠️ Guia: Como Compilar e Instalar o Workstation & Homelab Hub no Menu do Pop!_OS

> Passo a passo oficial para compilar o aplicativo nativo **COSMIC Desktop (`libcosmic` / Rust)** localizado em [`workstation-hub/`](../../workstation-hub) e registrá-lo no **Menu Principal (App Library) e Dock do Pop!_OS 24.04 LTS**.

---

## 📋 1. Pré-requisitos do Sistema

Todas as dependências de compilação já são instaladas automaticamente pelo módulo [`scripts/04_pacotes_base_dev.sh`](../../scripts/04_pacotes_base_dev.sh). Caso esteja em uma máquina recém-instalada antes de rodar o setup completo, instale manualmente:

```bash
sudo apt update
sudo apt install -y \
  build-essential cargo rustc just pkg-config cmake \
  libssl-dev libdbus-1-dev libglib2.0-dev \
  libxkbcommon-dev libwayland-dev libfontconfig1-dev libfreetype-dev
```

Verifique as versões disponíveis:

```bash
rustc --version   # Requerido >= 1.93
cargo --version
just --version
```

---

## 🚀 2. Compilação & Instalação Rápida (Recomendado via `just`)

Entre no diretório do aplicativo:

```bash
cd ~/Documentos/DevProjects/Bash/popos-workstation-setup/workstation-hub
```

### Opção A: Instalação Global (`/usr/local/bin`) + Atalho no Menu do Usuário

```bash
just install
```

O comando `just install` executa automaticamente:
1. Compilação otimizada (`cargo build --release`).
2. Instalação do binário em `/usr/local/bin/workstation-hub`.
3. Instalação do metainfo AppStream em `/usr/local/share/metainfo/br.dev.rezendepauloh.WorkstationHub.metainfo.xml`.
4. Instalação do atalho `.desktop` em `~/.local/share/applications/br.dev.rezendepauloh.WorkstationHub.desktop`.
5. Instalação do ícone vetorial SVG em `~/.local/share/icons/hicolor/scalable/apps/br.dev.rezendepauloh.WorkstationHub.svg`.
6. Atualização dos caches de desktop e ícones (`update-desktop-database` e `gtk-update-icon-cache`).

### Opção B: Instalação Exclusiva para o Usuário (`~/.local/bin`, sem `sudo`)

```bash
just install-user
```

---

## 🧪 3. Comandos Úteis de Desenvolvimento & Testes

| Comando | O que faz |
| :--- | :--- |
| `just check` | Valida tipos e compilação sem gerar binário final (`cargo check --all-targets`) |
| `just test` | Executa todos os testes unitários e de integração em Rust (`cargo test`) |
| `just build-debug` | Compila em modo debug (rápido durante alterações) |
| `just build-release` | Compila binário otimizado em `target/release/workstation-hub` |
| `just run` | Compila em release e abre a interface imediatamente |
| `just uninstall` | Remove binário, `.desktop` e ícone instalados |
| `just clean` | Limpa a pasta `target/` (libera espaço em disco) |

> [!NOTE]
> **Tempo da 1ª compilação:** Na primeira execução de `cargo build --release` ou `just install`, o Cargo baixará o `libcosmic` do GitHub e compilará todas as crates gráficas (~3 a 6 minutos, ocupando ~1.5–2 GB em `workstation-hub/target/`). Compilações incrementais subsequentes levam apenas alguns segundos.

---

## 🖥️ 4. Verificando no Menu Principal do COSMIC

1. Pressione a tecla `Super` (ou clique em **Aplicativos** na Dock).
2. Pesquise por **Workstation & Homelab Hub** (ou abra a categoria **Utilitários** se o módulo [`scripts/15_cosmic_menu_dock.sh`](../../scripts/15_cosmic_menu_dock.sh) estiver aplicado).
3. Para fixar na Dock: clique com o botão direito no ícone enquanto aberto (ou na App Library) e selecione **Fixar (Pin)**.

---

## 🔄 5. Atualizando Após Alterações no Repositório

Sempre que puxar atualizações via `git pull` ou modificar o código em `workstation-hub/`:

```bash
cd ~/Documentos/DevProjects/Bash/popos-workstation-setup/workstation-hub
just test && just install
```

E valide também a suíte global do repositório na raiz:

```bash
cd ~/Documentos/DevProjects/Bash/popos-workstation-setup
./setup_popos.sh --test
```
