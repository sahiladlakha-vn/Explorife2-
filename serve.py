import os, http.server, socketserver, functools

PORT = int(os.environ.get("PORT", 8080))
DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=DIR)

with socketserver.TCPServer(("", PORT), handler) as httpd:
    print(f"Serving {DIR} on port {PORT}")
    httpd.serve_forever()
