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

// ------------------------------------------------------------------ chẩn đoán
static NSString *LGImageOfIMP(IMP imp) {
    Dl_info di;
    if (imp && dladdr((const void *)imp, &di) && di.dli_fname) {
        const char *b = strrchr(di.dli_fname, '/');
        return [NSString stringWithUTF8String:b ? b + 1 : di.dli_fname];
    }
    return @"?";
}

static NSString *LGShort(id o, NSUInteger n) {
    NSString *s = o ? [NSString stringWithFormat:@"%@", o] : @"nil";
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return s.length > n ? [[s substringToIndex:n] stringByAppendingString:@"…"] : s;
}

// filters / backgroundFilters / compositingFilter đọc bằng KVC (không phụ thuộc việc SDK có khai báo trên iOS hay không)
static id LGKV(CALayer *l, NSString *key) {
    @try { return [l valueForKey:key]; } @catch (NSException *ex) { return nil; }
}

static BOOL LGNonEmpty(id o) {
    if (!o) return NO;
    if ([o isKindOfClass:NSArray.class]) return ((NSArray *)o).count > 0;
    return YES;
}

static void LGLayerNode(CALayer *l, int depth, int maxDepth, NSMutableString *out, int *count) {
    if (!l || depth > maxDepth || *count >= 80) return;
    (*count)++;
    NSMutableString *line = [NSMutableString string];
    for (int i = 0; i < depth; i++) [line appendString:@"  "];
    [line appendFormat:@"%s", object_getClassName(l)];
    id d = (id)l.delegate;
    if (d && [d isKindOfClass:UIView.class]) [line appendFormat:@" (view %s)", object_getClassName(d)];
    [line appendFormat:@" frame=%@", NSStringFromCGRect(l.frame)];
    if (l.hidden) [line appendString:@" HIDDEN"];
    if (l.opacity < 0.999f) [line appendFormat:@" op=%.2f", (double)l.opacity];
    if (l.cornerRadius > 0.5) [line appendFormat:@" rad=%.1f", (double)l.cornerRadius];
    if (l.mask) [line appendString:@" mask"];
    if (l.contents) [line appendString:@" contents"];
    id f = LGKV(l, @"filters"), bf = LGKV(l, @"backgroundFilters"), cf = LGKV(l, @"compositingFilter");
    if (LGNonEmpty(f)) [line appendFormat:@" filters=%@", LGShort(f, 200)];
    if (LGNonEmpty(bf)) [line appendFormat:@" backgroundFilters=%@", LGShort(bf, 200)];
    if (LGNonEmpty(cf)) [line appendFormat:@" compositingFilter=%@", LGShort(cf, 80)];
    NSArray<NSString *> *ak = l.animationKeys;
    if (ak.count) [line appendFormat:@" anim=%@", [ak componentsJoinedByString:@","]];
    [line appendString:@"\n"];
    [out appendString:line];
    for (CALayer *s in l.sublayers) LGLayerNode(s, depth + 1, maxDepth, out, count);
}

NSString *LGGlassProbe(LMGlassHost *host) {
    if (!host) return @"(không có hộp kính)";
    NSMutableString *out = [NSMutableString string];
    UIView *m = host.material;
    [out appendFormat:@"host=%s frame=%@ hidden=%d alpha=%.2f window=%s level=%.0f\n", object_getClassName(host), NSStringFromCGRect(host.frame),
                      (int)host.hidden, (double)host.alpha, host.window ? object_getClassName(host.window) : "(nil)",
                      host.window ? (double)host.window.windowLevel : 0.0];
    [out appendFormat:@"chuỗi view của material: %@\n", m ? LGGlassChain(m) : @"(nil)"];
    if (m) [out appendFormat:@"material=%s frame=%@ hidden=%d subviews=%lu layer.sublayers=%lu\n", object_getClassName(m), NSStringFromCGRect(m.frame),
                             (int)m.hidden, (unsigned long)m.subviews.count, (unsigned long)m.layer.sublayers.count];
    int cnt = 0;
    LGLayerNode(host.layer, 0, 6, out, &cnt);
    if (cnt >= 80) [out appendString:@"… (cắt ở 80 layer)\n"];
    return out;
}

static void LGScanReal(UIView *v, int depth, NSMutableString *out, int *shown, int *visited) {
    if (!v || depth > 14 || *visited > 600 || *shown >= 10) return;
    (*visited)++;
    const char *cn = object_getClassName(v);
    BOOL hit = strcasestr(cn, "Glass") || strcasestr(cn, "Material") || strcasestr(cn, "Backdrop") ||
               strcasestr(cn, "VisualEffect") || strcasestr(cn, "Platter") || strcasestr(cn, "Blur");
    if (hit) {
        (*shown)++;
        [out appendFormat:@"[%d] view %s  chuỗi: %@\n", *shown, cn, LGGlassChain(v)];
        int cnt = 0;
        LGLayerNode(v.layer, 1, 4, out, &cnt);
    }
    for (UIView *s in v.subviews) LGScanReal(s, depth + 1, out, shown, visited);
}

NSString *LGGlassScanReal(UIView *root) {
    if (!root) return @"(không có menu)";
    NSMutableString *out = [NSMutableString string];
    int shown = 0, visited = 0;
    LGScanReal(root, 0, out, &shown, &visited);
    if (!shown) [out appendFormat:@"(không có view nào tên Glass/Material/Backdrop/VisualEffect/Platter/Blur trong %d view đã quét)\n", visited];
    return out;
}

void LGGlassLogEnvironment(void) {
    // 1) IMP của MTMaterialView: còn nằm trong MaterialKit/UIKitCore = chưa bị hook; nằm trong dylib khác = tweak đã hook method đó
    Class mt = NSClassFromString(@"MTMaterialView");
    if (mt) {
        NSArray<NSString *> *sels = @[ @"initWithFrame:", @"willMoveToWindow:", @"didMoveToWindow", @"didMoveToSuperview", @"layoutSubviews",
                                       @"setFrame:", @"setBounds:", @"setHidden:", @"setAlpha:", @"addSubview:", @"insertSubview:atIndex:",
                                       @"traitCollectionDidChange:" ];
        NSMutableString *s = [NSMutableString string];
        for (NSString *n in sels) {
            Method m = class_getInstanceMethod(mt, NSSelectorFromString(n));
            [s appendFormat:@"%@=%@  ", n, m ? LGImageOfIMP(method_getImplementation(m)) : @"-"];
        }
        LGLog(@"kính: IMP của MTMaterialView -> dylib: %@", s);
    } else {
        LGLog(@"kính: không có class MTMaterialView trong tiến trình");
    }
    // 2) class tên Glass / Liquid / Lens do dylib ngoài hệ thống định nghĩa: có = mã của tweak kính đang nằm trong tiến trình này
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        unsigned int n = 0;
        Class *list = objc_copyClassList(&n);
        if (!list) return;
        NSMutableString *out = [NSMutableString stringWithFormat:@"%u class trong tiến trình. Class tên Glass/Liquid/Lens ngoài LG*/LM* và ngoài /System, /usr/lib (kèm dylib định nghĩa):\n", n];
        int shown = 0;
        for (unsigned int i = 0; i < n && shown < 60; i++) {
            const char *cn = class_getName(list[i]);
            if (!cn || !strncmp(cn, "LG", 2) || !strncmp(cn, "LM", 2)) continue;
            if (!strcasestr(cn, "glass") && !strcasestr(cn, "liquid") && !strcasestr(cn, "lens")) continue;
            const char *img = class_getImageName(list[i]);
            if (img && (!strncmp(img, "/System/", 8) || !strncmp(img, "/usr/lib/", 9))) continue;
            const char *b = img ? strrchr(img, '/') : NULL;
            [out appendFormat:@"  %s  <- %s\n", cn, img ? (b ? b + 1 : img) : "?"];
            shown++;
        }
        free(list);
        if (!shown) [out appendString:@"  (không có)\n"];
        LGLogBlock(@"kính: class của tweak kính", out);
    });
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
    static BOOL envLogged;
    if (!envLogged && gGlass && LGP.glassDebug) { envLogged = YES; LGGlassLogEnvironment(); }
    return gGlass;
}
