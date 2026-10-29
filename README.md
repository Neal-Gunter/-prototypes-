# 玄界 XUANJIE

2.5D 拼刀 / 肉鸽 · Godot 4.7.2（GL Compatibility）· 1280×720
零外部美术：所有角色、场景、特效均由 `_draw()` 程序化绘制。

## 当前版本：R38 · 因果 / 业力（三结局 + 魔剑）

七关 · 35 件法宝 · 4 种武器 · 24 条经脉 · 自测 196 条全过。

## 目录

| 路径 | 内容 |
|---|---|
| `scripts/` | 全部 GDScript（29 个） |
| `scenes/` | 场景文件 |
| `docs/` | 更新明细 / 任务进度表 / 纵深扩展总纲 / 自测记录 |
| `玩法说明.txt` | 面向玩家的完整说明（33 个核心机制） |
| `tools/` | 自测与审计脚本 |

## 本地运行

```
godot --path . 
```

自测：

```
godot --headless --path . --script res://tools/selftest.gd
```

## 构建

`XUANJIE.exe` / `XUANJIE.apk` 不入库（见 `.gitignore`）。
`export_presets.cfg` 因含签名口令同样不入库，需自行配置。
