# -*- coding: utf-8 -*-
"""
Form Runner nativo multiplataforma (Linux / Tkinter) com suporte total a regras dinâmicas
do uischema (SHOW/HIDE), listas de arrays multilinhas e estilização moderna Pop!_OS / Catppuccin.
"""

import os
import subprocess
import sys
import yaml
from pathlib import Path


def parse_uischema_rules(uischema_elements):
    """
    Extrai recursivamente as regras dinâmicas de visibilidade (SHOW/HIDE)
    definidas no uischema do JSON Forms / EDF.
    """
    rules = {}

    def walk(elements):
        if not elements:
            return
        for el in elements:
            rule = el.get("rule")
            scope = el.get("scope")

            # Se for um layout container com regra (ex: HorizontalLayout)
            if rule and not scope and el.get("elements"):
                cond = rule.get("condition", {})
                target_scope = cond.get("scope", "").replace("#/properties/", "")
                expected_val = cond.get("schema", {}).get("const")
                effect = rule.get("effect", "SHOW")

                for sub_el in el.get("elements", []):
                    sub_scope = sub_el.get("scope", "").replace("#/properties/", "")
                    if sub_scope:
                        rules[sub_scope] = {
                            "trigger_field": target_scope,
                            "expected_value": expected_val,
                            "effect": effect,
                        }
            elif rule and scope:
                field_name = scope.replace("#/properties/", "")
                cond = rule.get("condition", {})
                target_scope = cond.get("scope", "").replace("#/properties/", "")
                expected_val = cond.get("schema", {}).get("const")
                effect = rule.get("effect", "SHOW")
                rules[field_name] = {
                    "trigger_field": target_scope,
                    "expected_value": expected_val,
                    "effect": effect,
                }

            if el.get("elements"):
                walk(el["elements"])

    walk(uischema_elements)
    return rules


def run_gui_form(form_config_path):
    config_path = Path(form_config_path)
    if not config_path.exists():
        return {}

    try:
        form_data = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    except Exception:
        return {}

    properties = form_data.get("schema", {}).get("properties", {})
    defaults = form_data.get("data", {}) or {}
    rules = parse_uischema_rules(form_data.get("uischema", {}).get("elements", []))

    try:
        import tkinter as tk
        from tkinter import ttk

        root = tk.Tk()
        form_title = f"Espanso - {config_path.stem.replace('_', ' ').title()}"
        root.title(form_title)
        root.configure(bg="#1e1e2e")
        root.attributes("-topmost", True)
        root.geometry("560x700")
        root.minsize(500, 420)
        root.eval("tk::PlaceWindow . center")

        # Configuração de temas e fontes
        style = ttk.Style()
        style.theme_use("clam")
        style.configure(".", background="#1e1e2e", foreground="#cdd6f4", font=("Cantarell", 10))
        style.configure("TLabel", background="#1e1e2e", foreground="#cdd6f4", font=("Cantarell", 10, "bold"))
        style.configure("TEntry", fieldbackground="#313244", foreground="#ffffff", insertcolor="#ffffff")
        style.configure("TCombobox", fieldbackground="#313244", foreground="#ffffff")
        style.configure("TButton", background="#89b4fa", foreground="#11111b", font=("Cantarell", 10, "bold"))

        # Frame com scroll
        canvas = tk.Canvas(root, bg="#1e1e2e", highlightthickness=0)
        scrollbar = ttk.Scrollbar(root, orient="vertical", command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas, padding="15")

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all")),
        )

        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw", width=530)
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side="top", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        field_containers = {}
        entries = {}

        for field_name, field_info in properties.items():
            # Cria container individual por campo (permite esconder/mostrar dinamicamente)
            container = ttk.Frame(scrollable_frame)
            container.pack(fill="x", expand=True, pady=4)
            field_containers[field_name] = container

            title = field_info.get("title", field_name)
            lbl = ttk.Label(container, text=title)
            lbl.pack(anchor="w", pady=(0, 2))

            enums = field_info.get("enum")
            field_type = field_info.get("type")
            default_val = defaults.get(field_name, "")

            if enums:
                combo = ttk.Combobox(container, values=enums, state="readonly")
                if default_val and default_val in enums:
                    combo.set(default_val)
                elif enums:
                    combo.current(0)
                combo.pack(fill="x", expand=True)
                entries[field_name] = (combo, "combobox")
            elif field_type == "array":
                txt = tk.Text(
                    container,
                    height=4,
                    bg="#313244",
                    fg="#ffffff",
                    insertbackground="#ffffff",
                    relief="flat",
                    font=("Cantarell", 10),
                )
                if isinstance(default_val, list):
                    txt.insert("1.0", "\n".join(str(x) for x in default_val))
                elif default_val:
                    txt.insert("1.0", str(default_val))
                txt.pack(fill="x", expand=True)
                entries[field_name] = (txt, "text")
            else:
                entry = ttk.Entry(container)
                if default_val:
                    entry.insert(0, str(default_val))
                entry.pack(fill="x", expand=True)
                entries[field_name] = (entry, "entry")

        def get_current_values():
            vals = {}
            for fname, (widget, wtype) in entries.items():
                if wtype == "text":
                    vals[fname] = widget.get("1.0", "end-1c").strip()
                else:
                    vals[fname] = widget.get().strip()
            return vals

        def update_visibility(*args):
            current_vals = get_current_values()
            for fname, rule in rules.items():
                if fname not in field_containers:
                    continue
                trigger = rule["trigger_field"]
                expected = rule["expected_value"]
                effect = rule["effect"]
                current_trig_val = current_vals.get(trigger, "")

                is_match = (current_trig_val == expected)
                should_show = is_match if effect == "SHOW" else not is_match

                container = field_containers[fname]
                if should_show:
                    if not container.winfo_ismapped():
                        container.pack(fill="x", expand=True, pady=4)
                else:
                    if container.winfo_ismapped():
                        container.pack_forget()

            # Atualiza área de rolagem
            root.update_idletasks()
            canvas.configure(scrollregion=canvas.bbox("all"))

        # Conecta ouvintes para atualização dinâmica de regras
        for fname, (widget, wtype) in entries.items():
            if wtype == "combobox":
                widget.bind("<<ComboboxSelected>>", lambda e: update_visibility())
            elif wtype == "entry":
                widget.bind("<KeyRelease>", lambda e: update_visibility())

        # Executa uma vez no início para ajustar visibilidade inicial
        update_visibility()

        result_data = {}

        def on_submit(event=None):
            for fname, (widget, wtype) in entries.items():
                # Se o campo estiver oculto pelas regras do uischema, envia vazio
                container = field_containers[fname]
                if not container.winfo_ismapped():
                    result_data[fname] = ""
                    continue

                if wtype == "text":
                    result_data[fname] = widget.get("1.0", "end-1c").strip()
                else:
                    result_data[fname] = widget.get().strip()
            root.destroy()

        def on_cancel(event=None):
            root.destroy()

        btn_frame = ttk.Frame(root, padding="15")
        btn_frame.pack(side="bottom", fill="x")

        cancel_btn = ttk.Button(btn_frame, text="Cancelar", command=on_cancel)
        cancel_btn.pack(side=tk.RIGHT, padx=(8, 0))
        ok_btn = ttk.Button(btn_frame, text="Preencher", command=on_submit)
        ok_btn.pack(side=tk.RIGHT)

        root.bind("<Escape>", on_cancel)

        # Foca no primeiro campo visível
        for fname, (widget, wtype) in entries.items():
            if field_containers[fname].winfo_ismapped():
                widget.focus_set()
                break

        root.mainloop()
        return result_data

    except Exception:
        # Fallback para Zenity caso o Tkinter falhe
        cmd = ["zenity", "--forms", f"--title=Espanso - {config_path.stem}", "--text=Preencha as informações:"]
        fields_order = []
        for field_name, field_info in properties.items():
            cmd.append(f"--add-entry={field_info.get('title', field_name)}")
            fields_order.append(field_name)
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
            if res.returncode != 0 or not res.stdout.strip():
                return {}
            values = res.stdout.strip().split("|")
            return {fname: (values[i] if i < len(values) else "") for i, fname in enumerate(fields_order)}
        except Exception:
            return {}
