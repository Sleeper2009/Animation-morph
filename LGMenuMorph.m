#import "LGMenuMorph.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "LGMetaball.h"
#include "LGPlan.h"

LGParams LGP = { .omega = 29.0, .offsetDelay = 0.124, .contentDelay = 0.048,
                 .dotOmega = 36.0, .dotDelay = 0.01, .radOmega = 40.0, .radDelay = 0.075,
                 .blend = 24.0, .dur = 0.5, .speed = 1.0, .useGlass = YES, .debug = NO,
                 .coverButton = YES, .hideSource = YES };

// Đáp ứng spring tới hạn dạng đóng: 0 -> 1 kể từ t = 0
static double sp(double t, double w) { return t <= 0 ? 0 : 1 - (1 + w * t) * exp(-w * t); }
static double cl(double v, double lo, double hi) { return fmin(fmax(v, lo), hi); }
static double lerp(double a, double b, double t) { return a + (b - a) * t; }

// fmax/fmin trả về đối số không-NaN nên NaN (plist hỏng) cũng bị đẩy về cận dưới/trên.
void LGParamsFinalize(void) {
    LGP.omega = fmax(LGP.omega, 1.0);
    LGP.dotOmega = fmax(LGP.dotOmega, 1.0);
    LGP.radOmega = fmax(LGP.radOmega, 1.0);
    LGP.offsetDelay = fmax(LGP.offsetDelay, 0.0);
    LGP.contentDelay = fmax(LGP.contentDelay, 0.0);
    LGP.dotDelay = fmax(LGP.dotDelay, 0.0);
    LGP.radDelay = fmax(LGP.radDelay, 0.0);
    LGP.blend = fmax(LGP.blend, 0.0);
    LGP.speed = fmin(fmax(LGP.speed, 0.05), 10.0);   // speed<=0 sẽ làm tau không tăng -> menu thật bị ẩn mãi
    // spring 1 - (1+x)e^-x còn ~0.3% ở x = 8  ->  thời gian ổn định = delay + 8/omega
    double settle = fmax(fmax(LGP.offsetDelay + 8.0 / LGP.omega, LGP.contentDelay + 8.0 / LGP.omega),
                         fmax(LGP.dotDelay + 8.0 / LGP.dotOmega, LGP.radDelay + 8.0 / LGP.radOmega));
    LGP.dur = cl(settle, 0.5, 3.0);                  // mặc định ra 0.5 như cũ
}

static void sMove(void *c, double x, double y) { CGPathMoveToPoint((CGMutablePathRef)c, NULL, x, y); }
static void sLine(void *c, double x, double y) { CGPathAddLineToPoint((CGMutablePathRef)c, NULL, x, y); }
static void sClose(void *c) { CGPathCloseSubpath((CGMutablePathRef)c); }

static void Strip(UIView *v) {
    [v.layer removeAllAnimations];
    for (UIView *s in v.subviews) Strip(s);
}

// ---- Chỉ chạy khi debug = true: ghi lại những gì hệ thống làm với menu SAU khi morph mở xong
// (lúc nào bắt đầu đóng, alpha/scale thế nào, bao giờ bị gỡ) để làm animation đóng ở bước sau.
@interface LGWatcher : NSObject
@property (nonatomic, weak) UIView *body;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, copy) NSString *last;
@property (nonatomic) CFTimeInterval t0;
+ (void)watch:(UIView *)body;
@end

@implementation LGWatcher
+ (void)watch:(UIView *)body {
    LGWatcher *w = [LGWatcher new];
    w.body = body;
    w.t0 = CACurrentMediaTime();
    w.link = [CADisplayLink displayLinkWithTarget:w selector:@selector(tick:)];
    [w.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    NSLog(@"[LiquidMenu] watch: bắt đầu theo dõi menu (tối đa 15 s)");
}
- (void)tick:(CADisplayLink *)l {
    UIView *b = self.body;
    double dt = CACurrentMediaTime() - self.t0;
    if (!b || !b.window || dt > 15) {
        NSLog(@"[LiquidMenu] watch: kết thúc t=%.3f %@", dt, !b ? @"(body đã bị giải phóng)" : (!b.window ? @"(body rời khỏi window)" : @"(hết 15 s, menu vẫn mở)"));
        [l invalidate];
        self.link = nil;
        return;
    }
    double minA = 1;
    unsigned long anims = 0;
    for (UIView *v = b; v; v = v.superview) {
        CALayer *pl = v.layer.presentationLayer ?: v.layer;
        minA = fmin(minA, fmin((double)pl.opacity, (double)v.alpha));
        anims += (unsigned long)v.layer.animationKeys.count;
    }
    CALayer *bp = b.layer.presentationLayer ?: b.layer;
    NSString *sig = [NSString stringWithFormat:@"alphaMin=%.2f anims=%lu scale=%.2f hidden=%d", minA, anims, [bp affineTransform].a, (int)b.hidden];
    if (![sig isEqualToString:self.last]) {
        NSLog(@"[LiquidMenu] watch t=%.3f %@", dt, sig);
        self.last = sig;
    }
}
@end

static __weak LGMenuMorph *gActive;   // morph đang chạy (chỉ có thể có một)

@interface LGMenuMorph ()
@property (nonatomic, strong) UIView *body, *host, *shell, *snap, *srcView;
@property (nonatomic, strong) UIVisualEffectView *fx;
@property (nonatomic, strong) CAShapeLayer *mask, *rim;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval t0;
@property (nonatomic) CGRect F, cf;
@property (nonatomic) CGPoint A0, A1, C;        // C = tâm nút (chỗ chấm tròn), A0/A1 = điểm neo của thân lúc đầu/cuối
@property (nonatomic) CGFloat ax, ay, R, rBtn, srcAlpha;
@property (nonatomic, copy) void (^done)(void);
@end

@implementation LGMenuMorph

+ (UIVisualEffect *)effect {
    Class g = NSClassFromString(@"UIGlassEffect"); // iOS 26+
    if (LGP.useGlass && g) {
        id e = [g new];
        if ([e isKindOfClass:UIVisualEffect.class]) return e;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
}

+ (void)cancelActive {
    LGMenuMorph *m = gActive;
    if (m) [m finish];
}

+ (void)runForBody:(UIView *)body content:(UIView *)content source:(CGRect)src sourceView:(UIView *)sv done:(void (^)(void))done {
    UIView *host = body.superview;
    UIWindow *win = host.window;
    if (!host || !win) { if (done) done(); return; }

    // 1) Đưa menu thật về trạng thái cuối (bỏ animation hệ thống)
    Strip(body);
    // Nếu hệ thống để menu ở trạng thái đầu (vd scale nhỏ) thì `frame` bị méo -> khung cuối sai và lúc hiện lại
    // menu thật sẽ "nhảy". Trạng thái cuối của menu là transform = identity.
    if (!CGAffineTransformIsIdentity(body.transform)) {
        if (LGP.debug) NSLog(@"[LiquidMenu] body.transform != identity (%@) -> reset", NSStringFromCGAffineTransform(body.transform));
        body.transform = CGAffineTransformIdentity;
    }
    [body layoutIfNeeded];
    CGRect F0 = body.frame;
    if (CGRectIsEmpty(F0)) { if (done) done(); return; }

    // 2) Hình học theo bản Flutter (xem LGPlan.h): thân neo ở góc, trượt về góc của NÚT; menu thật được dời để đè lên nút
    CGRect scr = [host convertRect:win.bounds fromView:win];
    LGPlan pl = LGPlanGeometry((LGBox){ src.origin.x, src.origin.y, src.size.width, src.size.height },
                               (LGBox){ F0.origin.x, F0.origin.y, F0.size.width, F0.size.height },
                               (LGBox){ scr.origin.x, scr.origin.y, scr.size.width, scr.size.height }, LGP.coverButton);
    if (fabs(pl.dx) > 0.5 || fabs(pl.dy) > 0.5) {
        body.transform = CGAffineTransformMakeTranslation(pl.dx, pl.dy);   // dời menu thật; cf/F bên dưới tính sau khi dời
        [body layoutIfNeeded];
    }
    if (LGP.debug)
        NSLog(@"[LiquidMenu] plan cover=%d src=%@ menu=%@ -> dời (%+.1f,%+.1f) neo=(%.0f,%.0f) a0=(%.1f,%.1f) a1=(%.1f,%.1f)",
              (int)LGP.coverButton, NSStringFromCGRect(src), NSStringFromCGRect(F0), pl.dx, pl.dy, pl.ax, pl.ay, pl.a0x, pl.a0y, pl.a1x, pl.a1y);

    UIView *snap = [content snapshotViewAfterScreenUpdates:YES];
    if (!snap) {
        body.transform = CGAffineTransformIdentity;   // hoàn tác phần dời
        if (done) done();
        return;
    }

    LGMenuMorph *m = [LGMenuMorph new];
    m.body = body; m.host = host; m.done = done; m.snap = snap;
    m.F = body.frame;                                          // khung cuối của menu (sau khi dời)
    m.cf = [content convertRect:content.bounds toView:host];   // khung cuối của nội dung
    m.rBtn = fmin(src.size.width, src.size.height) / 2;
    m.C = CGPointMake(CGRectGetMidX(src), CGRectGetMidY(src));
    m.A0 = CGPointMake(pl.a0x, pl.a0y);
    m.A1 = CGPointMake(pl.a1x, pl.a1y);
    m.ax = (CGFloat)pl.ax;
    m.ay = (CGFloat)pl.ay;
    m.R = body.layer.cornerRadius > 1 ? body.layer.cornerRadius : 28;

    // 3) Vỏ kính của riêng ta: blur/glass + nội dung, cắt bằng mask metaball
    UIView *shell = [[UIView alloc] initWithFrame:host.bounds];
    shell.userInteractionEnabled = NO;
    UIView *masked = [[UIView alloc] initWithFrame:shell.bounds];
    UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:[self effect]];
    fx.frame = masked.bounds;
    [masked addSubview:fx];
    m.fx = fx;
    snap.bounds = CGRectMake(0, 0, m.cf.size.width, m.cf.size.height);
    [masked addSubview:snap];
    m.mask = [CAShapeLayer layer];
    m.mask.frame = masked.bounds;
    m.mask.fillColor = UIColor.blackColor.CGColor;
    masked.layer.mask = m.mask;
    m.rim = [CAShapeLayer layer];
    m.rim.frame = shell.bounds;
    m.rim.fillColor = nil;
    m.rim.strokeColor = [UIColor colorWithWhite:1 alpha:0.28].CGColor;
    m.rim.lineWidth = 0.7;
    [shell addSubview:masked];
    [shell.layer addSublayer:m.rim];
    [host insertSubview:shell aboveSubview:body];
    m.shell = shell;
    body.hidden = YES;       // menu thật ẩn trong lúc morph, hiện lại ở cuối

    // Nút gốc: bản Flutter cho icon nút biến mất ngay khung đầu; ở đây nút thật nằm dưới nên phải ẩn nó đi.
    // Không ẩn nếu view đó là tổ tiên/hậu duệ của menu (tránh ẩn nhầm cả màn hình hoặc chính menu).
    if (LGP.hideSource && sv && sv.window && ![host isDescendantOfView:sv] && ![sv isDescendantOfView:host]) {
        m.srcView = sv;
        m.srcAlpha = sv.alpha;
        sv.alpha = 0;
        if (LGP.debug) NSLog(@"[LiquidMenu] ẩn nút gốc %s", object_getClassName(sv));
    }

    [m renderAt:0];
    m.t0 = CACurrentMediaTime();
    m.link = [CADisplayLink displayLinkWithTarget:m selector:@selector(tick:)];
    [m.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    gActive = m;
}

- (void)tick:(CADisplayLink *)l {
    double tau = (CACurrentMediaTime() - self.t0) * LGP.speed;
    if (tau >= LGP.dur || !self.host.window) { [self finish]; return; }
    [self renderAt:tau];
}

- (void)finish {
    if (!self.link) return;                  // đã kết thúc rồi (tick + cancelActive có thể cùng gọi)
    [self.link invalidate];
    self.link = nil;
    if (gActive == self) gActive = nil;
    self.body.hidden = NO;
    if (self.srcView) {                      // trả lại nút gốc ở MỌI đường thoát
        self.srcView.alpha = self.srcAlpha;
        self.srcView = nil;
    }
    if (LGP.debug) [LGWatcher watch:self.body];
    // Không được đổi alpha của vỏ: alpha < 1 ở tổ tiên của UIVisualEffectView làm hiệu ứng mất ngay.
    // Mờ dần bằng cách đưa effect về nil, cùng lúc mờ nội dung chụp và viền.
    UIView *s = self.shell;
    UIVisualEffectView *fx = self.fx;
    UIView *snap = self.snap;
    CAShapeLayer *rim = self.rim;
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.08];
    rim.opacity = 0;
    [CATransaction commit];
    [UIView animateWithDuration:0.08 animations:^{ fx.effect = nil; snap.alpha = 0; }
                     completion:^(BOOL f) { [s removeFromSuperview]; }];
    if (self.done) self.done();
}

// Toàn bộ timeline đo từ 12 khung hình (xem bản Flutter): mỗi thành phần một spring riêng
- (void)renderAt:(double)tau {
    double ps = sp(tau, LGP.omega);                          // kích thước thân
    double po = sp(tau - LGP.offsetDelay, LGP.omega);        // trượt về điểm neo cuối (trễ)
    double pc = sp(tau - LGP.contentDelay, LGP.omega);       // nội dung phóng to
    double pd = sp(tau - LGP.dotDelay, LGP.dotOmega);        // chấm nút gốc co lại
    double pr = sp(tau - LGP.radDelay, LGP.radOmega);        // bo góc

    CGPoint a = CGPointMake(lerp(_A0.x, _A1.x, po), lerp(_A0.y, _A1.y, po));
    double w = _F.size.width * ps, h = _F.size.height * ps;
    CGRect Bt = CGRectMake(a.x - _ax * w, a.y - _ay * h, w, h);   // thân neo theo điểm (ax, ay)
    double r = fmin(lerp(150, _R, pr), fmin(w, h) / 2);
    double rd = _rBtn * (1 - pd);
    double k = LGP.blend * cl((0.24 - tau) / 0.08, 0, 1);

    CGMutablePathRef p = CGPathCreateMutable();
    if (w < 1 || h < 1) {
        CGPathAddEllipseInRect(p, NULL, CGRectMake(_C.x - rd, _C.y - rd, rd * 2, rd * 2));
    } else if (k < 0.5) {
        CGPathRef rr = CGPathCreateWithRoundedRect(Bt, r, r, NULL);
        CGPathAddPath(p, NULL, rr);
        CGPathRelease(rr);
    } else {
        LGSink s = { p, sMove, sLine, sClose };
        LGMetaball((LGBox){ Bt.origin.x, Bt.origin.y, w, h }, r, _C.x, _C.y, rd, k, 2.5, s);
    }

    double op = cl((pc - 0.35) / 0.5, 0, 1);
    CGPoint cc = CGPointMake(CGRectGetMidX(Bt) + (CGRectGetMidX(_cf) - CGRectGetMidX(_F)),
                             CGRectGetMinY(Bt) + (CGRectGetMidY(_cf) - CGRectGetMinY(_F)));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.mask.path = p;
    self.rim.path = p;
    self.snap.alpha = op;
    self.snap.center = cc;
    double sc = fmax(pc, 0.001);
    self.snap.transform = CGAffineTransformMakeScale(sc, sc);
    [CATransaction commit];
    CGPathRelease(p);
}
@end
