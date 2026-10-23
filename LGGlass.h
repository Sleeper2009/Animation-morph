#import <UIKit/UIKit.h>

// Lớp kính "Liquid Glass" cho animation: dùng MTMaterialView (private framework MaterialKit) đặt trong một view cha có TÊN LỚP RIÊNG (LMGlassHost).
// Tweak "Liquid (Gl)ass" nhận ra view cần bơm kính qua luật Custom Views:
//     Target Class   = MTMaterialView
//     Ancestor Class = LMGlassHost
// (Parent / Grandparent / Child để trống). Không cài Liquid (Gl)ass thì MTMaterialView vẫn hiện như kính mờ gốc của hệ thống.
// Cách tạo MTMaterialView (recipe 19, configuration 1, blur + zoom + recipeDynamic) học từ tweak BlurSearch (đọc mã máy của nó).
@interface LMGlassHost : UIView
@property (nonatomic, strong, readonly) UIView *material;     // nil nếu máy không có MaterialKit / MTMaterialView
/// Bo góc của hộp kính (cắt theo kiểu continuous như thẻ iOS).
- (void)setRadius:(CGFloat)r;
@end

/// Chuỗi tên class từ view lên tới cửa sổ (để ghi log: luật Ancestor Class của Liquid (Gl)ass khớp theo chuỗi này).
NSString *LGGlassChain(UIView *v);

/// Lấy hộp kính dùng lại (dựng một lần cho cả tiến trình). nil nếu không có MTMaterialView.
LMGlassHost *LGGlassAcquire(void);
