#import <UIKit/UIKit.h>

// Tham số animation (đọc từ plist trong %ctor). Timeline mở / đóng cố định theo bản mẫu "Menu Liquid Glass" (xem LGTimeline.h).
typedef struct {
    double closeDur;                            // thời gian đóng (s); mặc định 0,545 = đúng bảng khung đo của bản mẫu
    double speed;                               // hệ số tốc độ chung (1 = bản gốc)
    double tint, shadow, rim;                   // độ đậm lớp phủ màu / bóng / viền (0..1)
    int material;                               // -1 = chép hiệu ứng nền của menu thật; 0..4 = UltraThin..Chrome
    BOOL useGlass, debug, coverButton, hideSource, groupButtons, blurText, closeAnim, dump;
    double pressScale, pressOmega, pressZeta;   // ấn nút: phóng to tới (lần) / tần số góc / giảm chấn
    double ringMargin, ringPadX;                // vòng: cách mép cửa sổ tối thiểu (pt) / đệm hai bên chữ (pt)
    double pressFlash, pressHold;               // ấn nút: độ sáng lóe (1 = như video) / thời gian giữ tối thiểu trước khi menu morph (s)
    BOOL press;                                 // (suy ra) có ít nhất một trong hai hiệu ứng ấn
    BOOL pressFlashOn, pressZoomOn;             // lóe sáng khi ấn / phóng to khi ấn (bật tắt độc lập)
    BOOL ring, ringAll;                         // vòng tròn cố định quanh nút mở menu / quanh mọi UIButton nhỏ
    BOOL ringBack;                              // vòng quanh nút "quay lại" (thanh điều hướng)
    BOOL fallbackAnim;                          // menu không morph được -> chạy animation đơn giản thay vì hiện cái bụp
    double groupGap;                            // gộp các nút thành một viên thuốc khi khoảng hở giữa phần NHÌN THẤY <= giá trị này (pt)
    BOOL glass;                                 // kính Liquid Glass (MTMaterialView + tweak Liquid (Gl)ass) thay cho lớp blur
    int overlayMode;                            // 0 = tự chọn (extension -> view trong cửa sổ), 1 = UIWindow riêng, 2 = view trong cửa sổ
} LGParams;

extern LGParams LGP;
void LGParamsFinalize(void);

/// Một "phiên" animation cho mỗi menu: mở (lò xo từ nút) -> menu thật -> đóng (bảng khung đo).
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

/// App vừa present một view controller (vd bảng chọn tệp). Nếu ngay trước đó người dùng chạm vào một mục trong menu thì bỏ animation đóng
/// (menu thật còn nằm đó trong lúc bảng trượt lên, animation đóng chạy muộn trông rất buồn cười).
+ (void)modalPresented;

@end
