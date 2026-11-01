#import <UIKit/UIKit.h>

// Nút thanh điều hướng kiểu iOS 26: "Hủy" -> nút tròn dấu X; "Xong" / "Kết nối" -> nút tròn dấu ✓ (xám khi không bấm được, xanh khi bấm được).
typedef NS_ENUM(NSInteger, LGBarIconKind) { LGBarIconNone = 0, LGBarIconCancel = 1, LGBarIconDone = 2 };

/// Nhận ra loại nút theo chữ (Hủy / Cancel, Xong / Done / Kết nối / Join...). LGBarIconNone nếu không phải.
LGBarIconKind LGBarIconKindForTitle(NSString *title);

/// Ảnh nút tròn 44x44 pt, tự đổi sáng / tối theo giao diện. enabled chỉ có nghĩa với LGBarIconDone (xanh / xám).
UIImage *LGBarIconImage(LGBarIconKind kind, BOOL enabled);

/// Công tắc từng loại (từ plist).
BOOL LGBarIconWanted(LGBarIconKind kind);

/// Áp (hoặc cập nhật) ảnh cho một UIBarButtonItem theo chữ / loại đã nhớ và trạng thái enabled hiện tại.
void LGBarIconApply(UIBarButtonItem *item);

/// Đánh dấu loại nút (dùng cho nút hệ thống Done / Cancel do ta tự tạo bằng ảnh).
void LGBarIconSetKind(UIBarButtonItem *item, LGBarIconKind kind);
