#import "LGRing.h"
#import "LGMenuMorph.h"
#import "LGLog.h"
#import <objc/runtime.h>
#include "LGTimeline.h"

static const void *kRingKey = &kRingKey;

// ------------------------------------------------------------------ view vòng
@interface LGRingView : UIView
@property (nonatomic, strong) UIVisualEffectView *fx;
@property (nonatomic, strong) UIView *tintV;
- (void)restyle;
@end

@implementation LGRingView
- (instancetype)initWithFrame:(CGRect)f {
    if (!(self = [super initWithFrame:f])) return nil;
    self.userInteractionEnabled = NO;      // chạm xuyên qua tới nút
    self.clipsToBounds = YES;
    self.backgroundColor = UIColor.clearColor;
    self.layer.borderWidth = 0.8;          // cùng bề dày viền với khối kính của animation
    UIBlurEffectStyle styles[5] = { UIBlurEffectStyleSystemUltraThinMaterial, UIBlurEffectStyleSystemThinMaterial, UIBlurEffectStyleSystemMaterial,
                                    UIBlurEffectStyleSystemThickMaterial, UIBlurEffectStyleSystemChromeMaterial };
    int i = (LGP.material >= 0 && LGP.material <= 4) ? LGP.material : 4;
    _fx = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:styles[i]]];
    _fx.userInteractionEnabled = NO;
    [self addSubview:_fx];
    _tintV = [UIView new];
    _tintV.userInteractionEnabled = NO;
    [self addSubview:_tintV];
    [self restyle];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize s = self.bounds.size;
    self.layer.cornerRadius = fmin(s.width, s.height) / 2;     // = dotR của animation: tròn nếu vuông, viên thuốc nếu dài
    self.fx.frame = self.bounds;
    self.tintV.frame = self.bounds;
}

- (void)restyle {
    UITraitCollection *tc = self.traitCollection;
    self.layer.borderColor = [[UIColor.labelColor resolvedColorWithTraitCollection:tc] colorWithAlphaComponent:LGP.rim].CGColor;
    self.tintV.backgroundColor = [[UIColor.secondarySystemBackgroundColor resolvedColorWithTraitCollection:tc] colorWithAlphaComponent:LGP.tint];
}

- (void)traitCollectionDidChange:(UITraitCollection *)prev {
    [super traitCollectionDidChange:prev];
    [self restyle];     // sáng/tối đổi thì màu viền (CGColor) phải tính lại
}
@end

// ------------------------------------------------------------------ nhận diện nút
static BOOL LGHasMenu(UIView *v) {
    if ([v isKindOfClass:UIButton.class] && ((UIButton *)v).menu) return YES;
    for (id i in v.interactions) if ([i isKindOfClass:UIContextMenuInteraction.class]) return YES;
    return NO;
}

static BOOL LGRingBase(UIView *v) {
    if (!LGButtonLike(v) || v.hidden) return NO;
    CGSize s = v.bounds.size;
    if (s.width >= 120 || s.height >= 80) return NO;
    return LGHasMenu(v) || (LGP.ringAll && [v isKindOfClass:UIButton.class]);
}

static BOOL LGDescHasCandidate(UIView *v, int depth) {
    if (depth > 3) return NO;
    for (UIView *s in v.subviews)
        if (LGRingBase(s) || LGDescHasCandidate(s, depth + 1)) return YES;
    return NO;
}

BOOL LGRingIsCandidate(UIView *v) {
    return v && LGRingBase(v) && !LGDescHasCandidate(v, 0);
}

// ------------------------------------------------------------------ dựng / cập nhật
static LGRingView *LGRingOf(UIView *v) { return objc_getAssociatedObject(v, kRingKey); }

static void LGRingRemove(UIView *v) {
    LGRingView *r = LGRingOf(v);
    if (!r) return;
    [r removeFromSuperview];
    objc_setAssociatedObject(v, kRingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIView *LGCommonAncestor(NSArray<UIView *> *views) {
    for (UIView *cur = views.firstObject; cur; cur = cur.superview) {
        BOOL all = YES;
        for (UIView *v in views) if (![v isDescendantOfView:cur]) { all = NO; break; }
        if (all) return cur;
    }
    return nil;
}

static void LGRingRefresh(UIView *v, int attempt) {
    if (!v) return;
    if (!LGP.ring || !v.window || !LGRingIsCandidate(v)) { LGRingRemove(v); return; }
    CGRect r = [v convertRect:v.bounds toView:nil];
    if (r.size.width < 8 || r.size.height < 8) {      // chưa layout xong -> thử lại vài lần
        if (attempt < 4) {
            __weak UIView *w = v;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ LGRingRefresh(w, attempt + 1); });
        }
        return;
    }

    // nhóm nút liền nhau (vd chia sẻ + "…") -> MỘT viên thuốc; nút ứng viên ngoài cùng bên trái giữ vòng
    NSArray<UIView *> *group = LGGroupFor(v);
    UIView *owner = nil;
    CGRect u = CGRectNull;
    double ownerX = 0;
    for (UIView *b in group) {
        if (!b.window) continue;
        CGRect br = [b convertRect:b.bounds toView:nil];
        u = CGRectUnion(u, br);
        if (LGRingIsCandidate(b) && (!owner || br.origin.x < ownerX)) { owner = b; ownerX = br.origin.x; }
    }
    if (!owner) owner = v;
    if (owner != v) LGRingRemove(v);
    if (CGRectIsNull(u)) u = r;

    BOOL single = group.count <= 1;
    UIView *parent = single ? owner : (LGCommonAncestor(group) ?: owner);
    LGRingView *ring = LGRingOf(owner);
    if (!ring) {
        ring = [[LGRingView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(owner, kRingKey, ring, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (ring.superview != parent) [parent insertSubview:ring atIndex:0];    // sau mọi thứ khác: dưới icon của nút
    ring.frame = single ? parent.bounds : [parent convertRect:u fromView:nil];
    // một nút: ăn theo kích thước nút tự động; nhóm: khung đã tính theo vị trí hiện tại (làm lại khi view vào window)
    ring.autoresizingMask = single ? (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight) : UIViewAutoresizingNone;
    [ring setNeedsLayout];
    LGLog(@"vòng: %s %@ (%lu nút) bo=%.1f", object_getClassName(owner), NSStringFromCGRect(u), (unsigned long)group.count, fmin(u.size.width, u.size.height) / 2);
}

void LGRingSchedule(UIView *v) {
    if (!LGP.ring || !v) return;
    __weak UIView *w = v;
    // lần 1: ngay sau layout đầu; lần 2: sau khi thanh điều hướng xếp xong (hiệu ứng push)
    double delays[2] = { 0.05, 0.5 };
    for (int i = 0; i < 2; i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LGRingRefresh(w, 0); });
}

void LGRingDetach(UIView *v) {
    if (v && LGRingOf(v)) LGRingRemove(v);
}

BOOL LGRingHide(NSArray<UIView *> *views, BOOL hide) {
    BOOL any = NO;
    for (UIView *v in views) {
        LGRingView *r = LGRingOf(v);
        if (!r) continue;
        r.hidden = hide;
        any = YES;
    }
    return any;
}

// ------------------------------------------------------------------ hiệu ứng ẤN (lóe sáng + phóng to)
@interface LGPress : NSObject
@property (nonatomic, strong) UIWindow *ow;
@property (nonatomic, strong) UIView *holder, *flash;
@property (nonatomic, strong) CALayer *glow;
@property (nonatomic, strong) NSArray<UIView *> *sources;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *alphas;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, readonly) CFTimeInterval t0;
@property (nonatomic, readonly) BOOL released;
+ (void)beginWithSources:(NSArray<UIView *> *)sources;
- (void)release_;
- (void)restoreSources;
- (void)end;
@end

static LGPress *gPress;

@implementation LGPress {
    CFTimeInterval _t0, _tRel;
    BOOL _released, _restored;
    double _sCur, _fCur, _sRel, _fRel;
}
- (CFTimeInterval)t0 { return _t0; }
- (BOOL)released { return _released; }

+ (void)beginWithSources:(NSArray<UIView *> *)sources {
    [gPress end];
    CGRect u = CGRectNull;
    NSMutableArray<UIView *> *srcs = [NSMutableArray new];
    for (UIView *v in sources) {
        if (!v.window) continue;
        CGRect r = [v convertRect:v.bounds toView:nil];
        if (CGRectIsEmpty(r) || r.size.width > 200 || r.size.height > 100) continue;
        u = CGRectUnion(u, r);
        [srcs addObject:v];
    }
    if (!srcs.count || CGRectIsNull(u)) return;
    UIWindow *win = srcs.firstObject.window;

    LGPress *p = [LGPress new];
    p.sources = srcs;

    UIWindowScene *sc = win.windowScene;
    UIWindow *ow = sc ? [[UIWindow alloc] initWithWindowScene:sc] : [[UIWindow alloc] initWithFrame:win.bounds];
    ow.frame = win.frame;
    ow.windowLevel = fmax(UIWindowLevelAlert + 100, win.windowLevel + 1);
    ow.backgroundColor = UIColor.clearColor;
    ow.userInteractionEnabled = NO;
    p.ow = ow;

    // viên kính = đúng hình vòng cố định (cùng khung, cùng bo góc min(rộng, cao)/2)
    UIView *holder = [[UIView alloc] initWithFrame:u];
    holder.userInteractionEnabled = NO;
    [ow addSubview:holder];
    p.holder = holder;
    LGRingView *disc = [[LGRingView alloc] initWithFrame:holder.bounds];
    [holder addSubview:disc];
    double rad = fmin(u.size.width, u.size.height) / 2;

    // tối: lóe trắng (như video); sáng: lóe tối (trắng trên nền sáng không nhìn thấy)
    BOOL dark = win.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    double F = LGP.pressFlash;
    UIView *fl = [[UIView alloc] initWithFrame:holder.bounds];
    fl.userInteractionEnabled = NO;
    fl.layer.cornerRadius = rad;
    fl.backgroundColor = dark ? [UIColor colorWithWhite:1 alpha:fmin(0.475 * F, 1)] : [UIColor colorWithWhite:0 alpha:fmin(0.16 * F, 1)];
    fl.alpha = 0;
    [holder addSubview:fl];
    p.flash = fl;

    CALayer *glow = [CALayer layer];
    glow.frame = holder.bounds;
    glow.cornerRadius = rad;
    glow.borderWidth = 0.8;
    glow.borderColor = (dark ? [UIColor colorWithWhite:1 alpha:0.9] : [UIColor colorWithWhite:0 alpha:0.35]).CGColor;
    glow.opacity = 0;
    [holder.layer addSublayer:glow];
    p.glow = glow;

    // ẩn vòng cố định TRƯỚC khi chụp icon (để ảnh chụp không dính vòng), rồi mới ẩn nút thật
    BOOL hadRing = LGRingHide(srcs, YES);
    for (UIView *v in srcs) {
        UIView *s = [v snapshotViewAfterScreenUpdates:hadRing];
        if (!s) continue;
        CGRect r = [v convertRect:v.bounds toView:nil];
        s.frame = CGRectOffset(r, -u.origin.x, -u.origin.y);
        [holder addSubview:s];
    }
    p.alphas = [NSMutableArray new];
    for (UIView *v in srcs) {
        [p.alphas addObject:@(v.alpha < 0.05 ? 1.0 : v.alpha)];
        v.alpha = 0;
    }

    p->_t0 = CACurrentMediaTime();
    p->_sCur = 1;
    p->_fCur = 0;
    gPress = p;
    ow.hidden = NO;
    p.link = [CADisplayLink displayLinkWithTarget:p selector:@selector(tick:)];
    [p.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    LGLog(@"ẤN: %lu nút, khung %@ bo=%.1f %@", (unsigned long)srcs.count, NSStringFromCGRect(u), rad, dark ? @"(tối: lóe trắng)" : @"(sáng: lóe tối)");
}

- (void)apply:(double)s flash:(double)f {
    _sCur = s;
    _fCur = f;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.holder.transform = CGAffineTransformMakeScale((CGFloat)s, (CGFloat)s);
    self.flash.alpha = (CGFloat)f;
    self.glow.opacity = (float)f;
    [CATransaction commit];
}

- (void)tick:(CADisplayLink *)l {
    if (self != gPress) { [l invalidate]; return; }
    CFTimeInterval now = CACurrentMediaTime();
    if (!_released) {
        double t = now - _t0;
        [self apply:lgtl_press_scale(t, LGP.pressScale, LGP.pressOmega, LGP.pressZeta) flash:lgtl_press_flash(t, 0.03)];
        if (t > 3.0) [self release_];     // chốt an toàn: giữ quá lâu thì tự thu về
    } else {
        double t = now - _tRel, w = 30.0;
        double s = 1 + (_sRel - 1) * (1 + w * t) * exp(-w * t);     // lò xo tới hạn, vận tốc đầu 0
        double f = _fRel * exp(-t / 0.05);
        if (t > 0.35 || (fabs(s - 1) < 0.003 && f < 0.01)) { [self end]; return; }
        [self apply:s flash:f];
    }
}

- (void)release_ {
    if (_released) return;
    _released = YES;
    _tRel = CACurrentMediaTime();
    _sRel = _sCur;
    _fRel = _fCur;
}

// Trả nút thật + vòng về nguyên trạng (một lần duy nhất: morph có thể đã ẩn chúng lại ngay sau đó, không được trả lần nữa).
- (void)restoreSources {
    if (_restored) return;
    _restored = YES;
    for (NSUInteger i = 0; i < self.sources.count && i < self.alphas.count; i++) self.sources[i].alpha = (CGFloat)self.alphas[i].doubleValue;
    LGRingHide(self.sources, NO);
}

- (void)end {
    [self.link invalidate];
    self.link = nil;
    [self restoreSources];
    self.ow.hidden = YES;
    self.ow = nil;
    if (gPress == self) gPress = nil;
}
@end

void LGPressBegin(NSArray<UIView *> *sources) {
    if (!LGP.press) return;
    @try { [LGPress beginWithSources:sources]; }
    @catch (NSException *ex) { LGLog(@"NGOẠI LỆ khi bắt đầu ấn: %@ %@", ex.name, ex.reason); LGPressFinish(); }
}

void LGPressRelease(void) {
    LGPress *p = gPress;
    if (!p || p.released) return;
    // nhả tay chưa chắc là hết: menu có thể hiện ngay sau đó (morph sẽ gọi LGPressFinish) -> chờ một chút rồi mới thu về
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (gPress == p) [p release_];
    });
}

void LGPressRestoreSources(void) { [gPress restoreSources]; }

void LGPressFinish(void) { [gPress end]; }

double LGPressRemaining(void) {
    LGPress *p = gPress;
    if (!p) return 0;
    return fmax(0, LGP.pressHold - (CACurrentMediaTime() - p.t0));
}
