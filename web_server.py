"""Сервер для build/web с заголовками no-cache — браузер всегда берёт
свежую сборку, а не кэшированную старую (из-за этого «серые квадраты»)."""
import http.server
import os
import socketserver

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        # Главный фикс: не даём браузеру кэшировать main.dart.js и пр.
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        self.send_header('Pragma', 'no-cache')
        self.send_header('Expires', '0')
        super().end_headers()

    def log_message(self, *args):
        pass


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(('127.0.0.1', 8081), Handler) as httpd:
    httpd.serve_forever()
