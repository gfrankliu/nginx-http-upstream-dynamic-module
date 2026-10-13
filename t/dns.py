# Minimal DNS server for tests: answers A queries on 127.0.0.1:5353 from a
# JSON file re-read on every query, e.g. {"localhost": ["127.0.0.2"]},
# {"drop": true}, {"nxdomain": true} or {"delay": 2}.
import socket, struct, json, sys, time, threading
cfgf = sys.argv[1]
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 5353))
def handle(data, addr):
    cfg = json.load(open(cfgf))
    if cfg.get("drop"): return
    time.sleep(cfg.get("delay", 0))
    tid, flags, qd = struct.unpack(">HHH", data[:6])
    i = 12; labels = []
    while data[i]:
        l = data[i]; labels.append(data[i+1:i+1+l].decode()); i += l + 1
    qtype = struct.unpack(">H", data[i+1:i+3])[0]
    q = data[12:i+5]
    name = ".".join(labels).lower()
    ips = cfg.get(name, []) if qtype == 1 else []
    rcode = 3 if cfg.get("nxdomain") else 0
    ans = b""
    for ip in ips:
        ans += b"\xc0\x0c" + struct.pack(">HHIH", 1, 1, cfg.get("ttl", 1), 4) + socket.inet_aton(ip)
    hdr = struct.pack(">HHHHHH", tid, 0x8180 | rcode, 1, len(ips), 0, 0)
    s.sendto(hdr + q + ans, addr)
while True:
    data, addr = s.recvfrom(512)
    threading.Thread(target=handle, args=(data, addr), daemon=True).start()
