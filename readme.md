# 🚗 Waze HUD Pro - iOS Tweak & Standalone HUD

**Waze HUD Pro** là hệ thống màn hình hiển thị thông tin điều hướng hắt kính lái (HUD) chuyên nghiệp, nhận dữ liệu trực tiếp từ app Waze Mod. Hệ thống sở hữu giao diện thông minh có khả năng **tự động co giãn (Responsive)**, hiển thị xuất sắc và tràn viền trên **mọi kích thước màn hình** từ điện thoại cũ đến các dòng máy tràn viền tai thỏ hiện đại.

Dự án cung cấp 2 phương thức sử dụng: Tích hợp sâu vào hệ điều hành dưới dạng **Tweak cho máy Jailbreak (iOS 9 - 16+)**, hoặc chạy độc lập đa nền tảng thông qua **Python Server**.

*(Đã test hoạt động mượt mà và ổn định trên iPhone 8 - Rootless iOS 16.7.11)*

---

## 🌟 Tính năng nổi bật
- **Giao diện Responsive & Safe-area:** Tự động nhận diện và né các vùng "tai thỏ", "Dynamic Island" hay thanh Home Bar trên iOS đời cao. Cân đối hoàn hảo trên mọi tỷ lệ màn hình.
- **Tối ưu hóa hiệu năng (Anti-Lag):** Khóa cứng khung giao diện, sử dụng font số `tabular-nums` và loại bỏ các hiệu ứng đồ họa nặng để đảm bảo số liệu nhảy siêu mượt mà không gây nóng máy.
- **Tích hợp Tweak (iOS 9 - 16+):** Tương thích hoàn hảo với các môi trường Rootless (như Dopamine) và Rootful. Quản lý bật/tắt dịch vụ trực tiếp trong ứng dụng **Cài đặt (Settings)** của iOS.
- **Floating Menu (Nút Menu nổi):** Menu điều khiển ẩn/hiện thông minh giúp tùy chỉnh: 3 nấc kích cỡ, Lật gương (Ngang/Dọc), Giao diện Ngày/Đêm, và Bật/tắt cảnh báo vượt tốc độ.
- **Luôn sáng màn hình (WakeLock):** Giữ cho thiết bị hiển thị HUD không bao giờ bị tắt màn hình (Hỗ trợ Bypass policy của Safari trên iOS đời cao).
- **Cảnh báo thông minh:** Hiển thị rõ ràng Camera phạt nguội, Cảnh sát, Nguy hiểm... Vòng tốc độ sẽ nhấp nháy đỏ rực nếu xe chạy quá giới hạn tốc độ cho phép.

---

## 📦 Hướng dẫn cài đặt 1: Dành cho máy Jailbreak (iOS 9 - 16+)
Phương pháp này giúp server chạy ngầm ổn định cùng hệ thống iOS.

1. Truy cập mục [Releases](https://github.com/anhquannlee/WazeHUD-iOS/releases) và tải về file `.deb` mới nhất.
2. Mở file bằng các trình quản lý gói như **Sileo**, **Zebra** hoặc **Filza** và tiến hành cài đặt.
3. Chờ quá trình cài đặt hoàn tất và bấm **Restart SpringBoard (Respring)**.
4. Mở ứng dụng **Cài đặt (Settings) > WazeHUD Pro** để bật dịch vụ.
5. Mở trình duyệt Safari trên cùng máy đó (hoặc máy khác cùng mạng Wi-Fi) và truy cập `http://localhost:8080` (hoặc `http://<IP_Của_Điện_Thoại>:8080`).

---

## 💻 Hướng dẫn cài đặt 2: Chạy độc lập (Python Server Manual)
Dành cho các thiết bị Android, Windows, macOS, hoặc iOS chưa Jailbreak.

1. Yêu cầu thiết bị chủ (nguồn phát) đã cài đặt **Python 3**.
2. Tải mã nguồn về, mở Terminal/CMD, trỏ tới thư mục dự án (nơi chứa file `server.py` và `index.html`).
3. Chạy lệnh khởi động máy chủ:
   ```bash
   python3 server.py
4. có gì thì dùng AI hoặc hỏi trên github để được giải đáp
