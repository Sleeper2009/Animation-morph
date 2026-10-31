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

int LGGlassMaskMode = 0;

// Một "mặt nạ hợp hình": lớp gốc + các lớp CAShapeLayer con (mỗi hình một lớp, vùng nhìn thấy = hợp các hình).
@interface LGMaskSet : NSObject
@property (nonatomic, strong) CALayer *root;
@property (nonatomic, strong) NSMutableArray<CAShapeLayer *> *parts;
@end
@implementation LGMaskSet
- (instancetype)init { if ((self = [super init])) { _root = [CALayer layer]; _parts = [NSMutableArray new]; } return self; }
- (void)applyPaths:(NSArray *)paths bounds:(CGRect)b {
    _root.frame = b;
    while (_parts.count < paths.count) {
        CAShapeLayer *l = [CAShapeLayer layer];
        l.fillColor = UIColor.blackColor.CGColor;
        [_root addSublayer:l];
        [_parts addObject:l];
    }
    for (NSUInteger i = 0; i < _parts.count; i++) {
        _parts[i].frame = _root.bounds;
        _parts[i].path = i < paths.count ? (__bridge CGPathRef)paths[i] : NULL;
    }
}
@end

@implementation LMGlassHost {
    UIView *_material;
    LGMaskSet *_hostMask;       // mặt nạ đặt trên CHÍNH hộp (cắt mọi thứ nằm trong hộp, kể cả lớp kính do tweak Liquid (Gl)ass thêm vào)
    LGMaskSet *_matMask;        // mặt nạ đặt trên MTMaterialView
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
    if (!path) return;
    [self setShapePaths:@[ (__bridge id)path ] cornerRadius:0];
}

- (void)setShapePaths:(NSArray *)paths { [self setShapePaths:paths cornerRadius:0]; }

// Chế độ mặt nạ (LGGlassMaskMode): 0 = cả hộp lẫn MTMaterialView (mặc định), 1 = chỉ MTMaterialView, 2 = chỉ hộp.
// Lý do có cả hai: tweak Liquid (Gl)ass thay / thêm lớp kính riêng, mặt nạ chỉ đặt trên MTMaterialView không cắt được nó -> kính hiện thành
// HÌNH CHỮ NHẬT góc vuông; mặt nạ trên hộp cắt mọi thứ bên trong. cornerRadius = bo góc nhỏ nhất của khối (>0): đặt làm cornerRadius của lớp
// MTMaterialView để tweak kính nào đọc cornerRadius của view cũng ra đúng độ cong (nhỏ nhất nên không cắt mất phần mặt nạ cho phép).
- (void)setShapePaths:(NSArray *)paths cornerRadius:(CGFloat)cr {
    if (!_material) return;
    int mode = LGGlassMaskMode;
    BOOL onHost = mode != 1, onMat = mode != 2;
    if (onHost && !_hostMask) { _hostMask = [LGMaskSet new]; self.layer.mask = _hostMask.root; }
    if (onMat && !_matMask) { _matMask = [LGMaskSet new]; _material.layer.mask = _matMask.root; }
    if (!onHost && _hostMask) { self.layer.mask = nil; _hostMask = nil; }
    if (!onMat && _matMask) { _material.layer.mask = nil; _matMask = nil; }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_hostMask applyPaths:paths bounds:self.bounds];
    [_matMask applyPaths:paths bounds:_material.bounds];
    _material.layer.cornerRadius = cr > 0 ? cr : 0;
    if (@available(iOS 13.0, *)) _material.layer.cornerCurve = kCACornerCurveContinuous;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _material.frame = self.bounds;
    _hostMask.root.frame = self.bounds;
    _matMask.root.frame = _material.bounds;
    for (CAShapeLayer *l in _hostMask.parts) l.frame = _hostMask.root.bounds;
    for (CAShapeLayer *l in _matMask.parts) l.frame = _matMask.root.bounds;
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
