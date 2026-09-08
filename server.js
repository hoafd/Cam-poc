const express = require('express');
const { WebSocketServer } = require('ws');
const { spawn } = require('child_process');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');

// --- 1. TẢI CẤU HÌNH TỪ FILE config.json ---
const configPath = path.join(__dirname, 'config.json');
let CONFIG;
try {
    const rawData = fs.readFileSync(configPath, 'utf-8');
    CONFIG = JSON.parse(rawData);
    console.log(`[HỆ THỐNG] Đã tải cấu hình từ config.json thành công.`);
} catch (error) {
    console.error("LỖI NGHIÊM TRỌNG: Không thể đọc file config.json.");
    process.exit(1);
}

const HTTP_PORT = CONFIG.server.httpPort || 3000;
const WS_PORT = CONFIG.server.wsPort || 3001;
const NVRS = CONFIG.nvrs || {};

// --- 2. CƠ SỞ DỮ LIỆU TOKEN (LƯU VÀO FILE tokens.json) ---
const tokenDbPath = path.join(__dirname, 'tokens.json');
let TOKEN_DB = {};

function loadTokens() {
    if (fs.existsSync(tokenDbPath)) {
        try {
            const raw = fs.readFileSync(tokenDbPath, 'utf-8');
            TOKEN_DB = JSON.parse(raw);
        } catch(e) { 
            console.error("Không thể đọc tokens.json, tạo mới."); 
        }
    }
}

function saveTokens() {
    fs.writeFileSync(tokenDbPath, JSON.stringify(TOKEN_DB, null, 2));
}

// Gọi hàm nạp token khi khởi động
loadTokens();

const app = express();
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

// API gửi cấu hình cho Frontend
app.get('/api/config', (req, res) => {
    res.json({ wsPort: WS_PORT });
});

// --- 3. CÁC API DÀNH CHO TRANG QUẢN TRỊ ADMIN ---

// [API] Tạo Token Mới
app.post('/api/generate-token', (req, res) => {
    const { nvrId, camId, description, expireHours, playbackStart, playbackEnd } = req.body;
    
    if (!nvrId || !camId) return res.status(400).json({ error: 'Thiếu thông tin NVR/Camera' });
    if (!NVRS[nvrId]) return res.status(400).json({ error: 'NVR không tồn tại trong config.json' });
    if (!playbackStart || !playbackEnd) return res.status(400).json({ error: 'Thiếu thời gian Bắt đầu / Kết thúc xem lại' });

    const newToken = crypto.randomBytes(8).toString('hex');
    const now = Date.now();
    let expiresAt = null;
    
    // Tính toán thời gian hết hạn nếu có
    if (expireHours && expireHours > 0) {
        expiresAt = now + (expireHours * 60 * 60 * 1000);
    }

    TOKEN_DB[newToken] = {
        nvrId: nvrId.toString(),
        camId: camId.toString(),
        description: description || 'Không có ghi chú',
        createdAt: now,
        expiresAt: expiresAt,
        playbackStart: playbackStart,
        playbackEnd: playbackEnd
    };
    saveTokens(); // Ghi xuống ổ cứng ngay lập tức
    
    console.log(`[API ADMIN] Đã tạo Token: ${newToken} (Hết hạn sau: ${expireHours ? expireHours+'h' : 'Vĩnh viễn'})`);
    res.json({ success: true, token: newToken });
});

// [API] Lấy Danh Sách Token Hiện Có
app.get('/api/tokens', (req, res) => {
    const tokens = Object.keys(TOKEN_DB).map(token => {
        return {
            token: token,
            ...TOKEN_DB[token]
        };
    });
    res.json({ success: true, tokens: tokens });
});

// [API] Xem thông tin giới hạn của Token (Dành cho trình duyệt Web)
app.get('/api/token-info', (req, res) => {
    const { token } = req.query;
    if (TOKEN_DB[token]) {
        res.json({ 
            success: true, 
            playbackStart: TOKEN_DB[token].playbackStart, 
            playbackEnd: TOKEN_DB[token].playbackEnd 
        });
    } else {
        res.status(404).json({ error: 'Token không tồn tại hoặc đã bị xóa' });
    }
});

// [API] Xóa/Thu Hồi Token
app.post('/api/delete-token', (req, res) => {
    const { token } = req.body;
    if (TOKEN_DB[token]) {
        delete TOKEN_DB[token];
        saveTokens();
        
        // CHỨC NĂNG ĐẶC BIỆT: Đuổi cổ ngay lập tức những người đang dùng Token này xem camera
        wss.clients.forEach(client => {
            if (client.clientToken === token) {
                console.log(`[BẢO MẬT] Đang "ĐÁ" kết nối của Token vừa bị thu hồi: ${token}`);
                client.close();
            }
        });
        
        console.log(`[API ADMIN] Đã thu hồi và xóa vĩnh viễn Token: ${token}`);
        res.json({ success: true });
    } else {
        res.status(404).json({ error: 'Không tìm thấy Token trong hệ thống' });
    }
});

app.listen(HTTP_PORT, () => {
    console.log(`[HTTP] Web Server & API chạy tại: http://localhost:${HTTP_PORT}`);
});

// --- 4. WEBSOCKET SERVER TRUYỀN VIDEO ---
const wss = new WebSocketServer({ port: WS_PORT }, () => {
    console.log(`[WS] WebSocket chạy tại port: ${WS_PORT}`);
});

wss.on('connection', (ws, req) => {
    const baseURL = req.headers.host ? `http://${req.headers.host}` : 'http://localhost';
    const parsedUrl = new URL(req.url, baseURL);
    const clientToken = parsedUrl.searchParams.get('token');
    const reqStart = parsedUrl.searchParams.get('start'); // Tham số "Tua" từ Web
    
    // Lưu lại mã token của client này vào biến cục bộ để dễ dàng kiểm tra và "đá" (nếu bị xóa)
    ws.clientToken = clientToken; 

    const permission = TOKEN_DB[clientToken];

    // Kiểm tra tính hợp lệ
    if (!clientToken || !permission) {
        console.log(`[WS] TỪ CHỐI BẢO MẬT: Kết nối mang sai Token (${clientToken})`);
        ws.close();
        return;
    }

    // KIỂM TRA HẾT HẠN
    if (permission.expiresAt && Date.now() > permission.expiresAt) {
        console.log(`[WS] TỪ CHỐI BẢO MẬT: Token này đã HẾT HẠN sử dụng (${clientToken})`);
        ws.close();
        return;
    }

    const nvrId = permission.nvrId;
    const camId = permission.camId;
    const nvr = NVRS[nvrId];

    // Sử dụng Luồng chính (01) cho Playback vì đầu ghi thường không lưu luồng phụ
    const channel = `${camId}01`; 
    
    // Xử lý thời gian "Tua" (Seek)
    let playbackStart = permission.playbackStart;
    const playbackEnd = permission.playbackEnd;

    // Nếu khách yêu cầu tua đến một mốc thời gian cụ thể
    if (reqStart) {
        // Kiểm tra bảo mật: Không cho phép tua lố ra ngoài khoảng thời gian Admin đã cấp
        if (reqStart >= permission.playbackStart && reqStart <= permission.playbackEnd) {
            playbackStart = reqStart;
        } else {
            console.log(`[WS] TỪ CHỐI TUA: Khách cố tình chọn giờ ngoài giới hạn Token (${clientToken})`);
            ws.close();
            return;
        }
    }

    const rtspUrl = `rtsp://${nvr.user}:${nvr.pass}@${nvr.ip}:554/Streaming/tracks/${channel}?starttime=${playbackStart}&endtime=${playbackEnd}`;
    
    console.log(`[WS] Bắt đầu XEM LẠI NVR ${nvrId} Cam ${camId} từ ${playbackStart} đến ${playbackEnd}...`);

    const bitrate = CONFIG.video.bitrate || '500k';
    const fps = CONFIG.video.fps || '15';

    const ffmpegArgs = [
        '-hwaccel', 'auto',           // [TỐI ƯU MỚI] Kích hoạt giải mã luồng vào bằng Card đồ họa (GTX 1650)
        '-rtsp_transport', 'tcp',
        '-fflags', 'nobuffer',        // Tối ưu: Không dùng bộ đệm
        '-analyzeduration', '100000', // Tối ưu: Giảm thời gian FFmpeg phân tích luồng đầu vào
        '-probesize', '100000',       // Tối ưu: Giảm kích thước dữ liệu cần quét
        '-i', rtspUrl,
        '-f', 'mpegts',
        '-codec:v', 'mpeg1video',
        '-b:v', bitrate, 
        '-r', '25', // BẮT BUỘC LÀ 25 HOẶC 30. MPEG-1 KHÔNG HỖ TRỢ 15 FPS (SẼ GÂY CRASH FFMPEG)
        '-threads', 'auto',           // [TỐI ƯU MỚI] Dùng toàn bộ sức mạnh đa nhân của CPU Xeon
        '-an', 
        '-bf', '0',
        '-'
    ];

    const ffmpegProcess = spawn('ffmpeg', ffmpegArgs);

    ffmpegProcess.on('error', (err) => {
        console.error(`\n[LỖI] Không tìm thấy phần mềm FFmpeg (ffmpeg.exe)!\n`);
        if (ws.readyState === ws.OPEN) ws.close();
    });

    ffmpegProcess.stdout.on('data', (data) => {
        if (ws.readyState === ws.OPEN) ws.send(data);
    });

    ffmpegProcess.on('close', () => {
        if (ws.readyState === ws.OPEN) ws.close();
    });

    ws.on('close', () => {
        console.log(`[WS] Khách hàng ngắt kết nối. Đóng luồng Camera (Token: ${clientToken}).`);
        ffmpegProcess.kill('SIGKILL');
    });
});
