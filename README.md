# 🎥 Camera Evidence System POC

Hệ thống trích xuất và chia sẻ video Camera an ninh (NVR Hikvision) thông minh, an toàn và dễ sử dụng. Dự án này được thiết kế để giải quyết bài toán: **Làm sao để chia sẻ một đoạn video từ Camera cho khách hàng xem qua điện thoại/Web mà KHÔNG bị lộ địa chỉ IP và Mật khẩu của đầu ghi.**

## ✨ Tính năng nổi bật
* **🔒 Bảo mật tuyệt đối:** Hoạt động như một cầu nối (Proxy). Người xem chỉ thấy IP của Server Node.js, hoàn toàn ẩn danh hệ thống NVR gốc.
* **🔑 Token 1 lần (Magic Link):** Cấp quyền truy cập bằng Token có thời hạn (1 giờ, 24 giờ, 7 ngày). Khi hết hạn hoặc bị Thu hồi, link tự động trở thành rác.
* **📱 Xem trực tiếp trên Trình duyệt:** Không cần cài đặt bất kỳ Plugin hay App nào. Tương thích 100% với iPhone, Android, Chrome, Edge (Sử dụng công nghệ `JSMpeg`).
* **⏳ Tua lại dòng thời gian (Timeline):** Cho phép nhảy đến các mốc thời gian xem lại một cách linh hoạt mà không bị gián đoạn.
* **🚀 Quản trị bằng GUI trực quan:** Giao diện Quản trị viết bằng PowerShell chuẩn Windows, tích hợp nút Bật/Tắt Server chạy ngầm cực kỳ tiện lợi.
* **⚡ Tự động hóa cài đặt (Plug & Play):** Tự động phát hiện và tải lõi xử lý `FFmpeg` (130MB) từ GitHub nếu máy chủ chưa được cài đặt.

## 🏗 Kiến trúc hệ thống
Hệ thống bao gồm 3 thành phần chính:
1. **Admin UI (`AdminApp.ps1`):** Ứng dụng PowerShell giao diện đồ họa. Dùng để khởi động Server, chọn Camera, chọn mốc thời gian và sinh ra các Link chia sẻ (Magic Link). Quản lý và thu hồi Token.
2. **Node.js Server (`server.js`):** Xử lý API, xác thực Token, mở WebSocket. Đóng vai trò làm Proxy gọi lệnh `FFmpeg` để kéo luồng RTSP từ NVR và mã hóa trực tiếp thành chuẩn MPEG-1 nén.
3. **Web Client (`public/index.html`):** Giao diện cho người xem cuối. Sử dụng Canvas và thư viện `JSMpeg` để giải mã luồng WebSocket thành Video trên trình duyệt.

## 🚀 Hướng dẫn cài đặt và sử dụng

### 1. Yêu cầu hệ thống
- Máy tính chạy Windows 10/11 (Hoặc Windows Server).
- Cài đặt sẵn [Node.js](https://nodejs.org/).
- *(Không yêu cầu cài thêm phần mềm giả lập, hệ thống tự động xử lý mọi rào cản).*

### 2. Cài đặt
1. **Clone dự án:**
   ```bash
   git clone https://github.com/hoafd/Cam-poc.git
   cd Cam-poc
   ```
2. **Cài đặt thư viện Node.js:**
   ```bash
   npm install
   ```
3. **Cấu hình NVR:**
   - Đổi tên file `config.example.json` thành `config.json`.
   - Mở file `config.json` và điền IP, User, Password của các Đầu ghi NVR vào hệ thống.

### 3. Vận hành
1. Nhấn đúp chuột vào file `AdminApp.ps1` (Nếu bị chặn, chuột phải chọn *Run with PowerShell*).
2. *(Lần đầu tiên)* Phần mềm sẽ tự động kiểm tra và hỏi bạn tải file `ffmpeg.exe` về thư mục dự án. Hãy chọn **Yes** và đợi vài phút.
3. Bấm nút **"▶ KHỞI ĐỘNG MÁY CHỦ (CHẠY ẨN)"** ở góc dưới cùng phần mềm.
4. Chọn Đầu ghi, Camera, Thời gian và tạo Link chia sẻ.
5. Sao chép link và gửi cho khách hàng trải nghiệm!

## ⚠️ Lưu ý kỹ thuật (Về tính năng Tua nhanh 4x, 8x)
Hệ thống hiện tại lấy luồng video qua giao thức mở **RTSP (Port 554)**. Do giới hạn phần cứng của Hikvision NVR, cổng RTSP chỉ hỗ trợ xuất dữ liệu ở tốc độ thời gian thực (1x). Để giải quyết bài toán Tua nhanh, tính năng tải qua bộ đệm RAM bằng giao thức **ISAPI (Port 80 - Digest Auth)** đang được thử nghiệm, nhưng yêu cầu tất cả NVR phải mở cổng HTTP. Do đó, hệ thống hiện tại ưu tiên tối ưu hóa **Thanh điều hướng Timeline** làm phương án xem lại chính thức.

---
*Dự án POC (Proof of Concept) được xây dựng cho hệ thống trích xuất Camera bằng chứng.*
