# SDLPal Godot 复刻开发约束

## 适用范围

- 本仓同时包含根目录的 GPL 学习复刻实现（Legacy）与 `native/` 下独立编写的 MIT 运行时。下文“地图渲染基准”“CPU 对照渲染器”“最终退役条件”只适用于 Legacy；`PalTileMapWorld`、`GameSession`、CPU 对照及退役验收不是 Native 的实现依赖或前置条件。
- Native 任务以 `native/` 为 Godot 项目根，先读 `native/SOURCE_BOUNDARY.md`，再按任务读取 `native/README.md` 的相关功能、验证与未完成边界。使用其自身会话和 TileMap/GPU 呈现路径；视觉结论仍须有对应正式路径的带窗口证据。
- 不将 Legacy 代码、资源或测试迁入 Native，也不把根项目导出、Legacy 通关或 CPU 像素对照算作 Native 验收。双方产品目标与进度保留在各自现有文档和任务记录中。

## 地图渲染基准

- 正式运行和新增测试以 `TileMapLayer + PalTileMapWorld` 为准；不要把 CPU 合成画面当作功能完成依据。
- 人物选帧、坐标换算、调色板、Y 排序和遮挡规则应提取为共享逻辑，禁止在 CPU 与 TileMap 渲染器中各写一套容易分叉的实现。
- 修改地图、人物动作、镜头或遮挡后，至少验证 TileMap 正式路径；真实画面问题必须使用带窗口运行和实际像素截图检查，不能只断言 CPU 状态。

## CPU 对照渲染器

- `PalSceneRenderer` 的整屏 CPU 合成只用于开发期诊断、像素基准和临时回退，不再扩展为新的正式运行能力。
- 复刻画面出现差异时，可以把同一个 `GameSession` 分别交给 TileMap 和 CPU 路径，以 320×200、最近邻、整数相机坐标进行对照；截图只能写入被 Git 忽略的 `generated/pal/visual_tests/`。
- 对照发现差异后，应修复 TileMap 正式路径或共享规则；不能为了让 CPU 测试通过而遗漏 `PalTileMapWorld`。

## 最终退役条件

- 全部有效地图、主线剧情、特殊遮挡和完整通关均通过 TileMap 验收后，移除正式运行中的 CPU 地图渲染路径。
- 退役范围包括 `MapExplorer` 的 `_map_view`、`_use_legacy_renderer`、`--pal-map-backend=legacy` 以及生产流程中的整屏 CPU 合成与纹理上传。
- 如仍需要像素基准，只在 `tests/` 或 `tools/` 中保留最小对照能力，不随正式游戏运行。

## 提交约定

- 当前请求或本会话已有授权覆盖提交时，每完成并验证一个边界清晰的功能阶段或 Bug 修复，创建独立 Git 提交，不把后续功能、主线推进或无关改动混入同一提交。
- 提交前完成与改动风险相称的验证；纯文档/指令修改做差异和引用检查，产品行为修改再选择相关合成、真实资源或带窗口回归。只暂存本次完成项涉及的文件。
