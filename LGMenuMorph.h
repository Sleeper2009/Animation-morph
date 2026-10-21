#import <UIKit/UIKit.h>

// Tham số animation (đọc từ plist trong %ctor, có mặc định = đúng bản Flutter mẫu).
typedef struct {
    double omega, offsetDelay, contentDelay;    // thân menu: kích thước / trượt về góc nút / nội dung
    double dotOmega, dotDelay;                  // chấm "nút gốc" co lại
    double radOmega, radDelay;                  // bo góc 150 -> bo cuối
    double blend;                               // độ dính metaball (pt)
    double dur;                                 // tổng thời gian mở (s) - tính trong LGParamsFinalize
    double closeDur;                            // thời gian đóng (s): timeline mở chạy ngược
    double speed;                               // hệ số tốc độ chung (1 = bản gốc)
    double tint, shadow, rim;                   // độ đậm lớp phủ màu / bóng / viền (0..1)
    int material;                               // -1 = chép hiệu ứng nền của menu thật; 0..4 = UltraThin..Chrome
    double bounceAmp, bounceOmega, bounceZeta;  // nảy khi đóng: biên độ (pt) / tần số góc (rad/s) / giảm chấn (0..1, nhỏ = nảy nhiều)
    BOOL useGlass, debug, coverButton, hideSource, groupButtons, blurText, closeAnim, dump;
    double pressScale, pressOmega, pressZeta;   // ấn nút: phóng to tới (lần) / tần số góc / giảm chấn
    double ringMargin, ringPadX;                // vòng: cách mép cửa sổ tối thiểu (pt) / đệm hai bên chữ (pt)
    double pressFlash, pressHold;               // ấn nút: độ sáng lóe (1 = như video) / thời gian giữ tối thiểu trước khi menu morph (s)
    BOOL bounce;                                // bật nảy chéo khi đóng
    BOOL press;                                 // bật lóe sáng + phóng to khi ấn nút
    BOOL ring, ringAll;                         // vòng tròn cố định quanh nút mở menu / quanh mọi UIButton nhỏ
} LGParams;

extern LGParams LGP;
void LGParamsFinalize(void);

/// Một "phiên" animation cho mỗi menu: mở (morph) -> menu thật -> đóng (ngược lại).
/// Tất cả phải gọi từ main thread.
@interface LGMenuMorph : NSObject

/// Có phiên đang chạy (mở / đang mở / đang đóng) không.
+ (BOOL)isActive;
/// View container của menu mà phiên hiện tại đang quản (nil nếu không có).
+ (UIView *)activeContainer;

/// Bắt đầu phiên cho menu vừa xuất hiện.
/// sources: các nút (1 nút, hoặc nhóm nút liền nhau -> thành 1 viên thuốc) sinh ra menu.
/// rect: ô dự phòng (toạ độ window) nếu khung các nút không dùng được.
+ (void)beginWithContainer:(UIView *)container body:(UIView *)body sources:(NSArray<UIView *> *)sources fallbackRect:(CGRect)rect;

/// Mọi UITouch đi qua UIApplication sendEvent: đều được chuyển vào đây (chạm ngoài menu -> đóng).
+ (void)touch:(UITouch *)t;

/// Dừng ngay, trả lại mọi thứ về nguyên trạng (không animation).
+ (void)cancelAll;

@end
