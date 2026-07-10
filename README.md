# Brick

Brick 是一個 iOS 17+ 的 Screen Time 實驗性 app：使用者選定要封鎖的 apps、categories 與 websites，開始 block 後，必須等 session 到期、掃描已配對的固定 UID NFC key，或消耗一次 Emergency Unbrick 才能提前解除。

目前是個人開發版本，尚未達到 App Store production-ready。主要限制請先看[已知限制](#已知限制)。

## 核心流程

1. 在 Settings 選擇要封鎖的 apps 與 websites。
2. 使用 Settings → Add NFC Key 配對固定 UID 的 NFC tag 或卡片。
3. 在首頁選擇 block 時長，點綠色鎖頭立即開始。
4. Block 期間點紅色鎖頭並掃描已配對 key，可提前解除。
5. 若無法取得實體 key，可在 Settings 消耗一次 Emergency Unbrick。

Release build 不提供手動停止按鈕；相關控制只存在於 `#if DEBUG`。

## 需求

- Xcode 與 iOS 17+ SDK
- 支援 Core NFC 的實體 iPhone（Simulator 無法驗證 NFC）
- Apple Developer team
- Family Controls 與 NFC Tag Reading capabilities
- App Store 發佈前需另外取得 Apple 核准的 Family Controls entitlement

專案同時提交 `Brick.xcodeproj` 與 `project.yml`。若使用 XcodeGen 重新產生專案，請一併檢查產生結果，避免覆蓋 signing 或 capability 設定。

## 開始開發

1. 開啟 `Brick.xcodeproj`。
2. 在 Brick target 設定自己的 Development Team 與唯一 bundle identifier。
3. 確認 `Brick/Brick.entitlements` 內的 Family Controls 與 NFC entitlements 可由該 team 簽署。
4. 使用 Simulator 跑單元測試；NFC 與實際 shield 行為必須在實機驗證。

## 驗證

Core package tests：

```sh
swift test
```

iOS tests：

```sh
xcodebuild -project Brick.xcodeproj -scheme Brick -showdestinations
xcodebuild test \
  -project Brick.xcodeproj \
  -scheme Brick \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_ID>' \
  -derivedDataPath /tmp/brick-tests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

Release compile check：

```sh
xcodebuild build \
  -project Brick.xcodeproj \
  -scheme Brick \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/brick-release \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

## 結構

| 路徑 | 用途 |
| --- | --- |
| `Brick/BlockSessionModel.swift` | Block session、排程、配對與 Emergency 狀態 |
| `Brick/ScreenTimeShieldService.swift` | ManagedSettings shields |
| `Brick/NFCCardScanner.swift` | Core NFC session 與 fingerprint |
| `Brick/ContentView.swift` | SwiftUI 首頁、Settings 與配對畫面 |
| `BrickCore/BrickSettings.swift` | Codable settings、session 與 NFC key models |
| `BrickTests/` | iOS app/model tests |
| `BrickCoreTests/` | Swift Package core tests |

## 資料保存

- App selection、active session、paired key fingerprints 與排程存在 `UserDefaults`。
- NFC identifier 會先經 SHA-256，再保存 fingerprint；不保存原始 UID。
- Emergency Unbrick 剩餘次數存在 Keychain；舊版 `UserDefaults` 值會在首次啟動時 migration。若 Keychain 寫入失敗，才會暫時 fallback 到 `UserDefaults`。

## 已知限制

- Auto-brick timer 只保證 app 活躍時自動執行；背景時會送本地通知，使用者仍需開啟 app。尚未到期的排程會在 app 重啟時恢復。
- Block 到期清除目前依賴 app timer 或下次開啟 app；app 被終止時無法準時移除 shield。
- Random UID、空 identifier 或每次掃描 identifier 都改變的卡片無法當作 key。
- NFC 相容性取決於實際卡片、協定、iPhone 與 OS；不要只依卡片類別推定。
- 尚未實作 NDEF universal link 背景喚醒。

上述背景開始／到期限制預計透過 DeviceActivity monitor extension 解決。

## 文件

- [2026-07-10 交付紀錄](changelog-2026-07-10.html)
- [2026-07-09 changelog](changelog-2026-07-09.html)
- [改善計畫](improvement-plan.html)
- [首頁 UI redesign 紀錄](ui-redesign-plan.html)
