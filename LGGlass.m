#import "LGGlass.h"
#import "LGLog.h"
#import "LGMenuMorph.h"
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <string.h>

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

static LMGlassHost *gGlass;
static BOOL gGlassTried;

NSString *LGGlassChain(UIView *v) {
    NSMutableArray<NSString *> *a = [NSMutableArray new];
    for (UIView *c = v; c && a.count < 12; c = c.superview) [a addObject:[NSString stringWithUTF8String:object_getClassName(c)]];
    return [a componentsJoinedByString:@" < "];
}

// Ghi log danh sách tweak (dylib trong DynamicLibraries) đang được nạp trong tiến trình này: để biết tweak Liquid (Gl)ass
// có đang chạy trong app này không (luật chỉ có tác dụng ở tiến trình mà tweak kính được nạp).
static void LGLogInjectedTweaks(void) {
    NSMutableArray<NSString *> *names = [NSMutableArray new];
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *p = _dyld_get_image_name(i);
        if (p && (strstr(p, "DynamicLibraries") || strstr(p, "TweakInject"))) {
            const char *b = strrchr(p, '/');
            [names addObject:[NSString stringWithUTF8String:b ? b + 1 : p]];
        }
    }
    LGLog(@"tweak đang nạp trong tiến trình này (%lu): %@", (unsigned long)names.count, [names componentsJoinedByString:@", "]);
}

LMGlassHost *LGGlassAcquire(void) {
    if (!gGlassTried) {
        gGlassTried = YES;
        LMGlassHost *h = [[LMGlassHost alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
        if (h.material) gGlass = h;
        else LGLog(@"không có MTMaterialView (MaterialKit) -> không dùng được lớp kính");
    }
    [gGlass removeFromSuperview];
    // chế độ kiểm tra: viền đỏ quanh hộp kính (thấy viền = hộp kính có hiện đúng chỗ; không thấy kính = lỗi nằm ở phía luật / tweak Liquid (Gl)ass)
    gGlass.layer.borderWidth = LGP.glassDebug ? 3 : 0;
    gGlass.layer.borderColor = UIColor.redColor.CGColor;
    static BOOL logged;
    if (!logged && gGlass) { logged = YES; LGLogInjectedTweaks(); }
    return gGlass;
}
