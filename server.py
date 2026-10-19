import asyncio
import websockets
import http.server
import socketserver
import threading
import json
import socket

connected_webs = set()

# Lấy địa chỉ IP LAN thực tế của thiết bị
def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

# --- 1. WEBSOCKET SERVER (CỔNG 8765) ---
async def websocket_handler(websocket, path=None):
    # Tương thích ngược với các phiên bản websockets khác nhau
    if path is None:
        if hasattr(websocket, 'path'):
            path = websocket.path
        elif hasattr(websocket, 'request') and hasattr(websocket.request, 'path'):
            path = websocket.request.path
        else:
            path = "/"

    if path == "/hlp":
        print("🟢 [Waze Mod] Điện thoại Waze đã kết nối để truyền dữ liệu!")
        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    if data.get("t") == "ping":
                        await websocket.send('{"v":1,"t":"pong"}\n')
                        continue
                except:
                    pass

                try:
                    data = json.loads(message)
                    message_str = json.dumps(data) + "\n"
                except:
                    message_str = message

                for web in connected_webs.copy():
                    try:
                        await web.send(message_str)
                    except:
                        connected_webs.remove(web)
        except websockets.exceptions.ConnectionClosed:
            print("🔴 [Waze Mod] Waze đã ngắt kết nối!")
            
    elif path == "/web":
        print("🟢 [Web HUD] Màn hình HUD đã mở thành công!")
        connected_webs.add(websocket)
        try:
            real_ip = get_local_ip()
            await websocket.send(json.dumps({
                "type": "sys_info", 
                "ip": real_ip
            }))
            await websocket.wait_closed()
        finally:
            connected_webs.remove(websocket)
            print("🔴 [Web HUD] Màn hình HUD đã đóng!")

# --- 2. HTTP WEB SERVER (CỔNG 8080) ---
def start_web_server():
    
    class QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, format, *args):
            pass 
            
    class ReusableTCPServer(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
            
    port = 8080
    host_ip = get_local_ip()
    
    print("=" * 60)
    print("🚀 HỆ THỐNG WAZE HUD PRO ULTIMATE ĐÃ KHỞI ĐỘNG")
    print("=" * 60)
    print(f"👉 1. Mở màn hình HUD tại: http://localhost:{port} (Hoặc http://{host_ip}:{port})")
    print(f"👉 2. Nhập link sau vào app Waze Mod trên điện thoại để kết nối:")
    print(f"      ws://{host_ip}:8765/hlp")
    print("=" * 60)
    
    # Sử dụng ReusableTCPServer thay vì TCPServer mặc định
    with ReusableTCPServer(("0.0.0.0", port), QuietHandler) as httpd:
        httpd.serve_forever()

# --- 3. CHẠY SONG SONG ---
async def main():
    threading.Thread(target=start_web_server, daemon=True).start()
    
    # Hỗ trợ tương thích cú pháp websockets đời cũ và đời mới
    server_func = websockets.serve
    async with server_func(websocket_handler, "0.0.0.0", 8765):
        await asyncio.Future()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n🛑 Hệ thống đã tắt an toàn.")