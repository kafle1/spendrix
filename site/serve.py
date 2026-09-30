#!/usr/bin/env python3
"""Serves build/site the way firebase hosting does. Run: python3 site/serve.py [port]"""
import http.server, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'build', 'site')


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.exists(path):
            return super().send_head()
        if self.path.split('?')[0].startswith('/app/'):
            self.path = '/app/index.html'
            return super().send_head()
        self.path = '/404.html'
        f = super().send_head()
        return f

    def send_response(self, code, message=None):
        if code == 200 and self.path == '/404.html':
            code = 404
        super().send_response(code, message)

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
