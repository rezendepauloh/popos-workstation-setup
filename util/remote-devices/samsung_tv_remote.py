#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Utilitário: Controle Remoto de Smart TV & Projetor Samsung (Tizen LAN + Wake-on-LAN).
Utiliza apenas biblioteca padrão Python 3 (REST API :8001, WebSocket RFC6455 e UDP WoL).
"""

import argparse
import base64
import json
import os
import re
import socket
import struct
import sys
import urllib.error
import urllib.request


def load_env(env_path: str) -> dict:
    data = {}
    if not os.path.isfile(env_path) or os.path.islink(env_path):
        return data
    with open(env_path, "r", encoding="utf-8", errors="ignore") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k = k.strip()
            v = v.strip().strip('"').strip("'")
            data[k] = v
    return data


def validate_ip(ip: str) -> str:
    if not ip or not re.match(r"^[a-zA-Z0-9._-]+$", ip):
        raise ValueError("IP/host da TV/Projetor ausente ou inválido no .env.")
    return ip


def validate_mac(mac: str) -> str:
    if not mac or not re.match(r"^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$", mac):
        raise ValueError("MAC da TV/Projetor ausente ou inválido no .env (AA:BB:CC:DD:EE:FF).")
    return mac


def send_wol(mac: str) -> None:
    clean = mac.replace(":", "").replace("-", "")
    payload = b"\xff" * 6 + bytes.fromhex(clean) * 16
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(payload, ("255.255.255.255", 9))
    print(f"[OK] Pacote Wake-on-LAN enviado para {mac}.")


def get_status(ip: str) -> None:
    url = f"http://{ip}:8001/api/v2/"
    req = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=3) as resp:
            info = json.loads(resp.read().decode("utf-8", errors="ignore"))
        dev = info.get("device", {})
        print(f"Nome      : {dev.get('name', info.get('name', 'Samsung'))}")
        print(f"Modelo    : {dev.get('modelName', 'N/A')}")
        print(f"Energia   : {dev.get('PowerState', 'online')}")
        print(f"OS        : {dev.get('OS', 'Tizen')}")
        print(f"WiFi MAC  : {dev.get('wifiMac', 'N/A')}")
    except urllib.error.URLError as e:
        print(f"[!] Dispositivo {ip} inacessível na porta 8001 ({e.reason}).")
        sys.exit(1)


def ws_send_frame(sock: socket.socket, text: str) -> None:
    data = text.encode("utf-8")
    mask = os.urandom(4)
    header = bytearray([0x81])
    length = len(data)
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    header.extend(mask)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
    sock.sendall(bytes(header) + masked)


def send_remote_key(ip: str, key: str) -> None:
    if not re.match(r"^KEY_[A-Z0-9_]+$", key):
        raise ValueError(f"Tecla Samsung inválida: {key}")

    app_name = base64.b64encode(b"WorkstationHub").decode("ascii")
    path = f"/api/v2/channels/samsung.remote.control?name={app_name}"
    ws_key = base64.b64encode(os.urandom(16)).decode("ascii")

    with socket.create_connection((ip, 8001), timeout=4) as sock:
        handshake = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {ip}:8001\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {ws_key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        sock.sendall(handshake.encode("ascii"))
        resp = sock.recv(2048).decode("utf-8", errors="ignore")
        if "101" not in resp:
            print(f"[!] Handshake rejeitado ou TV exige confirmação/SSL (:8002): {resp.splitlines()[0] if resp else ''}")
            sys.exit(1)

        payload = json.dumps({
            "method": "ms.remote.control",
            "params": {
                "Cmd": "Click",
                "DataOfCmd": key,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            },
        })
        ws_send_frame(sock, payload)
        print(f"[OK] Comando '{key}' enviado para {ip}.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Controle Samsung Tizen LAN / WoL")
    parser.add_argument("--target", choices=["tv", "projector"], default="tv")
    parser.add_argument("--ip", default="")
    parser.add_argument("--mac", default="")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--wol", action="store_true")
    parser.add_argument("--key", default="")
    args = parser.parse_args()

    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    env = load_env(os.path.join(root, ".env"))

    if args.target == "tv":
        ip = args.ip or env.get("REMOTE_TV_IP", "")
        mac = args.mac or env.get("REMOTE_TV_MAC", "")
    else:
        ip = args.ip or env.get("REMOTE_PROJECTOR_IP", "")
        mac = args.mac or env.get("REMOTE_PROJECTOR_MAC", "")

    try:
        if args.wol:
            send_wol(validate_mac(mac))
        elif args.key:
            send_remote_key(validate_ip(ip), args.key)
        else:
            get_status(validate_ip(ip))
    except ValueError as err:
        print(f"[ERRO] {err}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
