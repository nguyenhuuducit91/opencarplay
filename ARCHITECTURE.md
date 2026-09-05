# OpenCarPlay — ARCHITECTURE

Thiết kế kỹ thuật. Đọc `RESEARCH.md` trước — mọi lựa chọn ở đây đều bắt nguồn từ bằng chứng
trong tài liệu đó.

- Package: `com.opencarplay.tweak`
- Target: iPhone 11 (arm64e), iOS 18.6.x, Dopamine rootless, ElleKit
- Ngôn ngữ: Objective-C / Objective-C++ (Logos `.x/.xm`), không Swift

---

## 1. Năm nguyên tắc bất di bất dịch

1. **Fail-safe trước, tính năng sau.** Trạng thái mặc định của tweak là *không làm gì*. Mọi thứ
   phải được bật tường minh. Nếu nghi ngờ → tắt tính năng, ghi log, để CarPlay chạy như nguyên bản.
2. **Không API nào được dùng nếu chưa probe.** Mọi class lấy qua `NSClassFromString`, mọi selector
   qua `respondsToSelector:`. Không có ngoại lệ, kể cả với class đã xác nhận trong `RESEARCH.md`
   (SDK ≠ thiết bị).
3. **Bề mặt inject nhỏ nhất.** Chỉ nạp vào process thực sự cần. Không dùng filter
   `com.apple.UIKit`.
4. **Không được làm hỏng CarPlay nguyên bản.** Nếu OpenCarPlay tắt hoặc không tương thích,
   hành vi hệ thống phải giống hệt khi chưa cài.
5. **Không đụng vào những thứ ngoài phạm vi jailbreak sẵn có.** Không kernel, không code-signing,
   không boot chain, không persistence riêng.

---

## 2. Sơ đồ tổng thể

```
┌─────────────────────────── iPhone ────────────────────────────┐
│                                                                │
│  com.apple.CarPlayApp            com.apple.springboard         │
│  ┌──────────────────────┐        ┌──────────────────────────┐  │
│  │ OpenCarPlay.dylib    │        │ OpenCarPlay.dylib        │  │
│  │  ├ OCPCore (chung)   │        │  ├ OCPCore (chung)       │  │
│  │  ├ OCPDashboardAgent │        │  ├ OCPHostController     │  │
│  │  │   • app discovery │  IPC   │  │   • tạo window trên   │  │
│  │  │   • policy hook   │ ─────► │  │     màn hình xe       │  │
│  │  │   • bắt tap icon  │        │  │   • dựng/gắn scene    │  │
│  │  └──────────────────┘         │  │   • lifecycle/assert  │  │
│  └──────────────────────┘        │  └──────────────────────┘  │
│                                   └──────────────────────────┘  │
│                                                                │
│  <app trong AllowedApplications>                               │
│  ┌────────────────────────────────┐                            │
│  │ OpenCarPlayApp.dylib (tối giản)│   ← chỉ orientation/thông  │
│  │  • OCPAppAgent                 │      tin, KHÔNG UI         │
│  └────────────────────────────────┘                            │
│                                                                │
│  Preferences (PreferenceLoader bundle) ──► com.opencarplay.plist│
└────────────────────────────────────────────────────────────────┘
```

**Vì sao tách hai dylib:** dylib chính chỉ nạp vào 2 process hệ thống. Dylib phụ nạp vào app
người dùng nhưng `%ctor` thoát ngay lập tức (trước khi hook bất cứ gì) nếu bundle ID không nằm
trong `AllowedApplications` — chi phí gần bằng 0 cho phần còn lại của hệ thống.

---

## 3. Cấu trúc thư mục

```
OpenCarPlay/
├── Makefile                     # aggregate: tweak + apptweak + prefs
├── control
├── README.md
├── LICENSE
├── RESEARCH.md
├── ARCHITECTURE.md
├── RESEARCH-DEVICE.md           # (Phase 4+) kết quả dump runtime thật
├── .gitignore
│
├── Core/                        # dùng chung mọi target — thuần logic, dễ unit-test
│   ├── OCPLog.h/.m              # logging có phân loại, tắt được
│   ├── OCPCompatibility.h/.m    # phát hiện iOS/kiến trúc/jailbreak
│   ├── OCPProbe.h/.m            # kiểm tra class/selector/ivar runtime
│   ├── OCPPreferences.h/.m      # đọc/ghi com.opencarplay.plist
│   ├── OCPAppRegistry.h/.m      # danh sách app được phép
│   ├── OCPDisplayConfiguration.h/.m
│   └── OCPTransport.h/.m        # IPC trừu tượng (3 backend)
│
├── Tweak/                       # dylib chính: SpringBoard + CarPlayApp
│   ├── OpenCarPlay.plist        # filter bundle
│   ├── Entry.xm                 # %ctor phân luồng theo process
│   ├── SpringBoard/
│   │   ├ OCPHostController.h/.mm     # điều phối hosting
│   │   ├ OCPCarPlayWindow.h/.mm      # window trên màn hình xe
│   │   ├ OCPSceneBridge.h/.mm        # dựng & gắn scene của app
│   │   ├ OCPLifecycleGuard.h/.mm     # assertion chống suspend
│   │   └ Hooks.xm
│   └── CarPlayApp/
│       ├ OCPDashboardAgent.h/.mm     # discovery + policy
│       └ Hooks.xm
│
├── AppTweak/                    # dylib phụ nạp vào app đích
│   ├── OpenCarPlayApp.plist
│   └── AppAgent.xm
│
├── Preferences/                 # PreferenceLoader bundle
│   ├── OCPRootListController.h/.m
│   ├── OCPAppListController.h/.m
│   ├── Resources/Root.plist
│   └── entry.plist
│
├── scripts/
│   ├── install.sh  uninstall.sh  diagnose.sh
│   ├── collect_logs.sh  inspect_carplay.sh
│   └── probe/                   # script Frida cho §7 RESEARCH.md
│
└── tests/                       # unit test chạy trên máy build (không cần thiết bị)
```

---

## 4. Module chi tiết

### 4.1 `OCPProbe` — nền tảng của nguyên tắc "không giả định"

Mọi truy cập private API đi qua đây. Không module nào được gọi `objc_getClass` trực tiếp.

```objc
typedef NS_ENUM(NSInteger, OCPFeature) {
    OCPFeatureCarPlayDetection = 0,
    OCPFeatureAppDiscovery,
    OCPFeatureSceneHosting,
    OCPFeatureOrientationControl,
    OCPFeatureLockAssertion,
    OCPFeatureCount
};

@interface OCPProbe : NSObject

+ (nullable Class)classNamed:(NSString *)name;                    // log 1 lần nếu thiếu
+ (BOOL)class:(NSString *)cls respondsTo:(NSString *)selector;    // instance method
+ (BOOL)metaClass:(NSString *)cls respondsTo:(NSString *)selector;// class method
+ (BOOL)instance:(id)obj hasIvar:(NSString *)ivarName;

// Kiểm tra trọn gói yêu cầu của một tính năng; kết quả được cache + log 1 lần.
+ (BOOL)featureAvailable:(OCPFeature)feature;
+ (NSDictionary<NSString *, NSNumber *> *)diagnosticsReport;      // dùng cho diagnose.sh

@end
```

Mỗi `OCPFeature` khai báo requirement dưới dạng dữ liệu (mảng cặp class/selector), nạp từ một
bảng tĩnh trong `OCPProbe.m`. Thêm/bớt yêu cầu = sửa bảng, không sửa logic.

### 4.2 `OCPCompatibility`

```objc
@interface OCPCompatibility : NSObject
+ (NSString *)systemVersion;          // "18.6.2"
+ (BOOL)isIOS18;
+ (BOOL)isIOS18_6;
+ (BOOL)isSupportedOS;                // mặc định: >= 18.0 && < 19.0, hẹp dần theo kết quả test
+ (BOOL)isRootlessEnvironment;        // tồn tại /var/jb hoặc JBROOT
+ (NSString *)jailbreakRootPath;      // "/var/jb" hoặc "/"
+ (NSString *)hookingRuntimeName;     // "ellekit" | "substrate" | "unknown"
+ (NSString *)architecture;           // "arm64e"
@end
```

`isSupportedOS` sai → `%ctor` thoát ngay, không `%init` bất kỳ group nào.

### 4.3 `OCPLog`

Danh mục cố định, ánh xạ 1-1 với yêu cầu ở đề bài:

```objc
typedef NS_ENUM(NSInteger, OCPLogCategory) {
    OCPLogCore, OCPLogCarPlay, OCPLogApplication, OCPLogRendering,
    OCPLogTouch, OCPLogAudio, OCPLogCompatibility, OCPLogError
};

#define OCPLogC(cat, fmt, ...) [OCPLog log:(cat) file:__FILE__ line:__LINE__ format:(fmt), ##__VA_ARGS__]
```

- Mặc định: chỉ `OCPLogError` được ghi. `DebugLogging = YES` mới bật hết.
- Đích: `os_log` (subsystem `com.opencarplay.tweak`) + tuỳ chọn file
  `/var/jb/var/mobile/Library/Logs/OpenCarPlay/ocp.log` có xoay vòng theo kích thước.
- Định dạng: `[OpenCarPlay][CarPlay] Connected — display 1280x720@2.0`

### 4.4 `OCPPreferences` + `OCPAppRegistry`

Đường dẫn: `$JBROOT/var/mobile/Library/Preferences/com.opencarplay.plist`

```
Enabled              Bool    (mặc định NO — nguyên tắc 1)
AllowedApplications  Array<String>
AutoLaunch           Bool    (NO)
HideStatusBar        Bool    (NO)
FullScreen           Bool    (NO)
ForceLandscape       Bool    (YES)
DebugLogging         Bool    (NO)
SchemaVersion        Number  (1)
```

```objc
@interface OCPAppRegistry : NSObject
+ (instancetype)sharedRegistry;
- (void)reload;
- (BOOL)isAllowed:(NSString *)bundleIdentifier;       // O(1), NSSet nội bộ
- (NSArray<NSString *> *)allowedApplications;
- (BOOL)isValidBundleIdentifier:(NSString *)candidate; // chặn rác/ký tự lạ
- (BOOL)shouldNeverExpose:(NSString *)bundleIdentifier;// chặn cứng: springboard, carplay, preferences...
@end
```

Không hard-code bundle ID người dùng. Chỉ có **denylist an toàn** cố định (các process hệ thống
mà việc host sẽ gây bootloop) — được ghi rõ trong README.

Thay đổi được truyền đi bằng `OCPTransport` (Darwin notification), mỗi process tự `reload`.

### 4.5 `OCPDisplayConfiguration`

```objc
@interface OCPDisplayConfiguration : NSObject
@property (nonatomic, readonly) CGSize   pixelSize;      // thật, từ hệ thống
@property (nonatomic, readonly) CGSize   pointSize;
@property (nonatomic, readonly) CGFloat  scale;
@property (nonatomic, readonly) UIEdgeInsets safeAreaInsets;
@property (nonatomic, readonly) UIInterfaceOrientation orientation;
@property (nonatomic, readonly) NSInteger maxFramesPerSecond;
@property (nonatomic, readonly, nullable) id displayConfiguration;  // FBSDisplayConfiguration
@property (nonatomic, readonly) BOOL isValid;

+ (nullable instancetype)currentCarPlayConfiguration;   // nil nếu chưa kết nối
- (CGPoint)convertPointToApplication:(CGPoint)carPlayPoint;   // dùng khi cần map thủ công
@end
```

Nguồn dữ liệu theo thứ tự (dừng ở nguồn đầu tiên khả dụng, ghi log nguồn đã dùng):
`FBSDisplayConfiguration` → `CARScreenInfo` → `UIScreen` fallback. **Không hard-code 800×480.**

### 4.6 `OCPTransport`

```objc
typedef NS_ENUM(NSInteger, OCPTransportBackend) {
    OCPTransportDarwinNotify = 0,   // notify_post + payload qua file (ưu tiên)
    OCPTransportMessagingCenter,    // CPDistributedMessagingCenter
    OCPTransportDistributedNC,      // NSDistributedNotificationCenter (chỉ nếu probe OK)
    OCPTransportUnavailable
};

@interface OCPTransport : NSObject
+ (instancetype)sharedTransport;
@property (nonatomic, readonly) OCPTransportBackend activeBackend;
- (void)postMessage:(NSString *)name payload:(nullable NSDictionary *)payload;
- (void)observeMessage:(NSString *)name handler:(void (^)(NSDictionary *payload))handler;
@end
```

Backend được chọn khi khởi động dựa trên probe, ghi log rõ ràng. Payload luôn là plist đơn giản
(string/number/bool) — không object phức tạp, không dữ liệu người dùng.

Tên message: `com.opencarplay.launch`, `com.opencarplay.dismiss`,
`com.opencarplay.prefs-changed`, `com.opencarplay.orientation`.

### 4.7 `OCPHostController` (SpringBoard) — máy trạng thái

```
        ┌────────┐   CarPlay connected    ┌───────────┐
        │  IDLE  │ ─────────────────────► │   READY   │
        └────────┘                        └───────────┘
             ▲                              │      ▲
             │ disconnected / disabled      │      │ dismiss / app died
             │                     launch req│      │
             │                              ▼      │
        ┌──────────┐   scene attached   ┌──────────┴──┐
        │ TEARDOWN │ ◄───────────────── │   HOSTING   │
        └──────────┘                    └─────────────┘
                                            │      ▲
                                    suspend │      │ resume
                                            ▼      │
                                        ┌──────────┴──┐
                                        │  BACKGROUND │
                                        └─────────────┘
```

Mọi chuyển trạng thái được ghi log. Mỗi trạng thái có invariant kiểm tra được (dùng trong test).
`TEARDOWN` phải luôn giải phóng: window, assertion, observer, gesture, snapshot — kể cả khi lỗi.

### 4.8 `OCPSceneBridge`

Đóng gói toàn bộ chuỗi private của SpringBoard thành các **bước có tiền đề**:

```objc
typedef NS_ENUM(NSInteger, OCPBridgeStage) {
    OCPBridgeStageResolveApplication, OCPBridgeStageResolveSceneIdentity,
    OCPBridgeStageCreateSceneHandle,  OCPBridgeStageCreateViewController,
    OCPBridgeStageBeginTransaction,   OCPBridgeStageAttachView,
    OCPBridgeStageObserveScene
};

@interface OCPSceneBridge : NSObject
+ (BOOL)isSupportedOnThisSystem;   // = OCPProbe featureAvailable: SceneHosting
- (BOOL)attachApplication:(NSString *)bundleID
                 toWindow:(UIWindow *)window
                    error:(NSError **)error;   // lỗi mang theo OCPBridgeStage thất bại
- (void)detachWithReason:(NSString *)reason;
@end
```

Một bước thiếu tiền đề → trả `NO` kèm stage → `OCPHostController` quay về `READY` và báo người
dùng, **không** để lại trạng thái nửa vời.

> Nội dung cụ thể của từng stage **chưa được viết** — chờ kết quả Q5/Q6 trong `RESEARCH.md §7.4`.

---

## 5. Bảo vệ chống crash

Tất cả đều bắt buộc, kiểm tra khi review code:

1. Mỗi hook body: `@try { ... } @catch (NSException *e) { OCPLogC(OCPLogError, ...); }` và **luôn**
   gọi `%orig` ở nhánh an toàn.
2. Không `assert`-style exception như `assertGotExpectedObject` của carplay-cast — nó *ném*
   exception trong process hệ thống. Ta trả `nil`/`NO` và log.
3. Không bao giờ hook nếu `OCPProbe featureAvailable:` trả `NO`.
4. **Kill switch:** nếu file `$JBROOT/var/mobile/Library/Preferences/com.opencarplay.disabled`
   tồn tại → `%ctor` thoát ngay. `scripts/diagnose.sh` và README hướng dẫn tạo file này qua SSH
   để cứu máy khi bootloop mà không cần gỡ package.
5. **Bộ đếm crash:** ghi timestamp mỗi lần khởi tạo. Nếu SpringBoard khởi động lại > 3 lần trong
   60 giây → tự vô hiệu hoá (viết file disabled) và ghi log. Đây là lưới an toàn cuối.
6. Không giữ strong reference tới object hệ thống ngoài vòng đời hosting.

---

## 6. Touch & orientation

**Nguyên tắc:** không tự bơm sự kiện chạm. Với Approach A (scene re-parenting), UIKit/BackBoard
định tuyến touch tự động vì view của app nằm trong cây view của window trên display CarPlay.
`OCPDisplayConfiguration -convertPointToApplication:` chỉ tồn tại cho trường hợp cần overlay
riêng của tweak.

Orientation: yêu cầu app xoay qua `OCPTransport` → `OCPAppAgent` trong process app thực thi. App
agent **không** vẽ gì, chỉ:
- nhận yêu cầu orientation, áp dụng qua API công khai nếu đủ (`UIWindowScene` geometry request),
  private là phương án dự phòng có probe;
- báo lại kích thước/hướng thực tế để `OCPCarPlayWindow` tính scale.

MVP hỗ trợ: tap, swipe, scroll (tự nhiên, không cần code). Multi-touch/gesture phức tạp là hệ quả
miễn phí nếu Approach A hoạt động.

---

## 7. Audio

MVP: **không có code audio.** Kết luận từ `RESEARCH.md §6`: app chạy như scene màn hình chính nên
audio đi theo route hệ thống, mà route đó đã là CarPlay khi đang kết nối. Phase 11 chỉ *quan sát
và ghi nhận*; chỉ khi thực địa cho thấy có vấn đề mới thiết kế can thiệp, và khi đó phải là can
thiệp tối thiểu, có thể tắt.

---

## 8. Đóng gói (rootless)

`control`:

```
Package: com.opencarplay.tweak
Name: OpenCarPlay
Version: 0.1.0
Architecture: iphoneos-arm64
Depends: firmware (>= 18.0), ellekit, preferenceloader
Section: Tweaks
Maintainer / Author: OpenCarPlay contributors
Description: Use selected iOS apps on the CarPlay screen (research tool)
```

`Makefile` (khung, chi tiết chốt ở Phase 2):

```make
export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = OpenCarPlay
...
SUBPROJECTS += AppTweak Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
```

Lệnh chuẩn:

```bash
make clean package                                # THEOS_PACKAGE_SCHEME đã export trong Makefile
make package THEOS_PACKAGE_SCHEME=rootless        # tương đương, tường minh
make package FINALPACKAGE=1
```

Sản phẩm: `packages/com.opencarplay.tweak_0.1.0_iphoneos-arm64.deb`

Đường dẫn cài đặt do Theos rootless tự thêm prefix `/var/jb`; **không** hard-code
`/Library/MobileSubstrate` trong bất kỳ file nào.

Sau cài đặt: `killall -9 CarPlay` là đủ cho thay đổi phía dashboard; thay đổi phía SpringBoard cần
respring (`sbreload` hoặc `killall -9 SpringBoard`). README sẽ nói rõ trường hợp nào cần gì.

---

## 9. Lộ trình & tiêu chí hoàn thành từng phase

| Phase | Nội dung | Tiêu chí "xong" (exit criteria) |
|---|---|---|
| 1 | Research | `RESEARCH.md` + `ARCHITECTURE.md` (tài liệu này) |
| 2 | Theos rootless, dylib rỗng | `make package` ra `.deb` `iphoneos-arm64`; cài qua Sileo; respring bình thường; log `%ctor` xuất hiện |
| 3 | `OCPLog`, `OCPCompatibility`, `OCPProbe` | log đúng iOS 18.6.2/arm64e/rootless/ellekit; `diagnose.sh` chạy được |
| 4 | Phát hiện CarPlay connect/disconnect | log đúng 2 sự kiện với head unit thật; `OCPDisplayConfiguration` in đúng kích thước màn hình xe (Q7, Q8) |
| 5 | Phát hiện process CarPlay + inject đúng chỗ | dylib có mặt trong CarPlay.app & SpringBoard, không nơi khác |
| 6 | AppRegistry + Preferences đọc/ghi | thay đổi plist được cả 2 process nhận |
| 7 | App discovery (icon lên dashboard) | **chỉ bắt đầu sau khi trả lời Q1–Q4**; icon app trong AllowedApplications xuất hiện; CarPlay native không đổi |
| 8 | Launch | tap icon → app khởi chạy đúng vòng đời, mọi trạng thái ở `RESEARCH.md §2.6` được xử lý |
| 9 | UI bridging | **chỉ sau Q5/Q6**; app hiển thị trên màn hình xe, không crash SpringBoard |
| 10 | Touch | tap/swipe/scroll hoạt động |
| 11 | Audio | xác nhận không phá audio xe (chỉ quan sát) |
| 12 | Preferences UI | bundle hiện trong Settings, đủ 8 mục |
| 13 | Packaging | `.deb` sạch, postinst/postrm đúng, gỡ cài không để lại rác |
| 14 | Stress test | checklist thiết bị đầy đủ; 30 phút connect/disconnect liên tục không crash |

Không chuyển phase khi phase hiện tại chưa build + test thành công trên thiết bị.

---

## 10. MVP (Phase 2 → 6)

MVP **không** chạy app tuỳ ý. MVP chứng minh nền móng an toàn:

- [x] phát hiện iOS version, kiến trúc, rootless, hooking runtime
- [x] nạp đúng process, không nạp process khác
- [x] phát hiện CarPlay kết nối / ngắt kết nối, đọc đúng cấu hình màn hình
- [x] đọc `AllowedApplications`, phản ứng khi plist đổi
- [x] log đầy đủ vòng đời, tắt được
- [x] `Enabled = NO` → hành vi hệ thống không khác gì khi chưa cài
- [x] không crash SpringBoard, không crash CarPlay, kill switch hoạt động

---

## 11. Chiến lược test

**Trên máy build (không cần thiết bị)** — `tests/`, biên dịch với clang host, không UIKit:
- parse phiên bản iOS (chuỗi hợp lệ/không hợp lệ/thiếu thành phần)
- validate bundle identifier (rỗng, ký tự lạ, quá dài, hợp lệ)
- parse plist (thiếu key, sai kiểu, mảng rỗng, giá trị rác)
- khớp app được phép (phân biệt hoa thường, trùng lặp, denylist thắng allowlist)
- tính toán scale/tọa độ của `OCPDisplayConfiguration` với các cặp kích thước giả lập
- chuyển trạng thái `OCPHostController` (bảng chuyển hợp lệ/không hợp lệ)

**Trên thiết bị** — script Frida trong `scripts/probe/`, chạy trước mỗi phase phụ thuộc private API.

**Trong xe** — checklist thủ công (mục 23 của đề bài) ghi vào `README.md`.

---

## 12. Ranh giới pháp lý & đạo đức

- Không sao chép mã nguồn của CarBridge, CarCast hay phần mềm thương mại khác. carplay-cast chỉ
  được dùng để **phân tích kiến trúc**; toàn bộ implementation là độc lập.
- Không upload dữ liệu người dùng, crashlog hay telemetry đi bất cứ đâu.
- README nêu rõ rủi ro an toàn giao thông và trách nhiệm người dùng.
- Giấy phép dự kiến: MIT hoặc GPLv3 (chọn ở Phase 2 — GPLv3 phù hợp hơn với tinh thần
  "nếu dùng lại thì mở mã").
