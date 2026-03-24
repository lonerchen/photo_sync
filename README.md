# Photo Storage Cleaner

手机照片备份与清理工具 —— 将手机照片无损备份到本地存储端，确认备份后安全清理手机空间。

## 项目结构

```
photo_storage_cleaner/
├── melos.yaml                  # Melos monorepo 配置
├── pubspec.yaml                # 根工作区 pubspec（仅含 melos dev 依赖）
└── packages/
    ├── common/                 # 共享数据模型、协议、上传队列
    ├── photo_manager_ui/       # 共享 Flutter UI 组件库
    ├── mobile_client/          # 手机端 Flutter App（iOS / Android）
    └── storage_server/         # 存储端 Flutter App（macOS / Windows / Linux）
```

### Package 依赖关系

```
common          ──────────────────────────────┐
photo_manager_ui ─────────────────────────────┤
                                              ↓
mobile_client   → common + photo_manager_ui
storage_server  → common + photo_manager_ui
```

| Package | 平台 | 依赖 |
|---|---|---|
| `common` | Dart（纯 Dart） | 无内部依赖 |
| `photo_manager_ui` | Flutter | 无内部依赖 |
| `mobile_client` | Flutter（iOS / Android） | `common`、`photo_manager_ui` |
| `storage_server` | Flutter（macOS / Windows / Linux） | `common`、`photo_manager_ui` |

## 环境要求

- Flutter SDK ≥ 3.0.0
- Dart SDK ≥ 3.0.0
- [Melos](https://melos.invertase.dev/) ≥ 6.0.0

## 快速开始

### 1. 安装 Melos

```bash
dart pub global activate melos
```

### 2. Bootstrap 工作区

```bash
cd photo_storage_cleaner
melos bootstrap
```

`melos bootstrap` 会为所有 package 执行 `dart pub get`，并通过 `pubspec_overrides.yaml` 将本地 path 依赖链接到工作区内的 package，无需发布到 pub.dev。

### 3. 运行各 App

#### 手机端（mobile_client）

```bash
# iOS
cd packages/mobile_client
flutter run -d <ios-device-id>

# Android
flutter run -d <android-device-id>
```

#### 存储端（storage_server）

```bash
# macOS
cd packages/storage_server
flutter run -d macos

# Windows
flutter run -d windows

# Linux
flutter run -d linux
```

## 常用 Melos 命令

```bash
# 在所有 package 中运行 flutter analyze
melos run analyze

# 在所有 package 中运行测试
melos run test

# 清理所有 package 的构建产物
melos clean
```

## 路径依赖验证

以下 path 依赖均相对于各 package 目录，路径正确：

| Package | 依赖 | 相对路径 | 实际路径 |
|---|---|---|---|
| `mobile_client` | `common` | `../common` | `packages/common` ✓ |
| `mobile_client` | `photo_manager_ui` | `../photo_manager_ui` | `packages/photo_manager_ui` ✓ |
| `storage_server` | `common` | `../common` | `packages/common` ✓ |
| `storage_server` | `photo_manager_ui` | `../photo_manager_ui` | `packages/photo_manager_ui` ✓ |

## 架构概览

- **common**：`MediaItem`、`Album`、`DeviceInfo`、`ServerInfo`、`UploadTask` 等数据模型；HTTP API DTO；WebSocket 消息模型；`UploadQueueManager`（断点续传、3并发、Live Photo 配对）
- **photo_manager_ui**：`ThumbnailCell`、`MediaGridView`、`MediaViewer`、`AlbumListView`、`UploadProgressBar`、`CleanupConfirmDialog`、`ConnectionStatusBadge`、`DateRangePicker`、`AppTheme`
- **mobile_client**：相册读取（`photo_manager`）、设备发现（mDNS + UDP）、WebSocket 连接、上传、清理、还原
- **storage_server**：HTTP + WebSocket 服务器（shelf）、SQLite 数据库（sqflite_ffi）、缩略图生成队列（Isolate）、mDNS 广播、桌面 UI
