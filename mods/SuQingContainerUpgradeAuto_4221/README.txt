蘇清的容器升级·自动识别测试版 / SuQing’s Automatic Container Upgrades — Experimental
0.1.0-test · Project Zomboid Build 42.21 单人 / single-player

建议使用固定名单版本；自动适配版本作者本人还没有游戏内实测。
Prefer the fixed-list release; the author has not play-tested this automatic-adaptation version in the game.
固定名单版 / Fixed-list release: https://github.com/suching8848/suqing-container-upgrade

中文
这是独立的普通容量升级实验版，不是EX。当前正式单人档未启用本版；作者当前完整配置游玩正常的反馈不构成本版的游戏内验证。
图像沿用普通版已有资源，本次未改图片；本实验版使用独立Mod ID、命名空间和记录，不读取或迁移普通版强化记录。
不要与普通版SuQingContainerUpgrade_4221同时启用；同时启用时实验版拒绝操作。不要直接替换已有普通强化的正式档。
本分支保留168项既有支持和排除策略，不等于普通发布版1.0.1的完整172项名单。
启动时只扫描一次脚本定义，更新本模组六条配方候选ID和脚本缓存；不扫地图、不逐帧遍历库存、不生成探测样品。
实际物品通过检查后，标准未知可穿戴容器才可收费强化；未知高容量、动态容量、OnCreate回调、换位/改码装备需单独适配；非穿戴箱子不支持。
制作分类“蘇清·自动识别测试”；材料、裁缝等级、五档目标及实付50%还原沿用本分支原规则。
卸下容器，放主物品栏，清空普通物品及全部液体后操作。
建议仅在有恢复方案的隔离新单人测试档使用。离线Kahlua/原生解析检查不等于作者游戏内实测，界面、真实转移和保存重进仍未由作者实机确认；多人未验证。
说明和mod.info描述已更新；运行代码、翻译、配方、图片、Mod ID及版本未改。当前包哈希见docs/runtime-sha256.json，不再宣称整个包与历史安装源逐字节相同。

English
This is an independent ordinary-capacity experiment, not EX. It is not enabled in the current main single-player save; reports of normal play in the author's complete setup do not validate this experiment in the game.
Images reuse the ordinary version's existing assets and are unchanged in this update. Mod ID, namespace and records are independent; ordinary-version upgrade records are neither read nor migrated.
Do not enable it with ordinary Mod ID SuQingContainerUpgrade_4221. Operations are refused when both are enabled. Do not directly replace an established ordinary-upgrade save.
This branch retains 168 existing supported IDs and exclusions, not the ordinary public 1.0.1 release's complete 172-ID list.
It scans script definitions once at startup, updating only its six recipes' candidate IDs and script caches; no world scan, per-frame inventory polling or discovery samples.
Standard unknown wearable containers can be paid-upgrade targets only after instance validation. Unknown high/dynamic capacity, OnCreate callbacks and position/size conversions need individual adapters; non-wearable crates are unsupported.
Use the “蘇清·自动识别测试” crafting category. Existing material costs, Tailoring levels, five tier targets and 50% actual-payment restoration remain unchanged.
Unequip the container, place it in main inventory and empty all items and fluids before use.
Use only in an isolated new single-player test save with a recovery option. Offline Kahlua/native-parser checks are not the author's in-game play-test. UI, real transfers and save/reload have not been accepted by the author in the game; multiplayer is untested.
Documentation and the mod.info description were revised. Runtime code, translations, recipes, images, Mod ID and version are unchanged. The current package snapshot is in docs/runtime-sha256.json; the whole package is no longer claimed to be byte-identical to its historical source.
