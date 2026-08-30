#!/usr/bin/env python3
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "0.0.0.0"
PORT = 7010
FILE = "jsonsave.json"

def save_data(data):
    # Selalu overwrite: file hanya berisi SATU object/data terbaru.
    with open(FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)

def load_data():
    try:
        with open(FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}

class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_json(204, {})

    def do_GET(self):
        if self.path == "/data":
            self.send_json(200, load_data())
        else:
            self.send_json(404, {"success": False, "error": "Not found"})

    def do_POST(self):
        if self.path == "/save":
            try:
                length = int(self.headers.get("Content-Length", 0))
                raw = self.rfile.read(length)
                data = json.loads(raw)

                if not isinstance(data, dict):
                    raise ValueError("Data harus berupa JSON object")

                # Timpa data lama. Tidak ada append/list.
                save_data(data)
                self.send_json(200, {
                    "success": True,
                    "message": "Data saved",
                    "data": data
                })
            except Exception as e:
                self.send_json(400, {"success": False, "error": str(e)})

        elif self.path == "/clear":
            save_data({})
            self.send_json(200, {"success": True})

        else:
            self.send_json(404, {"success": False, "error": "Not found"})

    def log_message(self, fmt, *args):
        print("[%s] %s" % (self.log_date_time_string(), fmt % args))

if __name__ == "__main__":
    print(f"Youtube Saver server running on http://127.0.0.1:{PORT}")
    print(f"Saving only the latest data to: {FILE}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
