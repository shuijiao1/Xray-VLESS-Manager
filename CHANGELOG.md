# Changelog

## [0.1.5] - 2026-05-29

- 修复旧版 `xray-vless.service` 与脚本标准 `xray.service` 不一致导致的运行状态误判。
- `查看客户端配置` 在 `client.txt` 缺失时会从现有配置自动恢复纯 VLESS TCP 客户端信息。
- 修正生成的客户端 JSON 为 Xray 标准 `vnext/users` 结构，并补充旧服务迁移菜单。

## [0.1.4] - 2026-05-20

- 补充 Issue 模板，增强 shellcheck/shfmt CI，并在 Release 中附带脚本文件。

## [0.1.3] - 2026-05-20

- 加入基础 CI、防泄密检查、Actions Node24 兼容设置和本地项目健康检查。

## [0.1.2] - 2026-05-20

- 补齐中英双语 README、统一部署说明，并加入本地 release helper。

All notable changes to this project are documented here.

## [0.1.1] - 2026-05-19

- 修复 Release workflow YAML，确保 tag 发布会自动用 CHANGELOG 生成 Release notes。

## [0.1.0] - 2026-05-19

- 初始版本基线；为脚本加入版本号、CHANGELOG 与 Release 流程。
