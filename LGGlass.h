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

// ---- Chẩn đoán (chỉ chạy khi bật "Kiểm tra kính" = glassDebug và log đang bật) ----
// Mục đích: biết tweak Liquid (Gl)ass có thật sự sửa MTMaterialView của hộp kính trong từng app hay không.
/// Cây layer của hộp kính (class, khung, filters, backgroundFilters, compositingFilter, animation...). Tweak kính nếu có tác động thì sẽ để lại dấu ở đây.
NSString *LGGlassProbe(LMGlassHost *host);
/// Quét menu THẬT (đang có kính từ tweak) tìm view tên chứa Glass/Material/Backdrop/VisualEffect/Platter/Blur và ghi cây layer của chúng, để so với hộp kính của ta.
NSString *LGGlassScanReal(UIView *root);
/// Một lần mỗi tiến trình: IMP của các method MTMaterialView đang nằm ở dylib nào (nằm ở dylib tweak = đã bị hook),
/// và class tên Glass/Liquid/Lens do dylib ngoài hệ thống định nghĩa (= mã của tweak kính có trong tiến trình này).
void LGGlassLogEnvironment(void);
