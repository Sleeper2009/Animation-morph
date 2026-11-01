#import <UIKit/UIKit.h>

// Nút phím Search / Go / Send / Join... của bàn phím iPhone kiểu iOS 26: nền xanh bo góc + mũi tên ↩ (xám khi nút bị mờ, chưa bấm được).
// Cách làm: một view phủ lên đúng ô phím Return của bàn phím (không chặn chạm), tự bám theo bàn phím bằng timer chỉ chạy khi có bàn phím.

/// Bật / tắt tính năng (gọi trên main thread, mỗi lần đọc lại cài đặt).
void LGKeyboardSetEnabled(BOOL on);
