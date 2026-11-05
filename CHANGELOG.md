# 更新记录

## v1.4.5 — 2026-11-05

适配官方 SCSKiller **1.4.5**。

- 译表扩到 **1114 条**，实际替换 **1152 处**
  （`SCSKiller.dll` 543 / `SCSKiller.Ui.Models.dll` 371 / `SCSKiller.Core.dll` 238）
- 新增翻译：游戏详情页的着色器覆盖说明、设置页多段长描述、编译队列的状态行与限流提示、
  缓存页分组标题、各类错误/警告对话框
- **修复崩溃问题**：1.4.5 把 `SharedSizeGroup`、样式类名、InfoBar `Severity` 也写成了字符串
  字面量，且与界面文案共用同一字符串条目；Avalonia 要求这些值必须是 ASCII 标识符，
  译成中文会启动即抛 `ArgumentException`
  → 新增按程序集生效的跳过清单（`Cache`、`Shaders`、`Time`、`Status`、`Details`、`Priority`、
  `Cards`、`Table`、`Narrow`、`Stacked`、`Loose` 等保持英文）
- 跨程序集同名词不受影响：`Pipelines`、`Cache` 在 UI 程序集里是组名（跳过），
  在 `Ui.Models` 里是表头（已译）
- 验证：官方 1.4.5 包离屏渲染 585 张截图 / 退出码 0；`#US` 堆外 0 处字节改动；
  PowerShell 5.1 与 Python 两套实现产出 SHA-256 一致；`-Revert` 可还原到官方哈希

## v1.4.2 — 2026-10-31

首个版本，适配官方 SCSKiller **1.4.2**。

- 译表 **702 条**，实际替换 **756 处**
  （`SCSKiller.dll` 539 / `SCSKiller.Ui.Models.dll` 150 / `SCSKiller.Core.dll` 67）
- 覆盖主窗口、游戏库（含状态列）、游戏详情、编译队列、缓存、设置、关于页与各类对话框
- 验证：汉化前后各 502 张离屏截图，数量与退出码一致；堆外 0 处字节改动
