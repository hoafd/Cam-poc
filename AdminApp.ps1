Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- 1. NẠP CẤU HÌNH ---
$configFile = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path $configFile)) {
    [System.Windows.Forms.MessageBox]::Show("Lỗi nghiêm trọng: Không tìm thấy file config.json", "Lỗi Khởi Động", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

$config = Get-Content $configFile -Encoding UTF8 | ConvertFrom-Json
$httpPort = if ($config.server.httpPort) { $config.server.httpPort } else { 3000 }
$nvrList = $config.nvrs

# --- 2. KIỂM TRA VÀ TỰ ĐỘNG TẢI FFMPEG ---
$ffmpegPath = Join-Path $PSScriptRoot "ffmpeg.exe"
if (-not (Test-Path $ffmpegPath)) {
    $ask = [System.Windows.Forms.MessageBox]::Show("Hệ thống không tìm thấy file 'ffmpeg.exe' (Công cụ lõi để xử lý Video).`n`nPhần mềm sẽ tự động tải về từ GitHub (Dung lượng khoảng 130MB). Bạn có đồng ý không?", "Thiếu Thành Phần Cốt Lõi", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    
    if ($ask -eq "Yes") {
        # Tạo Form báo đang tải
        $FormDown = New-Object System.Windows.Forms.Form
        $FormDown.Size = New-Object System.Drawing.Size(400,150)
        $FormDown.StartPosition = "CenterScreen"
        $FormDown.Text = "Đang Tải FFmpeg..."
        $FormDown.ControlBox = $False
        
        $LblDown = New-Object System.Windows.Forms.Label
        $LblDown.Text = "Đang tải công cụ xử lý Video (FFmpeg) từ Github...`nVui lòng đợi 1-3 phút tùy tốc độ mạng.`n`nLƯU Ý: Phần mềm có thể bị đơ tạm thời, TUYỆT ĐỐI KHÔNG TẮT!"
        $LblDown.Location = New-Object System.Drawing.Point(20, 20)
        $LblDown.Size = New-Object System.Drawing.Size(350, 70)
        $LblDown.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
        $FormDown.Controls.Add($LblDown)
        
        $FormDown.Show()
        [System.Windows.Forms.Application]::DoEvents()
        
        try {
            $zipUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
            $zipPath = Join-Path $PSScriptRoot "ffmpeg_temp.zip"
            $extractPath = Join-Path $PSScriptRoot "ffmpeg_extracted"
            
            # Ép dùng TLS 1.2 cho Invoke-WebRequest
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            # Tải và giải nén
            Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
            
            $LblDown.Text = "Đã tải xong! Đang giải nén file ZIP..."
            [System.Windows.Forms.Application]::DoEvents()
            
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            
            # Lấy file exe ra
            $exeSource = Join-Path $extractPath "ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe"
            Move-Item -Path $exeSource -Destination $ffmpegPath -Force
            
            # Dọn dẹp
            Remove-Item -Path $zipPath -Force
            Remove-Item -Path $extractPath -Recurse -Force
            
            $FormDown.Close()
            [System.Windows.Forms.MessageBox]::Show("Đã cài đặt FFmpeg thành công!", "Hoàn tất", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            $FormDown.Close()
            [System.Windows.Forms.MessageBox]::Show("Có lỗi xảy ra khi tải FFmpeg: $_ `n`nVui lòng tải thủ công file ffmpeg.exe bỏ vào thư mục này.", "Lỗi Tải Xuống", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            exit
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Phần mềm bắt buộc phải có ffmpeg.exe để chạy. Vui lòng tự tải và chép vào thư mục dự án.", "Lỗi Thiếu File", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        exit
    }
}

# Cấu hình Cửa sổ phần mềm chính (Đã mở rộng kích thước)
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "Phần Mềm Quản Trị Hệ Thống Camera BẢN CAO CẤP"
$Form.Size = New-Object System.Drawing.Size(950,520)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $False
$Form.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)

# ==============================================================
# KHU VỰC QUẢN LÝ MÁY CHỦ (SERVER)
# ==============================================================
$PanelServer = New-Object System.Windows.Forms.Panel
$PanelServer.Location = New-Object System.Drawing.Point(10,410)
$PanelServer.Size = New-Object System.Drawing.Size(910,60)
$PanelServer.BackColor = [System.Drawing.Color]::White
$PanelServer.BorderStyle = "FixedSingle"
$Form.Controls.Add($PanelServer)

$LabelServerStatus = New-Object System.Windows.Forms.Label
$LabelServerStatus.Text = "Trạng thái Server: ĐÃ DỪNG"
$LabelServerStatus.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$LabelServerStatus.ForeColor = [System.Drawing.Color]::Red
$LabelServerStatus.Location = New-Object System.Drawing.Point(20,20)
$LabelServerStatus.Size = New-Object System.Drawing.Size(300,30)
$PanelServer.Controls.Add($LabelServerStatus)

$BtnStartServer = New-Object System.Windows.Forms.Button
$BtnStartServer.Text = "▶ KHỞI ĐỘNG MÁY CHỦ (CHẠY ẨN)"
$BtnStartServer.Location = New-Object System.Drawing.Point(400,10)
$BtnStartServer.Size = New-Object System.Drawing.Size(250,40)
$BtnStartServer.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
$BtnStartServer.ForeColor = [System.Drawing.Color]::White
$BtnStartServer.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$BtnStartServer.Cursor = [System.Windows.Forms.Cursors]::Hand
$PanelServer.Controls.Add($BtnStartServer)

$BtnStopServer = New-Object System.Windows.Forms.Button
$BtnStopServer.Text = "⏹ TẮT MÁY CHỦ"
$BtnStopServer.Location = New-Object System.Drawing.Point(660,10)
$BtnStopServer.Size = New-Object System.Drawing.Size(150,40)
$BtnStopServer.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
$BtnStopServer.ForeColor = [System.Drawing.Color]::White
$BtnStopServer.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$BtnStopServer.Cursor = [System.Windows.Forms.Cursors]::Hand
$BtnStopServer.Enabled = $False
$PanelServer.Controls.Add($BtnStopServer)

# ==============================================================
# PANEL BÊN TRÁI: FORM TẠO TOKEN
# ==============================================================
$PanelLeft = New-Object System.Windows.Forms.Panel
$PanelLeft.Location = New-Object System.Drawing.Point(10,10)
$PanelLeft.Size = New-Object System.Drawing.Size(400,380)
$Form.Controls.Add($PanelLeft)

$LabelTitle = New-Object System.Windows.Forms.Label
$LabelTitle.Text = "TẠO MỚI QUYỀN TRUY CẬP"
$LabelTitle.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$LabelTitle.Location = New-Object System.Drawing.Point(10,0)
$LabelTitle.Size = New-Object System.Drawing.Size(380,30)
$PanelLeft.Controls.Add($LabelTitle)

$LabelNVR = New-Object System.Windows.Forms.Label
$LabelNVR.Location = New-Object System.Drawing.Point(10,40)
$LabelNVR.Text = "Chọn Đầu ghi:"
$PanelLeft.Controls.Add($LabelNVR)

$ComboNVR = New-Object System.Windows.Forms.ComboBox
$ComboNVR.Location = New-Object System.Drawing.Point(100,40)
$ComboNVR.Size = New-Object System.Drawing.Size(280,20)
$ComboNVR.DropDownStyle = "DropDownList"
$nvrKeys = @()
foreach ($prop in $nvrList.PSObject.Properties) {
    $ComboNVR.Items.Add($prop.Value.name)
    $nvrKeys += $prop.Name
}
if ($ComboNVR.Items.Count -gt 0) { $ComboNVR.SelectedIndex = 0 }
$PanelLeft.Controls.Add($ComboNVR)

$LabelCam = New-Object System.Windows.Forms.Label
$LabelCam.Location = New-Object System.Drawing.Point(10,75)
$LabelCam.Text = "Số Camera:"
$PanelLeft.Controls.Add($LabelCam)

$ComboCam = New-Object System.Windows.Forms.ComboBox
$ComboCam.Location = New-Object System.Drawing.Point(100,75)
$ComboCam.Size = New-Object System.Drawing.Size(280,20)
$ComboCam.DropDownStyle = "DropDownList"
for ($i=1; $i -le 16; $i++) { $ComboCam.Items.Add("Camera số $i") }
$ComboCam.SelectedIndex = 0
$PanelLeft.Controls.Add($ComboCam)

# --- THỜI GIAN BẮT ĐẦU XEM LẠI ---
$LabelStartTime = New-Object System.Windows.Forms.Label
$LabelStartTime.Location = New-Object System.Drawing.Point(10,110)
$LabelStartTime.Text = "Từ lúc:"
$PanelLeft.Controls.Add($LabelStartTime)

$PickerStart = New-Object System.Windows.Forms.DateTimePicker
$PickerStart.Location = New-Object System.Drawing.Point(100,110)
$PickerStart.Size = New-Object System.Drawing.Size(280,20)
$PickerStart.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$PickerStart.CustomFormat = "dd/MM/yyyy HH:mm:00"
$PickerStart.Value = [datetime]::Now.AddHours(-1)
$PanelLeft.Controls.Add($PickerStart)

# --- THỜI GIAN KẾT THÚC XEM LẠI ---
$LabelEndTime = New-Object System.Windows.Forms.Label
$LabelEndTime.Location = New-Object System.Drawing.Point(10,145)
$LabelEndTime.Text = "Đến lúc:"
$PanelLeft.Controls.Add($LabelEndTime)

$PickerEnd = New-Object System.Windows.Forms.DateTimePicker
$PickerEnd.Location = New-Object System.Drawing.Point(100,145)
$PickerEnd.Size = New-Object System.Drawing.Size(280,20)
$PickerEnd.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$PickerEnd.CustomFormat = "dd/MM/yyyy HH:mm:00"
$PickerEnd.Value = [datetime]::Now
$PanelLeft.Controls.Add($PickerEnd)


$LabelDesc = New-Object System.Windows.Forms.Label
$LabelDesc.Location = New-Object System.Drawing.Point(10,180)
$LabelDesc.Text = "Ghi chú:"
$PanelLeft.Controls.Add($LabelDesc)

$TextDesc = New-Object System.Windows.Forms.TextBox
$TextDesc.Location = New-Object System.Drawing.Point(100,180)
$TextDesc.Size = New-Object System.Drawing.Size(280,20)
$PanelLeft.Controls.Add($TextDesc)

# --- THÊM MỚI: TÙY CHỌN THỜI HẠN LINK ---
$LabelExp = New-Object System.Windows.Forms.Label
$LabelExp.Location = New-Object System.Drawing.Point(10,215)
$LabelExp.Text = "Hạn dùng Link:"
$PanelLeft.Controls.Add($LabelExp)

$ComboExp = New-Object System.Windows.Forms.ComboBox
$ComboExp.Location = New-Object System.Drawing.Point(100,215)
$ComboExp.Size = New-Object System.Drawing.Size(280,20)
$ComboExp.DropDownStyle = "DropDownList"
$ComboExp.Items.Add("Vĩnh viễn")
$ComboExp.Items.Add("1 Giờ (Xem tạm)")
$ComboExp.Items.Add("24 Giờ (Theo ngày)")
$ComboExp.Items.Add("7 Ngày (Theo tuần)")
$ComboExp.SelectedIndex = 2 # Mặc định để 24 Giờ cho an toàn
$PanelLeft.Controls.Add($ComboExp)

$ButtonGen = New-Object System.Windows.Forms.Button
$ButtonGen.Location = New-Object System.Drawing.Point(10,250)
$ButtonGen.Size = New-Object System.Drawing.Size(370,45)
$ButtonGen.Text = "TẠO BẰNG CHỨNG XEM LẠI (MAGIC LINK)"
$ButtonGen.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
$ButtonGen.ForeColor = [System.Drawing.Color]::White
$ButtonGen.Font = New-Object System.Drawing.Font("Arial", 11, [System.Drawing.FontStyle]::Bold)
$ButtonGen.Cursor = [System.Windows.Forms.Cursors]::Hand
$PanelLeft.Controls.Add($ButtonGen)

$LabelLink = New-Object System.Windows.Forms.Label
$LabelLink.Location = New-Object System.Drawing.Point(10,310)
$LabelLink.Size = New-Object System.Drawing.Size(370,20)
$LabelLink.Text = "Copy đường Link dưới đây để gửi cho người xem:"
$PanelLeft.Controls.Add($LabelLink)

$TextLink = New-Object System.Windows.Forms.TextBox
$TextLink.Location = New-Object System.Drawing.Point(10,330)
$TextLink.Size = New-Object System.Drawing.Size(260,60)
$TextLink.Multiline = $True
$TextLink.ReadOnly = $True
$TextLink.BackColor = [System.Drawing.Color]::WhiteSmoke
$TextLink.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Regular)
$PanelLeft.Controls.Add($TextLink)

$ButtonCopy = New-Object System.Windows.Forms.Button
$ButtonCopy.Location = New-Object System.Drawing.Point(280,330)
$ButtonCopy.Size = New-Object System.Drawing.Size(100,60)
$ButtonCopy.Text = "Sao Chép"
$ButtonCopy.BackColor = [System.Drawing.Color]::FromArgb(0, 123, 255)
$ButtonCopy.ForeColor = [System.Drawing.Color]::White
$ButtonCopy.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$ButtonCopy.Cursor = [System.Windows.Forms.Cursors]::Hand
$PanelLeft.Controls.Add($ButtonCopy)

# ==============================================================
# PANEL BÊN PHẢI: BẢNG DANH SÁCH & QUẢN LÝ
# ==============================================================
$PanelRight = New-Object System.Windows.Forms.Panel
$PanelRight.Location = New-Object System.Drawing.Point(420,10)
$PanelRight.Size = New-Object System.Drawing.Size(500,380)
$Form.Controls.Add($PanelRight)

$LabelGridTitle = New-Object System.Windows.Forms.Label
$LabelGridTitle.Text = "DANH SÁCH TOKEN ĐANG ĐƯỢC CẤP"
$LabelGridTitle.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$LabelGridTitle.Location = New-Object System.Drawing.Point(0,0)
$LabelGridTitle.Size = New-Object System.Drawing.Size(500,20)
$PanelRight.Controls.Add($LabelGridTitle)

$GridTokens = New-Object System.Windows.Forms.DataGridView
$GridTokens.Location = New-Object System.Drawing.Point(0,25)
$GridTokens.Size = New-Object System.Drawing.Size(500,300)
$GridTokens.AllowUserToAddRows = $False
$GridTokens.ReadOnly = $True
$GridTokens.SelectionMode = "FullRowSelect"
$GridTokens.MultiSelect = $False
$GridTokens.RowHeadersVisible = $False
$GridTokens.ColumnCount = 4
$GridTokens.Columns[0].Name = "Mã Token"
$GridTokens.Columns[1].Name = "Camera"
$GridTokens.Columns[2].Name = "Ghi chú"
$GridTokens.Columns[3].Name = "Hết hạn lúc"
$GridTokens.Columns[0].Width = 70
$GridTokens.Columns[1].Width = 70
$GridTokens.Columns[2].Width = 180
$GridTokens.Columns[3].Width = 140
$PanelRight.Controls.Add($GridTokens)

$ButtonRefresh = New-Object System.Windows.Forms.Button
$ButtonRefresh.Location = New-Object System.Drawing.Point(0,340)
$ButtonRefresh.Size = New-Object System.Drawing.Size(150,40)
$ButtonRefresh.Text = "Làm mới danh sách"
$ButtonRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand
$PanelRight.Controls.Add($ButtonRefresh)

$ButtonDelete = New-Object System.Windows.Forms.Button
$ButtonDelete.Location = New-Object System.Drawing.Point(300,340)
$ButtonDelete.Size = New-Object System.Drawing.Size(200,40)
$ButtonDelete.Text = "⚠️ THU HỒI QUYỀN NÀY ⚠️"
$ButtonDelete.BackColor = [System.Drawing.Color]::FromArgb(220, 53, 69)
$ButtonDelete.ForeColor = [System.Drawing.Color]::White
$ButtonDelete.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$ButtonDelete.Cursor = [System.Windows.Forms.Cursors]::Hand
$PanelRight.Controls.Add($ButtonDelete)


# ==============================================================
# XỬ LÝ SỰ KIỆN LOGIC
# ==============================================================

# Hàm tải danh sách từ Server
Function Refresh-TokenList {
    $GridTokens.Rows.Clear()
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:$httpPort/api/tokens" -Method Get
        if ($response.success) {
            foreach ($t in $response.tokens) {
                $expStr = "Vĩnh viễn"
                if ($t.expiresAt) {
                    # Đổi từ Timestamp Epoch ra Datetime
                    $dt = [datetime]::FromFileTimeUtc($t.expiresAt * 10000 + 116444736000000000)
                    $dt = $dt.ToLocalTime()
                    $expStr = $dt.ToString("dd/MM/yyyy HH:mm")
                }
                $camStr = "NVR" + $t.nvrId + "-C" + $t.camId
                $GridTokens.Rows.Add($t.token, $camStr, $t.description, $expStr) | Out-Null
            }
        }
    } catch { 
        # Bỏ qua lỗi nếu chưa kết nối được
    }
}

# Nút Tạo Token
$ButtonGen.Add_Click({
    $ButtonGen.Text = "Đang xử lý..."
    $ButtonGen.Enabled = $False
    [System.Windows.Forms.Application]::DoEvents()

    $nvrId = $nvrKeys[$ComboNVR.SelectedIndex]
    $camId = $ComboCam.SelectedIndex + 1
    
    # Xử lý chuỗi thời gian Playback sang định dạng Hikvision (Giờ Quốc Tế UTC)
    $startTimeUTC = $PickerStart.Value.ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $endTimeUTC = $PickerEnd.Value.ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    
    # Ghép thời gian vào Ghi chú cho dễ nhìn
    $timeStr = $PickerStart.Value.ToString("dd/MM HH:mm") + " - " + $PickerEnd.Value.ToString("dd/MM HH:mm")
    $desc = "[$timeStr] " + $TextDesc.Text
    
    # Xử lý thời hạn Link
    $expHours = 0
    if ($ComboExp.SelectedIndex -eq 1) { $expHours = 1 }
    if ($ComboExp.SelectedIndex -eq 2) { $expHours = 24 }
    if ($ComboExp.SelectedIndex -eq 3) { $expHours = 24 * 7 }
    
    $body = @{
        nvrId = $nvrId
        camId = $camId
        description = $desc
        expireHours = $expHours
        playbackStart = $startTimeUTC
        playbackEnd = $endTimeUTC
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:$httpPort/api/generate-token" -Method Post -Body $body -ContentType "application/json"
        
        if ($response.success) {
            $token = $response.token
            $TextLink.Text = "http://localhost:$httpPort/?token=$token"
            
            $ButtonCopy.Text = "Sao Chép"
            $ButtonCopy.BackColor = [System.Drawing.Color]::FromArgb(0, 123, 255)
            
            # Làm mới danh sách ngay lập tức
            Refresh-TokenList
        } else {
            [System.Windows.Forms.MessageBox]::Show("Lỗi từ Máy chủ: " + $response.error, "Lỗi", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("KHÔNG THỂ KẾT NỐI ĐẾN MÁY CHỦ!`n`nVui lòng đảm bảo Server Node.js đang chạy trên cổng $httpPort.", "Lỗi Mạng", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }

    $ButtonGen.Text = "TẠO LINK TRUY CẬP (MAGIC LINK)"
    $ButtonGen.Enabled = $True
})

# Nút Copy
$ButtonCopy.Add_Click({
    if (-not [string]::IsNullOrEmpty($TextLink.Text)) {
        [System.Windows.Forms.Clipboard]::SetText($TextLink.Text)
        $ButtonCopy.Text = "Đã Copy!"
        $ButtonCopy.BackColor = [System.Drawing.Color]::FromArgb(40, 167, 69)
    }
})

# Nút Làm mới
$ButtonRefresh.Add_Click({ Refresh-TokenList })

# Nút Xóa/Thu hồi
$ButtonDelete.Add_Click({
    if ($GridTokens.SelectedRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Vui lòng chọn một Token trong Bảng bên trên để xóa!", "Thông Báo", 0, 48)
        return
    }
    
    $selRow = $GridTokens.SelectedRows[0]
    $token = $selRow.Cells[0].Value
    $desc = $selRow.Cells[2].Value
    
    $confirm = [System.Windows.Forms.MessageBox]::Show("Bạn có chắc muốn THU HỒI quyền truy cập của: '$desc' không?`n`nCẢNH BÁO: Nếu họ đang xem video, họ sẽ bị ĐÁ văng ra ngoài ngay lập tức!", "Cảnh Báo Thu Hồi", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    
    if ($confirm -eq "Yes") {
        try {
            $body = @{ token = $token } | ConvertTo-Json
            $response = Invoke-RestMethod -Uri "http://localhost:$httpPort/api/delete-token" -Method Post -Body $body -ContentType "application/json"
            if ($response.success) {
                [System.Windows.Forms.MessageBox]::Show("Đã thu hồi quyền thành công. Đường link đó đã trở thành rác!", "Xong", 0, 64)
                Refresh-TokenList
                $TextLink.Text = ""
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Lỗi kết nối Máy chủ. Vui lòng thử lại.", "Lỗi", 0, 16)
        }
    }
})

# Logic Quản lý Server Node.js
$global:nodeProcess = $null

$BtnStartServer.Add_Click({
    if ($global:nodeProcess) { return }
    
    $LabelServerStatus.Text = "Trạng thái Server: ĐANG KHỞI ĐỘNG..."
    $LabelServerStatus.ForeColor = [System.Drawing.Color]::Orange
    [System.Windows.Forms.Application]::DoEvents()
    
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "node.exe"
    $psi.Arguments = "server.js"
    $psi.WorkingDirectory = $PSScriptRoot
    $psi.WindowStyle = "Hidden"
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    
    try {
        $global:nodeProcess = [System.Diagnostics.Process]::Start($psi)
        Start-Sleep -Seconds 2 # Đợi server khởi động
        $LabelServerStatus.Text = "Trạng thái Server: ĐANG CHẠY (ẨN)"
        $LabelServerStatus.ForeColor = [System.Drawing.Color]::Green
        $BtnStartServer.Enabled = $false
        $BtnStopServer.Enabled = $true
        Refresh-TokenList
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Lỗi khởi động Node.js: $_", "Lỗi", 0, 16)
        $LabelServerStatus.Text = "Trạng thái Server: LỖI"
        $LabelServerStatus.ForeColor = [System.Drawing.Color]::Red
    }
})

$BtnStopServer.Add_Click({
    $LabelServerStatus.Text = "Trạng thái Server: ĐANG TẮT..."
    $LabelServerStatus.ForeColor = [System.Drawing.Color]::Orange
    [System.Windows.Forms.Application]::DoEvents()

    if ($global:nodeProcess) {
        Stop-Process -Id $global:nodeProcess.Id -Force -ErrorAction SilentlyContinue
        $global:nodeProcess = $null
    }
    
    # Dọn dẹp sạch sẽ các process node.js đang chạy server.js (nếu có)
    Get-WmiObject Win32_Process -Filter "Name='node.exe' AND CommandLine LIKE '%server.js%'" | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $LabelServerStatus.Text = "Trạng thái Server: ĐÃ DỪNG"
    $LabelServerStatus.ForeColor = [System.Drawing.Color]::Red
    $BtnStartServer.Enabled = $true
    $BtnStopServer.Enabled = $false
})

# Đảm bảo khi tắt phần mềm Admin thì Server ẩn cũng tự động bị tắt theo
$Form.Add_FormClosing({
    if ($global:nodeProcess) {
        Stop-Process -Id $global:nodeProcess.Id -Force -ErrorAction SilentlyContinue
    }
})

# Tự động lấy danh sách khi bật phần mềm lên
Refresh-TokenList

$Form.ShowDialog() | Out-Null
