/**
 * 智能人脸枕头 - ESP32 Cam 固件
 * 功能：人脸识别、侧脸(耳朵轮廓)识别、液面高度调节
 * 配合APP进行人脸录入和液面设定
 */

#include "esp_camera.h"
#include "WiFi.h"
#include "ESPAsyncWebServer.h"
#include "AsyncJson.h"
#include "SPIFFS.h"
#include "ArduinoJson.h"

// ============ 引脚定义 (根据实际硬件修改) ============
#define MOTOR_PIN1  12   // 电机正转/电桥控制
#define MOTOR_PIN2  13   // 电机反转/电桥控制
#define LEVEL_SENSOR_PIN 34  // 液面传感器模拟输入 (ADC)

// ============ WiFi 配置 ============
#define WIFI_AP_SSID "FacePillow_Setup"
#define WIFI_AP_PASS "12345678"
#define WIFI_AP_CHANNEL 1

// ============ 液面参数 ============
#define LEVEL_MIN_CM 5
#define LEVEL_MAX_CM 15
#define LEVEL_TOLERANCE_CM 0.5  // 液面调节容差
#define ADC_MIN 0
#define ADC_MAX 4095

// ============ 人脸数据库 (最多5人，每人正脸+2侧脸) ============
#define MAX_FACES 5
#define FACE_FEATURE_SIZE 256  // 简化特征向量大小

struct FaceRecord {
  int id;
  char name[32];
  float liquidLevelCm;  // 设定的液面高度(cm)
  uint8_t feature[FACE_FEATURE_SIZE];  // 人脸/耳朵特征
  uint8_t faceType;  // 0=正脸, 1=左侧脸, 2=右侧脸
  bool enabled;
};

FaceRecord faceDB[MAX_FACES];
int faceCount = 0;
int currentRecognizedId = -1;
float currentLiquidLevelCm = 0;

// ============ 相机配置 (ESP32-CAM AI-Thinker) ============
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

// ============ Web 服务器 ============
AsyncWebServer server(80);

// ============ 函数声明 ============
bool initCamera();
void initMotor();
float readLiquidLevel();
void setMotor(int dir);  // 1=上升, -1=下降, 0=停止
void adjustLiquidLevel(float targetCm);
int recognizeFace(camera_fb_t *fb);
void saveFaceDB();
void loadFaceDB();

void setup() {
  Serial.begin(115200);
  Serial.println("\n===== 智能人脸枕头 ESP32-CAM =====");

  // 初始化SPIFFS存储
  if (!SPIFFS.begin(true)) {
    Serial.println("SPIFFS 初始化失败");
  }

  // 初始化相机
  if (!initCamera()) {
    Serial.println("相机初始化失败!");
    return;
  }

  // 初始化电机
  initMotor();

  // 加载人脸数据库
  loadFaceDB();

  // 启动AP模式供手机连接
  WiFi.mode(WIFI_AP);
  WiFi.softAP(WIFI_AP_SSID, WIFI_AP_PASS, WIFI_AP_CHANNEL);
  Serial.print("AP IP: ");
  Serial.println(WiFi.softAPIP());

  // ============ API 路由 ============
  
  // 获取当前状态
  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    StaticJsonDocument<512> doc;
    doc["faceId"] = currentRecognizedId;
    doc["faceName"] = currentRecognizedId >= 0 && currentRecognizedId < faceCount 
      ? faceDB[currentRecognizedId].name : "";
    doc["setLevelCm"] = currentRecognizedId >= 0 ? faceDB[currentRecognizedId].liquidLevelCm : 0;
    doc["currentLevelCm"] = readLiquidLevel();
    doc["faceCount"] = faceCount;
    
    // 如有识别的人脸，附加最新截图URL
    doc["faceImageUrl"] = "/api/capture";
    
    String response;
    serializeJson(doc, response);
    request->send(200, "application/json", response);
  });

  // 摄像头截图
  server.on("/api/capture", HTTP_GET, [](AsyncWebServerRequest *request) {
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
      request->send(500, "text/plain", "Camera capture failed");
      return;
    }
    request->send_P(200, "image/jpeg", fb->buf, fb->len);
    esp_camera_fb_return(fb);
  });

  // 录入新用户 - 拍照并存储特征
  server.on("/api/enroll", HTTP_POST, [](AsyncWebServerRequest *request) {
    if (faceCount >= MAX_FACES) {
      request->send(400, "application/json", "{\"error\":\"已达最大人脸数量\"}");
      return;
    }
    camera_fb_t *fb = esp_camera_fb_get();
    if (!fb) {
      request->send(500, "application/json", "{\"error\":\"拍照失败\"}");
      return;
    }
    
    // 简化的特征提取 (实际应接入 ESP-DL/ESP-WHO 或 Edge Impulse)
    // 这里用图像块均值模拟特征，生产环境需替换为真实模型
    int id = faceCount;
    for (int i = 0; i < FACE_FEATURE_SIZE && i < fb->len; i++) {
      faceDB[id].feature[i] = fb->buf[(i * 37) % fb->len];
    }
    
    strncpy(faceDB[id].name, "用户", sizeof(faceDB[id].name) - 1);
    faceDB[id].name[sizeof(faceDB[id].name)-1] = '\0';
    faceDB[id].liquidLevelCm = 10.0f;
    faceDB[id].faceType = 0;
    faceDB[id].enabled = true;
    faceDB[id].id = id;
    
    faceCount++;
    esp_camera_fb_return(fb);
    saveFaceDB();

    StaticJsonDocument<128> doc;
    doc["id"] = id;
    doc["name"] = faceDB[id].name;
    String response;
    serializeJson(doc, response);
    request->send(200, "application/json", response);
  });

  // 确定录入人脸ID并更新命名 (使用 AsyncCallbackJsonWebHandler)
  AsyncCallbackJsonWebHandler* enrollConfirmHandler = new AsyncCallbackJsonWebHandler("/api/enroll/confirm");
  enrollConfirmHandler->onRequest([](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject obj = json.as<JsonObject>();
    if (!obj.containsKey("id") || !obj.containsKey("name")) {
      request->send(400, "application/json", "{\"error\":\"参数错误\"}");
      return;
    }
    int id = obj["id"];
    const char* name = obj["name"] | "用户";
    if (id < 0 || id >= faceCount) {
      request->send(400, "application/json", "{\"error\":\"无效ID\"}");
      return;
    }
    strncpy(faceDB[id].name, name, sizeof(faceDB[id].name) - 1);
    faceDB[id].name[sizeof(faceDB[id].name)-1] = '\0';
    saveFaceDB();
    request->send(200, "application/json", "{\"ok\":true}");
  });
  server.addHandler(enrollConfirmHandler);

  // 删除人脸
  AsyncCallbackJsonWebHandler* deleteHandler = new AsyncCallbackJsonWebHandler("/api/face/delete");
  deleteHandler->onRequest([](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject obj = json.as<JsonObject>();
    if (!obj.containsKey("id")) {
      request->send(400, "application/json", "{\"error\":\"参数错误\"}");
      return;
    }
    int id = obj["id"];
    if (id < 0 || id >= faceCount) {
      request->send(400, "application/json", "{\"error\":\"无效ID\"}");
      return;
    }
    for (int i = id; i < faceCount - 1; i++) {
      faceDB[i] = faceDB[i + 1];
      faceDB[i].id = i;
    }
    faceCount--;
    saveFaceDB();
    request->send(200, "application/json", "{\"ok\":true}");
  });
  server.addHandler(deleteHandler);

  // 液面高度设定
  AsyncCallbackJsonWebHandler* levelSetHandler = new AsyncCallbackJsonWebHandler("/api/level/set");
  levelSetHandler->onRequest([](AsyncWebServerRequest *request, JsonVariant &json) {
    JsonObject obj = json.as<JsonObject>();
    if (!obj.containsKey("faceId") || !obj.containsKey("levelCm")) {
      request->send(400, "application/json", "{\"error\":\"参数错误\"}");
      return;
    }
    int faceId = obj["faceId"];
    float levelCm = obj["levelCm"];
    if (faceId < 0 || faceId >= faceCount || levelCm < LEVEL_MIN_CM || levelCm > LEVEL_MAX_CM) {
      request->send(400, "application/json", "{\"error\":\"参数超出范围\"}");
      return;
    }
    faceDB[faceId].liquidLevelCm = levelCm;
    saveFaceDB();
    request->send(200, "application/json", "{\"ok\":true}");
  });
  server.addHandler(levelSetHandler);

  // 获取人脸列表
  server.on("/api/faces", HTTP_GET, [](AsyncWebServerRequest *request) {
    StaticJsonDocument<1024> doc;
    JsonArray arr = doc.to<JsonArray>();
    for (int i = 0; i < faceCount; i++) {
      JsonObject obj = arr.add<JsonObject>();
      obj["id"] = faceDB[i].id;
      obj["name"] = faceDB[i].name;
      obj["liquidLevelCm"] = faceDB[i].liquidLevelCm;
    }
    String response;
    serializeJson(doc, response);
    request->send(200, "application/json", response);
  });

  // 静态文件 (可选，用于简单配置页)
  server.serveStatic("/", SPIFFS, "/").setDefaultFile("index.html");

  server.begin();
  Serial.println("HTTP 服务器已启动");
}

void loop() {
  // 1. 拍照并识别人脸
  camera_fb_t *fb = esp_camera_fb_get();
  if (fb) {
    int id = recognizeFace(fb);
    esp_camera_fb_return(fb);

    if (id >= 0) {
      currentRecognizedId = id;
      float targetLevel = faceDB[id].liquidLevelCm;
      adjustLiquidLevel(targetLevel);
    } else {
      currentRecognizedId = -1;
    }
  }

  // 2. 周期性更新当前液面
  currentLiquidLevelCm = readLiquidLevel();

  delay(500);
}

bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_SVGA;
  config.jpeg_quality = 12;
  config.fb_count = 1;
  config.grab_mode = CAMERA_GRAB_LATEST;

  if (psramFound()) {
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 10;
    config.fb_count = 2;
  }

  esp_err_t err = esp_camera_init(&config);
  return (err == ESP_OK);
}

void initMotor() {
  pinMode(MOTOR_PIN1, OUTPUT);
  pinMode(MOTOR_PIN2, OUTPUT);
  digitalWrite(MOTOR_PIN1, LOW);
  digitalWrite(MOTOR_PIN2, LOW);
  pinMode(LEVEL_SENSOR_PIN, INPUT);
}

float readLiquidLevel() {
  int raw = analogRead(LEVEL_SENSOR_PIN);
  float cm = LEVEL_MIN_CM + (LEVEL_MAX_CM - LEVEL_MIN_CM) * (raw - ADC_MIN) / (float)(ADC_MAX - ADC_MIN);
  return constrain(cm, LEVEL_MIN_CM, LEVEL_MAX_CM);
}

void setMotor(int dir) {
  if (dir > 0) {
    digitalWrite(MOTOR_PIN1, HIGH);
    digitalWrite(MOTOR_PIN2, LOW);
  } else if (dir < 0) {
    digitalWrite(MOTOR_PIN1, LOW);
    digitalWrite(MOTOR_PIN2, HIGH);
  } else {
    digitalWrite(MOTOR_PIN1, LOW);
    digitalWrite(MOTOR_PIN2, LOW);
  }
}

void adjustLiquidLevel(float targetCm) {
  float current = readLiquidLevel();
  if (fabs(current - targetCm) <= LEVEL_TOLERANCE_CM) {
    setMotor(0);
    return;
  }
  if (current < targetCm) {
    setMotor(1);
  } else {
    setMotor(-1);
  }
}

// 简化的人脸识别 - 生产环境需接入 ESP-WHO/ESP-DL 或 Edge Impulse
int recognizeFace(camera_fb_t *fb) {
  if (faceCount == 0) return -1;
  
  // 简化的相似度匹配 (占位实现)
  // 实际应使用深度学习模型提取特征并比对
  int bestId = -1;
  float bestScore = 0.5f;  // 阈值

  for (int i = 0; i < faceCount; i++) {
    if (!faceDB[i].enabled) continue;
    float sum = 0;
    int cnt = 0;
    for (int j = 0; j < FACE_FEATURE_SIZE && j < (int)fb->len; j++) {
      uint8_t a = faceDB[i].feature[j];
      uint8_t b = fb->buf[(j * 37) % fb->len];
      sum += 1.0f - (float)abs(a - b) / 255.0f;
      cnt++;
    }
    float score = cnt > 0 ? sum / cnt : 0;
    if (score > bestScore) {
      bestScore = score;
      bestId = i;
    }
  }
  return bestId;
}

void saveFaceDB() {
  File f = SPIFFS.open("/faceDB.bin", "w");
  if (!f) return;
  f.write((uint8_t*)&faceCount, sizeof(faceCount));
  f.write((uint8_t*)faceDB, sizeof(faceDB));
  f.close();
}

void loadFaceDB() {
  if (!SPIFFS.exists("/faceDB.bin")) return;
  File f = SPIFFS.open("/faceDB.bin", "r");
  if (!f) return;
  f.read((uint8_t*)&faceCount, sizeof(faceCount));
  f.read((uint8_t*)faceDB, sizeof(faceDB));
  f.close();
}
