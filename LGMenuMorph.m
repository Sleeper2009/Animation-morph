#import "LGMenuMorph.h"
#import <QuartzCore/QuartzCore.h>
#include "LGMetaball.h"

LGParams LGP = { .omega = 29.0, .offsetDelay = 0.124, .contentDelay = 0.048,
                 .dotOmega = 36.0, .dotDelay = 0.01, .radOmega = 40.0, .radDelay = 0.075,
                 .blend = 24.0, .dur = 0.5, .speed = 1.0, .useGlass = YES, .debug = NO };

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

static __weak LGMenuMorph *gActive;   // morph đang chạy (chỉ có thể có một)

@interface LGMenuMorph ()
@property (nonatomic, strong) UIView *body, *host, *shell, *snap;
@property (nonatomic, strong) UIVisualEffectView *fx;
@property (nonatomic, strong) CAShapeLayer *mask, *rim;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval t0;
@property (nonatomic) CGRect F, cf;
@property (nonatomic) CGPoint A0, A1;
@property (nonatomic) CGFloat ax, ay, R, rBtn;
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

+ (void)runForBody:(UIView *)body content:(UIView *)content source:(CGRect)src done:(void (^)(void))done {
    UIView *host = body.superview;
    if (!host) { if (done) done(); return; }

    // 1) Đưa menu thật về trạng thái cuối (bỏ animation hệ thống) rồi chụp nội dung
    Strip(body);
    // Nếu hệ thống để menu ở trạng thái đầu (vd scale nhỏ) thì `frame` bị méo -> khung cuối sai và lúc hiện lại
    // menu thật sẽ "nhảy". Trạng thái cuối của menu là transform = identity.
    if (!CGAffineTransformIsIdentity(body.transform)) {
        if (LGP.debug) NSLog(@"[LiquidMenu] body.transform != identity (%@) -> reset", NSStringFromCGAffineTransform(body.transform));
        body.transform = CGAffineTransformIdentity;
    }
    [body layoutIfNeeded];
    if (CGRectIsEmpty(body.frame)) { if (done) done(); return; }
    UIView *snap = [content snapshotViewAfterScreenUpdates:YES];
    if (!snap) { if (done) done(); return; }

    LGMenuMorph *m = [LGMenuMorph new];
    m.body = body; m.host = host; m.done = done; m.snap = snap;
    m.F = body.frame;                                          // khung cuối của menu
    m.cf = [content convertRect:content.bounds toView:host];   // khung cuối của nội dung
    m.rBtn = fmin(src.size.width, src.size.height) / 2;
    CGPoint c = CGPointMake(CGRectGetMidX(src), CGRectGetMidY(src));
    // điểm neo cuối = điểm của menu gần tâm nút nhất (bản Flutter: góc trên-phải)
    CGPoint n = CGPointMake(cl(c.x, CGRectGetMinX(m.F), CGRectGetMaxX(m.F)),
                            cl(c.y, CGRectGetMinY(m.F), CGRectGetMaxY(m.F)));
    m.A0 = c; m.A1 = n;
    m.ax = (n.x - m.F.origin.x) / m.F.size.width;
    m.ay = (n.y - m.F.origin.y) / m.F.size.height;
    m.R = body.layer.cornerRadius > 1 ? body.layer.cornerRadius : 28;

    // 2) Vỏ kính của riêng ta: blur/glass + nội dung, cắt bằng mask metaball
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
        CGPathAddEllipseInRect(p, NULL, CGRectMake(_A0.x - rd, _A0.y - rd, rd * 2, rd * 2));
    } else if (k < 0.5) {
        CGPathRef rr = CGPathCreateWithRoundedRect(Bt, r, r, NULL);
        CGPathAddPath(p, NULL, rr);
        CGPathRelease(rr);
    } else {
        LGSink s = { p, sMove, sLine, sClose };
        LGMetaball((LGBox){ Bt.origin.x, Bt.origin.y, w, h }, r, _A0.x, _A0.y, rd, k, 2.5, s);
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
