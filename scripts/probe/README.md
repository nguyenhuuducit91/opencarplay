# Frida probes — thu thập bằng chứng runtime iOS 18.6.2

Trả lời các câu hỏi Q1–Q12 trong [`../../RESEARCH.md`](../../RESEARCH.md) §7.4.
**Tất cả script chỉ đọc/trace. Không script nào thay đổi hành vi hệ thống.**

## Chuẩn bị

Trên thiết bị (Sileo): `frida` từ repo `https://build.frida.re`.
Trên máy build: `pipx install frida-tools` (hoặc `pip install --user frida-tools`).

```bash
iproxy 2222 22 &          # nếu dùng USB
frida-ps -U | head        # kiểm tra kết nối
```

## Thứ tự chạy

| Script | Process | Khi nào | Trả lời |
|---|---|---|---|
| `01-classes.js` | SpringBoard **và** CarPlay | bất kỳ lúc nào | Q2, Q3, Q5, Q6, Q10 |
| `03-display.js` | SpringBoard | **đang cắm CarPlay** | Q7 |
| `04-notifications.js` | SpringBoard | cắm rồi rút trong lúc chạy | Q8, Q10 |
| `02-carplay-policy.js` | CarPlay | đang cắm, mở dashboard | Q1, Q4 |

```bash
frida -U -n SpringBoard -l 01-classes.js -q  > ../../out-sb-classes.txt
frida -U -n CarPlay     -l 01-classes.js -q  > ../../out-cp-classes.txt
frida -U -n SpringBoard -l 03-display.js -q  > ../../out-display.txt
frida -U -n SpringBoard -l 04-notifications.js   # Ctrl-C sau khi rút dây
frida -U -n CarPlay     -l 02-carplay-policy.js  # Ctrl-C sau khi mở dashboard
```

Gửi lại 5 file output — chúng là đầu vào bắt buộc cho Phase 7 và Phase 9.
