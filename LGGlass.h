#import <UIKit/UIKit.h>

// Lớp kính "Liquid Glass" cho animation: dùng MTMaterialView (private framework MaterialKit) đặt trong một view cha có TÊN LỚP RIÊNG (LMGlassHost).
// Tweak "Liquid (Gl)ass" nhận ra view cần bơm kính qua luật Custom Views:
//     Target Class   = MTMaterialView
//     Ancestor Class = LMGlassHost
// (Parent / Grandparent / Child để trống). Không cài Liquid (Gl)ass thì MTMaterialView vẫn hiện như kính mờ gốc của hệ thống.
// Cách tạo MTMaterialView (recipe 19, configuration 1, blur + zoom + recipeDynamic) học từ tweak BlurSearch (đọc mã máy của nó).
@interface LMGlassHost : UIView
@property (nonatomic, strong, readonly) UIView *material;     // nil nếu máy không có MaterialKit / MTMaterialView
/// Hình dạng của khối kính: path theo toạ độ của hộp (gốc = góc trái-trên của hộp), đặt làm mặt nạ của MTMaterialView.
/// Dùng mặt nạ thay vì cornerRadius vì hình có bốn góc bầu dục khác nhau (góc trên-phải giữ độ cong của nút).
- (void)setShapePath:(CGPathRef)path;
@end

/// Lấy hộp kính dùng lại (dựng một lần cho cả tiến trình). nil nếu không có MTMaterialView.
LMGlassHost *LGGlassAcquire(void);
