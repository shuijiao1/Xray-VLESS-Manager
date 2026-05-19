# Xray VLESS Manager

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![Xray](https://img.shields.io/badge/Core-Xray--core-blue?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

**中文** | [English](README.en.md)

**一个轻量的 Xray-core / VLESS 一键管理脚本，按官方 XTLS/Xray-examples 模板生成常用 VLESS 组合配置。**

> 适合快速在 VPS 上安装 Xray-core、生成 VLESS 服务端配置和客户端链接。默认推荐 `VLESS + XTLS Vision + REALITY`。

---

## 🎯 核心特性

- 支持 Xray-core 官方安装脚本安装 / 更新
- 按官方模板生成服务端配置，并在重启前执行 `xray test -config` 校验
- 自动生成 UUID、REALITY X25519 key、shortId、WS/XHTTP path、gRPC serviceName
- 输出 VLESS URI、关键参数和客户端 JSON
- 菜单风格简洁，支持查看配置、重启、日志、卸载

---

## 🧩 支持组合

| 菜单 | 组合 | 参考官方模板 / 文档 | 说明 |
| --- | --- | --- | --- |
| 2 | VLESS TCP 明文 | `VLESS-TCP` | 仅建议测试或套前置，不推荐公网裸跑 |
| 3 | VLESS + XTLS Vision + REALITY | `VLESS-TCP-XTLS-Vision-REALITY` | 推荐默认方案 |
| 4 | VLESS TCP + REALITY | `VLESS-TCP-REALITY` | 不启用 Vision flow |
| 5 | VLESS + WebSocket + TLS | `VLESS-WSS-Nginx` / `VLESS-TCP-TLS-WS` | 初版内置自签证书，生产建议前置 ACME |
| 6 | VLESS + gRPC + REALITY | `VLESS-gRPC-REALITY` | 可选 REALITY 组合 |
| 7 | VLESS + XHTTP + REALITY | `VLESS-XHTTP-Reality` | 较新方案，建议 Xray >= v25.3.6 |
| 8 | VLESS Encryption TCP | VLESS Encryption / `xray vlessenc` | 需要服务端和客户端都支持新字段 |

---

## 🚀 快速开始

```bash
bash <(curl -Ls https://xray.shuijiao.de)
```

备用方式：

```bash
curl -Lo xray-vless.sh https://raw.githubusercontent.com/shuijiao1/Xray-VLESS-Manager/main/xray-vless.sh
chmod +x xray-vless.sh
./xray-vless.sh
```

---

## 💬 菜单预览

```text
============================================
 Xray VLESS Manager
 Repo: Xray-VLESS-Manager
 Author: shuijiao
============================================
安装状态: 已安装 / 未安装
运行状态: 运行中 / 未运行

=== 基础功能 ===
 1) 安装/更新 Xray-core
 2) 安装 VLESS TCP 明文
 3) 安装 VLESS + XTLS Vision + REALITY（推荐）
 4) 安装 VLESS TCP + REALITY
 5) 安装 VLESS + WebSocket + TLS
 6) 安装 VLESS + gRPC + REALITY
 7) 安装 VLESS + XHTTP + REALITY
 8) 安装 VLESS Encryption TCP

=== 服务管理 ===
 9) 查看客户端配置
10) 重启 Xray
11) 查看日志

=== 系统功能 ===
12) 卸载 Xray
 0) 退出
```

---

## ⚙️ 安装流程

选择安装组合后，脚本通常只需要 1-3 个输入：

- 端口，默认 `443`
- REALITY SNI / target，默认 `www.microsoft.com`
- 域名或路径，仅 WS/TLS、XHTTP 等模式需要

脚本会自动完成：

1. 检查 / 安装依赖
2. 安装或复用 Xray-core
3. 生成密钥与随机参数
4. 写入 `/usr/local/etc/xray/config.json`
5. 生成 `/usr/local/etc/xray/client.txt` 和 `client.json`
6. 执行 `xray test -config /usr/local/etc/xray/config.json`
7. 校验通过后重启 `xray`

---

## ⚠️ 注意事项

- REALITY 的目标站点建议选择支持 TLS 1.3 / H2、非跳转主站的海外站点。
- `VLESS TCP 明文` 没有传输层加密，不推荐公网裸跑。
- `VLESS Encryption` 是较新的能力，脚本使用 `xray vlessenc` 生成字段；客户端不支持时可能无法导入或连接。
- `WebSocket + TLS` 初版使用自签证书；生产环境更推荐 Caddy / Nginx / ACME 作为前置。
- 脚本会覆盖 `/usr/local/etc/xray/config.json`，已有复杂配置请先备份。

---

## 🛠 测试

仓库包含基础静态检查：

```bash
bash tests/static-check.sh
```

实际安装前，脚本每次都会执行：

```bash
xray test -config /usr/local/etc/xray/config.json
```

校验通过后才会重启服务。

---

## 📄 许可证

MIT License
