#import <UIKit/UIKit.h>

typedef struct {
    double omega, offsetDelay, contentDelay;   // spring tới hạn cho size / trượt / nội dung
    double dotOmega, dotDelay;                 // chấm "nút gốc" co lại
    double radOmega, radDelay;                 // bo góc: viên thuốc -> bo cuối
    double blend;                              // độ dính metaball (pt)
    double dur, speed;                         // thời lượng (s), hệ số tốc độ (<1 = chậm)
    BOOL useGlass;                             // thử UIGlassEffect (iOS 26) trước khi dùng blur thường
    BOOL debug;                                // ghi log NSLog
} LGParams;

extern LGParams LGP;

/// Gọi một lần sau khi đọc plist: chặn giá trị vô nghĩa (speed<=0, omega<=0...) và tính lại `dur`
/// đủ dài để mọi spring kịp ổn định (để lúc hiện lại menu thật không bị nhảy).
void LGParamsFinalize(void);

@interface LGMenuMorph : NSObject
/// body: view thân menu (đang hiển thị), content: view chứa chữ/icon, src: khung nút nguồn (toạ độ của body.superview)
+ (void)runForBody:(UIView *)body content:(UIView *)content source:(CGRect)src done:(void (^)(void))done;
/// Kết thúc ngay morph đang chạy (nếu có): hiện lại menu thật, gỡ vỏ kính.
+ (void)cancelActive;
@end
