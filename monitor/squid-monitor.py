#!/usr/bin/env python3
# squid-monitor.py — Real-time Squid cache monitoring API
# Run: python3 squid-monitor.py
# Repo: https://github.com/budijoi/squid-stb

import os, sys, json, time, threading, re, struct, zlib, logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("squid-monitor")

ACCESS_LOG = "/var/log/squid/access.log"
HOST = "0.0.0.0"
PORT = 8080

stats = {
    "total": 0, "hits": 0, "misses": 0, "tunnels": 0,
    "denied": 0, "errors": 0, "other": 0, "start_time": time.time()
}
recent = []
MAX_RECENT = 100
domains = {}
lock = threading.Lock()

LOG_RE = re.compile(
    r'^(\d+\.\d+)\s+(\d+)\s+(\S+)\s+(\S+)/(\d+)\s+(\d+)\s+(\S+)\s+(\S+)'
)


def cache_size_mb():
    try:
        r = os.popen("du -sb /var/spool/squid 2>/dev/null").read()
        return int(r.split()[0]) / (1024 * 1024) if r else 0
    except Exception:
        return 0


def domain_of(url):
    if url.startswith("http://") or url.startswith("https://"):
        p = url.split("/")
        return p[2] if len(p) > 2 else None
    if "://" not in url and "." in url:
        return url.split(":")[0]
    return None


def tail():
    while True:
        try:
            if not os.path.exists(ACCESS_LOG):
                log.warning("access.log belum ada, menunggu 5 detik...")
                time.sleep(5)
                continue
            f = open(ACCESS_LOG, "r")
            break
        except PermissionError:
            log.error("Tidak bisa membaca %s — izin ditolak. Jalankan monitor sebagai user yang tepat.", ACCESS_LOG)
            time.sleep(10)
        except Exception as e:
            log.error("Gagal membuka access.log: %s", e)
            time.sleep(10)
    log.info("Memantau %s", ACCESS_LOG)
    f.seek(0, 2)
    while True:
        line = f.readline()
        if not line:
            time.sleep(0.3)
            continue
        m = LOG_RE.match(line)
        if not m:
            log.debug("Baris tidak cocok dengan regex: %s", line.rstrip())
            continue
        ts, dur, cli, res, st, sz, meth, url = (
            float(m.group(1)), int(m.group(2)), m.group(3),
            m.group(4), int(m.group(5)), int(m.group(6)),
            m.group(7), m.group(8)
        )
        with lock:
            stats["total"] += 1
            if "HIT" in res:
                stats["hits"] += 1
            elif res == "TCP_MISS":
                stats["misses"] += 1
            elif res == "TCP_TUNNEL":
                stats["tunnels"] += 1
            elif res in ("TCP_DENIED", "TCP_REFRESH_FAIL"):
                stats["denied"] += 1
            elif res.startswith("ERR_"):
                stats["errors"] += 1
            else:
                stats["other"] += 1

            recent.insert(0, {
                "time": time.strftime("%H:%M:%S", time.localtime(ts)),
                "method": meth, "url": url[:90],
                "result": res, "status": st,
                "size": sz, "ms": dur
            })
            if len(recent) > MAX_RECENT:
                recent.pop()

            dom = domain_of(url)
            if dom:
                d = domains.setdefault(dom, {"total": 0, "hits": 0})
                d["total"] += 1
                if "HIT" in res:
                    d["hits"] += 1


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlparse(self.path).path.rstrip("/")
        if path == "/api/stats":
            self.json(self._stats())
        elif path == "/api/recent":
            with lock:
                self.json(recent[:30])
        elif path == "/api/domains":
            with lock:
                top = sorted(domains.items(), key=lambda x: -x[1]["total"])[:40]
                self.json([{"domain": d, **v} for d, v in top])
        elif path == "/":
            self.json({"ok": True, "docs": "/api/stats, /api/recent, /api/domains"})
        else:
            self.send_error(404)

    def _stats(self):
        with lock:
            t = stats["total"]
            h = stats["hits"]
            ratio = round(h / t * 100, 1) if t else 0
            up = int(time.time() - stats["start_time"])
            return {
                "total_requests": t, "cache_hits": h,
                "cache_misses": stats["misses"],
                "cache_tunnels": stats["tunnels"],
                "cache_denied": stats["denied"],
                "cache_errors": stats["errors"],
                "hit_ratio": ratio,
                "cache_size_mb": round(cache_size_mb(), 1),
                "uptime_seconds": up,
                "uptime": f"{up//3600}h {(up%3600)//60}m"
            }

    def json(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def log_message(self, fmt, *a):
        log.info(fmt % a)


def main():
    threading.Thread(target=tail, daemon=True).start()
    srv = HTTPServer((HOST, PORT), Handler)
    log.info("Squid Monitor API → http://%s:%s", HOST, PORT)
    log.info("  /api/stats    — cache statistics")
    log.info("  /api/recent   — recent requests")
    log.info("  /api/domains  — top domains")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        srv.shutdown()


if __name__ == "__main__":
    main()
