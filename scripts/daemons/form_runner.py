# -*- coding: utf-8 -*-
"""
Form Runner nativo moderno em Python/GTK3 (PyGObject) para Pop!_OS e COSMIC Desktop.
Implementa:
- Estilização moderna CSS completa (Catppuccin Mocha / Pop Dark)
- Menus suspensos nativos Wayland que NÃO bugam no canto superior esquerdo da tela
- Ocultamento dinâmico real (SHOW/HIDE) baseado nas regras uischema do JSON Forms
- Suporte a arrays e caixas multilinhas
- Fallback automático para Tkinter caso PyGObject não esteja disponível
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


def run_gtk3_form(config_path, form_data):
    """Renderizador moderno GTK3 com suporte a CSS e popups nativos Wayland."""
    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gtk, Gdk

    properties = form_data.get("schema", {}).get("properties", {})
    defaults = form_data.get("data", {}) or {}
    rules = parse_uischema_rules(form_data.get("uischema", {}).get("elements", []))

    win = Gtk.Window(title=f"Espanso - {config_path.stem.replace('_', ' ').title()}")
    win.set_default_size(560, 680)
    win.set_position(Gtk.WindowPosition.CENTER)
    win.set_keep_above(True)

    # CSS moderno no estilo Pop!_OS / Catppuccin Mocha
    css = b"""
    window {
        background-color: #1e1e2e;
        color: #cdd6f4;
        font-family: 'Cantarell', 'Ubuntu', sans-serif;
    }
    .field-label {
        color: #cdd6f4;
        font-size: 13px;
        font-weight: bold;
        margin-bottom: 3px;
    }
    entry {
        background-color: #313244;
        color: #ffffff;
        border: 1px solid #45475a;
        border-radius: 8px;
        padding: 8px 12px;
        font-size: 13px;
        min-height: 24px;
    }
    entry:focus {
        border-color: #89b4fa;
        box-shadow: 0 0 0 1px #89b4fa;
    }
    textview {
        background-color: #313244;
        color: #ffffff;
        border: 1px solid #45475a;
        border-radius: 8px;
        padding: 8px;
        font-size: 13px;
    }
    textview text {
        background-color: #313244;
        color: #ffffff;
    }
    textview:focus {
        border-color: #89b4fa;
    }
    combobox button {
        background-color: #313244;
        color: #ffffff;
        border: 1px solid #45475a;
        border-radius: 8px;
        padding: 6px 12px;
        min-height: 28px;
    }
    combobox button:hover {
        background-color: #45475a;
    }
    menu {
        background-color: #1e1e2e;
        color: #ffffff;
        border: 1px solid #45475a;
        border-radius: 8px;
        padding: 6px;
    }
    menuitem {
        padding: 6px 12px;
        color: #cdd6f4;
        border-radius: 4px;
    }
    menuitem:hover {
        background-color: #89b4fa;
        color: #11111b;
        font-weight: bold;
    }
    .btn-submit {
        background-color: #89b4fa;
        color: #11111b;
        font-weight: bold;
        border-radius: 8px;
        padding: 9px 24px;
        border: none;
    }
    .btn-submit:hover {
        background-color: #b4befe;
    }
    .btn-cancel {
        background-color: #313244;
        color: #cdd6f4;
        border-radius: 8px;
        padding: 9px 20px;
        border: 1px solid #45475a;
    }
    .btn-cancel:hover {
        background-color: #45475a;
    }
    .footer-bar {
        border-top: 1px solid #313244;
        padding: 12px 20px;
        background-color: #181825;
    }
    """
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(),
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )

    main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
    win.add(main_box)

    scrolled = Gtk.ScrolledWindow()
    scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
    scrolled.set_vexpand(True)
    main_box.pack_start(scrolled, True, True, 0)

    form_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
    form_box.set_margin_start(20)
    form_box.set_margin_end(20)
    form_box.set_margin_top(20)
    form_box.set_margin_bottom(20)
    scrolled.add(form_box)

    field_containers = {}
    widgets = {}

    for field_name, field_info in properties.items():
        row_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        field_containers[field_name] = row_box

        title = field_info.get("title", field_name)
        lbl = Gtk.Label(label=title, xalign=0)
        lbl.get_style_context().add_class("field-label")
        row_box.pack_start(lbl, False, False, 0)

        enums = field_info.get("enum")
        field_type = field_info.get("type")
        default_val = defaults.get(field_name, "")

        if enums:
            combo = Gtk.ComboBoxText()
            for idx, val in enumerate(enums):
                combo.append_text(str(val))
            if default_val and default_val in enums:
                combo.set_active(enums.index(default_val))
            else:
                combo.set_active(0)
            row_box.pack_start(combo, False, False, 0)
            widgets[field_name] = (combo, "combobox", enums)
        elif field_type == "array":
            tv = Gtk.TextView()
            tv.set_wrap_mode(Gtk.WrapMode.WORD)
            buf = tv.get_buffer()
            if isinstance(default_val, list):
                buf.set_text("\n".join(str(x) for x in default_val))
            elif default_val:
                buf.set_text(str(default_val))
            tv.set_size_request(-1, 80)
            row_box.pack_start(tv, False, False, 0)
            widgets[field_name] = (tv, "text", None)
        else:
            entry = Gtk.Entry()
            if default_val:
                entry.set_text(str(default_val))
            row_box.pack_start(entry, False, False, 0)
            widgets[field_name] = (entry, "entry", None)

        form_box.pack_start(row_box, False, False, 0)

    def get_current_values():
        vals = {}
        for fname, (w, wtype, extra) in widgets.items():
            if wtype == "combobox":
                active_idx = w.get_active()
                vals[fname] = extra[active_idx] if 0 <= active_idx < len(extra) else ""
            elif wtype == "text":
                buf = w.get_buffer()
                start, end = buf.get_bounds()
                vals[fname] = buf.get_text(start, end, True).strip()
            else:
                vals[fname] = w.get_text().strip()
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

            box = field_containers[fname]
            box.set_visible(should_show)
            box.set_no_show_all(not should_show)

    for fname, (w, wtype, extra) in widgets.items():
        if wtype == "combobox":
            w.connect("changed", update_visibility)
        elif wtype == "entry":
            w.connect("changed", update_visibility)

    result_data = {}

    def on_submit(btn=None):
        nonlocal result_data
        for fname, (w, wtype, extra) in widgets.items():
            box = field_containers[fname]
            if not box.get_visible():
                result_data[fname] = ""
                continue

            if wtype == "combobox":
                active_idx = w.get_active()
                result_data[fname] = extra[active_idx] if 0 <= active_idx < len(extra) else ""
            elif wtype == "text":
                buf = w.get_buffer()
                start, end = buf.get_bounds()
                result_data[fname] = buf.get_text(start, end, True).strip()
            else:
                result_data[fname] = w.get_text().strip()

        win.destroy()
        Gtk.main_quit()

    def on_cancel(btn=None):
        win.destroy()
        Gtk.main_quit()

    def on_key_press(widget, event):
        if event.keyval == Gdk.KEY_Escape:
            on_cancel()
            return True
        return False

    win.connect("key-press-event", on_key_press)
    win.connect("destroy", Gtk.main_quit)

    # Barra inferior de ações
    footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
    footer.get_style_context().add_class("footer-bar")
    main_box.pack_end(footer, False, False, 0)

    btn_cancel = Gtk.Button(label="Cancelar")
    btn_cancel.get_style_context().add_class("btn-cancel")
    btn_cancel.connect("clicked", on_cancel)

    btn_ok = Gtk.Button(label="Preencher")
    btn_ok.get_style_context().add_class("btn-submit")
    btn_ok.connect("clicked", on_submit)

    footer.pack_end(btn_ok, False, False, 0)
    footer.pack_end(btn_cancel, False, False, 0)

    win.show_all()
    update_visibility()

    # Foca no primeiro campo visível
    for fname, (w, wtype, extra) in widgets.items():
        if field_containers[fname].get_visible():
            w.grab_focus()
            break

    Gtk.main()
    return result_data


def run_gui_form(form_config_path):
    """Ponto de entrada: tenta GTK3 primeiro e recorre a Zenity em último caso."""
    config_path = Path(form_config_path)
    if not config_path.exists():
        return {}

    try:
        form_data = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    except Exception:
        return {}

    try:
        return run_gtk3_form(config_path, form_data)
    except Exception as e:
        # Fallback para Zenity
        properties = form_data.get("schema", {}).get("properties", {})
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
