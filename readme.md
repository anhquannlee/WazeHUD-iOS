# 🚗 Waze HUD Pro - Rootless iOS Tweak & Standalone HUD

**Waze HUD Pro** là hệ thống màn hình hiển thị thông tin điều hướng (HUD) lấy dữ liệu từ app Waze Mod. Hệ thống được tinh chỉnh và tối ưu không gian hiển thị xuất sắc cho các dòng máy có màn hình 4.7 inch (**iPhone 6, 7, 8, SE,...**).

Dự án này bao gồm một Tweak (Preference Bundle) tích hợp sâu vào hệ điều hành cho máy Jailbreak Rootless, và một bộ Web/Python Server có thể chạy độc lập đa nền tảng.

## 🌟 Tính năng nổi bật
- **Giao diện tối ưu:** Các thông số tốc độ, biển báo, hướng rẽ to rõ, chống chói lóa.
- **Tích hợp Tweak Rootless:** Tương thích hoàn hảo với Dopamine (iOS 15 - 16). Quản lý cấu hình trực tiếp trong ứng dụng **Cài đặt (Settings)** của iOS.
- **Chạy đa nguồn:** Có thể chạy độc lập làm Trạm phát (Server) trên thiết bị Android, Windows, macOS.
- **Quick Menu:** Chạm nhẹ vào màn hình HUD để mở menu ẩn (Phóng to chữ, Lật gương hắt kính lái, Chế độ Ngày/Đêm).
- **Cảnh báo thông minh:** Hiển thị và nhấp nháy đỏ khi gặp Cảnh sát, Camera phạt nguội, ngã tư đèn đỏ.

## 📦 Hướng dẫn cài đặt cho máy Jailbreak (Rootless)
1. Truy cập mục [Releases](https://github.com/anhquannlee/WazeHUD-iOS/releases) và tải về file `.deb` mới nhất.
2. Mở file bằng **Sileo** hoặc **Zebra** trên thiết bị và chọn Cài đặt.
3. Bấm **Respring** thiết bị sau khi cài xong.
4. Vào **Cài đặt > WazeHUD Pro** để tinh chỉnh hệ thống.

## 💻 Hướng dẫn chạy độc lập (Dành cho Android/PC/Máy không Jailbreak)
Sử dụng các file trong thư mục `standalone_test/`:
1. Yêu cầu thiết bị chủ (nguồn phát) đã cài đặt Python 3.
2. Mở Terminal/CMD, trỏ tới thư mục chứa mã nguồn và chạy lệnh:
   ```bash
   python3 server.py
