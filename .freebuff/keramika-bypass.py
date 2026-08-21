# -*- coding: utf-8 -*-
"""
KERAMIKA BYPASS — свой тотальный обход DPI одним файлом.
Никакого zapret. Своя реализация двух механизмов:

  1) DoH-DNS прокси  — локальный резолвер на 127.0.0.1:53,
     все DNS-запросы уходят в Cloudflare/Google по HTTPS (dns-message).
     Решает DNS-блокировки (подмена/подрезка ответов провайдером).

  2) Фрагментация TLS ClientHello — перехват TCP:443 через системный
     драйвер WinDivert (уже установлен). TLS ClientHello делится на
     два сегмента, чтобы DPI не видел SNI целиком в одном пакете
     (принцип GoodbyeDPI, реализация своя).

Запуск (от имени администратора):
    python keramika-bypass.py start     # включить (поднимет DNS+фрагментацию)
    python keramika-bypass.py stop      # выключить и вернуть DNS
    python keramika-bypass.py status    # состояние

После start системный DNS автоматически ставится на 127.0.0.1 —
интернет продолжает работать, но заблокированные домены резолвятся
через DoH, а TLS-рукопожатия фрагментируются.
"""

import argparse
import ctypes
import ctypes.wintypes as wt
import json
import os
import socket
import struct
import subprocess
import sys
import threading
import time
import urllib.request

# ---------------------------------------------------------------- пути
DLL_WINDIVERT = r"C:\zapret-discord-youtube-1.9.9c\bin\WinDivert.dll"
DNS_PORT = 53

# ---------------------------------------------------------------- DoH
_DOH_ENDPOINTS = [
    "https://cloudflare-dns.com/dns-query",
    "https://dns.google/resolve",
    "https://dns.quad9.net/dns-query",
]
_DNS_CACHE = {}
_CACHE_TTL = 300


def _doh_resolve(raw_query: bytes) -> bytes:
    """Отправляет сырой DNS-запрос через DoH, возвращает сырой ответ."""
    for ep in _DOH_ENDPOINTS:
        try:
            if "dns-query" in ep:
                req = urllib.request.Request(
                    ep,
                    data=raw_query,
                    headers={
                        "Content-Type": "application/dns-message",
                        "Accept": "application/dns-message",
                        "User-Agent": "keramika-bypass/1.0",
                    },
                    method="POST",
                )
                with urllib.request.urlopen(req, timeout=8) as r:
                    return r.read()
            else:  # dns.google/resolve — JSON
                qname, qtype = _parse_question(raw_query)
                if qname is None:
                    continue
                url = (
                    f"https://dns.google/resolve?name={qname}"
                    f"&type={qtype}&dnssec=false"
                )
                with urllib.request.urlopen(url, timeout=8) as r:
                    data = json.loads(r.read().decode("utf-8"))
                return _json_to_dns(raw_query, data)
        except Exception:
            continue
    return _refused(raw_query)


def _parse_question(raw: bytes):
    if len(raw) < 12:
        return None, None
    try:
        labels, qname_bytes = _decode_qname(raw, 12)
    except Exception:
        return None, None
    off = 12 + len(qname_bytes)
    if len(raw) < off + 4:
        return None, None
    qtype = struct.unpack(">H", raw[off: off + 2])[0]
    return labels, qtype


def _decode_qname(raw: bytes, off: int):
    labels = []
    end = off
    while True:
        ln = raw[end]
        if ln & 0xC0 == 0xC0:
            end += 2
            break
        if ln == 0:
            end += 1
            break
        end += 1
        labels.append(raw[end: end + ln].decode("idna", "ignore"))
        end += ln
    return ".".join(labels), raw[off:end]


def _encode_qname(name: str) -> bytes:
    if name in (".", ""):
        return b"\x00"
    out = bytearray()
    for label in name.rstrip(".").split("."):
        b = label.encode("idna")
        out.append(len(b))
        out += b
    out.append(0)
    return bytes(out)


def _json_to_dns(raw: bytes, data: dict) -> bytes:
    tid = raw[0:2]
    answers = data.get("Answer", [])
    rcode = 0 if data.get("Status") == 0 else 3
    flags = 0x8180 | rcode
    ancount = len(answers)
    # вопрос из raw (id + флаги + qdcount заменяем, вопрос оставляем)
    qd = raw[12:]
    header = tid + struct.pack(">HHHHH", flags, 1, ancount, 0, 0)
    body = bytearray(header + qd)
    for a in answers:
        name = _encode_qname(a.get("name", "."))
        rtype = int(a.get("type", 1))
        ttl = int(a.get("TTL", 60))
        rdata_raw = a.get("data", "")
        if rtype == 1:
            rdata = socket.inet_aton(rdata_raw)
        elif rtype == 28:
            rdata = socket.inet_pton(socket.AF_INET6, rdata_raw)
        else:
            rdata = _encode_qname(rdata_raw)
        body += name + struct.pack(">HHIH", rtype, 1, ttl, len(rdata)) + rdata
    return bytes(body)


def _refused(raw: bytes) -> bytes:
    if len(raw) < 12:
        return raw
    tid = raw[0:2]
    return tid + struct.pack(">HHHHH", 0x8183, 1, 0, 0, 0) + raw[12:]


class DohDnsProxy(threading.Thread):
    """UDP-сервер на 127.0.0.1:53, резолвит через DoH."""

    def __init__(self):
        super().__init__(daemon=True)
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind(("127.0.0.1", DNS_PORT))
        self._running = True

    def run(self):
        print("[dns] DoH proxy listening on 127.0.0.1:53")
        while self._running:
            try:
                data, addr = self._sock.recvfrom(4096)
                threading.Thread(
                    target=self._handle, args=(data, addr), daemon=True
                ).start()
            except OSError:
                break

    def _handle(self, data, addr):
        try:
            key = data[:64]
            if key in _DNS_CACHE:
                resp, ts = _DNS_CACHE[key]
                if time.time() - ts < _CACHE_TTL:
                    self._sock.sendto(resp, addr)
                    return
            resp = _doh_resolve(data)
            _DNS_CACHE[key] = (resp, time.time())
            self._sock.sendto(resp, addr)
        except Exception:
            pass

    def stop(self):
        self._running = False
        try:
            self._sock.close()
        except Exception:
            pass


# ------------------------------------------------- WinDivert (ctypes)
class WinDivertAddress(ctypes.Structure):
    _fields_ = [
        ("Timestamp", ctypes.c_int64),
        ("InterfaceIndex", ctypes.c_uint32),
        ("SubInterfaceIndex", ctypes.c_uint32),
        ("Flags", ctypes.c_uint8),
        ("Reserved", ctypes.c_uint8 * 7),
    ]


WD_LAYER_NETWORK = 0


def _load_windivert():
    if not os.path.exists(DLL_WINDIVERT):
        raise RuntimeError(f"WinDivert.dll не найден: {DLL_WINDIVERT}")
    wd = ctypes.WinDLL(DLL_WINDIVERT)
    wd.WinDivertOpen.restype = ctypes.c_void_p
    wd.WinDivertOpen.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_uint64]
    wd.WinDivertRecv.restype = wt.BOOL
    wd.WinDivertRecv.argtypes = [ctypes.c_void_p, ctypes.c_void_p, wt.UINT, ctypes.POINTER(WinDivertAddress), ctypes.POINTER(wt.UINT)]
    wd.WinDivertSend.restype = wt.BOOL
    wd.WinDivertSend.argtypes = [ctypes.c_void_p, ctypes.c_void_p, wt.UINT, ctypes.POINTER(WinDivertAddress), ctypes.POINTER(wt.UINT)]
    wd.WinDivertClose.restype = wt.BOOL
    wd.WinDivertClose.argtypes = [ctypes.c_void_p]
    return wd


def _tcp_parse(pkt: bytes):
    try:
        vihl = pkt[0]
        if vihl >> 4 == 4:
            ihl = (vihl & 0x0F) * 4
            proto = pkt[9]
            total_len = struct.unpack(">H", pkt[2:4])[0]
            src = pkt[12:16]
            dst = pkt[16:20]
        elif vihl >> 4 == 6:
            ihl = 40
            proto = pkt[6]
            total_len = 40 + struct.unpack(">H", pkt[4:6])[0]
            src = pkt[8:24]
            dst = pkt[24:40]
        else:
            return None
        if proto != 6:
            return None
        tcp_off = ihl
        if len(pkt) < tcp_off + 20:
            return None
        sport, dport = struct.unpack(">HH", pkt[tcp_off: tcp_off + 4])
        seq = struct.unpack(">I", pkt[tcp_off + 4: tcp_off + 8])[0]
        data_off = ((pkt[tcp_off + 12] >> 4) & 0x0F) * 4
        payload_off = tcp_off + data_off
        end = min(total_len, len(pkt))
        payload = pkt[payload_off:end]
        return {
            "ip_off": 0, "tcp_off": tcp_off, "payload_off": payload_off,
            "ihl": ihl, "total_len": total_len, "src": src, "dst": dst,
            "sport": sport, "dport": dport, "seq": seq, "payload": payload,
            "pkt": pkt,
        }
    except Exception:
        return None


def _checksum(data: bytes) -> int:
    if len(data) % 2:
        data += b"\x00"
    s = sum(struct.unpack(">%dH" % (len(data) // 2), data))
    s = (s & 0xFFFF) + (s >> 16)
    s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def _pseudo_checksum(src, dst, proto, tcp_len) -> int:
    if len(src) == 4:
        pseudo = src + dst + struct.pack(">BBH", 0, proto, tcp_len)
    else:
        pseudo = src + dst + struct.pack(">I", tcp_len) + b"\x00" * 3 + bytes([proto])
    return _checksum(pseudo)


def _build_tcp_packet(base: dict, new_payload: bytes, seq_off: int = 0) -> bytes:
    old = base
    tcp_hdr = old["pkt"][old["tcp_off"]: old["payload_off"]]
    seq = (old["seq"] + seq_off) & 0xFFFFFFFF
    tcp_hdr = tcp_hdr[:4] + struct.pack(">I", seq) + tcp_hdr[8:]
    # PSH|ACK
    tcp_hdr = tcp_hdr[:12] + b"\x50\x18" + tcp_hdr[14:]
    tcp_hdr = tcp_hdr[:16] + b"\x00\x00" + tcp_hdr[18:]
    tcp_len = len(tcp_hdr) + len(new_payload)
    psum = _pseudo_checksum(old["src"], old["dst"], 6, tcp_len)
    csum = _checksum(psum + tcp_hdr + new_payload)
    tcp_hdr = tcp_hdr[:16] + struct.pack(">H", csum) + tcp_hdr[18:]

    if len(old["src"]) == 4:
        ip_hdr = bytearray(old["pkt"][0: old["ihl"]])
        ip_hdr[2:4] = struct.pack(">H", old["ihl"] + tcp_len)
        ip_hdr[10:12] = b"\x00\x00"
        ip_hdr[10:12] = struct.pack(">H", _checksum(bytes(ip_hdr)))
        return bytes(ip_hdr) + tcp_hdr + new_payload
    else:
        ip_hdr = bytearray(old["pkt"][0:40])
        ip_hdr[4:6] = struct.pack(">H", tcp_len)
        return bytes(ip_hdr) + tcp_hdr + new_payload


class TlsFragmentation(threading.Thread):
    """Фрагментация исходящих ClientHello на TCP:443."""

    def __init__(self):
        super().__init__(daemon=True)
        self._running = True

    def run(self):
        try:
            wd = _load_windivert()
        except Exception as e:
            print(f"[tls] Ошибка загрузки WinDivert: {e}")
            return
        filt = b"tcp and tcp.DstPort == 443 and outbound"
        handle = wd.WinDivertOpen(filt, WD_LAYER_NETWORK, 0, 0)
        if not handle:
            print("[tls] Не удалось открыть WinDivert (нужны права администратора)")
            return
        print("[tls] ClientHello фрагментация активна (TCP:443)")
        buf = ctypes.create_string_buffer(65536)
        addr = WinDivertAddress()
        recv_len = wt.UINT(0)
        while self._running:
            ok = wd.WinDivertRecv(
                handle, buf, 65536, ctypes.byref(addr), ctypes.byref(recv_len)
            )
            if not ok:
                continue
            pkt = buf.raw[: recv_len.value]
            p = _tcp_parse(pkt)
            if p is None or not p["payload"]:
                wd.WinDivertSend(
                    handle, buf, recv_len.value, ctypes.byref(addr), ctypes.byref(recv_len)
                )
                continue
            payload = p["payload"]
            if len(payload) >= 5 and payload[0] == 0x16 and payload[1] == 0x03:
                tls_len = struct.unpack(">H", payload[3:5])[0]
                full = payload[: tls_len + 5] if len(payload) >= tls_len + 5 else payload
                if len(full) > 2:
                    part1 = full[:2]
                    part2 = full[2:]
                    pkt1 = _build_tcp_packet(p, part1, 0)
                    buf1 = ctypes.create_string_buffer(pkt1)
                    ln1 = wt.UINT(len(pkt1))
                    wd.WinDivertSend(handle, buf1, ln1.value, ctypes.byref(addr), ctypes.byref(ln1))
                    pkt2 = _build_tcp_packet(p, part2, 2)
                    buf2 = ctypes.create_string_buffer(pkt2)
                    ln2 = wt.UINT(len(pkt2))
                    time.sleep(0.002)
                    wd.WinDivertSend(handle, buf2, ln2.value, ctypes.byref(addr), ctypes.byref(ln2))
                    continue
            wd.WinDivertSend(
                handle, buf, recv_len.value, ctypes.byref(addr), ctypes.byref(recv_len)
            )
        wd.WinDivertClose(handle)

    def stop(self):
        self._running = False


# --------------------------------------------------- системный DNS
def _set_system_dns(on: bool):
    try:
        out = subprocess.run(
            ["netsh", "interface", "ip", "show", "interfaces"],
            capture_output=True, text=True, timeout=20,
        ).stdout
        names = []
        for line in out.splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 4 and parts[0].isdigit():
                names.append(" ".join(parts[3:]))
        for name in names:
            try:
                if on:
                    subprocess.run(
                        ["netsh", "interface", "ip", "set", "dns", name, "static", "127.0.0.1"],
                        capture_output=True, timeout=20,
                    )
                else:
                    subprocess.run(
                        ["netsh", "interface", "ip", "set", "dns", name, "dhcp"],
                        capture_output=True, timeout=20,
                    )
            except Exception:
                pass
    except Exception:
        pass


def _is_admin() -> bool:
    try:
        return ctypes.windll.shell32.IsUserAnAdmin() != 0
    except Exception:
        return False


# --------------------------------------------------------- main
_dns = None
_tls = None


def start():
    global _dns, _tls
    if not _is_admin():
        print("Нужны права администратора. Запусти консоль от админа.")
        return 1
    _dns = DohDnsProxy()
    _dns.start()
    _tls = TlsFragmentation()
    _tls.start()
    time.sleep(1.0)
    _set_system_dns(True)
    print("[+] keramika-bypass запущен")
    print("    DNS: 127.0.0.1 -> DoH (Cloudflare/Google/Quad9)")
    print("    TLS: ClientHello фрагментация на TCP:443")
    print("    Ctrl+C для остановки")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        stop()


def stop():
    global _dns, _tls
    if _dns:
        _dns.stop()
    if _tls:
        _tls.stop()
    _set_system_dns(False)
    print("[-] keramika-bypass остановлен, DNS возвращён на авто")


def status():
    print("[*] keramika-bypass status")
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.bind(("127.0.0.1", DNS_PORT))
            print("    DNS-прокси: НЕ работает")
    except OSError:
        print("    DNS-прокси: работает на 127.0.0.1:53")
    try:
        out = subprocess.run(
            ["netsh", "interface", "ip", "show", "dnsservers"],
            capture_output=True, text=True, timeout=15,
        ).stdout
        for line in out.splitlines():
            if "127.0.0.1" in line:
                print("    Системный DNS: 127.0.0.1 (обход активен)")
                return
        print("    Системный DNS: не на 127.0.0.1")
    except Exception:
        pass


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Keramika total bypass")
    ap.add_argument("cmd", choices=["start", "stop", "status"])
    args = ap.parse_args()
    if args.cmd == "start":
        sys.exit(start())
    elif args.cmd == "stop":
        stop()
    else:
        status()
