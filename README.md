# AirCard Manager 🎴

> **macOS 卡面管理端** — 在 [AirCard](https://github.com/Mak5er/AirCard) 之上补齐卡面素材库、卡名管理、应用历史与回滚、卡面包分享。
> 上游能力全部保留：Apple Wallet 卡面刷写与锁屏密码主题（iOS 18+，免越狱）。

**Fork 自 [`Mak5er/AirCard`](https://github.com/Mak5er/AirCard) 1.2.4（MIT）。** 设备通信与刷写路径未改动，本项目只在其上叠了一层卡面管理。

---

## 为什么要做管理端

上游把卡 hash 存在 `UserDefaults` 和 `~/.aircard_cards.json` 里，但**卡↔卡面的对应关系从不持久化**：
`saveCards()` 只写 hash 数组，所以重启 App 后每张卡分配的图全部丢失，只能重新挑一遍。
另外卡片只用 base64 hash 标识，也没有素材收藏和已刷记录。

AirCard Manager 把这层状态收进一个本地素材库：

| 问题 | 现在的行为 |
| --- | --- |
| 分配关系重启即丢 | 存进 `~/Library/Application Support/AirCard Manager/library.json`，启动自动恢复 |
| 原图被移动/删除后卡面失效 | 导入时把图片**复制**进素材库，之后与原文件无关 |
| 满屏 base64 hash 认不出哪张是哪张 | 每张卡可起中文别名，界面按别名展示，同时保留 hash 复制入口 |
| 刷坏了想换回上一版 | 每张卡记录成功刷入历史，可从历史列表一键重刷 |
| 想把一套卡面给朋友 | 选中若干张导出成 `.aircardpack`（zip + manifest），对方拖进来按内容哈希去重合并 |

---

## Features

### 新增（管理端）
- 🗂 **卡面库：** 独立标签页，缩略图网格 + 搜索 + 收藏 + 标签 + 重命名，支持多选批量删除。
- 🔗 **导入即复制：** PNG / JPG / HEIC / TIFF 等拖进来即收进素材库，SHA-256 去重，原图可随意处置。
- 🏷 **卡别名：** 给每张 Wallet 卡起中文名，卡片列表和刷写记录都按名字显示。
- 🕘 **应用历史与回滚：** 每次成功刷入都落库，可对单张卡重刷历史卡面。
- 📦 **卡面包：** 导出 / 导入 `.aircardpack`，携带名称、收藏位与标签，用于跨机迁移和分享。
- 🧰 **批量分配：** 素材右键「应用到卡片…」，一次把一张卡面分给多张卡。

### 上游原有
- 🎨 **Custom Card Skins:** Assign custom artwork, textures, or bank logos to Apple Pay and Wallet cards.
- 🔢 **Lock Screen Passcode Themes (.passthm):** Apply custom keypad button artwork from popular `.passthm` themes directly to iOS 18+ lockscreen.
- 🧩 **Passcode Theme Creator:** Create custom themes from a single wallpaper (Seamless Poster Slicing) or build key-by-key (Individual Keys).
- 🔍 **Interactive Photo Framing:** Pan and zoom artwork directly inside keypad buttons with real-time iPhone preview.
- ✏️ **Edit Existing .passthm Themes:** Open any Cowabunga or Nugget theme package directly in the creator, tweak button artwork, reposition photos, and re-export or flash.
- ⚡ **Per-Card & Bulk Customization:** Set unique artwork for each card or apply one design across all cards with a single click.
- 📱 **Zero-Hassle Card Detection:** Tap any card in your iPhone's Wallet app to detect its hash in real-time.
- 🚀 **100% Standalone (Universal):** Native support for both **Apple Silicon** and **Intel (x86)** Macs. All required device-communication utilities and image engines are pre-bundled inside the app.

---

## 数据放在哪

```
~/Library/Application Support/AirCard Manager/
├── library.json          # 素材索引、卡别名、卡↔卡面分配、刷写历史
└── Skins/                # 导入时复制进来的图片本体
```

删掉这个目录就恢复成空白状态。首次启动会自动并入 `~/.aircard_cards.json`、旧版
`UserDefaults`（`mak5er.savedCards` / `LumiCards.savedCards`）里的卡 hash。

---

## Installation

### macOS (Universal DMG)
1. Download **`AirCardManager.dmg`** from [Releases](https://github.com/WilliamWang1721/aircard-manager/releases).
2. Open it and drag **`AirCardManager.app`** into your **Applications** folder.
3. Fully compatible with both **Apple Silicon** and **Intel (x86)** Macs.

> [!NOTE]
> **First Launch on macOS (Gatekeeper):**
> If macOS displays an unidentified developer prompt on first launch:
> - **Method 1 (UI):** Right-click (or Control-click) `AirCardManager.app` in Applications ➔ click **Open** ➔ click **Open**.
> - **Method 2 (Terminal):**
>   ```sh
>   sudo xattr -cr /Applications/AirCardManager.app
>   ```

---

## 用法：管理并刷入卡面

1. iPhone 用数据线连 Mac，保持解锁并已信任。
2. 切到 **卡面库** 标签，把喜欢的图拖进去（或点「导入图片」）。
3. 切到 **Apple Wallet** 标签，点 **Scan Cards**，然后在 iPhone 上：
   - **双击侧键**打开 Apple Pay ➔ Face ID 认证 ➔ **点一下要识别的卡**。
4. 点卡片缩略图或「换卡面」，从卡面库里挑一张，顺手给它起个中文别名。
5. 勾上要处理的卡，点 **Flash Skins**。
6. 在 iPhone 的 App Switcher 里彻底关掉**钱包**（或重启）即可看到新卡面。
7. 想换回去：点这张卡的 🕘 图标，在应用记录里选「刷回这个」。

分配关系会一直留着，重启 App 后仍然有效。

---

## How to Apply Lockscreen Passcode Themes (.passthm)

1. Switch to the **Passcode Themes** tab at the top.
2. Drag & drop any `.passthm` file into the app (or click **Choose .passthm File**).
3. The theme is inspected and previewed on the numeric keypad (0–9, \*, #).
4. Click **Apply Passcode Theme**.
5. Restart your iPhone to reload the lock screen cache and see your custom passcode buttons!

> [!TIP]
> **Universal Language & Bold Text Support:**
> Custom keypad assets are expanded and flashed for all system locales, and both standard and
> **Bold Text** cache bitmaps (`--white` and `--white-bold`) are generated, so the theme works
> regardless of iOS language or accessibility display settings.

---

## If scanning finds no cards

The scanner uses the iPhone's unified log service, including Info/Debug events.
On iOS 18.6.2, the legacy log service can show Wallet activity while omitting the
resource lookup messages that contain card identifiers.

Open **Log** and check for `Connected to the unified device log stream`, then
double-click the side button, authenticate, and tap or switch cards. If the log
reader stops, reconnect and unlock the iPhone, then start another scan. Values
that iOS replaces with `<private>` cannot be recovered by the scanner.

See [scanner validation](docs/wallet-card-detection.md) for the verified environment
and remaining coverage.

---

## Building from Source

```sh
git clone https://github.com/WilliamWang1721/aircard-manager.git
cd aircard-manager
chmod +x build.sh
./build.sh
```

产出 `build/AirCardManager.app` 与 `build/AirCardManager.dmg`（universal：`arm64` + `x86_64`）。

> [!IMPORTANT]
> **SDK 版本**
> 上游的 SwiftUI 代码目前只能对着 **macOS 26 SDK** 编译；用 macOS 27 SDK 会在若干 `@State`
> 赋值处报 `cannot assign through subscript: 'self' is immutable`。`build.sh` 在只装了
> Command Line Tools 的机器上会自动回退到 `MacOSX26.sdk`。装了完整 Xcode 的机器请选 26.x
> 的 SDK，或先修掉这批 Swift 6 严格并发下的写法问题。
>
> 只想快速验证界面（跳过 `make` 和设备端 helper）：
> ```sh
> swiftc -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
>   -parse-as-library -target arm64-apple-macosx14.0 \
>   AirCardApp.swift ManagerStore.swift SkinLibraryView.swift -o /tmp/acm
> ```

---

## Scope

本项目只演进**卡面管理**这一层。设备通信与刷写实现（`Sources/`、`aircard.py`、
`aircard_backend.py`、`apply_card_skin.py`、`card_assets.py`）保持上游原样；本项目负责决定
「给哪张卡刷哪张图」以及把这些状态可靠地存下来，刷写动作本身仍走上游的
`aircard_backend.py --flash`。

---

## Contributors
- **[@mak5er](https://github.com/mak5er)** (Developer) — [GitHub](https://github.com/mak5er) · [Twitter / X](https://x.com/mak5er)
- **[@Lumid-Off](https://github.com/Lumid-Off)** (Contributor & Developer) — [GitHub](https://github.com/Lumid-Off) · [Twitter / X](https://x.com/LumidOff)
- **[AirLift](https://github.com/0xjohnnydev/airlift)** by **[0xjohnny (@0xjohnnydev)](https://github.com/0xjohnnydev)**: Original AirTraffic/ATAirlock sandbox escape and proof of concept underlying `AirliftFFI`.

## Credits
- Core exploit based on `airlift` (AirTraffic sync escape).
- 卡面管理端（本项目）by **[@WilliamWang1721](https://github.com/WilliamWang1721)**.

---

## Support

上游 AirCard 的开发支持渠道（与本项目无关）：

- **PayPal**: [Donate via PayPal](https://www.paypal.com/donate/?hosted_button_id=98QRTC2HFRA4Y)
- **TON**: `UQBm9KPhtMw-XVVjirUoa09wzrlyWsbeZhKfefl1Uw-qNZ-r`
- **USDT (TRC20)**: `TDkDMCyjYxgvkWUnQiF5Erk2RyPQMT6G1n`
- **USDT / BNB (BEP20)**: `0x0954dc491c502849d04956ef74634aa5931a08e8`
