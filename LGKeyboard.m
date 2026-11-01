#import "LGKeyboard.h"
#import "LGLog.h"
#import <objc/runtime.h>

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
static __weak UIView *gPlane;
static __weak UIView *gLoggedPlane;
static int gIdle;

static id LGKV(id o, NSString *k) {
    if (!o) return nil;
    @try { return [o valueForKey:k]; } @catch (__unused NSException *e) { return nil; }
}

static BOOL LGViewVisible(UIView *v) {
    for (UIView *p = v; p; p = p.superview) if (p.hidden || p.alpha < 0.01) return NO;
    return v.window != nil;
}

static UIView *LGFindPlane(UIView *v, int depth) {
    if (depth > 14) return nil;
    if (strcmp(object_getClassName(v), "UIKBKeyplaneView") == 0 && LGViewVisible(v)) return v;
    for (UIView *s in v.subviews) { UIView *r = LGFindPlane(s, depth + 1); if (r) return r; }
    return nil;
}

static UIView *LGKeyboardPlane(void) {
    UIView *p = gPlane;
    if (p && LGViewVisible(p)) return p;
    gPlane = nil;
    NSMutableOrderedSet<UIWindow *> *ws = [NSMutableOrderedSet new];
    UIApplication *app = [UIApplication sharedApplication];
    for (UIWindow *w in app.windows) [ws addObject:w];
    for (UIScene *sc in app.connectedScenes)
        if ([sc isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)sc).windows) [ws addObject:w];
    for (UIWindow *w in ws) {
        const char *n = object_getClassName(w);
        if (!strstr(n, "Keyboard") && !strstr(n, "TextEffects") && !strstr(n, "InputWindow")) continue;
        UIView *r = LGFindPlane(w, 0);
        if (r) { gPlane = r; return r; }
    }
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

static void LGCollectKeys(id tree, NSMutableArray *out, int depth) {
    if (!tree || depth > 6) return;
    NSArray *ks = LGKV(tree, @"keys");
    if ([ks isKindOfClass:NSArray.class] && ks.count) { [out addObjectsFromArray:ks]; return; }
    NSArray *sub = LGKV(tree, @"subtrees");
    if ([sub isKindOfClass:NSArray.class]) for (id s in sub) LGCollectKeys(s, out, depth + 1);
}

static CGRect LGReturnKeyRect(UIView *plane) {
    id kp = LGKV(plane, @"keyplane");
    NSMutableArray *keys = [NSMutableArray new];
    LGCollectKeys(kp, keys, 0);
    if (LGLogOn && gLoggedPlane != plane) {
        gLoggedPlane = plane;
        NSMutableString *s = [NSMutableString stringWithFormat:@"keyplane=%@ plane=%@ bounds=%@ số phím=%lu\n", kp ? NSStringFromClass([kp class]) : @"nil",
                              NSStringFromClass(plane.class), NSStringFromCGRect(plane.bounds), (unsigned long)keys.count];
        for (id k in keys) {
            NSValue *fv = LGKV(k, @"frame");
            [s appendFormat:@"  name=%@ rep=%@ frame=%@\n", LGKV(k, @"name"), LGKV(k, @"representedString"), fv ? NSStringFromCGRect(fv.CGRectValue) : @"?"];
        }
        LGLogBlock(@"bàn phím (nút phím Return)", s);
        LGLogTree(@"bàn phím: cây view của keyplane", plane);
    }
    CGRect best = CGRectNull;
    for (id k in keys) {
        NSString *name = LGKV(k, @"name");
        NSString *rep = LGKV(k, @"representedString");
        BOOL isRet = LGIsReturnName(name) || ([rep isKindOfClass:NSString.class] && ([rep isEqualToString:@"\n"] || [rep isEqualToString:@"\r"]));
        if (!isRet) continue;
        NSValue *fv = LGKV(k, @"frame");
        if (![fv isKindOfClass:NSValue.class]) continue;
        CGRect r = fv.CGRectValue;
        if (r.size.width < 20 || r.size.height < 20 || !CGRectIntersectsRect(plane.bounds, r)) continue;
        if (CGRectIsNull(best) || CGRectGetMaxX(r) > CGRectGetMaxX(best) + 1 || (fabs(CGRectGetMaxX(r) - CGRectGetMaxX(best)) <= 1 && CGRectGetMaxY(r) > CGRectGetMaxY(best)))
            best = r;
    }
    return best;
}

static void LGRemoveKey(void) {
    if (gKey) { [gKey removeFromSuperview]; gKey = nil; }
}

static void LGTick(void) {
    if (!gOn) return;
    @try {
        UIResponder *r = LGFirstResponder();
        UIView *plane = r ? LGKeyboardPlane() : nil;
        if (!plane) { LGRemoveKey(); if (++gIdle > 25) { [gTimer invalidate]; gTimer = nil; } return; }
        gIdle = 0;
        // chỉ đổi những phím xanh (Search / Go / Send / Join / Route / Done / Continue...); Return / Next xám giữ nguyên
        BOOL want = NO, en = YES;
        if ([r conformsToProtocol:@protocol(UITextInputTraits)]) {
            id<UITextInputTraits> t = (id<UITextInputTraits>)r;
            UIReturnKeyType rk = [t respondsToSelector:@selector(returnKeyType)] ? t.returnKeyType : UIReturnKeyDefault;
            want = rk != UIReturnKeyDefault && rk != UIReturnKeyNext && rk != UIReturnKeyEmergencyCall;
            if ([t respondsToSelector:@selector(enablesReturnKeyAutomatically)] && t.enablesReturnKeyAutomatically && [r conformsToProtocol:@protocol(UIKeyInput)])
                en = ((id<UIKeyInput>)r).hasText;
        }
        CGRect rect = want ? LGReturnKeyRect(plane) : CGRectNull;
        if (!want || CGRectIsNull(rect)) { LGRemoveKey(); return; }
        if (!gKey) gKey = [[LGKbKey alloc] initWithFrame:rect];
        if (gKey.superview != plane) [plane addSubview:gKey];
        else if (plane.subviews.lastObject != gKey) [plane bringSubviewToFront:gKey];
        if (!CGRectEqualToRect(gKey.frame, rect)) gKey.frame = rect;
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
