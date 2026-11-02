#import "LGKeyboard.h"
#import "LGLog.h"
#import <objc/runtime.h>
#import <objc/message.h>

// ------------------------------------------------------------------ tìm view đang nhận chữ
static __weak UIResponder *gFirst;
@interface UIResponder (LGKbFirst)
- (void)lg_kbGrabFirst:(id)sender;
@end
@implementation UIResponder (LGKbFirst)
- (void)lg_kbGrabFirst:(id)sender { gFirst = self; }
@end

static UIResponder *LGFirstResponder(void) {
    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return nil;
    gFirst = nil;
    [app sendAction:@selector(lg_kbGrabFirst:) to:nil from:nil forEvent:nil];   // to:nil -> đi dọc responder chain từ first responder
    return gFirst;
}

// ------------------------------------------------------------------ view phủ lên phím
@interface LGKbKey : UIView
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic) int look;     // -1 chưa có, 0 = xám, 1 = xanh
- (void)setLook:(int)look;
@end

static UIColor *LGDyn(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

@implementation LGKbKey
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _look = -1;
        self.userInteractionEnabled = NO;                       // không chặn chạm: phím thật bên dưới vẫn nhận
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.zPosition = 1000;
        UIImage *img = [UIImage systemImageNamed:@"arrow.turn.down.left"
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]];
        if (!img) img = [UIImage systemImageNamed:@"return"];
        _icon = [[UIImageView alloc] initWithImage:[img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
        _icon.contentMode = UIViewContentModeCenter;
        [self addSubview:_icon];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = fmin(self.bounds.size.height * 0.25, 12);
    _icon.frame = self.bounds;
}
- (void)setLook:(int)look {
    if (look == _look) return;
    BOOL first = _look < 0;
    _look = look;
    void (^apply)(void) = ^{
        if (look) {
            self.backgroundColor = [UIColor colorWithRed:0.20 green:0.47 blue:0.96 alpha:1];
            self.icon.tintColor = [UIColor colorWithRed:0.88 green:0.97 blue:1.0 alpha:1];
        } else {
            self.backgroundColor = LGDyn([UIColor colorWithRed:0.80 green:0.80 blue:0.82 alpha:1], [UIColor colorWithRed:0.28 green:0.28 blue:0.30 alpha:1]);
            self.icon.tintColor = LGDyn([UIColor colorWithWhite:1 alpha:0.95], [UIColor colorWithWhite:1 alpha:0.45]);
        }
    };
    if (first) apply();
    else [UIView transitionWithView:self duration:0.15 options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction animations:apply completion:nil];
}
@end

// ------------------------------------------------------------------ dò bàn phím
static BOOL gOn;
static NSTimer *gTimer;
static LGKbKey *gKey;
static __weak UIView *gPlane;          // view chứa các phím (UIKBKeyplaneView, hoặc chính view bàn phím nếu không tìm thấy)
static __weak UIView *gLoggedPlane;
static int gIdle, gMiss;
static CFTimeInterval gLastMissLog;

static id LGKV(id o, NSString *k) {
    if (!o) return nil;
    @try { return [o valueForKey:k]; } @catch (__unused NSException *e) { return nil; }
}

static BOOL LGViewVisible(UIView *v) {
    for (UIView *p = v; p; p = p.superview) if (p.hidden || p.alpha < 0.01) return NO;
    return v.window != nil;
}

static BOOL LGNameHas(UIView *v, const char *sub) { return strstr(object_getClassName(v), sub) != NULL; }

static UIView *LGFindPlane(UIView *v, int depth) {
    if (depth > 16) return nil;
    if (LGNameHas(v, "KeyplaneView") && LGViewVisible(v)) return v;
    for (UIView *s in v.subviews) { UIView *r = LGFindPlane(s, depth + 1); if (r) return r; }
    return nil;
}

// Bàn phím hiện tại: thử các đường private đã biết (UIKeyboard.activeKeyboard, UIKeyboardImpl.activeInstance), rồi cửa sổ bàn phím, cuối cùng (thưa hơn) mọi cửa sổ.
static UIView *LGActiveView(NSString *cls, NSString *sel) {
    Class c = NSClassFromString(cls);
    SEL s = NSSelectorFromString(sel);
    if (!c || ![c respondsToSelector:s]) return nil;
    id v = ((id (*)(id, SEL))objc_msgSend)(c, s);
    return [v isKindOfClass:UIView.class] ? v : nil;
}

static NSArray<UIView *> *LGKeyboardRoots(BOOL allWindows) {
    NSMutableArray<UIView *> *roots = [NSMutableArray new];
    UIView *kb = LGActiveView(@"UIKeyboard", @"activeKeyboard");
    if (kb) [roots addObject:kb];
    UIView *impl = LGActiveView(@"UIKeyboardImpl", @"activeInstance");
    if (impl && impl != kb) [roots addObject:impl];
    NSMutableOrderedSet<UIWindow *> *ws = [NSMutableOrderedSet new];
    UIApplication *app = [UIApplication sharedApplication];
    for (UIWindow *w in app.windows) [ws addObject:w];
    for (UIScene *sc in app.connectedScenes)
        if ([sc isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)sc).windows) [ws addObject:w];
    for (UIWindow *w in ws) {
        BOOL kbWin = LGNameHas(w, "Keyboard") || LGNameHas(w, "TextEffects") || LGNameHas(w, "InputWindow");
        if (kbWin || allWindows) [roots addObject:w];
    }
    return roots;
}

// Trả về view chứa phím + cờ "là UIKBKeyplaneView thật".
static UIView *LGKeyboardContainer(void) {
    UIView *p = gPlane;
    if (p && LGViewVisible(p)) {
        if (LGNameHas(p, "KeyplaneView")) return p;
        for (UIView *root in LGKeyboardRoots(NO)) { UIView *r = LGFindPlane(root, 0); if (r) { gPlane = r; return r; } }   // đang dùng view dự phòng: thử tìm lại keyplane thật
        return p;
    }
    gPlane = nil;
    gMiss++;
    for (int pass = 0; pass < 2; pass++) {
        if (pass == 1 && gMiss % 7 != 1) break;                      // quét mọi cửa sổ: thưa hơn (mỗi ~1 s)
        for (UIView *root in LGKeyboardRoots(pass == 1)) {
            UIView *r = LGFindPlane(root, 0);
            if (r) { gPlane = r; return r; }
        }
    }
    // không có UIKBKeyplaneView: dùng thẳng view bàn phím (UIKeyboard / UIKeyboardImpl) và tìm view phím bên trong
    UIView *kb = LGActiveView(@"UIKeyboard", @"activeKeyboard") ?: LGActiveView(@"UIKeyboardImpl", @"activeInstance");
    if (kb && LGViewVisible(kb)) { gPlane = kb; return kb; }
    return nil;
}

// Tên phím Return trong UIKBTree: "Return-Key" (các loại Search / Go / Send... dùng chung khung phím này).
static BOOL LGIsReturnName(NSString *n) {
    if (![n isKindOfClass:NSString.class]) return NO;
    NSString *l = n.lowercaseString;
    for (NSString *w in @[ @"return", @"search", @"go-", @"send", @"join", @"route", @"done", @"continue", @"enter" ])
        if ([l containsString:w]) return YES;
    return NO;
}

static BOOL LGIsReturnKey(id k) {
    NSString *name = LGKV(k, @"name"), *rep = LGKV(k, @"representedString");
    return LGIsReturnName(name) || ([rep isKindOfClass:NSString.class] && ([rep isEqualToString:@"\n"] || [rep isEqualToString:@"\r"]));
}

static void LGCollectKeys(id tree, NSMutableArray *out, int depth) {
    if (!tree || depth > 6) return;
    NSArray *ks = LGKV(tree, @"keys");
    if ([ks isKindOfClass:NSArray.class] && ks.count) { [out addObjectsFromArray:ks]; return; }
    NSArray *sub = LGKV(tree, @"subtrees");
    if ([sub isKindOfClass:NSArray.class]) for (id s in sub) LGCollectKeys(s, out, depth + 1);
}

static void LGCollectKeyViews(UIView *v, UIView *container, NSMutableArray<UIView *> *out, int depth) {
    if (depth > 10 || out.count > 200) return;
    for (UIView *s in v.subviews) {
        if (s.hidden || s.alpha < 0.01) continue;
        if (LGNameHas(s, "KeyView") && s.bounds.size.width > 15 && s.bounds.size.height > 15) { [out addObject:s]; continue; }
        LGCollectKeyViews(s, container, out, depth + 1);
    }
}

static BOOL LGBetter(CGRect r, CGRect best) {    // phím nằm sát phải / sát đáy hơn
    if (CGRectIsNull(best)) return YES;
    if (CGRectGetMaxX(r) > CGRectGetMaxX(best) + 1) return YES;
    return fabs(CGRectGetMaxX(r) - CGRectGetMaxX(best)) <= 1 && CGRectGetMaxY(r) > CGRectGetMaxY(best);
}

static void LGLogMiss(UIView *c, NSString *why) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - gLastMissLog < 8) return;
    gLastMissLog = now;
    LGLog(@"nút bàn phím: KHÔNG tìm được phím Return (%@) container=%s", why, c ? object_getClassName(c) : "nil");
    if (c) LGLogTree(@"bàn phím: cây view (không thấy phím Return)", c);
}

static CGRect LGReturnKeyRect(UIView *plane) {
    id kp = LGKV(plane, @"keyplane");
    NSMutableArray *keys = [NSMutableArray new];
    LGCollectKeys(kp, keys, 0);
    NSMutableArray<UIView *> *kviews = [NSMutableArray new];
    LGCollectKeyViews(plane, plane, kviews, 0);
    if (LGLogOn && gLoggedPlane != plane) {
        gLoggedPlane = plane;
        NSMutableString *s = [NSMutableString stringWithFormat:@"container=%s bounds=%@ keyplane=%@ phím(tree)=%lu view phím=%lu\n", object_getClassName(plane),
                              NSStringFromCGRect(plane.bounds), kp ? NSStringFromClass([kp class]) : @"nil", (unsigned long)keys.count, (unsigned long)kviews.count];
        for (id k in keys) {
            NSValue *fv = LGKV(k, @"frame");
            NSValue *pv = LGKV(k, @"paddedFrame");
            [s appendFormat:@"  tree name=%@ rep=%@ disp=%@ type=%@ state=%@ frame=%@ padded=%@\n", LGKV(k, @"name"), LGKV(k, @"representedString"), LGKV(k, @"displayString"),
             LGKV(k, @"displayType"), LGKV(k, @"state"), fv ? NSStringFromCGRect(fv.CGRectValue) : @"?", pv ? NSStringFromCGRect(pv.CGRectValue) : @"?"];
        }
        for (UIView *v in kviews)
            [s appendFormat:@"  view %s key=%@ frame=%@\n", object_getClassName(v), LGKV(v, @"key") ? LGKV(LGKV(v, @"key"), @"name") : @"?", NSStringFromCGRect([v convertRect:v.bounds toView:plane])];
        LGLogBlock(@"bàn phím (nút phím Return)", s);
        LGLogTree(@"bàn phím: cây view", plane);
    }
    CGRect best = CGRectNull;
    // 1) UIKBTree: phím có tên Return
    for (id k in keys) {
        if (!LGIsReturnKey(k)) continue;
        NSValue *fv = LGKV(k, @"frame");
        if (![fv isKindOfClass:NSValue.class]) continue;
        CGRect r = fv.CGRectValue;
        if (r.size.width < 20 || r.size.height < 20 || !CGRectIntersectsRect(plane.bounds, r)) continue;
        if (LGBetter(r, best)) best = r;
    }
    if (!CGRectIsNull(best)) return best;
    // 2) view phím (UIKBKeyView) có key tên Return
    for (UIView *v in kviews) {
        id k = LGKV(v, @"key");
        if (!k || !LGIsReturnKey(k)) continue;
        CGRect r = [v convertRect:v.bounds toView:plane];
        if (LGBetter(r, best)) best = r;
    }
    if (!CGRectIsNull(best)) return best;
    // 3) hình học: phím nằm sát góc dưới phải nhất (cách làm của các tweak đổi màu phím Done)
    if (kviews.count >= 6) {
        for (UIView *v in kviews) {
            CGRect r = [v convertRect:v.bounds toView:plane];
            if (LGBetter(r, best)) best = r;
        }
        if (!CGRectIsNull(best)) return best;
    }
    LGLogMiss(plane, [NSString stringWithFormat:@"tree=%lu view=%lu", (unsigned long)keys.count, (unsigned long)kviews.count]);
    return CGRectNull;
}

static void LGRemoveKey(void) {
    if (gKey) { [gKey removeFromSuperview]; gKey = nil; }
}

static void LGTick(void) {
    if (!gOn) return;
    @try {
        UIResponder *r = LGFirstResponder();
        UIView *plane = r ? LGKeyboardContainer() : nil;
        if (!plane) {
            LGRemoveKey();
            if (!r) { if (++gIdle > 25) { [gTimer invalidate]; gTimer = nil; } }      // không có ô nhập: dừng timer sau ~4 s (bàn phím hiện lại sẽ bật lại)
            else if (++gIdle % 40 == 3) LGLog(@"nút bàn phím: có ô nhập (%@) nhưng chưa thấy view bàn phím", NSStringFromClass(r.class));
            return;
        }
        gIdle = 0;
        // đổi mọi phím Return, trừ phím Gọi khẩn cấp
        BOOL want = NO, en = YES;
        UIReturnKeyType rk = UIReturnKeyDefault;
        if ([r conformsToProtocol:@protocol(UITextInputTraits)]) {
            id<UITextInputTraits> t = (id<UITextInputTraits>)r;
            rk = [t respondsToSelector:@selector(returnKeyType)] ? t.returnKeyType : UIReturnKeyDefault;
            want = rk != UIReturnKeyEmergencyCall;      // mọi phím Return (Tìm / Đi / Gửi / Xong và cả "nhập" / "Tiếp" thường) -> nút xanh ↩
            if ([t respondsToSelector:@selector(enablesReturnKeyAutomatically)] && t.enablesReturnKeyAutomatically && [r conformsToProtocol:@protocol(UIKeyInput)])
                en = ((id<UIKeyInput>)r).hasText;
        }
        static UIReturnKeyType lastRk = -1; static BOOL lastWant = NO; static __weak UIResponder *lastR;
        if (lastR != r || lastRk != rk || lastWant != want) {
            lastR = r; lastRk = rk; lastWant = want;
            LGLog(@"nút bàn phím: ô nhập %@ returnKeyType=%ld đổi=%d bấm được=%d", NSStringFromClass(r.class), (long)rk, want, en);
        }
        CGRect rect = want ? LGReturnKeyRect(plane) : CGRectNull;
        if (!want || CGRectIsNull(rect)) { LGRemoveKey(); return; }
        if (!gKey) gKey = [[LGKbKey alloc] initWithFrame:rect];
        if (gKey.superview != plane) [plane addSubview:gKey];
        else if (plane.subviews.lastObject != gKey) [plane bringSubviewToFront:gKey];
        if (!CGRectEqualToRect(gKey.frame, rect)) { gKey.frame = rect; LGLog(@"nút bàn phím: phủ lên khung %@ (container %s %@)", NSStringFromCGRect(rect), object_getClassName(plane), NSStringFromCGRect(plane.bounds)); }
        [gKey setLook:en ? 1 : 0];
    } @catch (NSException *ex) {
        LGLog(@"NGOẠI LỆ nút bàn phím: %@ %@", ex.name, ex.reason);
    }
}

static void LGStartTimer(void) {
    if (!gOn || gTimer) return;
    gIdle = 0;
    gTimer = [NSTimer timerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *t) { LGTick(); }];
    [NSRunLoop.mainRunLoop addTimer:gTimer forMode:NSRunLoopCommonModes];
}

void LGKeyboardSetEnabled(BOOL on) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ LGKeyboardSetEnabled(on); }); return; }
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        void (^show)(NSNotification *) = ^(NSNotification *n) { LGStartTimer(); };
        [nc addObserverForName:UIKeyboardWillShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:show];
        [nc addObserverForName:UIKeyboardDidShowNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:show];
        [nc addObserverForName:UIKeyboardDidHideNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            LGRemoveKey(); [gTimer invalidate]; gTimer = nil;
        }];
    });
    gOn = on;
    if (on) { LGStartTimer(); LGTick(); }       // có thể bàn phím đang hiện sẵn khi vừa bật trong Cài đặt
    else { LGRemoveKey(); [gTimer invalidate]; gTimer = nil; }
}
