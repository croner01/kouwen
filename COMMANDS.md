# 叩问 — 命令速查

## Release 签名信息

| 项目 | 值 |
|------|-----|
| Keystore | `android/app/kouwen.keystore` |
| Alias | `kouwen` |
| 密码 | `kouwen123` |
| 证书 | CN=叩问, O=KouWen |
| SHA-256 | `82ecac4ff0a44cb683c4431f50d660f7d598173edf012fccaedfc121f8ce4541` |
| APK 大小 | 23.3MB (release, minified) |
| 输出路径 | `build/app/outputs/flutter-apk/app-release.apk` |

## 环境变量（每次新终端需设置）

```bash
export PATH="/usr/local/flutter/bin:$PATH"
export ANDROID_SDK_ROOT=/usr/local/android-sdk
export ANDROID_HOME=/usr/local/android-sdk
export DISPLAY=:14.0
```

## 启动模拟器

```bash
cd /root/kouwen

# 启动（后台，需 30-60 秒冷启动）
/usr/local/android-sdk/emulator/emulator \
  -avd test_phone \
  -no-window \
  -no-audio \
  -gpu swiftshader_indirect \
  -no-boot-anim \
  -no-metrics \
  &

# 等待就绪
until adb get-state 2>/dev/null | grep -q device; do sleep 2; done
echo "模拟器就绪"
```

## 构建与安装

```bash
# Debug 构建（开发用）
flutter build apk --debug

# Release 构建（签名，发布用）
flutter build apk --release
# 输出: build/app/outputs/flutter-apk/app-release.apk (23MB, 已签名)

# Google Play 用 App Bundle
flutter build appbundle

# 一键：Debug 构建 + 安装 + 启动
flutter build apk --debug && \
  adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk && \
  adb -s emulator-5554 shell am start -n com.kouwen.app/.MainActivity

# Release APK 直接安装到手机
adb install build/app/outputs/flutter-apk/app-release.apk
```

## 测试命令

```bash
# 静态分析
flutter analyze

# 单元测试（8 tests）
flutter test

# 指定测试
flutter test test/engine/
```

## 开发工作流

```bash
# 每次改代码后：
flutter analyze      # 1. 检查语法（2-5秒）
flutter test         # 2. 跑测试（3-5秒）
                      # 3. 如果通过，一建重建安装
```

## 模拟器操作

```bash
# 截图
adb -s emulator-5554 exec-out screencap -p > screenshot.png

# 点击 (x y)
adb -s emulator-5554 shell input tap 540 1200

# 输入文字
adb -s emulator-5554 shell input text "test"

# 返回键
adb -s emulator-5554 shell input keyevent 4

# 解锁屏幕（如果锁了）
adb -s emulator-5554 shell input keyevent 82

# 列表
adb -s emulator-5554 shell pm list packages | grep skill

# 卸载
adb -s emulator-5554 uninstall com.kouwen.app

# 重启 App
adb -s emulator-5554 shell am force-stop com.kouwen.app
adb -s emulator-5554 shell am start -n com.kouwen.app/.MainActivity

# 清空数据（重置 App）
adb -s emulator-5554 shell pm clear com.kouwen.app

# 查看日志（过滤 Flutter）
adb -s emulator-5554 logcat -s flutter,AndroidRuntime

# 停止模拟器
adb -s emulator-5554 emu kill
```
