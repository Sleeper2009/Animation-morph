#import "LGGlass.h"
#import "LGLog.h"
#import <objc/message.h>
#import <dlfcn.h>

// MTMaterialView theo đúng trình tự của BlurSearch:
//   dlopen MaterialKit -> +materialViewWithRecipe:19 configuration:1 -> nền trong suốt, không nhận chạm, giãn theo cha,
//   setRecipeDynamic:YES, setBlurEnabled:YES, setZoomEnabled:YES (mỗi hàm chỉ gọi nếu có).
static UIView *LGMakeMaterial(void) {
    @try {
        Class mt = NSClassFromString(@"MTMaterialView");
        if (!mt) {
            dlopen("/System/Library/PrivateFrameworks/MaterialKit.framework/MaterialKit", RTLD_LAZY | RTLD_LOCAL);
            mt = NSClassFromString(@"MTMaterialView");
        }
        SEL mk = NSSelectorFromString(@"materialViewWithRecipe:configuration:");
        if (!mt || ![mt isSubclassOfClass:UIView.class] || ![mt respondsToSelector:mk]) return nil;
        UIView *v = ((UIView *(*)(Class, SEL, long long, long long))objc_msgSend)(mt, mk, 19, 1);
        if (![v isKindOfClass:UIView.class]) return nil;
        v.backgroundColor = UIColor.clearColor;
        v.opaque = NO;
        v.userInteractionEnabled = NO;
        v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        for (NSString *name in @[ @"setRecipeDynamic:", @"setBlurEnabled:", @"setZoomEnabled:" ]) {
            SEL s = NSSelectorFromString(name);
            if ([v respondsToSelector:s]) ((void (*)(id, SEL, BOOL))objc_msgSend)(v, s, YES);
        }
        return v;
    } @catch (NSException *ex) {
        LGLog(@"NGOẠI LỆ khi tạo MTMaterialView: %@ %@", ex.name, ex.reason);
        return nil;
    }
}

@implementation LMGlassHost {
    UIView *_material;
}
- (UIView *)material { return _material; }

- (instancetype)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.clipsToBounds = YES;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _material = LGMakeMaterial();
    if (_material) {
        _material.frame = self.bounds;
        _material.layer.cornerCurve = kCACornerCurveContinuous;
        _material.clipsToBounds = YES;
        [self addSubview:_material];
    }
    return self;
}

- (void)setRadius:(CGFloat)r { self.layer.cornerRadius = r; }

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _material.frame = self.bounds;
    _material.layer.cornerRadius = self.layer.cornerRadius;
    [CATransaction commit];
}

// Đổi sáng / tối: MTMaterialView phải nạp lại recipe.
- (void)traitCollectionDidChange:(UITraitCollection *)prev {
    [super traitCollectionDidChange:prev];
    SEL s = NSSelectorFromString(@"setRecipeDynamic:");
    if ([_material respondsToSelector:s]) ((void (*)(id, SEL, BOOL))objc_msgSend)(_material, s, YES);
}
@end

// Hai hộp kính dùng lại cho cả tiến trình: 0 = thân menu, 1 = "chấm" (chính nút đang co lại trong lúc thân lớn ra).
static LMGlassHost *gGlass[2];
static BOOL gGlassTried[2];

LMGlassHost *LGGlassAcquire(int slot) {
    if (slot < 0 || slot > 1) return nil;
    if (!gGlassTried[slot]) {
        gGlassTried[slot] = YES;
        LMGlassHost *h = [[LMGlassHost alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
        if (h.material) gGlass[slot] = h;
        else LGLog(@"không có MTMaterialView (MaterialKit) -> không dùng được lớp kính");
    }
    [gGlass[slot] removeFromSuperview];
    return gGlass[slot];
}
