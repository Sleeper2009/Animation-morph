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
    CAShapeLayer *_mask;
}
- (UIView *)material { return _material; }

- (instancetype)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.clipsToBounds = YES;
    _material = LGMakeMaterial();
    if (_material) {
        _material.frame = self.bounds;
        _material.clipsToBounds = YES;
        [self addSubview:_material];
    }
    return self;
}

- (void)setShapePath:(CGPathRef)path {
    if (!_material) return;
    if (!_mask) {
        _mask = [CAShapeLayer layer];
        _mask.fillColor = UIColor.blackColor.CGColor;
        _material.layer.mask = _mask;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _mask.frame = self.bounds;
    _mask.path = path;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _material.frame = self.bounds;
    _mask.frame = self.bounds;
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

LMGlassHost *LGGlassAcquire(void) {
    if (!gGlassTried) {
        gGlassTried = YES;
        LMGlassHost *h = [[LMGlassHost alloc] initWithFrame:CGRectMake(0, 0, 100, 100)];
        if (h.material) gGlass = h;
        else LGLog(@"không có MTMaterialView (MaterialKit) -> không dùng được lớp kính");
    }
    [gGlass removeFromSuperview];
    return gGlass;
}
