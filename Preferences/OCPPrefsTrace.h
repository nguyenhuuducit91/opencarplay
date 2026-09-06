// OpenCarPlay — dấu vết từng bước khi Settings nạp bảng cài đặt.
//
// VÌ SAO CẦN
//
// Bảng cài đặt làm Settings crash và ba lần chẩn đoán liên tiếp đều sai vì dựa trên
// suy luận từ code. File này bỏ hẳn lối đó: mỗi bước trên đường nạp ghi đúng một dòng,
// nên "nó chết ở đâu" trở thành thứ ĐỌC ĐƯỢC thay vì thứ phải đoán.
//
// Ghi bằng cả hai đường, vì mỗi đường có một điểm mù:
//   • syslog() — hiện trong `idevicesyslog` qua cáp USB, không cần quyền ghi file nào.
//     Đây là đường chính: Settings bị sandbox và có thể không ghi được file.
//   • file — đọc lại được bất cứ lúc nào sau khi crash, không cần bắt đúng thời điểm.
//
// C thuần, không Objective-C, không block: xem mục "Giới hạn của toolchain Linux"
// trong README.
//
// Copyright (C) 2026 OpenCarPlay contributors — GPLv3.

#ifndef OCP_PREFS_TRACE_H
#define OCP_PREFS_TRACE_H

/// Ghi một mốc. `detail` có thể là NULL.
void OCPPrefsTrace(const char *step, const char *detail);

/// Xoá dấu vết cũ để lần mở bảng này bắt đầu từ trang trắng.
void OCPPrefsTraceReset(void);

#endif /* OCP_PREFS_TRACE_H */
