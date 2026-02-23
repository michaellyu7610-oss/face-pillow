# 智能人脸枕头

消费者扫码下载APP，初次使用时手动录入人脸/侧脸并设定液面高度；日常使用中ESP32 Cam识别到已录入ID时自动调节液面。

## 项目结构

```
人脸枕头/
├── esp32_cam/          # ESP32 Cam 固件 (Arduino)
│   ├── esp32_cam.ino   # 主程序
│   └── libraries.txt   # 库依赖说明
├── app/                # 手机 APP (Flutter)
│   └── lib/            # 源码
└── README.md
```

## 硬件连接（非代码部分）

- **ESP32-CAM**：连接液面传感器（模拟输入）、电桥（控制电机正反转）
- 引脚定义见 `esp32_cam.ino` 顶部，可根据实际接线修改

## 部署步骤

### 1. ESP32 Cam 固件上传

1. 安装 Arduino IDE，添加 ESP32 板卡支持
2. 安装库：`ESPAsyncWebServer`、`AsyncTCP`、`ArduinoJson`
3. 若使用 AsyncCallbackJsonWebHandler，需 `AsyncJson`（或改用项目中的手动 JSON 解析）
4. 打开 `esp32_cam/esp32_cam.ino`
5. 选择开发板：**AI Thinker ESP32-CAM**
6. 点击上传

### 2. APP 云端部署

**首次构建前**：若 `app/android` 目录不完整，在 `app` 目录执行 `flutter create .` 生成平台代码。

在 `app/android/app/src/main/AndroidManifest.xml` 的 `<application>` 标签内添加 `android:usesCleartextTraffic="true"`，以支持 HTTP 访问 ESP32。

**方式一：直接生成 APK 供扫码下载**

```bash
cd app
flutter pub get
flutter build apk --release
```

生成的 APK：`build/app/outputs/flutter-apk/app-release.apk`  
将 APK 上传到云存储（如七牛云、阿里云 OSS）或自建服务器，生成下载链接，制作二维码供用户扫码下载。

**方式二：上架应用商店**

```bash
flutter build appbundle   # Android
flutter build ios        # iOS（需 Mac + Xcode）
```

按应用商店要求提交审核。

### 3. 初次使用流程

1. 手机连接 WiFi：`FacePillow_Setup`，密码：`12345678`
2. 打开 APP，右上角设置中确认 ESP32 地址为 `http://192.168.4.1`（默认 AP 网关）
3. **人脸录入**：  
   - 1. 录入新用户 → 对准摄像头点击  
   - 2. 确定录入 → 选择人脸，弹出对话框输入命名，确定  
   - 3. 删除 → 选择要删除的人脸，确认删除
4. **液面高度设定**：  
   - 点击「液面高度设定」  
   - 1号轮盘选择人脸  
   - 2号轮盘选择液面高度 5–15 cm  
   - 点击「确定录入液面高度」
5. 日常使用：APP 参数显示区会显示当前人脸、液面设定及当前液面高度；ESP32 识别到 ID 后自动驱动泵调节液面

## 人脸识别说明

当前固件使用**简化特征匹配**作为占位实现，适合快速验证流程。若要提升识别效果，可替换为：

1. **ESP-WHO / ESP-DL**（ESP-IDF 项目，如 [klumw/esp32_cam_face_recognition](https://github.com/klumw/esp32_cam_face_recognition)）
2. **Edge Impulse**：采集正脸和侧脸（耳朵轮廓）数据，训练模型后导出 Arduino 库
3. **TensorFlow Lite**：在 ESP32-S3 上运行自定义人脸/耳朵识别模型

侧脸（耳朵轮廓）识别与正脸类似，可训练多类别模型或分别训练正脸、左侧脸、右侧脸模型。

## API 接口（APP 与 ESP32 通信）

| 接口 | 方法 | 说明 |
|------|------|------|
| `/api/status` | GET | 获取当前状态（人脸ID、名称、设定液面、当前液面） |
| `/api/capture` | GET | 获取摄像头截图 |
| `/api/faces` | GET | 获取已录入人脸列表 |
| `/api/enroll` | POST | 录入新用户 |
| `/api/enroll/confirm` | POST | 确认录入并更新命名 `{id, name}` |
| `/api/face/delete` | POST | 删除人脸 `{id}` |
| `/api/level/set` | POST | 设置人脸对应液面 `{faceId, levelCm}` |

## 注意事项

- 人脸识别精度要求不高，仅录入 3–5 人时，开源实现即可满足
- ESP32-CAM 标准版资源有限，复杂模型建议使用 ESP32-S3
- 液面传感器需根据实际型号调整 ADC 换算公式（`readLiquidLevel()`）
- 电机控制引脚和电桥接线需与实际硬件一致
