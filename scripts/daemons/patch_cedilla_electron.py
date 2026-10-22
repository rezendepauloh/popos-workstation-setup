#!/usr/bin/env python3
"""
Patch em binários Chromium/Electron para converter ' + c em ç no Wayland.
Substitui as sequências da tabela ui::CharacterComposer:
  c (0x0063) -> ć (0x0107) [63 00 07 01] por [63 00 e7 00] (ç, U+00E7)
  C (0x0043) -> Ć (0x0106) [43 00 06 01] por [43 00 c7 00] (Ç, U+00C7)
"""
import sys, os, shutil

DEFAULT_TARGETS = [
    "/opt/antigravity/antigravity-ide",
    "/usr/share/code/code",
    "/opt/google/chrome/chrome",
    "/opt/brave.com/brave/brave",
]

PATCHES = [
    # Cedilha: ' + c -> ç e ' + C -> Ç
    ("c -> ç", b"\x63\x00\x07\x01", b"\x63\x00\xe7\x00"),
    ("C -> Ç", b"\x43\x00\x06\x01", b"\x43\x00\xc7\x00"),
    # Aspas duplas (" 2x ou Shift+' isolado): converte U+00A8 (¨) em U+0022 (")
    ("¨ -> \" (subtable)", b"\x22\x00\xa8\x00\x27\x00\x44\x03", b"\x22\x00\x22\x00\x27\x00\x44\x03"),
    ("¨ -> \" (standalone)", b"\x08\x03\xa8\x00", b"\x08\x03\x22\x00"),
    # Aspas simples (' 2x ou ' isolado): converte U+00B4 (´) em U+0027 (')
    ("'' -> '", b"\x27\x00\xb4\x00\x2c\x00\x1a\x20", b"\x27\x00\x27\x00\x2c\x00\x1a\x20"),
]

def patch_binary(path):
    if not os.path.isfile(path):
        return False

    try:
        with open(path, "rb") as f:
            data = f.read()
    except Exception as e:
        print(f"[erro] Não foi possível ler {path}: {e}", file=sys.stderr)
        return False

    pending_patches = [(desc, old, new) for desc, old, new in PATCHES if old in data]
    if not pending_patches:
        already_applied = all(new in data for _, _, new in PATCHES)
        if already_applied:
            print(f"[ok] {path} já está com todos os patches (cedilha e aspas) aplicados.")
            return True
        print(f"[aviso] Padrões não encontrados em {path} (versão incompatível ou já tratada).", file=sys.stderr)
        return False

    new_data = data
    report = []
    for desc, old, new in pending_patches:
        n = new_data.count(old)
        new_data = new_data.replace(old, new)
        report.append(f"{desc}: {n}")

    # Salva cópia .orig limpa permanente caso não exista
    orig_path = path + ".orig"
    if not os.path.exists(orig_path):
        try:
            shutil.copy2(path, orig_path)
            print(f"[backup] Cópia original salva em {orig_path}")
        except Exception as e:
            print(f"[aviso] Falha ao criar backup original {orig_path}: {e}")

    try:
        with open(path, "r+b") as f:
            f.write(new_data)
            f.truncate(len(new_data))
        print(f"[sucesso] Patch aplicado em {path} ({', '.join(report)})")
        return True
    except Exception as e:
        print(f"[erro] Falha ao gravar patch em {path}: {e}", file=sys.stderr)
        return False

def main():
    targets = sys.argv[1:] if len(sys.argv) > 1 else DEFAULT_TARGETS
    count = 0
    for target in targets:
        if os.path.exists(target):
            if patch_binary(target):
                count += 1
    if count == 0 and len(targets) == len(DEFAULT_TARGETS):
        print("[info] Nenhum binário elegível para patch foi modificado.")

if __name__ == "__main__":
    main()
