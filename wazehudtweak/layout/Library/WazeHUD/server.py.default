import asyncio
import http.server
import socketserver
import threading
import json
import socket
import os
import sys
import struct
import base64
import hashlib
import re
import subprocess

connected_webs = set()

# Đọc cổng từ Command Line hoặc dùng mặc định
HTTP_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WS_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8765

PID_FILE = "/var/mobile/wazehud.pid"
try:
    with open(PID_FILE, "w") as f:
        f.write(str(os.getpid()))
except Exception:
    pass

# Lấy địa chỉ IP LAN thực tế của thiết bị
def get_local_ip():
    # 1. Thử UDP connect tới 8.8.8.8
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(0.5)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127."):
            return ip
    except Exception:
        pass

    # 2. Đọc IP từ plist tweak (do Settings lưu khi mở menu)
    try:
        plist_path = "/var/mobile/Library/Preferences/com.quanlee.wazehud.plist"
        if os.path.exists(plist_path):
            import plistlib
            with open(plist_path, "rb") as f:
                pl = plistlib.load(f)
                dev_ip = pl.get("deviceIP")
                if dev_ip and not str(dev_ip).startswith("127.") and "Không" not in str(dev_ip):
                    return str(dev_ip).strip()
    except Exception:
        pass

    # 3. Quét qua ifconfig tìm interface Wi-Fi (en0) hoặc Hotspot (bridge100 / ap1)
    try:
        out = subprocess.check_output(["ifconfig"], stderr=subprocess.DEVNULL, text=True)
        m = re.search(r"en0:.*?\n(?:\s+.*\n)*?\s+inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        if m and not m.group(1).startswith("127."):
            return m.group(1)
        m = re.search(r"(?:bridge100|ap1):.*?\n(?:\s+.*\n)*?\s+inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        if m and not m.group(1).startswith("127."):
            return m.group(1)
        ips = re.findall(r"inet\s+(\d+\.\d+\.\d+\.\d+)", out)
        for cand in ips:
            if not cand.startswith("127."):
                return cand
    except Exception:
        pass

    return "127.0.0.1"


# ==============================================================
# WEBSOCKET WRAPPER CHUẨN RFC 6455 (HỖ TRỢ KHÓA GHI & ĐÓNG AN TOÀN)
# ==============================================================
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

class UnifiedWebSocket:
    def __init__(self, reader, writer, path, subprotocol=None):
        self.reader = reader
        self.writer = writer
        self.path = path
        self.subprotocol = subprotocol
        self.closed = False
        self._send_lock = asyncio.Lock()
        self._close_event = asyncio.Event()

    async def send(self, message):
        if self.closed:
            return
        async with self._send_lock:
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
                self._close_event.set()

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
                    self._close_event.set()
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
                    async with self._send_lock:
                        self.writer.write(struct.pack('!BB', 0x8A, len(p_data)) + p_data)
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

                if opcode in (0x1, 0x2):  # Text hoặc Binary frame
                    return data.decode('utf-8', errors='ignore')
            except Exception:
                self.closed = True
                self._close_event.set()
                return None
        return None

    async def wait_closed(self):
        await self._close_event.wait()

    def __aiter__(self):
        return self

    async def __anext__(self):
        msg = await self.recv()
        if msg is None or self.closed:
            raise StopAsyncIteration
        return msg


# ==============================================================
# BỘ XỬ LÝ KẾT NỐI ĐA GIAO THỨC (WEBSOCKET + SUBPROTOCOLS + RAW TCP)
# ==============================================================
async def handle_client_connection(reader, writer):
    # Đọc chunk dữ liệu đầu tiên để xác định giao thức
    try:
        initial_chunk = await asyncio.wait_for(reader.read(1024), timeout=15.0)
    except Exception:
        try:
            writer.close()
        except Exception:
            pass
        return

    if not initial_chunk:
        try:
            writer.close()
        except Exception:
            pass
        return

    # KIỂM TRA 1: KẾT NỐI WEBSOCKET / HTTP
    if initial_chunk.startswith((b"GET ", b"POST ", b"HEAD ", b"PUT ", b"OPTIONS ")):
        req = initial_chunk
        while b"\r\n\r\n" not in req:
            try:
                chunk = await asyncio.wait_for(reader.read(1024), timeout=5.0)
                if not chunk:
                    break
                req += chunk
                if len(req) > 16384:
                    break
            except Exception:
                break

        req_str = req.decode('utf-8', errors='ignore')
        lines = req_str.split("\r\n")
        first_line_parts = lines[0].split()
        path = first_line_parts[1] if len(first_line_parts) > 1 else "/"
        clean_path = path.split("?")[0].rstrip("/")

        key = None
        subprotocol = None
        for line in lines[1:]:
            l_lower = line.lower()
            if l_lower.startswith("sec-websocket-key:"):
                key = line.split(":", 1)[1].strip()
            elif l_lower.startswith("sec-websocket-protocol:"):
                # Bắt subprotocol mà WazeMod yêu cầu (ví dụ: hlp.v1)
                raw_protos = line.split(":", 1)[1].strip()
                protos = [p.strip() for p in raw_protos.split(",") if p.strip()]
                if protos:
                    subprotocol = protos[0]

        # Nếu không có Sec-WebSocket-Key: Trả về HTTP thông báo dịch vụ
        if not key:
            resp = (
                "HTTP/1.1 200 OK\r\n"
                "Content-Type: text/plain; charset=utf-8\r\n"
                "Connection: close\r\n\r\n"
                f"WazeHUD Service Running. Port: {WS_PORT}\n"
            )
            writer.write(resp.encode())
            try:
                await writer.drain()
                writer.close()
            except Exception:
                pass
            return

        # Handshake WebSocket (HTTP 101 Switching Protocols)
        # QUAN TRỌNG: Phải phản hồi đúng Sec-WebSocket-Protocol nếu client yêu cầu (như WazeMod với hlp.v1)
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        resp_lines = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            f"Sec-WebSocket-Accept: {accept}"
        ]
        if subprotocol:
            resp_lines.append(f"Sec-WebSocket-Protocol: {subprotocol}")
        resp_lines.append("\r\n")
        resp = "\r\n".join(resp_lines).encode()
        writer.write(resp)
        await writer.drain()

        ws = UnifiedWebSocket(reader, writer, path, subprotocol)

        # PHÂN LOẠI CLIENT:
        # Nếu path là /web hoặc chứa 'web' -> Là Web HUD (Màn hình hiển thị)
        # TẤT CẢ các đường dẫn còn lại (/hlp, /, /waze, /ws, ...) -> Đều là Nguồn phát Waze Mod!
        if clean_path == "/web" or "web" in path.lower():
            print(f"🟢 [Web HUD] Màn hình HUD đã mở thành công!")
            connected_webs.add(ws)
            try:
                real_ip = get_local_ip()
                await ws.send(json.dumps({
                    "type": "sys_info",
                    "ip": real_ip,
                    "port": WS_PORT
                }))
                await ws.wait_closed()
            finally:
                connected_webs.discard(ws)
                print("🔴 [Web HUD] Màn hình HUD đã đóng!")
        else:
            print(f"🟢 [Waze Mod - WebSocket] Nguồn phát Waze đã kết nối thành công! (Path: {path}, Subprotocol: {subprotocol})")
            try:
                async for message in ws:
                    try:
                        data = json.loads(message)
                        if data.get("t") == "ping":
                            await ws.send('{"v":1,"t":"pong"}\n')
                            continue
                    except Exception:
                        pass

                    # Chuyển tiếp ngay lập tức toàn bộ dữ liệu Waze sang tất cả Web HUD đang mở
                    msg_to_send = message if message.endswith('\n') else (message + '\n')
                    for web in connected_webs.copy():
                        try:
                            await web.send(msg_to_send)
                        except Exception:
                            connected_webs.discard(web)
            except Exception:
                pass
            finally:
                print("🔴 [Waze Mod - WebSocket] Nguồn phát Waze đã ngắt kết nối.")

    # KIỂM TRA 2: KẾT NỐI RAW TCP SOCKET (gửi stream JSON trực tiếp phân cách bởi \n)
    else:
        print("🟢 [Waze Mod - Raw TCP] Nguồn phát Waze đã kết nối trực tiếp qua TCP Socket!")
        buf = initial_chunk
        try:
            while True:
                while b"\n" in buf:
                    line_bytes, buf = buf.split(b"\n", 1)
                    line = line_bytes.decode('utf-8', errors='ignore').strip()
                    if not line:
                        continue

                    # Bắt và phản hồi Ping -> Pong
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
                    for web in connected_webs.copy():
                        try:
                            await web.send(msg_to_send)
                        except Exception:
                            connected_webs.discard(web)

                chunk = await reader.read(4096)
                if not chunk:
                    break
                buf += chunk
        except Exception:
            pass
        finally:
            try:
                writer.close()
            except Exception:
                pass
            print("🔴 [Waze Mod - Raw TCP] Nguồn phát Waze đã ngắt kết nối.")


# ==============================================================
# HTTP WEB SERVER (CỔNG HTTP_PORT, PHỤC VỤ INDEX.HTML)
# ==============================================================
def start_web_server():
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format, *args):
            pass 

        def do_GET(self):
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
            
    port = HTTP_PORT
    host_ip = get_local_ip()
    
    print("=" * 60)
    print("🚀 HỆ THỐNG WAZE HUD PRO ULTIMATE ĐÃ KHỞI ĐỘNG")
    print("=" * 60)
    print(f"👉 1. Màn hình HUD (Web): http://localhost:{port} (Hoặc http://{host_ip}:{port})")
    print(f"👉 2. Nhập thông tin sau vào App Waze Mod trên điện thoại để kết nối:")
    print(f"      IP: {host_ip}   Port: {WS_PORT}")
    print("=" * 60)
    
    web_dir = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
    os.chdir(web_dir)
    
    with ReusableTCPServer(("0.0.0.0", port), QuietHandler) as httpd:
        httpd.serve_forever()


# ==============================================================
# CHẠY SONG SONG CẢ HAI SERVER
# ==============================================================
async def main():
    # 1. Chạy HTTP Web Server trên thread riêng (cổng HTTP_PORT)
    threading.Thread(target=start_web_server, daemon=True).start()
    
    # 2. Chạy Socket/WebSocket Server trên main thread (cổng WS_PORT)
    # Lắng nghe 0.0.0.0 trên WS_PORT, hỗ trợ tất cả: WebSocket (hlp.v1, root /, /hlp,...) & Raw TCP Socket
    server = await asyncio.start_server(handle_client_connection, "0.0.0.0", WS_PORT)
    print(f"📡 Waze Server đang lắng nghe tại 0.0.0.0:{WS_PORT}")
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n🛑 Hệ thống đã tắt an toàn.")