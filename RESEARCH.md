# OpenCarPlay — RESEARCH

Tài liệu nghiên cứu Phase 1. Mục tiêu: xác định **bằng chứng** (không phải giả định) về cách
CarPlay hoạt động trên iOS 18.6.x, và cách một tweak rootless có thể đưa ứng dụng iOS thông
thường lên màn hình CarPlay.

- Ngày lập: 2026-09-05
- Thiết bị mục tiêu: iPhone 11 (A13, arm64e), iOS 18.6.2, Dopamine (rootless), Sileo
- Máy build: Ubuntu 26.04 x86_64 (Theos + iOS SDK, chưa cài — xem §8)

---

## 0. Quy ước mức độ tin cậy

Mọi khẳng định kỹ thuật trong tài liệu này được gắn nhãn:

| Nhãn | Ý nghĩa | Nguồn |
|---|---|---|
| `[SRC]` | Đọc trực tiếp từ source code công khai | `git clone` carplay-cast, đã đọc toàn bộ 2204 dòng |
| `[SDK18.6]` | Symbol tồn tại trong **iOS 18.6 SDK stub** (`.tbd`) | `xybp888/iOS-SDKs` → `iPhoneOS18.6.sdk` |
| `[DOC]` | Tài liệu công khai của Apple | developer.apple.com |
| `[ASSUMED]` | Suy luận hợp lý — **chưa xác minh** | phải verify trước khi code |
| `[DEVICE]` | **Bắt buộc** dump/probe trên iPhone 11 mới kết luận được | xem §7 |

**Giới hạn của `[SDK18.6]`:** file `.tbd` chỉ export danh sách `objc-classes` và `objc-ivars`.
Nó chứng minh **class/ivar tồn tại** trong framework trên iOS 18.6, nhưng **không** cho biết
signature của method. Ngoài ra, class nằm trong **binary của app** (`SpringBoard.app`,
`CarPlay.app`) hoàn toàn **không** có trong SDK — bắt buộc dump trên thiết bị (§7.3).

> Không có dòng nào trong tài liệu này được phép chuyển thành code nếu nó còn nhãn
> `[ASSUMED]` hoặc `[DEVICE]` chưa giải quyết.

---

## 1. TL;DR — kết luận chính

1. **Kiến trúc tổng thể của carplay-cast vẫn còn nền móng trên iOS 18.6.** Các API nền tảng mà
   nó dựa vào (`UIRootSceneWindow`, `FBSDisplayConfiguration`, `FBScene`, `FBSceneMonitor`,
   `CRCarPlayAppDeclaration`, `CARSessionStatus`) **đều tồn tại** trên iOS 18.6 `[SDK18.6]`.
   Điều này bác bỏ giả thuyết "phải vứt bỏ toàn bộ và làm lại từ đầu".

2. **Nhưng lớp quyết định "app nào được lên CarPlay" đã thay đổi bản chất.** iOS 18.6 có thêm
   `CRCarPlayAppPolicy` / `CRCarPlayAppPolicyEvaluator` / `CRCarPlayAppDenylist` /
   `CRCarPlayCapabilities` trong **CarKit.framework** `[SDK18.6]` — những class **không tồn tại
   trong tư duy của carplay-cast (2021)**. Việc chỉ set ivar `_carPlayDeclaration` như iOS 14
   **nhiều khả năng không còn đủ** `[ASSUMED]`. Đây là điểm điều tra số 1 (§7.4).

3. **Toàn bộ hook vào `SpringBoard.app` và `CarPlay.app` của carplay-cast phải coi là chưa xác
   minh.** Chúng là class nội bộ của app binary; tên/selector đã thay đổi nhiều lần từ iOS 14 →
   18. Không có nguồn public nào chứng minh chúng còn nguyên `[DEVICE]`.

4. **Có một con đường thứ tư mà carplay-cast không dùng**, và nó là con đường Apple dùng nội bộ:
   `SBSRemoteAlertDefinition` có ivar `_forCarPlay` và `_impersonatedCarPlayAppIdentifier`
   `[SDK18.6]`. Đây là cơ chế chính thức (private) để một process hiển thị view controller trên
   màn hình CarPlay. Cần đánh giá (§6, Approach D).

5. **Rào cản khó nhất không phải là render UI — mà là chính sách + audio + ổn định.** Việc bơm
   một scene lên màn hình phụ là bài toán đã có lời giải trong hệ thống; việc thuyết phục
   `CARSession` / policy layer chấp nhận app không entitlement, và giữ audio route không phá
   HFP/A2DP của xe, mới là phần dễ hỏng.

6. **Môi trường khả thi:** Dopamine hỗ trợ **A12/A13 tới iOS 18.7.1** — iPhone 11 (A13) trên
   18.6.2 nằm trong phạm vi. Không có blocker về jailbreak.

---

## 2. Phân tích carplay-cast (EthanArbuckle)

Nguồn: `https://github.com/EthanArbuckle/carplay-cast`, clone ngày 2026-09-05.
Commit cuối: `696bc72` — **2021-04-18** ("taurine jb fix"). `[SRC]`

### 2.1 Metadata dự án

| Mục | Giá trị | Ghi chú cho OpenCarPlay |
|---|---|---|
| `Makefile: TARGET` | `iphone:clang:13.5.1:13.5.1` | SDK 13.5 — cách iOS 18.6 **năm thế hệ** |
| `Makefile: ARCHS` | `arm64 arm64e` | giữ nguyên |
| `control: Architecture` | `iphoneos-arm` | **rootful** — ta cần `iphoneos-arm64` (rootless) |
| `control: Depends` | `firmware (>= 14.0), mobilesubstrate, preferenceloader` | rootless: `ellekit`, không `mobilesubstrate` |
| `control: Version` | `1.0.1` | — |
| Kích thước | 2204 dòng (3 hook file + 1 window class + prefs) | rất gọn — đáng học |
| Test | 2 file Cycript (`.cy`) | **Cycript đã chết** trên iOS 15+ → dùng Frida |
| Crash reporting | upload crashlog lên cloud function riêng | **loại bỏ** — vi phạm privacy, ta không làm |

### 2.2 Nó inject vào process nào?

`carplayenable.plist` — MobileSubstrate filter `[SRC]`:

```xml
<key>Bundles</key>
<array>
  <string>com.apple.CarPlayApp</string>   <!-- process CarPlay dashboard -->
  <string>com.apple.springboard</string>  <!-- SpringBoard -->
  <string>com.apple.UIKit</string>        <!-- => MỌI app dùng UIKit -->
</array>
```

Ba `%ctor` riêng biệt tự phân luồng theo `[[NSBundle mainBundle] bundleIdentifier]`:

| File | Điều kiện load | Vai trò |
|---|---|---|
| `src/hooks/CarPlay.xm:311` | `== com.apple.CarPlayApp` | ép app xuất hiện trên dashboard, bắt sự kiện tap |
| `src/hooks/SpringBoard.xm:452` | `== com.apple.springboard` | **host UI**, quản lý vòng đời, chống suspend |
| `src/hooks/UIApplication.xm:73` | bundlePath chứa `.app` && id không chứa `com.apple.` | ép xoay màn hình trong app đích |

> **Nhận xét kiến trúc:** filter `com.apple.UIKit` khiến dylib nạp vào **mọi** process UI trên
> máy — chi phí ổn định rất lớn cho một tính năng chỉ cần ở 2–3 process. OpenCarPlay sẽ tách
> thành **hai dylib** với filter hẹp (§ARCHITECTURE).

### 2.3 Nó hook class nào?

**Trong `com.apple.CarPlayApp`** `[SRC]` — `src/hooks/CarPlay.xm`:

| Class | Method | Mục đích |
|---|---|---|
| `CARApplication` | `+_newApplicationLibrary` (:71) | **thay thế hoàn toàn** app library của CarPlay bằng library chứa *tất cả* app |
| `SBIconListGridLayoutConfiguration` | `-numberOfPortraitColumns` (:118), `-iconImageInfoForGridSizeClass:` (:131) | 5 cột icon |
| `CARApplicationLaunchInfo` | `+launchInfoForApplication:withActivationSettings:` (:148) | chặn launch bình thường, bắn notification sang SpringBoard, **trả `nil`** |
| `CARAppDockViewController` | `-_dockButtonPressed:` (:198) | giữ dock enabled |
| `_CARDashboardHomeViewController` | `-initWithEnvironment:` (:221), `-_handleAppLibraryRefresh` (:245) | refresh library khi cài/gỡ app |
| `CARIconView` | `-initWithConfigurationOptions:listLayoutProvider:` (:290) + `%new handleLaunchAppInNormalMode:` | long-press 1.5s để mở app CarPlay-native ở chế độ "full" |

**Trong `com.apple.springboard`** `[SRC]` — `src/hooks/SpringBoard.xm`:

| Class | Method | Mục đích |
|---|---|---|
| `SpringBoard` | `-applicationDidFinishLaunching:` (:82) + 3 `%new` | đăng ký observer, tạo `lockAssertions`, xử lý launch request |
| `SBSuspendedUnderLockManager` | `-_shouldBeBackgroundUnderLockForScene:withSettings:` (:21) | **không** background app khi khoá máy |
| `FBScene` | `-updateSettings:withTransitionContext:completion:` (:186) | chặn mọi lệnh đưa app xuống background |
| `SBSceneView` | `-_updateReferenceSize:andOrientation:` (:166) | tránh crash khi thiết bị nằm ngửa (orientation 5/6) |
| `SBMainSwitcherViewController` | `-_updateContentViewInterfaceOrientation:` (:213) | app switcher theo hướng máy, không theo hướng app |
| `SBDeviceApplicationSceneView` | `-layoutSubviews` (:253), `-setDisplayMode:animationFactory:completion:` (:370) + 3 `%new` | vẽ placeholder "Running on CarPlay Screen" trên màn hình máy |
| `UIScreen` | `%new -boundsForOrientation:` (:391) | tiện ích |
| C function | `BKSDisplayServicesSetScreenBlanked` via `MSHookFunction` (:457) | **giữ render khi màn hình iPhone tắt** |

**Trong app đích** `[SRC]` — `src/hooks/UIApplication.xm`:

| Class | Method | Mục đích |
|---|---|---|
| `UIApplication` | `-init` (:15) + `%new handleRotationRequest:` | nhận lệnh xoay qua distributed notification |
| `UIWindow` | `-_setRotatableViewOrientation:duration:force:` (:52) | ép orientation |

### 2.4 Nó thay đổi lifecycle CarPlay như thế nào?

Luồng end-to-end `[SRC]`:

```
[CarPlay.app]  người dùng chạm icon trên dashboard
      │
      ├─ CARApplicationLaunchInfo +launchInfoForApplication:  ← hook
      │     • kiểm tra appInfo.tags có "CarPlayEnable"?
      │     • post NSDistributedNotification "com.carplayenable" {identifier}
      │     • cập nhật app history + refresh dock
      │     • đóng app CarPlay-native đang chạy (CAREvent type 1 = home)
      │     • return nil   ← CarPlay KHÔNG tự launch app
      │
      ▼  (IPC: NSDistributedNotificationCenter)
[SpringBoard]  -handleCarPlayLaunchNotification: → -launchAppOnCarplay:
      │
      ├─ dismiss window CarPlay đang sống (nếu có)
      └─ [[CRCarPlayWindow alloc] initWithBundleIdentifier:]
             │
             ├─ getCarplayCADisplay():
             │     AVExternalDevice.currentCarPlayExternalDevice → screenIDs[0]
             │     → tìm CADisplay khớp uniqueId
             ├─ FBSDisplayConfiguration initWithCADisplay:isMainDisplay:0
             ├─ UIRootSceneWindow initWithDisplayConfiguration:   ← cửa sổ trên màn hình xe
             ├─ setupWallpaperBackground / setupDock (rộng 40pt) / setupLaunchImage
             ├─ setupLiveAppView:                                 ← TRÁI TIM
             │     SBSceneManagerCoordinator.mainDisplaySceneManager
             │     → _sceneIdentityForApplication:createPrimaryIfRequired:
             │     → SBApplicationSceneHandleRequest defaultRequestForApplication:sceneIdentity:displayIdentity:
             │     → fetchOrCreateApplicationSceneHandleForRequest:
             │     → SBDeviceApplicationSceneEntity initWithApplicationSceneHandle:
             │     → SBAppViewController initWithIdentifier:andApplicationSceneEntity:
             │     → _createSceneUpdateTransactionForApplicationSceneEntity:deliveringActions:
             │     → appView setDisplayMode:4 (LiveContent)
             │     → FBSceneMonitor initWithSceneID: (phát hiện app chết)
             ├─ thêm view của SBAppViewController vào window CarPlay
             ├─ resizeAppViewForOrientation: (scale transform trên _sceneContentContainerView)
             ├─ orig_BKSDisplayServicesSetScreenBlanked(0)  ← unblank để vẫn render
             └─ vẽ placeholder lên scene view của app trên màn hình chính
```

**Điểm mấu chốt về mặt kiến trúc:** app **không** chạy trên "màn hình CarPlay" theo nghĩa hệ
thống. Nó chạy như một scene **của màn hình chính** (`mainDisplaySceneManager`,
`mainScreenIdentity`), rồi **view của scene đó được gắn vào một `UIWindow` nằm trên màn hình
CarPlay**, có scale transform. Đây là *view re-parenting*, không phải multi-display thật sự.

Hệ quả trực tiếp (giải thích mọi hack còn lại trong repo):
- App tin rằng nó ở màn hình chính → orientation phải ép bằng IPC (`UIApplication.xm`).
- App không thể chạy đồng thời trên 2 màn hình → phải vẽ placeholder ở màn hình chính.
- Khoá máy sẽ suspend scene → phải có `lockAssertions` + hook `FBScene`/`SBSuspendedUnderLockManager`.
- Tắt màn hình sẽ dừng render → phải hook `BKSDisplayServicesSetScreenBlanked`.

### 2.5 Nó làm app không hỗ trợ CarPlay xuất hiện như thế nào?

Hai bước `[SRC]` (`CarPlay.xm:21-106`):

1. **Thay app library:** `+[CARApplication _newApplicationLibrary]` được thay bằng một
   `FBSApplicationLibrary` tạo từ `FBSApplicationLibraryConfiguration` với
   `applicationInfoClass = CARApplicationInfo`, lọc bỏ app tag `hidden`. `%orig` chỉ trả về
   app có CarPlay entitlement nên bị bỏ hoàn toàn.
2. **Chế "tuyên bố CarPlay" giả:** với mỗi app chưa có, tạo `CRCarPlayAppDeclaration`:
   - `setSupportsTemplates:0` ← **quan trọng**: nếu `1`, `CarPlayTemplateUIHost` sẽ liên tục
     spawn rồi crash vì không tìm thấy template.
   - `setSupportsMaps:1` ← mượn "vai" ứng dụng bản đồ để được cấp toàn màn hình.
   - gán vào ivar `_carPlayDeclaration` của `CARApplicationInfo`.
   - thêm tag `"CarPlayEnable"` vào `_tags` để nhận diện sau này.

### 2.6 Nó xử lý application launching như thế nào?

Không dùng `SBSLaunchApplicationWithIdentifier` / `openApplicationWithBundleID`. Thay vào đó nó
**tự dựng scene** trong SpringBoard (chi tiết ở §2.4). Ưu điểm: có ngay `SBAppViewController` để
re-parent view. Nhược điểm: phụ thuộc ~10 private selector của SpringBoard, mỗi bản iOS đều có
thể đổi.

Trạng thái app được xử lý:
- App chưa chạy → `createPrimaryIfRequired:1` tạo scene mới, hiện launch image từ
  `XBApplicationSnapshotManifest`.
- App đang chạy ở màn hình chính → scene handle được tái sử dụng; màn hình chính chuyển sang
  `displayMode 1` (Placeholder).
- App chết/crash → `FBSceneMonitor` delegate `sceneMonitor:sceneWasDestroyed:` → `dismiss`.
- CarPlay rút dây → `CarPlayIsConnectedDidChange` → kiểm tra `getCarplayCADisplay()` → `dismiss`.

### 2.7 Nó xử lý UI rendering như thế nào?

**Không** mirror, **không** screenshot. Nó dùng scene layer thật:
`SBAppViewController.view` → `_deviceAppViewController._sceneView._sceneContentContainerView`,
áp `CGAffineTransformMakeScale(widthScale, heightScale)` để co từ kích thước màn hình iPhone
xuống kích thước màn hình xe (`CRCarplayWindow.mm:539-560`).

Touch **không được xử lý thủ công** — vì view thuộc cây view của SpringBoard trên window của màn
hình CarPlay, UIKit + BackBoard tự định tuyến sự kiện chạm xuống scene của app. Đây là điểm
thanh lịch nhất của thiết kế và là lý do nên giữ hướng này.

Chỉ có **một** gesture được thêm thủ công: `UITapGestureRecognizer` đăng ký với
`_UISystemGestureManager addGestureRecognizer:toDisplayWithIdentity:` để thoát fullscreen.

### 2.8 Nó xử lý screenshot / screen mirroring như thế nào?

Chỉ dùng snapshot cho **launch image**, không phải để render:
`XBApplicationSnapshotManifest` → chọn snapshot landscape → nếu chỉ có portrait thì sau khi app
khởi động sẽ tự tạo snapshot landscape tên `CarPlayLaunchImage` qua `FBSSceneSnapshotContext`
(`CRCarplayWindow.mm:207-260, 318-331`).

### 2.9 Phần nào chắc chắn/nhiều khả năng đã lỗi thời trên iOS 18

| Thành phần carplay-cast | Trạng thái trên iOS 18.6 | Bằng chứng |
|---|---|---|
| `control: Architecture: iphoneos-arm` | **Hỏng** — rootless cần `iphoneos-arm64` + prefix `/var/jb` | Dopamine rootless |
| `Depends: mobilesubstrate` | **Hỏng** — Dopamine dùng **ElleKit** | Dopamine |
| `TARGET iphone:clang:13.5.1` | **Hỏng** — cần SDK ≥ 15 cho rootless | Theos rootless |
| Test bằng Cycript (`.cy`) | **Hỏng** — Cycript không hoạt động iOS 15+ | `[ASSUMED]` mạnh |
| `BAIL_IF_UNSUPPORTED_IOS` (≥14.0) | Quá lỏng — cần chặn theo range chính xác | thiết kế |
| Upload crashlog lên server tác giả | **Loại bỏ** (privacy) | quyết định dự án |
| `AVExternalDevice currentCarPlayExternalDevice` | `[DEVICE]` — chưa xác minh trên 18.6 | §7.4 |
| `CADisplay.displays` / `uniqueId` | `[DEVICE]` | §7.4 |
| `UIScreen.screens` + `_isCarScreen` | API `UIScreen.screens` **deprecated từ iOS 16** `[DOC]`; `_isCarScreen` `[DEVICE]` | dùng `FBSDisplayConfiguration`/`CARScreenInfo` thay thế |
| Set ivar `_carPlayDeclaration` là **đủ** | **Nhiều khả năng không còn đủ** — đã có policy layer mới | §3.5 |
| Toàn bộ selector `SB*` trong SpringBoard | `[DEVICE]` — 100% phải dump lại | §7.3 |
| Toàn bộ class `CAR*` trong CarPlay.app | `[DEVICE]` — 100% phải dump lại | §7.3 |
| `NSDistributedNotificationCenter` làm IPC | `[DEVICE]` — cần kiểm tra sandbox 18.6 | §7.6 |
| 5 cột icon (`SBIconListGridLayoutConfiguration`) | tính năng phụ, bỏ khỏi MVP | thiết kế |

### 2.10 Phần nào tái sử dụng được **về mặt kiến trúc**

Không copy code — tái sử dụng **ý tưởng**:

1. Tách vai trò: process dashboard chỉ *phát hiện ý định*, SpringBoard *thực thi hosting*.
2. Dùng **scene re-parenting** thay vì mirroring (→ touch/keyboard miễn phí).
3. Đánh dấu app đã "ép CarPlay" bằng **tag** thay vì so sánh danh sách bundle ID rải rác.
4. Tắt `supportsTemplates` để không đánh thức `CarPlayTemplateUIHost`.
5. `FBSceneMonitor` để bắt app chết.
6. Placeholder ở màn hình chính vì app chỉ sống trên một màn hình.
7. Assertion chống suspend khi khoá máy (cần thiết kế lại cho an toàn hơn).

---

## 3. Kiến trúc CarPlay trên iOS 18.6 — bằng chứng SDK

Nguồn: `iPhoneOS18.6.sdk` (`xybp888/iOS-SDKs`), phân tích `objc-classes` / `objc-ivars` trong
`.tbd`. 17 framework đã tải; kết quả lưu tại `/tmp/sdk18/classes.json` trong phiên làm việc.

### 3.1 Bản đồ process (cần xác nhận lại bằng `ps` — §7.2)

| Process | Bundle ID | Vai trò `[ASSUMED]` |
|---|---|---|
| SpringBoard | `com.apple.springboard` | scene manager toàn hệ thống, chủ màn hình |
| CarPlay dashboard | `com.apple.CarPlayApp` | UI dashboard trên màn hình xe |
| Template host | `com.apple.CarPlayTemplateUIHost` | render template của app CarPlay-native |
| Music UI service | `com.apple.MusicUIService` | Now Playing |
| CarPlay settings | `com.apple.CarPlaySettings` | cài đặt trên xe |
| InCall | `com.apple.InCallService` | UI cuộc gọi |
| Daemon phần cứng | `carplayd` / `CarKit` XPC | phiên CarPlay, USB/wireless |

### 3.2 CarPlay.framework (public) trên 18.6 `[SDK18.6]`

90 class, bao gồm: `CPTemplateApplicationScene`, `CPTemplateApplicationDashboardScene`,
`CPTemplateApplicationInstrumentClusterScene`, `CPInterfaceController`, `CPWindow`,
`CPSessionConfiguration`, `CPDashboardController`, `CPInstrumentClusterController`, cùng toàn bộ
họ template (`CPMapTemplate`, `CPListTemplate`, `CPGridTemplate`, `CPNowPlayingTemplate`…).

Cũng có ba scene specification UIKit-side: `CPUITemplateApplicationSceneSpecification`,
`CPUITemplateDashboardSceneSpecification`, `CPUITemplateInstrumentClusterSceneSpecification`.

**Ý nghĩa:** đây là con đường "hợp pháp" cho app CarPlay — dựa trên **template**, không phải UIKit
tự do. Nó **không** phải mục tiêu của OpenCarPlay (ta muốn chạy UI gốc của app), nhưng ta phải
**tránh** đi vào nhánh này (giống bài học `setSupportsTemplates:0` của carplay-cast).

### 3.3 Stack private CarPlay trên 18.6 `[SDK18.6]`

| Framework | Prefix | Số class | Vai trò |
|---|---|---|---|
| `CarKit` | `CAR*`, `CR*` | — | phiên CarPlay, phần cứng, **policy app**, thông tin màn hình |
| `CarPlayServices` | `CRS*` | 18 | XPC service: icon layout, app history, open app, session |
| `CarPlayUIServices` | `CRSUI*` | 77 | **scene specification/settings cho CarPlay**, wallpaper, punch-through, cluster theme |
| `CarPlaySupport` | `CPS*` | 131 | implementation của template UI (host phía hệ thống) |
| `CarPlayUI` | `CPUI*` | 62 | component UI (Now Playing, table cell, button…) |

**Class đáng chú ý nhất cho OpenCarPlay:**

```
CarKit:
  CRCarPlayAppDeclaration        ← carplay-cast dùng — VẪN TỒN TẠI trên 18.6
  CRCarPlayAppPolicy             ← MỚI so với tư duy 2021
  CRCarPlayAppPolicyEvaluator    ← MỚI
  CRCarPlayAppDenylist           ← MỚI
  CRCarPlayCapabilities          ← MỚI
  CARSessionStatus, CARSession, CARSessionScreenBorrowToken
  CARScreenInfo, CARDisplayInfo, CARScreenViewArea
  CARInputDevice, CARInputDeviceTouchpad, CARInputDeviceManager
  CARConnectionSession, CARConnectionEvent

CarPlayServices:
  CRSOpenApplicationService, CRSIconLayoutService/Controller/State, CRSApplicationIcon,
  CRSAppHistoryController/Service, CRSSessionController/Service

CarPlayUIServices:
  CRSUIApplicationSceneSpecification / SceneSettings / MutableApplicationSceneSettings
  CRSUIProxyApplicationSceneSpecification / ProxyApplicationSceneSettings
  CRSUIWindow, CRSUIClusterWindow, CRSUIDashboardWidgetWindow
  CRSUIPunchThroughController / PunchThroughService / PunchThroughSpecification
  CRSUIWallpaperPreferences   ← carplay-cast dùng — VẪN TỒN TẠI
  CRSUIStatusBarStyleService, CRSUIVolumeNotificationService
```

### 3.4 Cơ chế quyết định "app nào lên CarPlay" — điểm thay đổi lớn nhất

`CRCarPlayAppDeclaration` trên 18.6 có **21 ivar** `[SDK18.6]`:

```
_bundleIdentifier, _bundlePath, __applicationCategory, _systemApp, _autoMakerProtocols,
_requiresGeoSupport, _launchUsingSiri, _launchNotificationsUsingSiri,
_supportsTemplates, _supportsMaps, _supportsAudio, _supportsCalling, _supportsCharging,
_supportsCommunication, _supportsDrivingTask, _supportsFueling, _supportsMessaging,
_supportsParking, _supportsPlayableContent, _supportsPublicSafety, _supportsQuickOrdering
```

→ `_supportsTemplates` và `_supportsMaps` mà carplay-cast set **vẫn còn**. Tin tốt.

Nhưng iOS 18.6 có thêm `CRCarPlayAppPolicy` với **13 ivar** `[SDK18.6]`:

```
_bundlePath, _applicationCategory, _carPlayCapable, _carPlaySupported, _canDisplayOnCarScreen,
_launchUsingTemplateUI, _launchUsingMusicUIService, _launchUsingSiri,
_launchNotificationsUsingSiri, _handlesCarIntents, _showsNotifications, _badgesAppIcon,
_siriActivationOptions
```

và `CRCarPlayAppPolicyEvaluator` với:

```
_denylist, _sessionStatus, _lockedOrHiddenApps, _geoSupported, _evaluatorWantsGeoManagement, ...
```

**Diễn giải `[ASSUMED]` — cần xác minh §7.4:** iOS 18 đã tách "tuyên bố khả năng của app"
(`Declaration`, đọc từ Info.plist/LaunchServices) khỏi "chính sách hiển thị"
(`Policy`, kết quả đánh giá của `PolicyEvaluator` dựa trên declaration + denylist +
session + app bị khoá/ẩn). Nếu đúng, điểm hook hiệu quả trên iOS 18.6 là
**`CRCarPlayAppPolicyEvaluator`** (trả về policy có `_canDisplayOnCarScreen = YES`), chứ không
phải chỉ nhét declaration vào app info như iOS 14.

Đây là **câu hỏi điều tra số 1** của dự án.

### 3.5 Thông tin màn hình xe — thay cho hard-code 800×480

`CARScreenInfo` (25 ivar) `[SDK18.6]` cho đúng thứ `OCPDisplayConfiguration` cần:

```
_pixelSize, _physicalSize, _squaredPixelSize, _maxFramesPerSecond, _nightMode,
_viewAreas, _currentViewArea, _adjacentViewArea, _limitedUI, _limitedUIElements,
_supportsHighFidelityTouch, _supportsLayerTracking, _supportsAppearanceMode, _wantsCornerMasks,
_screenType, _physicalDisplay, _identifier, ...
```

`CARDisplayInfo` (11 ivar): `_pixelSize`, `_physicalSize`, `_supportsCarPlayContent`,
`_supportsInstrumentClusterContent`, `_supportsMapContent`, `_oemPunchThroughs`, `_streams`.

`FBSDisplayConfiguration` + `FBSDisplayMode` + `FBSDisplayMonitor` `[SDK18.6]` là nguồn thay thế
độc lập, và là API mà SpringBoard thực sự dùng.

→ **Quyết định thiết kế:** `OCPDisplayConfiguration` lấy số liệu theo thứ tự ưu tiên
`FBSDisplayConfiguration` → `CARScreenInfo` → `UIScreen` (fallback cuối), không hard-code.

### 3.6 Bộ máy scene của FrontBoardServices trên 18.6 `[SDK18.6]`

Toàn bộ vẫn còn và còn phong phú hơn iOS 14:

```
FBSScene, FBSSceneIdentity, FBSSceneDefinition, FBSSceneParameters, FBSSceneSpecification,
FBSSceneSettings / MutableSceneSettings / SceneSettingsDiff / DiffInspector,
FBSSceneClientSettings, FBSSceneTransitionContext, FBSSceneUpdate,
FBSSceneHostHandle, FBSSceneLayer, FBSCAContextSceneLayer, _FBSCapturedSceneLayer,
FBSSceneSnapshotContext / Request / RequestHandle / Action,
FBSDisplayConfiguration / Identity / Mode / Monitor / Layout / LayoutMonitor,
FBSApplicationLibrary, FBSApplicationLibraryConfiguration, FBSApplicationInfo,
FBSApplicationPlaceholder
FrontBoard: FBScene, FBSceneMonitor
```

**`FBSSceneHostHandle` + `FBSCAContextSceneLayer`** là nền tảng cho việc một process host layer
của scene thuộc process khác — chính là cơ chế nằm dưới `SBAppViewController`. Đây là bằng chứng
mạnh nhất rằng Approach A (§6) còn khả thi trên 18.6.

`FBSApplicationInfo` trên 18.6 **có** ivar `_tags` `[SDK18.6]` → kỹ thuật đánh dấu bằng tag vẫn dùng được.
`FBSApplicationInfo` **không** có ivar `_carPlayDeclaration` — ivar đó thuộc `CARApplicationInfo`
(subclass nằm trong binary CarPlay.app) `[DEVICE]`.

### 3.7 Phía UIKit trên 18.6 `[SDK18.6]`

| Symbol | Trạng thái | Ghi chú |
|---|---|---|
| `UIRootSceneWindow` | **TỒN TẠI** | carplay-cast dùng để tạo window trên màn hình xe |
| `_UISystemGestureManager` | **TỒN TẠI** | đăng ký gesture theo display identity |
| `UICarPlayApplicationSceneSettings` | **TỒN TẠI** | settings scene CarPlay phía UIKit |
| `UIMutableCarPlayApplicationSceneSettings` | **TỒN TẠI** | — |
| `_UICarPlaySceneComponent`, `_UICarPlaySceneDiffAction`, `_UICarPlaySession` | **TỒN TẠI** | UIKit biết về phiên CarPlay |
| `UIScreen._carPlayHumanPresenceStatus` (ivar) | **TỒN TẠI** | UIScreen vẫn mang trạng thái CarPlay |
| `UITextInputTraits.isCarPlayIdiom` (ivar) | **TỒN TẠI** | bàn phím có chế độ CarPlay |
| `UIKBPhoneToCarPlayTransformation` | **TỒN TẠI** | chuyển đổi bàn phím sang CarPlay |
| `_UIHostedWindow` | **TỒN TẠI** | — |

### 3.8 Con đường thứ tư: SBSRemoteAlert

`SBSRemoteAlertDefinition` (SpringBoardServices) trên 18.6 có ivar `[SDK18.6]`:

```
_forCarPlay, _impersonatedCarPlayAppIdentifier, _prefersEmbeddedDisplayPresentation,
_supportsMultipleDisplayPresentations, _viewControllerClassName, _serviceName,
_sceneProvidingProcess, _configurationIdentifier, ...
```

Sự tồn tại của `_forCarPlay` **và** `_impersonatedCarPlayAppIdentifier` cho thấy hệ thống có sẵn
cơ chế: "hiển thị view controller của process X trên màn hình CarPlay, đội lốt bundle ID Y".
Đây là hạ tầng Apple dùng cho InCall/Siri trên CarPlay `[ASSUMED]`.

Với OpenCarPlay, nó có thể là **kênh hiển thị UI riêng của tweak** (ví dụ màn hình chọn app,
overlay điều khiển) mà không cần tự tạo `UIRootSceneWindow`. Cần điều tra (§7.5).

---

## 4. OLD APPROACH → NEW APPROACH

### 4.1 Bảng đối chiếu

```
OLD APPROACH (carplay-cast, iOS 13.5–14.x)
  ↓
[1] Rootful package, mobilesubstrate, SDK 13.5, filter com.apple.UIKit
      ↓ Vì sao hỏng trên iOS 18.6:
        • Dopamine là rootless: mọi đường dẫn cần prefix /var/jb; Architecture phải là
          iphoneos-arm64; substrate là ElleKit chứ không phải MobileSubstrate.
        • Filter com.apple.UIKit nạp dylib vào ~mọi process → rủi ro ổn định không chấp nhận được.
  ↓
NEW APPROACH
      • Theos rootless (THEOS_PACKAGE_SCHEME=rootless), SDK ≥ 16.5 (khuyến nghị 18.x),
        Depends: ellekit.
      • Tách 2 dylib: OpenCarPlay (SpringBoard + CarPlayApp) và OpenCarPlayApp (chỉ app trong
        AllowedApplications, lọc runtime trong %ctor).

OLD APPROACH
  ↓
[2] Chỉ cần gán ivar _carPlayDeclaration để app hiện trên dashboard
      ↓ Vì sao có thể hỏng trên iOS 18.6:
        • iOS 18.6 có CRCarPlayAppPolicy / CRCarPlayAppPolicyEvaluator / CRCarPlayAppDenylist
          / CRCarPlayCapabilities [SDK18.6] — lớp chính sách này không tồn tại trong mô hình 2021.
        • Nếu dashboard hỏi Policy thay vì đọc Declaration, việc nhét declaration là vô ích.
  ↓
NEW APPROACH
      • Hook ở tầng policy: cung cấp CRCarPlayAppPolicy với _canDisplayOnCarScreen=YES,
        _carPlaySupported=YES, _launchUsingTemplateUI=NO cho các app trong AllowedApplications.
      • Giữ declaration injection như lớp thứ hai (defense in depth), không phải lớp duy nhất.
      ↓ Điều tra bắt buộc trước khi code: §7.4 (Q1–Q4)

OLD APPROACH
  ↓
[3] Dựng scene bằng chuỗi selector SpringBoard cụ thể (SBApplicationSceneHandleRequest,
    SBDeviceApplicationSceneEntity, SBAppViewController, _createSceneUpdateTransaction...)
      ↓ Vì sao rủi ro trên iOS 18.6:
        • Đây là class nội bộ của SpringBoard.app; giữa iOS 14 và 18 SpringBoard đã qua 4 vòng
          tái cấu trúc scene/layout. Không có bằng chứng public nào cho thấy chúng còn nguyên.
  ↓
NEW APPROACH
      • Không viết chuỗi gọi cứng. Xây "capability probe": mỗi bước là một OCPStep có
        điều kiện tiền đề (class + selector) được kiểm tra runtime; thiếu bước nào thì
        vô hiệu hoá tính năng và log, không crash.
      • Ưu tiên API tầng framework (FBS*/CRSUI*) hơn class nội bộ app khi có lựa chọn tương đương.
      ↓ Điều tra bắt buộc: §7.3 (class-dump SpringBoard 18.6.2)

OLD APPROACH
  ↓
[4] NSDistributedNotificationCenter làm IPC giữa CarPlayApp và SpringBoard
      ↓ Vì sao rủi ro: kênh này bị siết dần theo sandbox; chưa xác minh trên 18.6.
  ↓
NEW APPROACH
      • Thiết kế lớp trừu tượng OCPTransport với 3 backend, chọn theo kết quả probe:
        (a) CPDistributedMessagingCenter [SDK18.6: AppSupport có class này]
        (b) Darwin notification (notify_post) + payload qua file trong /var/jb/... (an toàn nhất)
        (c) NSDistributedNotificationCenter (chỉ nếu probe cho thấy còn hoạt động)

OLD APPROACH
  ↓
[5] Cycript test, upload crashlog lên server bên thứ ba
      ↓ Cycript đã chết; upload crashlog vi phạm quyền riêng tư.
  ↓
NEW APPROACH
      • Frida cho probe/regression trên thiết bị; unit test logic thuần trên máy build.
      • Log chỉ ghi cục bộ, mặc định tắt, có công tắc trong Preferences.
```

### 4.2 Cái gì **không** cần thay đổi

- Mô hình "dashboard phát hiện ý định → SpringBoard hosting".
- Scene re-parenting thay vì mirroring.
- `setSupportsTemplates:NO` để tránh `CarPlayTemplateUIHost`.
- Theo dõi app chết bằng `FBSceneMonitor` (class còn tồn tại `[SDK18.6]`).
- Placeholder trên màn hình chính.

---

## 5. So sánh các hướng render UI

| Tiêu chí | **A. Scene re-parenting** (host scene của app trong window trên màn hình xe) | **B. CarPlay scene specification** (tạo scene CarPlay thật cho app qua `CRSUI*`) | **C. Mirroring / capture + inject touch** | **D. SBSRemoteAlert (`_forCarPlay`)** |
|---|---|---|---|---|
| Ý tưởng | như carplay-cast: `UIRootSceneWindow` trên display xe + view của `SBAppViewController` | ép app tạo scene với `CRSUIApplicationSceneSpecification` để nó **thật sự** chạy trên màn hình xe | chụp/stream layer màn hình app, vẽ lên CarPlay, bơm touch bằng HID | dùng hạ tầng remote alert của hệ thống để hiển thị VC trên CarPlay |
| Độ khó | Trung bình–cao | **Rất cao** (chưa ai công bố làm được) | Cao | Trung bình (nhưng hạn chế) |
| Hiệu năng | Native — layer do WindowServer hợp thành | Native | Kém: encode/copy mỗi frame | Native |
| Độ trễ | ~0 frame thêm | ~0 | 1–3 frame | ~0 |
| Touch | **Miễn phí** (UIKit tự route) | Miễn phí | Phải tự bơm `IOHIDEvent` — rủi ro & khó chính xác | Miễn phí trong VC của mình |
| Bàn phím | Có (đi kèm scene) | Có, đúng CarPlay idiom | Rất khó | Có |
| Audio | Không đụng — app tự route | Không đụng | Không đụng | Không đụng |
| Ổn định | Phụ thuộc private SpringBoard | Phụ thuộc private CarPlayUIServices | Nhiều điểm hỏng, tốn pin | Cao nhất (API hệ thống) |
| App chạy 2 màn hình | Không (phải placeholder) | **Có thể có** (scene riêng cho màn hình xe) | Có | N/A |
| Khả năng iOS 18.6 | Nền tảng còn đủ `[SDK18.6]`, chi tiết `[DEVICE]` | Nền tảng tồn tại `[SDK18.6]`, cách dùng hoàn toàn `[DEVICE]` | Luôn khả thi nhưng chất lượng thấp | Nền tảng tồn tại `[SDK18.6]` |
| Phù hợp mục tiêu | ✅ chạy app tuỳ ý | ✅✅ nếu làm được thì tốt nhất | ⚠️ giải pháp cuối | ❌ không chạy được app bên thứ ba |

### 5.1 Lựa chọn

**Chính: A (scene re-parenting).** Lý do — không phải vì dễ, mà vì:
- Là hướng duy nhất có bằng chứng nền tảng đầy đủ trên 18.6 (`UIRootSceneWindow`,
  `FBSSceneHostHandle`, `FBSCAContextSceneLayer`, `FBSDisplayConfiguration` `[SDK18.6]`).
- Touch/keyboard/audio hoạt động qua đường hệ thống → giảm mạnh diện tích lỗi.
- Có tiền lệ hoạt động thực tế (carplay-cast trên 14, CarCast trên 17).

**Nghiên cứu song song: B.** Nếu `CRSUIApplicationSceneSpecification` cho phép tạo scene ứng dụng
thật trên display CarPlay, đó là lời giải sạch hơn hẳn (app biết mình ở CarPlay, không cần
placeholder, không cần ép orientation, không cần chống suspend). Đưa vào Phase 9 như một nhánh
thử nghiệm có cổng đánh giá.

**D làm phụ trợ:** dùng cho UI của chính OpenCarPlay nếu cần.

**C là phương án dự phòng cuối cùng**, chỉ dùng nếu A và B đều bị chặn — và phải nói rõ với người
dùng về độ trễ/pin.

---

## 6. Vấn đề audio (nghiên cứu sơ bộ)

- Trên CarPlay, tuyến audio do hệ thống quản lý qua phiên CarPlay (`CARSession`), không phải do
  app quyết định. App chạy qua scene re-parenting vẫn là app thường ở màn hình chính → audio đi
  theo route mặc định, mà khi CarPlay đang kết nối thì route mặc định **đã là** CarPlay `[ASSUMED]`.
- Do đó dự đoán: **MVP không cần đụng gì tới audio**. Đây là kết luận cần kiểm chứng thực địa
  (§7.7) trước khi viết bất kỳ code audio nào.
- Tuyệt đối không tự ý `setActive:`/`setCategory:` trên `AVAudioSession` từ tweak — sẽ phá
  ducking, navigation prompt và cuộc gọi của xe.
- `CRSUIVolumeNotificationService`, `CRSInCallAssertionService` `[SDK18.6]` là những chỗ hệ thống
  quản lý ưu tiên audio — chỉ đọc, không can thiệp.

---

## 7. KẾ HOẠCH ĐIỀU TRA RUNTIME (bắt buộc trước Phase 7)

Không có bước nào ở đây là tuỳ chọn. Kết quả sẽ được ghi lại thành `RESEARCH-DEVICE.md`.

### 7.1 Chuẩn bị môi trường

Trên máy Linux:

```bash
# libimobiledevice: đọc log hệ thống, lấy thông tin thiết bị
sudo apt install -y libimobiledevice-utils usbmuxd ideviceinstaller

# ipsw (blacktop): class-dump Mach-O và dyld shared cache — chạy tốt trên Linux
curl -sSL https://github.com/blacktop/ipsw/releases/latest/download/ipsw_Linux_x86_64.tar.gz \
  | tar xz -C /tmp && sudo install /tmp/ipsw /usr/local/bin/

# Frida (client)
pipx install frida-tools   # hoặc: python3 -m pip install --user frida-tools
```

Trên iPhone (qua Sileo): `openssh`, `frida` (repo build.frida.re), `ldid`, `com.ex.substitute`
hoặc ElleKit (đã có sẵn cùng Dopamine).

```bash
# Từ Linux, mở SSH qua USB
iproxy 2222 22 &
ssh -p 2222 mobile@127.0.0.1
```

### 7.2 Xác minh môi trường (chạy trên thiết bị)

```bash
# iOS version chính xác
plutil -p /System/Library/CoreServices/SystemVersion.plist

# Kiến trúc
uname -m                      # kỳ vọng: arm64e

# Rootless prefix
ls -ld /var/jb /var/jb/usr/lib /var/jb/Library/MobileSubstrate/DynamicLibraries

# Hooking runtime nào đang dùng
ls -l /var/jb/usr/lib/libellekit.dylib /var/jb/usr/lib/libsubstrate.dylib 2>&1
dpkg-query -W -f='${Package} ${Version}\n' | grep -Ei 'ellekit|substrate|substitute|libhooker'

# Các process liên quan CarPlay khi CHƯA cắm và KHI ĐÃ cắm
ps -Ao pid,comm | grep -iE 'carplay|springboard|InCall|MusicUI'

# Bundle nào thực sự tồn tại
ls -d /System/Library/CoreServices/CarPlay*.app /Applications/CarPlay*.app 2>/dev/null
for p in /System/Library/CoreServices/CarPlay.app /System/Library/CoreServices/SpringBoard.app; do
  echo "== $p"; plutil -p "$p/Info.plist" 2>/dev/null | grep -E 'CFBundleIdentifier|CFBundleExecutable'
done
```

### 7.3 Dump Objective-C runtime của SpringBoard và CarPlay (đây là phần quan trọng nhất)

Cách A — copy binary về Linux rồi class-dump offline (khuyến nghị, không cần chạy gì trên máy):

```bash
# trên Linux
scp -P 2222 mobile@127.0.0.1:/System/Library/CoreServices/SpringBoard.app/SpringBoard ./dump/
scp -P 2222 mobile@127.0.0.1:/System/Library/CoreServices/CarPlay.app/CarPlay ./dump/

ipsw class-dump ./dump/SpringBoard --headers -o ./headers/SpringBoard
ipsw class-dump ./dump/CarPlay     --headers -o ./headers/CarPlay

# framework nằm trong dyld shared cache → phải trích xuất trước
scp -P 2222 'mobile@127.0.0.1:/System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64e*' ./dsc/
ipsw dyld info   ./dsc/dyld_shared_cache_arm64e
ipsw dyld extract ./dsc/dyld_shared_cache_arm64e CarKit
ipsw class-dump  ./dsc/dyld_shared_cache_arm64e --fileset-entry CarKit --headers -o ./headers/CarKit
# lặp lại cho: CarPlayServices, CarPlayUIServices, CarPlaySupport, FrontBoard, FrontBoardServices,
#              SpringBoardServices, UIKitCore
```

Cách B — probe trực tiếp bằng Frida (nhanh, đúng runtime thật):

```bash
frida -U -n SpringBoard -q -e '
  var want = ["SBAppViewController","SBDeviceApplicationSceneEntity",
              "SBApplicationSceneHandleRequest","SBSceneManagerCoordinator",
              "SBMainDisplaySceneManager","SBDeviceApplicationSceneHandle",
              "SBDeviceApplicationSceneView","SBSceneView","SBApplicationController",
              "SBSuspendedUnderLockManager","SBMainSwitcherViewController",
              "SBMainDisplaySceneLayoutViewController","SBOrientationTransformWrapperView",
              "UIRootSceneWindow","FBScene","FBSceneMonitor","FBSDisplayConfiguration"];
  want.forEach(function (n) { console.log((ObjC.classes[n] ? "OK   " : "MISS ") + n); });'
```

```bash
# liệt kê đầy đủ selector của một class (thay tên class theo nhu cầu)
frida -U -n SpringBoard -q -e '
  var c = ObjC.classes["SBAppViewController"];
  if (!c) { console.log("class missing"); }
  else { c.$ownMethods.forEach(function (m) { console.log(m); }); }'
```

```bash
# trong process CarPlay dashboard
frida -U -n CarPlay -q -e '
  ["CARApplication","CARApplicationInfo","CARApplicationLaunchInfo","CARDashboard",
   "CARIconView","CARAppDockViewController","_CARDashboardHomeViewController",
   "CRCarPlayAppDeclaration","CRCarPlayAppPolicy","CRCarPlayAppPolicyEvaluator"]
  .forEach(function (n){ console.log((ObjC.classes[n]?"OK   ":"MISS ")+n); });'
```

### 7.4 Câu hỏi điều tra bắt buộc (Q1–Q12)

| # | Câu hỏi | Cách trả lời | Chặn phase nào |
|---|---|---|---|
| Q1 | `CRCarPlayAppPolicyEvaluator` có những method nào, ai gọi nó? | `frida-trace -U -n CarPlay -m "*[CRCarPlayAppPolicyEvaluator *]"` khi mở dashboard | 7 |
| Q2 | Dashboard lấy danh sách app từ đâu trên 18.6? `+[CARApplication _newApplicationLibrary]` còn tồn tại? | Frida probe class/selector + trace | 7 |
| Q3 | `CARApplicationInfo` còn ivar `_carPlayDeclaration`? | `ipsw class-dump CarPlay` → grep | 7 |
| Q4 | Đặt policy `_canDisplayOnCarScreen=YES` có làm icon xuất hiện? | thử nghiệm trực tiếp | 7 |
| Q5 | Chuỗi tạo scene của SpringBoard còn nguyên selector nào? | class-dump + so sánh với bảng §2.4 | 9 |
| Q6 | `UIRootSceneWindow -initWithDisplayConfiguration:` còn hoạt động trong SpringBoard? | Frida thử tạo window ẩn khi CarPlay đang cắm | 9 |
| Q7 | Cách đúng để lấy `FBSDisplayConfiguration` của màn hình xe trên 18.6 (`AVExternalDevice` còn dùng được?) | probe `FBSDisplayMonitor`/`CARScreenInfo` song song | 4/9 |
| Q8 | Notification nào báo CarPlay connect/disconnect trên 18.6? (`CarPlayIsConnectedDidChange` còn?) | `notifyutil -w`/ Darwin notify sniff + trace `NSNotificationCenter` | 4 |
| Q9 | `CRSUIApplicationSceneSpecification` được dùng thế nào — có thể tạo scene app thật trên màn hình xe? | class-dump CarPlayUIServices + trace khi mở app CarPlay-native | 9 (nhánh B) |
| Q10 | IPC nào còn hoạt động giữa CarPlay.app ↔ SpringBoard? | thử lần lượt 3 backend §4.1[4] | 6 |
| Q11 | Audio có tự đi đúng route khi app chạy trên màn hình xe? | thực địa trong xe | 11 |
| Q12 | `SBSRemoteAlertDefinition._forCarPlay` được kích hoạt ra sao? | trace khi có cuộc gọi đến lúc CarPlay đang cắm | phụ trợ |

### 7.5 Theo dõi log thời gian thực

```bash
# Trên Linux, lọc log của thiết bị
idevicesyslog | grep -iE 'carplay|springboard|OpenCarPlay'

# hoặc trên thiết bị nếu đã cài oslog/log
/var/jb/usr/bin/log stream --predicate 'processImagePath CONTAINS "CarPlay"' --style compact
```

### 7.6 Sniff notification (Q8, Q10)

```bash
# Darwin notifications
notifyutil -v -w com.apple.carplay.isconnected 2>/dev/null

# hoặc trace bằng Frida trong SpringBoard
frida -U -n SpringBoard -q -e '
  var f = Module.findExportByName(null, "notify_post");
  Interceptor.attach(f, { onEnter: function (a) {
      var n = a[0].readUtf8String();
      if (/car|Car/.test(n)) console.log("notify_post: " + n);
  }});'
```

### 7.7 Kiểm chứng trong xe (không thể thay thế bằng bàn giấy)

Cần một buổi test thực tế với head unit thật: cắm dây, quan sát log lúc connect/disconnect,
lúc khoá máy, lúc có cuộc gọi đến, lúc chuyển app. Simulator **không** mô phỏng được lớp
`CARSession`/policy này.

---

## 8. Môi trường build (đã kiểm tra trên máy hiện tại)

Kết quả `2026-09-05` trên Ubuntu 26.04:

```
git ✓   curl ✓   make ✓   perl ✓   python3 ✓   dpkg-deb ✓   fakeroot ✓
clang ✗   ldid ✗   xcrun ✗   THEOS chưa cài
```

Việc cần làm ở Phase 2:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
# SDK: iPhoneOS18.6.sdk (xybp888/iOS-SDKs) đặt vào $THEOS/sdks/
# Rootless:
export THEOS_PACKAGE_SCHEME=rootless
```

Ghi chú: SDK iOS 18.6 đã được xác nhận có sẵn công khai và **chính là bản dùng để đối chiếu
symbol trong tài liệu này**.

---

## 9. Rủi ro & giới hạn

| Rủi ro | Mức | Giảm thiểu |
|---|---|---|
| Selector SpringBoard đổi → crash SpringBoard (bootloop) | **Cao** | mọi bước đều probe trước; không hook nếu thiếu; test trong safe mode; có script gỡ cài khẩn cấp |
| Policy layer chặn app → không hiện icon | Cao | điều tra Q1–Q4 trước khi code Phase 7 |
| Video app (Netflix/YouTube) chặn màn hình phụ vì DRM | Trung bình | ghi rõ giới hạn; không bypass DRM |
| Ảnh hưởng audio/cuộc gọi của xe | Trung bình | không chạm `AVAudioSession`; chỉ quan sát |
| An toàn giao thông | **Cao (ngoài kỹ thuật)** | README nêu rõ: người lái chịu trách nhiệm; đây là công cụ nghiên cứu |
| Pin/nhiệt khi giữ màn hình không blank | Trung bình | chỉ giữ khi thực sự đang host app; giải phóng ngay khi rút |
| Vi phạm bản quyền carplay-cast | Thấp | không copy code; tài liệu này ghi rõ ranh giới; giữ nguyên attribution ở README |

---

## 10. Nguồn

- carplay-cast — https://github.com/EthanArbuckle/carplay-cast (đọc toàn bộ source, commit 696bc72)
- Apple CarPlay documentation — https://developer.apple.com/documentation/carplay
- Dopamine (ma trận hỗ trợ A12/A13 → iOS 18.7.1) — https://github.com/opa334/Dopamine
- iOS SDKs (iPhoneOS18.6.sdk, symbol private framework) — https://github.com/xybp888/iOS-SDKs
- Theos — https://theos.dev/docs/installation-linux
- ipsw (class-dump trên Linux) — https://github.com/blacktop/ipsw
