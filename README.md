# 蘇清的容器自动识别升级模组（实验版） / SuQing’s Automatic Container Upgrades Mod — Experimental

[中文](#中文) · [English](#english)

> **建议使用[固定名单版本](https://github.com/suching8848/suqing-container-upgrade)；自动适配版本作者本人还没有游戏内实测。**
>
> **Prefer the [fixed-list release](https://github.com/suching8848/suqing-container-upgrade); the author has not play-tested this automatic-adaptation version in the game.**

**0.1.0-test · Project Zomboid Build 42.21 · 单人实验版 / Single-player experimental version**

## 中文

**建议使用固定名单版本；自动适配版本作者本人还没有游戏内实测。**

为未来新档准备的独立普通容量升级实验版，Mod ID `SuQingContainerUpgradeAuto_4221`。**当前正式单人档未启用本版；不能把作者当前配置游玩正常的反馈当成本实验版已完成实机验收。** 本次只更新说明和元数据，不修改运行代码、图片、存档、默认启用列表或游戏安装。

它与[普通容器升级模组](https://github.com/suching8848/suqing-container-upgrade)是互斥选择。代码检测普通 Mod ID `SuQingContainerUpgrade_4221` 同时启用时拒绝操作；它使用独立命名空间和记录，不读取或迁移普通版的强化记录。**不要把两个普通升级版同时启用，也不要直接用本版替换已有强化的正式档。** EX 背包超级升级是另一独立项目。

### 能做什么

- 保留本实验分支的 168 项既有适配和原生升级链等排除策略；它不是将普通发布版 1.0.1 的 172 项名单整体移植过来。
- 启动时只扫描一次脚本定义，将容器候选写入本模组六条配方自己的 ID 和脚本缓存，不扫描地图、逐帧遍历库存或生成探测物品。
- 实际检查物品实例时，只让满足条件的标准可穿戴容器进入收费升级。未知高容量、动态容量、OnCreate 回调、原生换位/改码装备等需要单独适配；候选出现在制作菜单不等于可完成升级。
- 沿用五档容量 12/20/30/40/最高 49、减重 90/93/95/97/99%，既有更高值保留，实际容量受自重安全上限和角色特性影响。
- 五档分别消耗布/皮革/普通线用量 4/0/2、6/2/4、10/4/6、14/6/8、20/10/10；裁缝 0–4，针保留。普通满卷线是 20 用量。
- 成功还原返有效账本真实实付材料的 50%，各项向下取整，线按用量返还。免费制作、跳档和旧无账记录不产生新返料。

### 安装、补丁与停用

退出游戏并保留恢复方案后，将 `mods/SuQingContainerUpgradeAuto_4221` 复制到用户 `Zomboid/mods`，保留 `42`、`common`。仅在隔离的新单人测试档中启用，保持来源模组所需顺序；不自动部署或更改任何列表。制作分类为“蘇清·自动识别测试”；卸下容器，放主物品栏，清空物品及全部液体后操作。

[蘇清的僵尸毁灭工程补丁合集 / SuQing’s Project Zomboid Patches](https://github.com/suching8848/suqing-project-zomboid-patches)保留作者环境的独立修复，但**普通版专用兼容补丁不自动适用于本实验版**。例如 `Codex_SuQingWearableCompat_4221` 明确依赖普通容器主模组；不要为满足它而同时打开普通版和自动版。未知特殊容器需要针对本命名空间的适配及测试。

已强化物品要先按需还原再移除本模组。普通强化会保存物理属性，停用不会自动恢复；本实验版也不会替你迁移回普通版记录。不要执行历史默认名单回滚脚本覆盖后续设置。本仓库没有包含部署、回滚脚本或个人配置。

### 验证与来源

保留开发期识别/材料事务 fixture 和原生配方缓存验证源码，可用 [验证入口](docs/TESTING.md) 在自有游戏安装上重跑。离线模拟不等于真实 UI、转移、保存重进或所有未知模组兼容；多人和专用服务器未验证。

本实验版来源于作者自己的普通容器代码分支，图标复用同作者普通版已有 AI 辅助资源；未生成新图像。`mods/` 内的运行 Lua、配方、翻译与图片保持开发安装包原字节；只有 `README.txt` 和 `42/mod.info` 的说明按本次要求更新。`docs/runtime-sha256.json` 记录当前包快照，不能再把整包称为与历史源逐字节一致。原游戏和装备来源模组归各自作者，未擅加统一开源许可。详见 [来源与素材](docs/SOURCES.md)。

## English

**Prefer the fixed-list release; the author has not play-tested this automatic-adaptation version in the game.**

An independent ordinary-capacity experiment intended for future new saves, with Mod ID `SuQingContainerUpgradeAuto_4221`. **It is not enabled in the author's current main single-player save. Reports of normal play in the current setup do not establish in-game acceptance of this experiment.** This update changes documentation and metadata only, without changing runtime code, images, saves, default enabled lists or the installed game.

It is an alternative to [ordinary Container Upgrades](https://github.com/suching8848/suqing-container-upgrade). Code refuses operations when ordinary Mod ID `SuQingContainerUpgrade_4221` is also enabled. Its namespace and records are independent; it neither reads nor migrates ordinary upgrade records. **Do not enable both ordinary-upgrade versions together or directly replace an established upgraded save with this experiment.** EX Backpack Super Upgrades is another independent project.

### Behavior

- Preserves this branch's 168 existing supported IDs and exclusions such as native upgrade chains. It does not port the ordinary public 1.0.1 release's complete 172-ID list.
- Scans script definitions once at startup and updates only its six recipes' own candidate IDs/script caches. It does not scan the world, poll inventories every frame or create discovery samples.
- Validates the actual item before accepting standard wearable containers for paid upgrades. Unknown high/dynamic capacity, OnCreate callbacks and native position/size conversions require individual adapters. Appearing as a crafting candidate does not establish upgrade eligibility.
- Five capacity targets are 12/20/30/40/up to 49, with weight reduction 90/93/95/97/99%. Higher existing values remain; self-weight safety caps and character traits still affect actual capacity.
- Per-tier sheet/leather/normal-thread-use costs are 4/0/2, 6/2/4, 10/4/6, 14/6/8 and 20/10/10. Tailoring requirements are 0–4; a needle is kept. A full normal spool has 20 uses.
- Successful restoration refunds 50% of recorded actual payments, rounded down per material; thread returns in uses. Free crafting, skipped tiers and unrecorded old payments create no new refundable entitlement.

### Installation, patches and removal

Exit the game and retain a recovery option, then copy `mods/SuQingContainerUpgradeAuto_4221` into the user's `Zomboid/mods`, preserving `42` and `common`. Enable only in an isolated new single-player test save, respecting original mods' order. No script automatically deploys or changes lists. Use the “蘇清·自动识别测试” crafting category with the container unequipped in main inventory, empty of all items and fluids.

[SuQing’s Project Zomboid Patches](https://github.com/suching8848/suqing-project-zomboid-patches) contains separate fixes used in the author's environment, but **ordinary-version-specific adapters do not automatically apply to this experimental namespace**. For example, `Codex_SuQingWearableCompat_4221` explicitly requires the ordinary main mod; do not enable ordinary and automatic versions together to satisfy that dependency. Unknown special containers need dedicated adapters and tests.

Restore upgraded items as appropriate before removing this mod. Ordinary upgrades save physical attributes; disabling does not automatically restore them. This experiment does not migrate records back to the ordinary version. Do not apply historical default-list rollback scripts over later choices. No deployment/rollback scripts or personal configuration are included here.

### Validation and sources

Authored recognition/material-transaction fixtures and native recipe-cache tests are retained. Use the [validation entry point](docs/TESTING.md) with your own game installation. Offline mocks do not establish real UI, transfers, save/reload or compatibility with every unknown mod. Multiplayer and dedicated servers remain untested.

This branch derives from the author's ordinary container code. Icons reuse the same author's existing AI-assisted ordinary-version assets; no new images were generated. Runtime Lua, recipes, translations and images in `mods/` retain the development package bytes. Only `README.txt` and the description in `42/mod.info` were revised. `docs/runtime-sha256.json` records the current package snapshot; the whole package is no longer claimed to be byte-identical to the historical source. Original game/equipment mods belong to their authors; no blanket open-source license is assigned. See [Sources and assets](docs/SOURCES.md).

## 相关项目与配置快照

[10 个源码仓库与 42 个 Mod ID](docs/project-index.md) · [2026-11-02 01:10 的单人档启用快照（205 项）](docs/current-single-player-modlist.md) · [作者 Steam 合集](https://steamcommunity.com/sharedfiles/filedetails/?id=3823981387)

源码索引涵盖 42 个 Mod ID。Steam 合集不附带独立本地补丁；按各项目的前置和条件兼容说明选择子项。启用快照不代表每个项目或新增版本均已通过游戏内验收。

## Related projects and setup snapshot

[Ten source repositories and 42 Mod IDs](docs/project-index.md) · [Single-player enabled snapshot: 205 IDs on 2026-11-02 01:10 UTC+08:00](docs/current-single-player-modlist.md) · [Author’s Steam collection](https://steamcommunity.com/sharedfiles/filedetails/?id=3823981387)

The source index covers 42 Mod IDs. The Steam collection does not include separately installed local patches; select entries using each project’s requirements and conditional integration notes. Enabled state does not establish in-game acceptance of every project or new version.
