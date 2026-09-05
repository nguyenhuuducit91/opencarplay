# OpenCarPlay

Tweak jailbreak mã nguồn mở cho phép dùng một số ứng dụng iOS thông thường trên màn hình CarPlay.

> **Trạng thái: đang phát triển — Phase 2/14.** Bản hiện tại *chưa* đưa được app lên CarPlay.
> Nó mới dựng nền: nạp đúng process, không ảnh hưởng CarPlay nguyên bản. Xem
> [lộ trình](ARCHITECTURE.md#9-lộ-trình--tiêu-chí-hoàn-thành-từng-phase).

---

## Tính năng

Đã có:

- Nạp có kiểm soát vào `SpringBoard` và `CarPlay.app`, không nạp process khác
- Đóng gói rootless (`iphoneos-arm64`), không hard-code `/Library/MobileSubstrate`
- Kill switch cứu máy khi bootloop mà không cần gỡ package

Đang làm (theo lộ trình):

- Phát hiện CarPlay kết nối/ngắt + đọc cấu hình màn hình xe (Phase 4)
- Danh sách app được phép, đọc từ plist (Phase 6)
- Đưa app lên dashboard CarPlay (Phase 7 — **chờ bằng chứng runtime**, xem bên dưới)
- Khởi chạy và hiển thị app trên màn hình xe (Phase 8–9)
- Chạm, cuộn, vuốt (Phase 10)
- Preference bundle (Phase 12)

## iOS được hỗ trợ

| Mục | Giá trị |
|---|---|
| iOS | 18.6.x (phát triển & test trên 18.6.2) |
| Thiết bị | iPhone 11 (A13, arm64e) |
| Jailbreak | Dopamine (rootless), ElleKit |
| Package manager | Sileo |

Ngoài phạm vi này tweak **tự vô hiệu hoá** thay vì hook mù.

## Yêu cầu

- iPhone đã jailbreak rootless, có `ellekit`
- Máy build Linux hoặc macOS với [Theos](https://theos.dev)
- Đầu CarPlay thật để test (simulator không mô phỏng được lớp `CARSession`/policy)

## Cài đặt

**Qua Sileo (khuyến nghị)** — thêm repo:

```
https://nguyenhuuducit91.github.io/opencarplay/
```

Sileo → Sources → thêm URL trên → cài **OpenCarPlay** → respring.

**Thủ công**

1. Build (xem mục dưới) hoặc lấy `.deb` từ `packages/`
2. Copy `.deb` sang thiết bị
3. Cài bằng Sileo (hoặc `dpkg -i`)
4. Respring — chỉ cần khi thay đổi ảnh hưởng SpringBoard; thay đổi phía dashboard chỉ cần
   `killall -9 CarPlay`
5. Bật OpenCarPlay trong **Settings → OpenCarPlay**
6. Cắm CarPlay
7. Chọn app được phép

Hoặc dùng script (tự build → copy → cài → restart):

```bash
DEVICE_PORT=2222 ./scripts/install.sh
```

## Build

```bash
export THEOS=$HOME/theos
make clean package                  # rootless đã bật sẵn trong Makefile
make package FINALPACKAGE=1         # bản phát hành
```

Sản phẩm: `packages/com.opencarplay.tweak_<version>_iphoneos-arm64.deb`

Cập nhật APT repo (thư mục `docs/`, phục vụ bởi GitHub Pages):

```bash
make package FINALPACKAGE=1 && make repo
```

`scripts/make_repo.py` sinh `Packages`, `Packages.{gz,bz2,xz}` và `Release`, chỉ dùng thư viện
chuẩn của Python — không cần `dpkg-dev` hay `apt-utils`.

Yêu cầu toolchain hỗ trợ **arm64e ABI có ptrauth versioning** — toolchain quá cũ sẽ tạo slice
arm64e mà iOS 18 từ chối nạp. Xem [ARCHITECTURE.md §8](ARCHITECTURE.md).

## Development

Tài liệu bắt buộc đọc trước khi sửa code:

- [`RESEARCH.md`](RESEARCH.md) — CarPlay hoạt động thế nào trên iOS 18.6, cái gì đã đổi so với
  iOS 14, và **12 câu hỏi runtime chưa trả lời** (Q1–Q12)
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — thiết kế module, máy trạng thái, lộ trình

Nguyên tắc số một: **không API nào được dùng nếu chưa probe runtime.** Mọi class lấy qua
`NSClassFromString`, mọi selector qua `respondsToSelector:`. Thiếu thì tắt tính năng và ghi log,
không bao giờ crash.

Thu thập bằng chứng runtime:

```bash
sh scripts/inspect_carplay.sh              # chạy trên thiết bị
frida -U -n SpringBoard -l scripts/probe/01-classes.js -q
```

Chi tiết: [`scripts/probe/README.md`](scripts/probe/README.md).

## Architecture

```
CarPlay.app                    SpringBoard
  phát hiện ý định   ── IPC ──►  dựng & gắn scene của app lên màn hình xe
  (app discovery)                (hosting, lifecycle, assertion)
```

Hướng render đã chọn là **scene re-parenting** — view của scene ứng dụng được gắn vào một window
trên display CarPlay, không mirroring, không bơm sự kiện chạm thủ công. Lý do và so sánh với 3
hướng khác: [RESEARCH.md §5](RESEARCH.md).

## Troubleshooting

**Bootloop / SpringBoard chết liên tục**

Tweak tự phát hiện và tắt: nếu SpringBoard nạp lại 4 lần trong 45 giây, nó tự tạo file kill
switch và ngừng hoạt động, máy trở lại bình thường ở lần respring kế tiếp. Nếu cần tắt thủ công:

```bash
ssh mobile@<device>
touch /var/jb/var/mobile/Library/Preferences/com.opencarplay.disabled
sbreload
```

Tweak sẽ không nạp cho tới khi xoá file đó. Không cần gỡ package.

**Chẩn đoán tổng quát**

```bash
scp -P 2222 scripts/diagnose.sh mobile@127.0.0.1:/tmp/
ssh -p 2222 mobile@127.0.0.1 sh /tmp/diagnose.sh
```

Kiểm tra: phiên bản iOS, kiến trúc, môi trường rootless, gói đã cài, process CarPlay,
dylib đã nạp, trạng thái kill switch.

## Logs

Mặc định chỉ ghi lỗi. Bật đầy đủ bằng `DebugLogging = YES` trong
`/var/jb/var/mobile/Library/Preferences/com.opencarplay.plist`.

```bash
./scripts/collect_logs.sh                 # từ máy build
idevicesyslog | grep -i opencarplay       # tương đương
```

Danh mục log: `[OpenCarPlay] [CarPlay] [Application] [Rendering] [Touch] [Audio]
[Compatibility] [Error]`.

Khi ứng dụng đang hiển thị trên màn hình xe, danh mục `[Touch]` cho biết sự kiện chạm đi tới
đâu — thanh điều khiển thấy chạm, tầng display thấy chạm, hay không tầng nào thấy. Ba trường
hợp đó chỉ tới ba nguyên nhân khác nhau.

Danh mục `[Audio]` ghi lại tuyến âm thanh tại bốn thời điểm: khi CarPlay kết nối, khi ngắt, khi
ứng dụng được gắn lên màn hình xe và khi đóng. OpenCarPlay **không bao giờ** thay đổi cấu hình
âm thanh — nó chỉ đọc, để bạn xác nhận được rằng tweak không phá ducking, chỉ dẫn dẫn đường hay
cuộc gọi của xe.

### Công cụ nghiên cứu

Hai khoá trong plist, mặc định tắt, chỉ dùng khi cần thu thập bằng chứng runtime:

| Khoá | Tác dụng |
|---|---|
| `SignalDiscovery` | Ghi lại mọi notification có tên liên quan tới CarPlay/display mà SpringBoard nhận được (mỗi tên một lần) — trả lời Q8 trong `RESEARCH.md` |
| `RuntimeSurvey` | Khảo sát Objective-C runtime của process: class nào tồn tại theo tiền tố, selector và ivar của các class mà kiến trúc phụ thuộc — trả lời Q1–Q6 |

Kết quả khảo sát ghi vào `/var/mobile/Media/OpenCarPlay/`, lấy về máy build qua USB
**không cần SSH**:

```bash
./scripts/fetch_survey.sh
```

Đây là cách kiểm chứng xem chuỗi private API mà carplay-cast dùng trên iOS 14 còn tồn tại
trên iOS 18.6.2 hay không, thay vì đoán.

### Cấu hình

Dùng **Settings → OpenCarPlay**, hoặc sửa trực tiếp
`/var/jb/var/mobile/Library/Preferences/com.opencarplay.plist` — xem
[`examples/com.opencarplay.plist`](examples/com.opencarplay.plist).

Bảng cài đặt ghi thẳng vào file đó và bắn Darwin notification, nên thay đổi có hiệu lực ngay
mà không cần respring.

| Khoá | Mặc định | Ý nghĩa |
|---|---|---|
| `Enabled` | `NO` | Công tắc chính; `NO` thì tweak không đổi gì trong hệ thống |
| `AllowedApplications` | `[]` | Bundle id được phép dùng với CarPlay |
| `AutoLaunch` | `NO` | Tự mở app khi CarPlay kết nối |
| `HideStatusBar` / `FullScreen` | `NO` | Trình bày trên màn hình xe |
| `ForceLandscape` | `YES` | Ép app xoay ngang |
| `DebugLogging` | `NO` | Ghi log đầy đủ thay vì chỉ lỗi |
| `ExperimentalDiscovery` | `NO` | **Thử nghiệm** — đưa app trong danh sách lên dashboard CarPlay |
| `ExperimentalSceneHosting` | `NO` | **Thử nghiệm, rủi ro cao** — gắn giao diện app lên màn hình xe |

Mục nhập sai (chuỗi rác, process hệ thống) bị loại khi nạp và ghi log kèm lý do — danh sách
chặn cứng luôn thắng danh sách cho phép, nên một dòng cấu hình sai không thể đưa SpringBoard
hay chính CarPlay dashboard lên màn hình xe.

## Known limitations

- Việc đưa app lên dashboard (`ExperimentalDiscovery`) dựa trên cơ chế của iOS 14 và **chưa
  được kiểm chứng trên iOS 18.6**. iOS 18 có thêm lớp chính sách `CRCarPlayAppPolicy` mà dự án
  chưa giải mã (Q1–Q4 trong `RESEARCH.md`); nếu dashboard hỏi lớp đó thay vì đọc tuyên bố của
  ứng dụng thì cách hiện tại sẽ không có tác dụng. Tweak sẽ ghi log nói rõ điều đó thay vì im lặng.
- Gắn giao diện lên màn hình xe (`ExperimentalSceneHosting`) dựa trên chuỗi private API nội bộ
  của SpringBoard mà **chưa ai kiểm chứng trên iOS 18.6** (Q5 trong `RESEARCH.md`). Nếu chuỗi đã
  đổi, tweak từ chối chạy và ghi log tên bước hỏng, rồi lùi về mở ứng dụng trên màn hình iPhone.
- Chạm và cuộn trên màn hình xe chưa được kiểm chứng trên xe thật. Tweak không tự xử lý sự
  kiện chạm (UIKit định tuyến sẵn khi view của scene nằm trong cửa sổ trên màn hình xe), nhưng
  có hai lớp ghi log để biết chạm đi tới đâu: thanh điều khiển và tầng display.
- Ứng dụng chỉ sống trên một màn hình tại một thời điểm; khi đang ở màn hình xe, màn hình iPhone
  chưa có ảnh thay thế (sẽ làm ở phase sau).
- Một app chỉ chạy trên một màn hình tại một thời điểm; khi đang ở CarPlay, màn hình iPhone sẽ
  hiện placeholder
- Ứng dụng video có DRM có thể tự chặn hiển thị trên màn hình ngoài — dự án **không** bypass DRM
- Chưa hỗ trợ instrument cluster, dashboard widget, CarPlay không dây chưa được test riêng

## Security

- Chỉ dùng quyền mà jailbreak rootless đã cấp. Không patch kernel, không đụng code-signing,
  Secure Enclave hay boot chain, không tạo cơ chế persistence riêng.
- Không thu thập, không gửi dữ liệu đi bất kỳ đâu. Log chỉ nằm trên máy và mặc định tắt.
- Danh sách chặn cứng ngăn host các process hệ thống có thể gây bootloop.

**An toàn giao thông:** đưa ứng dụng tuỳ ý lên màn hình xe có thể gây mất tập trung và có thể vi
phạm luật ở nơi bạn sống. Đây là công cụ nghiên cứu. Người sử dụng chịu hoàn toàn trách nhiệm.

## License

**GPLv3** — xem [`LICENSE`](LICENSE). Nếu bạn fork hoặc dùng lại nghiên cứu/mã nguồn ở đây,
bản phái sinh cũng phải mở mã theo GPLv3.

Dự án không sao chép mã nguồn của CarBridge, CarCast hay phần mềm
thương mại khác. [carplay-cast](https://github.com/EthanArbuckle/carplay-cast) của Ethan Arbuckle
được dùng làm **tài liệu tham khảo kiến trúc**; phần phân tích nằm trong `RESEARCH.md` và toàn bộ
implementation ở đây là độc lập.
