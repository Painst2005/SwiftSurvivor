# Thunder Swift

一个使用 Swift 6.x、Swift Package Manager 和 SDL3 的 2D 纵向卷轴飞行射击小游戏。玩法参考经典街机飞行射击：战机在屏幕下方移动，自动向上开火，迎战敌机编队、敌方弹幕和阶段 Boss。当前采用渐进迁移策略：成熟的 Win32/GDI 游戏后端继续作为兼容路径，SDL3 平台层、渲染抽象、输入动作层和固定时间步已接入，后续按模块迁移实际战斗渲染。

## 运行环境

- Windows 10/11
- Swift 6.x for Windows（本机已验证 Swift 6.3.3）
- SDL3 3.4.14（随项目放在 `Vendor/SDL3-3.4.14`，运行时需要 `SDL3.dll`）

## 编译与运行

在此目录打开 PowerShell：

```powershell
swift build -c release --scratch-path .build-game
Copy-Item Vendor\SDL3-3.4.14\lib\x64\SDL3.dll .build-game\x86_64-unknown-windows-msvc\release -Force
.build-game\x86_64-unknown-windows-msvc\release\SwiftSurvivor.exe
```

也可以直接运行 `BuildAndRun.ps1`，脚本会自动复制 SDL3 运行库。

验证 SDL3 窗口、输入和基础 2D Renderer：

```powershell
.build-game\x86_64-unknown-windows-msvc\release\SwiftSurvivor.exe --sdl-smoke
```

运行第一版 SDL 战斗纵向切片（复用现有战斗逻辑，暂不包含完整菜单 UI）：

```powershell
.build-game\x86_64-unknown-windows-msvc\release\SwiftSurvivor.exe --sdl-game
```

运行完整本地化 UI 的 SDL 展示桥接模式（GDI 负责字体栅格化，SDL 负责窗口和最终呈现）：

```powershell
.build-game\x86_64-unknown-windows-msvc\release\SwiftSurvivor.exe --sdl-full
```

也可以直接运行构建出的程序：

```powershell
.build-game\x86_64-unknown-windows-msvc\release\SwiftSurvivor.exe
```

如果直接双击项目根目录的旧版 `SwiftSurvivor.exe`，它仍使用兼容的 GDI 后端；通过脚本构建的版本会同时带上 SDL3 运行库。

## 操作

- 菜单按 **Enter** 开始
- 游戏中使用 **WASD** 或方向键驾驶战机
- 按住 **Shift** 进入低速精准模式，战机核心碰撞点会高亮
- 武器会自动向上连续射击，火力等级越高弹道越宽
- 敌机按编队从上方进入，逐步加入战斗机、俯冲机、炮艇、狙击机、护盾机、自爆机和母舰
- 不同敌人拥有不同职责：炮艇定点压制、狙击机先显示锁定线、护盾机保护附近敌机、自爆机高速冲刺、母舰周期召唤小飞机
- 敌方弹道分为垂直直线、横向摆动和仅修正 X 轴的追踪弹；所有敌弹的 Y 方向始终向下，不会倒退
- 击毁敌机有机会掉落限时战斗道具
- 战斗道具现在包括限时穿透激光、无敌反弹护盾和额外子弹阵列
- 每次拾取道具都会在 HUD 下方显示名称、效果和剩余提示时间
- 收集 XP 升级时按 **1/2/3** 选择强化模块
- 局内升级现在从 12 种模块中随机抽取 3 个，并带有 Common / Rare / Epic / Legendary 四档品质
- 强化会影响武器等级、射速、伤害、暴击、穿透、辅助弹幕、擦弹窗口、Combo 分数和雷霆能量
- 武器最高进化到 7 级；Laser Focus + Cryo Core 会激活 **Frost Ray**，Auxiliary Array + Overdrive 会激活 **Flight Array**，Storm Core + 暴击会激活 **Storm Crit**
- 主武器现支持 **Cannon / Laser / Scatter / Missile / EMP** 五种类型，游戏中按 **Q** 循环切换；每种武器拥有独立的射速、弹道、伤害和穿透表现
- Missile 会自动寻找最近目标并进行转向追踪；EMP 发射带有横向摆动轨迹的电磁球，适合持续压制
- 敌方弹幕采用 Bullet / Emitter / Pattern / Modifier 分层：支持直线、瞄准、三连、扇形、环形、螺旋，以及加速、限时追踪、蛇形、延迟启动、停顿爆发、曲线、分裂和边界反弹等组合
- 子弹统一经过回收池管理，并设置全局弹幕上限；敌方子弹只会向屏幕下方推进，不会在追踪时出现 Y 轴回退
- 难度会随时间平滑递增：前 20 秒为熟悉阶段，之后逐渐增加速度、血量、数量和弹幕频率
- 约第 42 秒出现首个大型 Boss，之后约每 45 秒穿插一次；Boss 战期间暂停普通编队
- Boss 拥有 100%-70%、70%-30%、30%-0% 三个阶段，阶段切换会改变移动方式、弹幕密度并显示预警；章节会轮换无畏战舰、裂隙巨兽、寒霜守望者和起源构造者四类 Boss
- Boss 拥有左右独立炮塔弱点；炮塔被摧毁后会禁用对应侧武器。二、三阶段会加入带锁定提示的固定航道激光，预警结束后才激活
- Boss 被击毁后会进入短暂奖励过场：清除残弹、修复部分机体、补充雷霆能量并释放三件限时战斗道具
- Boss 奖励同时提供额外 XP 和分数，奖励缓存会在 HUD 中显示，避免下一波敌人无缝压入造成节奏突兀
- Boss 击毁时会延迟到当前子弹更新结束后再清理敌方残弹，避免数组遍历中修改导致闪退
- 启动后自动播放适合战斗的太空合成器循环配乐；首选 `thunder_swift_battle.mp3`，若系统 MPEG 解码器不可用则自动回退到本地 PCM 配乐
- 音频系统支持背景音乐与独立短音效（射击、命中、爆炸、道具、Boss、强化、成就），Settings 可分别调整 BGM/SFX 音量
- 连续击杀会形成 **Combo**，擦过敌弹会触发 **Graze** 并积累雷霆能量
- 雷霆能量达到 100% 后按 **Space** 释放雷霆超载：清除敌弹、短暂无敌并强化火力
- 主菜单提供 **New Game / Controls / Hangar / Archive / Settings / Exit** 按钮，支持鼠标悬停和点击
- 开始界面左上角提供 **SAVE SLOT** 存档入口，支持 3 个独立存档位；点击可载入已有档案或创建新档案，进度自动写入游戏根目录
- 点击 **New Game** 会进入 Mission Control，可选择章节区域和飞行模式；章节完成后自动解锁下一关
- 当前提供 **Campaign / Endless / Blitz / Zen** 四种模式：章节模式有明确时长和 Boss 目标，无尽模式持续挑战，爽快模式提高火力与掉落并要求限时击杀目标，禅模式降低受伤压力并保留密集编队
- 不同章节拥有独立的难度、Boss 时间、推荐战力和奖励倍率，选定模式后会动态调整敌机数量、敌弹伤害、玩家火力和结算奖励；爽快模式会在 HUD 显示击杀目标
- Settings 页面支持 **English / 中文** 双语切换，选择会立即刷新主要界面并写入本地存档
- Settings 还支持屏幕震动 OFF/LOW/MED/HIGH，设置会写入版本化存档
- Settings 支持 **FULLSCREEN / WINDOWED** 全屏与窗口化切换，切换立即生效并写入当前存档
- Settings 支持 **1024 × 768 / 1280 × 720** 分辨率切换；窗口化会按所选分辨率调整窗口，设置按存档保存
- 局内不再显示或维护玩家等级：经验只作为“强化选择充能”，达到阈值即可进入三选一强化；武器等级与机库模块等级均取消硬上限，品质提升也不再要求先达到指定等级
- 主菜单 Archive 提供成就进度和战斗图鉴；图鉴按武器、敌机、Boss 分类，并按战斗进度解锁条目
- 主菜单的 **Hangar** 机库入口可查看战机模块、等级、品质和强化费用
- 击杀敌机和 Boss 会获得 **Credits / Cores / Alloy**；资源、装备等级和战机选择会自动保存到本地
- 机库包含机体、主武器、副武器、装甲和僚机相关的 Loadout/Vault 管理；点击装备卡即可强化，点击仓库模块即可替换对应槽位
- 装备支持等级、品质、星级、进阶和稀有随机词条；高等级模块会在关键等级自动进阶
- 机库提供 **THUNDER / GHOST / HEAVY / DESTROYER / CARRIER** 五种战机，各自改变生命、速度、伤害或被动效果
- 副武器会独立定时发射，僚机会按等级生成侧翼弹幕；装甲提供减伤和一次性护盾
- 机库显示 Combat Power、模块仓库数量和强化所需的 C / A / CORE 成本
- 装备品质支持白/蓝/紫/金/红五档；模块最高 50 级，达到等级门槛后可消耗金币、合金和核心升品，升品会提升星级/进阶并补充词条
- 模块仓库支持按槽位筛选、按品质/等级/槽位排序、分页浏览；五个装备槽位均可从仓库替换
- Boss 稀有模块掉落带有保底计数，连续未掉落后会自动保证下一次稀有缓存
- 存档带有版本号和备份副本，优先读取主档，异常时自动回退到备份档；旧版 v1/v2 存档会自动迁移，设置和成就也会保存
- 存档文件位于游戏根目录：`SwiftSurvivorSave1.json`、`SwiftSurvivorSave2.json`、`SwiftSurvivorSave3.json`，并为每个存档保留 `.backup.json` 备份
- 窗口采用持久化双缓冲和无擦除刷新，避免高频重绘、爆炸特效和 Boss 战期间的画面闪烁
- 游戏以无边框全屏方式运行，星空背景与战斗画布覆盖整个显示器；战斗使用 1000×760 逻辑分辨率并按 DPI 等比放大，保持战机、子弹和 HUD 的合适尺寸，避免高分辨率下画面空旷
- 背景音乐使用 Windows 原生 `PlaySoundW` 循环播放由 `thunder_swift_battle.mp3` 解码得到的 `thunder_swift_battle.wav`，绕过 MCI 解码器并保留原始 MP3 资源
- Windows 版本按图形子系统链接，启动时不会额外弹出控制台终端窗口
- 性能优化：GDI 画刷跨帧缓存、粒子原地压缩、弹幕回收减少数组搬移、碰撞使用平方距离、战斗中的鼠标移动不再触发重复全屏重绘；粒子密集时自动降低绘制采样而不改变碰撞逻辑。音频命令在独立队列执行，窗口启用 DPI 感知，并以 1ms 唤醒配合独立 60Hz 截止时间稳定呈现；战斗 HUD 会显示实时 FPS
- Controls 页面可切换 **WASD** 或 **Mouse Follow** 驾驶方式
- 游戏中按 **P** 或 **Esc** 打开暂停菜单，可选择 Resume、Restart、Controls、Main Menu（回到开始界面）或 Exit to Desktop
- 死亡结算页面可点击 Restart 或 Main Menu，按 **R** 也可重新出击

最高分会保存在 Windows 的用户应用设置中，下次启动仍然保留。

## 文件说明

- `Package.swift`：Swift Package Manager 配置
- `Sources/SwiftSurvivor/App.swift`：游戏状态、敌人逻辑、升级系统、音频播放、Win32 窗口与 GDI 绘制
- `Sources/SwiftSurvivor/Combat/BulletSystem.swift`：Bullet 核心数据、Emitter、Pattern、Modifier 和子弹类型定义
- `Sources/SwiftSurvivor/Progression/SaveManager.swift`：版本化本地玩家档案、资源、装备和备份存档
- `Resources/Audio/thunder_swift_bgm.wav`：原创 48 秒循环背景音乐
- `Resources/Audio/thunder_swift_battle.mp3`：OpenGameArt《Space Battle》（MintoDog，CC0）战斗配乐
- `Tools/generate_audio.py`：重新生成背景音乐的脚本
- `Tools/generate_sfx.py`：重新生成射击、命中、爆炸、道具、Boss、强化和成就音效的脚本
