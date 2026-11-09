# KuXuan 原生 iOS 版（自用）

按 `markruan/kuxuan` 的视觉样式做的 iPhone 原生 App。**只给自己用，不上架、不发布、不联网取音源。**

---

## 零、最短操作路径（2026-11-09 更新）

USB 信任**已验证生效**（`python3 check_device.py` 读到配对 HostID，UDID
`00008130-0018486C0A9A001C`）。剩下三步只能你本人做：

1. **双击 `一键编译IPA.command`** → 粘贴一个 GitHub PAT（repo 权限）。
   脚本自动：建公开仓库 → 单次 commit 上传 15 个文件 → 触发 Actions →
   轮询编译 → 下载 `~/Downloads/KuXuan-unsigned.ipa`。
   token 用 `getpass` 读取，不回显、不写盘、不进对话。
2. **浏览器打开 sideloadly.io 下载 Sideloadly**（官网 DMG 在本命令行环境被
   SSL 层拦截，`UNEXPECTED_EOF_WHILE_READING`，重试 6 次均失败；你的浏览器不受此限）。
   拖入 IPA → 输入**你自己的** Apple ID → Start。密码我不经手。
3. **手机**：设置 → 通用 → VPN与设备管理 → 信任你的 Apple ID；
   iOS 16+ 若提示还需开「开发者模式」。免费签名 7 天过期需重签。

> `check_device.py` 用纯标准库实现 usbmuxd + lockdown，可随时复查配对状态，
> 不依赖 libimobiledevice（本机装 pymobiledevice3 会因 CLT 损坏、cryptography
> 编译失败而装不上）。

**修过的两个真问题**：
- `unsigned-ipa.yml` 去掉了 `on: push`——上传用 contents API 逐文件提交会产生
  多次 commit，挂 push 会重复跑 N 次 CI；现改为一次性 `workflow_dispatch`。
- `one_click.py` 不再排除 `.png`——`KuXuan/Resources/icon.png` 是前端引用的资源，
  排除会导致编译产物里 favicon 404。上传改用 Git Data API 单次 commit。

**如实说明**：CI 从未真跑过，首次大概率要看报错迭代 1–2 轮；把失败日志贴给我即可。
Sideloadly 官网自称支持 iOS 7–27+，但对 **27.3 beta** 的兼容性无第三方确认，
AltStore Classic 在 27 beta 大面积失败，我不替它打包票。

---

## 一、结论先行

| | |
|---|---|
| 能不能装进你自己的 iPhone | **能，且合规**（免费 Apple ID 允许把自写 App 装到自己的设备） |
| 你这台 Mac 能不能编译 | **不能，硬件级死局**（见下） |
| 那怎么编译 | **GitHub Actions 云端编译出未签名 IPA**，公开仓库免费 |
| 装进手机的方式 | Sideloadly / SideStore 侧载（免费 7 天重签，或付费 ¥688/年）；或付费后走 TestFlight |
| 我本机能不能验证编译 | **不能**。本机无 Xcode、CLT 损坏，首轮 CI 需要看日志迭代 |

**判断（非事实）**：如果你的核心诉求只是「后台播放 + 锁屏控制」，这一版值得做；如果只是「手机上看得到这个界面」，上一版的 PWA 已经够了，不必折腾签名。

---

## 二、为什么本机编译这条路走不通（事实）

刚在这台 Mac 上实测：

| 项 | 结果 |
|---|---|
| 机型 / 系统 | MacBookPro15,2（2018 Intel）/ macOS 13.7.8 |
| Xcode | 未安装；系统上限 **Xcode 15.2**（Apple《SDK 与系统要求》：15.2 支持 Ventura 13.5–Sonoma 14.x，15.3 起要求 Sonoma 14.x，16 要求 14.5+） |
| Command Line Tools | 损坏，缺 `xcrun`；`git` / `swift` 均报 `invalid active developer path` |
| `sudo` 免密 | 不可用 |
| 钥匙串签名证书 | 0 个 |
| GitHub 工具链 | `gh` 未安装、`git` 不可用、无 token |

而你的 iPhone 是 **iPhone 15 Pro / iOS 27.3 beta（24C5037i）**。Apple 开发者站 2026-11-03 公告明确写着「请务必使用 **Xcode 27.3** 进行构建和测试」。Xcode 27 需要 macOS 27，而 **macOS 26 起已彻底放弃 Intel 机型**。

→ 结论：**本机 Xcode 直连调试 iOS 27.3 不可能实现**，不是装个软件或改配置能绕的。上一轮评估里「装 Xcode 15.2 试试」的说法在此作废。

顺带更正上一轮另外两点：
- CLT 损坏**不是死局**（装完整 Xcode 后可用 `DEVELOPER_DIR` 环境变量绕过），只是现在没必要修了；
- 原生版**不需要重写 UI**：本工程用 WKWebView 直接复用了上一版的 `style.css` 和界面结构。

---

## 三、三条落地路径（iOS 27.3 beta 下的重新排序）

| 路径 | 成本 | 稳定性 | 说明 |
|---|---|---|---|
| **A 云端编译 + 免费侧载** | ¥0 | ⚠️ beta 上偏脆 | 出 unsigned IPA，Sideloadly 用免费 Apple ID 签，**7 天过期**、最多 3 个侧载 App |
| **B 云端编译 + 付费侧载** | ¥688/年 | 较稳 | 同一个 IPA，付费账号签名有效期 1 年 |
| **C 付费 + TestFlight 内部测试** | ¥688/年 | **最稳** | 内部测试员**无需 Beta 审核**，构建 90 天有效；Apple 官方渠道必然兼容 27.3 beta；不用开发者模式、不用信任证书、不用每周重签 |
| D 保持 PWA | ¥0 | 稳 | 已可用，但没有后台播放、锁屏控制，且依赖 Mac 开机 |

### iOS 27.3 beta 的额外风险（必须知道）

- **TrollStore 巨魔完全不适用**：只支持 iOS 14.0–16.6.1 / 16.7 RC / 17.0，CoreTrust 漏洞在 17.0.1 已修，且无法降级。别信「付费激活码装 iOS 18/27 巨魔」。
- **免费侧载工具在 iOS 27 beta 上状态不一**：AltStore Classic 大面积失败（AltServer 取不到 anisette machineID，截至资料发布时无修复）；SideStore 可运行但有 UDID bug；Sideloadly 官网自述支持 iOS 7–27+ 且 macOS 10.12+，但第三方资料说 iOS 27 尚未获官方确认 —— **两方说法冲突，我不替它打包票**，以你实机结果为准。
- **中国大陆不适用欧盟 DMA 第三方商店**：目前仅欧盟、日本、巴西，且要求账号地区与实际所在地一致。
- 免费 Apple ID 侧载需要：设置 → 隐私与安全性 → **开发者模式** 打开，安装后在「VPN 与设备管理」里信任证书。

### 我的推荐

想要长期省心、天天用 → **路径 C（TestFlight）**，代价是 ¥688/年 + 每 90 天重新上传一次构建。
想零成本先试 → **路径 A**，但接受 beta 上可能要重配对、重签。
**无论选哪个，工程代码和 IPA 都是同一套**，不用现在就决定。

---

## 四、技术方案

```
界面：WKWebView 加载包内 index.html / style.css / native.js（复刻原有橙粉→玫红渐变、旋转唱片、歌词页、底部播放条）
音频：原生 AVPlayer + AVAudioSession(.playback) + MPNowPlayingInfoCenter + MPRemoteCommandCenter
通信：JS → window.webkit.messageHandlers.kx.postMessage({cmd,...})
      原生 → webView.evaluateJavaScript("KX.onSongs/onSong/onState/onLyric(...)")
曲库：App 的 Documents 目录，UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace
      支持 mp3/m4a/aac/wav/aiff/caf/flac；AVAsset 读内嵌 title/artist/封面；同名 .lrc 出歌词
```

**关键设计判断**：音频绝不放在 WebView 里播。WKWebView 内的 HTML5 audio 在 App 切后台后通常会被系统暂停，那样「原生」就白做了。由原生驱动还能保证**后台自动续播**、锁屏切歌都正常工作。

**曲库改成手机本地**（上一版的曲库在 Mac 上）：否则 Mac 关机/休眠/换网，原生 App 的离线优势会被抵消。App 内「导入帮助」标签页写了三种导入方式。

**目录**

```
native/                          ← 把这个目录当作 GitHub 仓库的根
├── project.yml                  XcodeGen 配置（CI 里生成 .xcodeproj）
├── KuXuan/
│   ├── App.swift                入口、初始化音频会话
│   ├── ContentView.swift        WKWebView + JS bridge
│   ├── Player.swift             AVPlayer / 后台 / 锁屏 / 线控
│   ├── Library.swift            曲库扫描、标签与歌词解析
│   └── Resources/
│       ├── index.html
│       ├── style.css            ← 直接复用 PWA 版
│       ├── native.js            ← 数据层改为 bridge
│       └── icon.png
├── .github/workflows/unsigned-ipa.yml
├── upload_to_github.py         一键建仓并上传（不需要本机 git）
└── README.md
```

---

## 五、操作步骤

### 1. 上传代码（约 2 分钟）

本机 `git` 坏了、`gh` 没装，所以用 REST API 上传。需要你生成一个 GitHub PAT（classic 勾 `repo`，或 fine-grained 勾 Contents 读写）。

```bash
cd kuxuan-ios/native
python3 upload_to_github.py --token ghp_xxxxxxxxxxxx
```

脚本会：建公开仓库 → 逐文件上传（含 workflow）→ 打印仓库地址。
**建议公开**：公开仓库的 macOS runner 免费且不限时长；私有仓库按 10 倍系数扣 Actions 分钟数。仓库里只有界面代码，没有隐私数据。

### 2. 云端编译（约 5–10 分钟）

打开仓库 → **Actions** → **Build unsigned IPA** → **Run workflow**。
跑完后在 job 页面底部下载 `KuXuan-unsigned-IPA` 附件，解压得到 `KuXuan-unsigned.ipa`。

> runner 默认 `macos-26`（GA 镜像）。若要严格对齐 iOS 27 SDK，把 workflow 里的 `runs-on` 改成 `xcode-27`（公共预览）。旧 SDK 编译的 App 一般也能在新系统运行，本工程没用任何新 API。

### 3. 装进 iPhone（路径 A / B）

1. Mac 装 [Sideloadly](https://sideloadly.io/)（支持 macOS 10.12+，你这台能跑）
2. iPhone 用数据线连 Mac，打开「开发者模式」
3. 把 IPA 拖进 Sideloadly，登录**你自己的** Apple ID → Start
4. 手机上：设置 → 通用 → VPN 与设备管理 → 信任该证书
5. 免费账号 7 天后需重签（Sideloadly 可自动刷新）；付费账号 1 年

> 密码请你在 GUI 里自己输入，我不经手，也不需要你告诉我。

### 4. 导入音乐

- iPhone「文件」App → 我的 iPhone → **KuXuan** → 放入音频文件
- 或 Mac Finder 选中 iPhone → 文件 → KuXuan → 拖入
- 文件名写成 `歌手 - 歌名.mp3` 可自动识别；同名 `.lrc` 显示歌词
- 回到 App 下拉列表刷新

---

## 六、已知限制与未验证项（如实说明）

1. **本机无法编译验证**：没有 Xcode、CLT 损坏，Swift 代码只做了静态检查。第一次 CI 大概率需要看报错日志迭代 1–2 轮 —— 把日志贴给我，我来改。
2. **XcodeGen 配置未在真机环境验证**：用配置生成 `.xcodeproj` 是为了避免手写 pbxproj 出错，但 `buildPhase: resources` 是否能正确把 html/css/js 打进包，要等 CI 首跑确认。
3. **Sideloadly 对 iOS 27.3 beta 的兼容性未经证实**（厂商自述与第三方资料冲突）。若装不上，可试 SideStore，或改走 TestFlight。
4. **TestFlight 的签名/上传 workflow 这一版没写**：它需要把证书或 App Store Connect API 密钥放进 GitHub Secrets，步骤较多。你确定走付费路线后我再补齐，或改用 Transporter 手工上传。
5. **曲库只能是你自己的文件**：不接第三方免费音源。理由是版权与稳定性 —— 你刚在红果上吃过「接口一变就返回为空」的亏，第三方音源是同一类风险，而且免费音源大多是独立音乐人曲库，搜不到华语流行，和原项目体验差距很大。
6. **原生版每次改界面都要重新编译 + 重签**；PWA 版改文件即生效。这是维护成本。
7. 锁屏封面只在音频文件内嵌 artwork 时显示；无封面时用内置渐变唱片图。

---

## 七、还需要你定的两件事

1. 选 **免费侧载（7 天重签）** 还是 **¥688/年（TestFlight 或付费签名）**？
2. 是否愿意先把仓库建成**公开**？（只为白嫖 CI 时长，代码里没有隐私）

以及一个现实提醒：你现在跑的是 iOS 27.3 **开发者 beta**，Apple 官方自己都在要求开发者配对应 beta 版 Xcode。beta 系统上的侧载工具出问题，不全是工具的问题。如果这台手机是主力机、App 要天天用，付费 + TestFlight 是唯一不折腾的组合。
