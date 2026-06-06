# 拍照附件功能

## 概述

在聊天输入栏增加拍照按钮，调用系统相机拍照后自动压缩，作为附件随消息发送给 AI 分析。

## 插件

- `image_picker` — Flutter 官方插件，调用系统相机/图库

## Android 权限

- `CAMERA` — 拍照必须，`image_picker` 通过系统相机 App 间接使用

## 改动范围

| 文件 | 改动 |
|------|------|
| `AndroidManifest.xml` | 添加 CAMERA 权限声明 |
| `pubspec.yaml` | 添加 image_picker 依赖 |
| `file_attachment_service.dart` | 新增 `pickCamera()` 方法，含压缩逻辑 |
| `chat_input_bar.dart` | 在 📎 按钮旁增加 📷 按钮 |

## 拍照流程

1. 用户点击 📷 按钮
2. 调用 `ImagePicker().pickImage(source: ImageSource.camera)`
3. 拍照成功后压缩到 maxWidth=1024, quality=85 (JPEG)
4. 生成 `FileAttachment`（name、path、size、无 extractedText）
5. 加入附件列表，显示 chip
6. 用户点发送，随消息一起发送
