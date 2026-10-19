import asyncio
import http.server
import socketserver
import threading
import json
import socket
import sys
import os
import subprocess
import re
import hashlib
import base64
import struct

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# Đọc cổng từ Command Line hoặc dùng mặc định
HTTP_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WS_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765

PID_FILE = "/var/mobile/wazehud.pid"
try:
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
except Exception:
    pass

# Lấy địa chỉ IP LAN thực tế của thiết bị theo thời gian thực
def get_local_ip():
    # 1. Thử kết nối UDP socket tới DNS 8.8.8.8 để tìm IP của interface đang có mạng (Wi-Fi, 4G, Hotspot)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.3)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127."):
            return ip
    except Exception:
        pass

    # 2. Quét ifconfig tìm IP en0 (Wi-Fi), ap1/bridge100 (Hotspot), hoặc các interface khác
    try:
        out = subprocess.check_output(["ifconfig"], stderr=subprocess.DEVNULL, text=True)
        # Ưu tiên Wi-Fi (en0)
        en0_match = re.search(r"en0:.*?\n(?:\s+.*\n)*?\s+inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        if en0_match:
            return en0_match.group(1)
        # Ưu tiên Hotspot (bridge100 hoặc ap1)
        hs_match = re.search(r"(?:bridge100|ap1):.*?\n(?:\s+.*\n)*?\s+inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        if hs_match:
            return hs_match.group(1)
        # Bất kỳ IP nào không phải 127.
        ips = re.findall(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        for cand in ips:
            if not cand.startswith("127."):
                return cand
    except Exception:
        pass

    # 3. Đọc IP do Settings lưu trong plist (nếu có)
    try:
        import plistlib
        plist_path = "/var/mobile/Library/Preferences/com.quanlee.wazehud.plist"
        if os.path.exists(plist_path):
            with open(plist_path, "rb") as f:
                pl = plistlib.load(f)
                dev_ip = pl.get("deviceIP")
                if dev_ip and not str(dev_ip).startswith("127.") and "Không" not in str(dev_ip):
                    return str(dev_ip).strip()
    except Exception:
        pass

    # 4. Quét hostname
    try:
        for item in socket.gethostbyname_ex(socket.gethostname())[2]:
            if not item.startswith("127."):
                return item
    except Exception:
        pass

    return "127.0.0.1"


# ==============================================================
# PURE PYTHON RFC 6455 WEBSOCKET IMPLEMENTATION (ZERO PIP DEPENDENCIES)
# ==============================================================
class SimpleWebSocket:
    def __init__(self, reader, writer, path):
        self.reader = reader
        self.writer = writer
        self.path = path
        self.closed = False

    async def send(self, message):
        if self.closed:
            return
        try:
            data = message.encode('utf-8') if isinstance(message, str) else message
            length = len(data)
            if length <= 125:
                header = struct.pack('!BB', 0x81, length)
            elif length <= 65535:
                header = struct.pack('!BBH', 0x81, 126, length)
            else:
                header = struct.pack('!BBQ', 0x81, 127, length)
            self.writer.write(header + data)
            await self.writer.drain()
        except Exception:
            self.closed = True

    async def recv(self):
        while not self.closed:
            try:
                header = await self.reader.readexactly(2)
                b1, b2 = header[0], header[1]
                opcode = b1 & 0x0F
                masked = bool(b2 & 0x80)
                payload_len = b2 & 0x7F

                if opcode == 0x8:  # Close frame
                    self.closed = True
                    try:
                        self.writer.write(struct.pack('!BB', 0x88, 0))
                        await self.writer.drain()
                    except Exception:
                        pass
                    return None
                elif opcode == 0x9:  # Ping frame -> gửi Pong
                    mask = await self.reader.readexactly(4) if masked else None
                    p_data = await self.reader.readexactly(payload_len) if payload_len > 0 else b""
                    if masked and p_data:
                        p_data = bytes(p_data[i] ^ mask[i % 4] for i in range(len(p_data)))
                    pong_hdr = struct.pack('!BB', 0x8A, len(p_data))
                    self.writer.write(pong_hdr + p_data)
                    await self.writer.drain()
                    continue
                elif opcode == 0xA:  # Pong frame
                    continue

                if payload_len == 126:
                    ext = await self.reader.readexactly(2)
                    payload_len = struct.unpack('!H', ext)[0]
                elif payload_len == 127:
                    ext = await self.reader.readexactly(8)
                    payload_len = struct.unpack('!Q', ext)[0]

                mask = None
                if masked:
                    mask = await self.reader.readexactly(4)

                data = await self.reader.readexactly(payload_len)
                if masked:
                    unmasked = bytearray(len(data))
                    for i in range(len(data)):
                        unmasked[i] = data[i] ^ mask[i % 4]
                    data = bytes(unmasked)

                if opcode in (0x1, 0x2):  # Text or Binary frame
                    return data.decode('utf-8', errors='ignore')
            except Exception:
                self.closed = True
                return None
        return None

    def close(self):
        self.closed = True
        try:
            self.writer.close()
        except Exception:
            pass


connected_webs = set()

async def handle_client(reader, writer):
    # Đọc chunk đầu tiên để xác định giao thức (WebSocket, Raw TCP Socket hay HTTP)
    try:
        initial_chunk = await asyncio.wait_for(reader.read(1024), timeout=15.0)
    except Exception:
        writer.close()
        return

    if not initial_chunk:
        writer.close()
        return

    # KIỂM TRA 1: Có phải HTTP / WebSocket Request hay không?
    if initial_chunk.startswith((b"GET ", b"POST ", b"HEAD ", b"PUT ", b"OPTIONS ")):
        req = initial_chunk
        while b"\r\n\r\n" not in req:
            try:
                chunk = await asyncio.wait_for(reader.read(1024), timeout=5.0)
            except Exception:
                break
            if not chunk:
                break
            req += chunk
            if len(req) > 16384:
                break

        req_str = req.decode('utf-8', errors='ignore')
        lines = req_str.split("\r\n")
        first_line_parts = lines[0].split()
        path = first_line_parts[1] if len(first_line_parts) > 1 else "/"

        key = None
        for line in lines[1:]:
            if line.lower().startswith("sec-websocket-key:"):
                key = line.split(":", 1)[1].strip()
                break

        # Nếu không có Sec-WebSocket-Key: Trả về HTTP thông báo dịch vụ đang hoạt động
        if not key:
            resp = (
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: text/plain; charset=utf-8\r\n"
                "Connection: close\r\n\r\n"
                f"WazeHUD Service Running. WebSocket Port: {WS_PORT}, Web HUD Port: {HTTP_PORT}\n"
            )
            writer.write(resp.encode())
            try:
                await writer.drain()
            except Exception:
                pass
            writer.close()
            return

        # WebSocket Handshake (HTTP 101 Switching Protocols)
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        resp = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        )
        writer.write(resp.encode())
        await writer.drain()

        ws = SimpleWebSocket(reader, writer, path)

        # Phân loại Client WebSocket: Web HUD (/web) hay Waze Mod (bất kỳ đường dẫn nào khác)
        if "web" in path.lower():
            print(f"🟢 [Web HUD] Màn hình HUD đã kết nối!")
            connected_webs.add(ws)
            try:
                real_ip = get_local_ip()
                await ws.send(json.dumps({
                    "type": "sys_info",
                    "ip": real_ip,
                    "port": WS_PORT
                }))
                while not ws.closed:
                    msg = await ws.recv()
                    if msg is None:
                        break
            finally:
                connected_webs.discard(ws)
                ws.close()
                print("🔴 [Web HUD] Màn hình HUD đã đóng.")
        else:
            # Client Waze Mod kết nối qua WebSocket (ví dụ ws://ip:port/hlp hoặc ws://ip:port/)
            print(f"🟢 [Waze Mod - WebSocket] App Waze đã kết nối thành công qua đường dẫn: {path}")
            try:
                while not ws.closed:
                    msg = await ws.recv()
                    if msg is None:
                        break

                    try:
                        data = json.loads(msg)
                        if data.get("t") == "ping":
                            await ws.send('{"v":1,"t":"pong"}\n')
                            continue
                    except Exception:
                        pass

                    # Chuyển tiếp ngay lập tức toàn bộ dữ liệu Waze sang tất cả Web HUD đang mở
                    msg_to_send = msg if msg.endswith('\n') else (msg + '\n')
                    for web in list(connected_webs):
                        try:
                            asyncio.create_task(web.send(msg_to_send))
                        except Exception:
                            connected_webs.discard(web)
            finally:
                ws.close()
                print("🔴 [Waze Mod - WebSocket] App Waze đã ngắt kết nối.")

    # KIỂM TRA 2: Client kết nối qua Raw TCP Socket (gửi JSON stream phân cách bởi \n)
    else:
        print("🟢 [Waze Mod - Raw TCP] App Waze đã kết nối trực tiếp qua TCP Socket!")
        buf = initial_chunk
        try:
            while True:
                while b"\n" in buf:
                    line_bytes, buf = buf.split(b"\n", 1)
                    line = line_bytes.decode('utf-8', errors='ignore').strip()
                    if not line:
                        continue

                    # Xử lý Ping / Pong
                    try:
                        data = json.loads(line)
                        if data.get("t") == "ping":
                            writer.write(b'{"v":1,"t":"pong"}\n')
                            await writer.drain()
                            continue
                    except Exception:
                        pass

                    # Chuyển tiếp sang Web HUD
                    msg_to_send = line + "\n"
                    for web in list(connected_webs):
                        try:
                            asyncio.create_task(web.send(msg_to_send))
                        except Exception:
                            connected_webs.discard(web)

                chunk = await reader.read(4096)
                if not chunk:
                    break
                buf += chunk
        except Exception:
            pass
        finally:
            writer.close()
            print("🔴 [Waze Mod - Raw TCP] App Waze đã ngắt kết nối.")


# ==============================================================
# HTTP WEB SERVER (CỔNG HTTP_PORT)
# ==============================================================
def start_web_server():
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format, *args):
            pass 

        def do_GET(self):
            # Cung cấp IP và Cổng cho Web UI
            if self.path == "/api/info":
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                info = {
                    "ip": get_local_ip(),
                    "ws_port": WS_PORT,
                    "http_port": HTTP_PORT
                }
                self.wfile.write(json.dumps(info).encode("utf-8"))
                return
            return super().do_GET()
            
    class ReusableTCPServer(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
            
    host_ip = get_local_ip()
    
    print("=" * 60)
    print("🚀 HỆ THỐNG WAZE HUD PRO ULTIMATE ĐÃ KHỞI ĐỘNG")
    print("=" * 60)
    print(f"👉 1. Mở màn hình HUD tại: http://localhost:{HTTP_PORT} (Hoặc http://{host_ip}:{HTTP_PORT})")
    print(f"👉 2. Nhập thông tin sau vào App Waze Mod trên điện thoại:")
    print(f"      IP: {host_ip}   Port: {WS_PORT}")
    print("=" * 60)
    
    web_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(web_dir)
    
    with ReusableTCPServer(("0.0.0.0", HTTP_PORT), QuietHandler) as httpd:
        httpd.serve_forever()


# ==============================================================
# CHẠY SONG SONG CẢ HAI SERVER (HTTP + WEBSOCKET/TCP)
# ==============================================================
async def main():
    # 1. Chạy HTTP Server trên thread riêng (cổng 8080)
    threading.Thread(target=start_web_server, daemon=True).start()
    
    # 2. Chạy WebSocket/TCP Server chuẩn RFC 6455 (cổng 8765) trên main thread
    server = await asyncio.start_server(handle_client, "0.0.0.0", WS_PORT)
    print(f"📡 Waze Socket/WebSocket Server đang lắng nghe tại 0.0.0.0:{WS_PORT}")
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n🛑 Hệ thống đã tắt an toàn.")