#import "LGMenuMorph.h"
#import "LGLog.h"
#import "LGRing.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#include "LGMetaball.h"
#include "LGPlan.h"
#include "LGTimeline.h"

LGParams LGP = { .omega = 29.0, .offsetDelay = 0.124, .contentDelay = 0.048,
                 .dotOmega = 36.0, .dotDelay = 0.01, .radOmega = 40.0, .radDelay = 0.075,
                 .blend = 24.0, .dur = 0.5, .closeDur = 0.38, .speed = 1.0,
                 .tint = 0.12, .shadow = 0.18, .rim = 0.14, .material = -1,
                 .bounceAmp = 10.0, .bounceOmega = 22.0, .bounceZeta = 0.4, .bounce = YES, .ring = YES, .ringAll = NO,
                 .pressScale = 1.30, .pressOmega = 34.0, .pressZeta = 0.55, .pressFlash = 1.0, .pressHold = 0.12, .press = YES, .pressFlashOn = YES, .pressZoomOn = YES, .ringMargin = 8.0, .ringPadX = 12.0, .ringBack = YES, .fallbackAnim = YES, .groupGap = 16.0, .overlayMode = 0, .style = 0, .liquidDrop = 0.06,
                 .useGlass = YES, .debug = YES, .coverButton = YES, .hideSource = YES, .groupButtons = YES,
                 .blurText = YES, .closeAnim = YES, .dump = YES };

// fmax/fmin trả về đối số không-NaN nên NaN (plist hỏng) cũng bị đẩy về cận.
void LGParamsFinalize(void) {
    LGP.omega = fmax(LGP.omega, 1.0);
    LGP.dotOmega = fmax(LGP.dotOmega, 1.0);
    LGP.radOmega = fmax(LGP.radOmega, 1.0);
    LGP.offsetDelay = fmax(LGP.offsetDelay, 0.0);
    LGP.contentDelay = fmax(LGP.contentDelay, 0.0);
    LGP.dotDelay = fmax(LGP.dotDelay, 0.0);
    LGP.radDelay = fmax(LGP.radDelay, 0.0);
    LGP.blend = fmax(LGP.blend, 0.0);
    LGP.speed = fmin(fmax(LGP.speed, 0.05), 10.0);
    LGP.closeDur = fmin(fmax(LGP.closeDur, 0.05), 5.0);
    LGP.tint = fmin(fmax(LGP.tint, 0.0), 1.0);
    LGP.shadow = fmin(fmax(LGP.shadow, 0.0), 1.0);
    LGP.rim = fmin(fmax(LGP.rim, 0.0), 1.0);
    LGP.bounceAmp = fmin(fmax(LGP.bounceAmp, 0.0), 40.0);
    LGP.bounceOmega = fmin(fmax(LGP.bounceOmega, 4.0), 80.0);
    LGP.bounceZeta = fmin(fmax(LGP.bounceZeta, 0.05), 1.0);
    LGP.pressScale = fmin(fmax(LGP.pressScale, 1.0), 2.0);
    LGP.pressOmega = fmin(fmax(LGP.pressOmega, 5.0), 100.0);
    LGP.pressZeta = fmin(fmax(LGP.pressZeta, 0.1), 1.0);
    LGP.pressFlash = fmin(fmax(LGP.pressFlash, 0.0), 2.0);
    LGP.pressHold = fmin(fmax(LGP.pressHold, 0.0), 0.6);
    LGP.ringMargin = fmin(fmax(LGP.ringMargin, 0.0), 40.0);
    LGP.ringPadX = fmin(fmax(LGP.ringPadX, 0.0), 30.0);
    LGP.groupGap = fmin(fmax(LGP.groupGap, 0.0), 60.0);
    if (LGP.overlayMode < 0 || LGP.overlayMode > 2) LGP.overlayMode = 0;
    if (LGP.style < 0 || LGP.style > 1) LGP.style = 0;
    LGP.liquidDrop = fmin(fmax(LGP.liquidDrop, 0.0), 0.3);
    LGP.speed = fmin(fmax(LGP.speed, 0.4), 3.0);
    if (LGP.material < -1) LGP.material = -1;
    if (LGP.material > 4) LGP.material = 4;
    // spring 1 - (1+x)e^-x còn ~0.3% ở x = 8  ->  thời gian ổn định = delay + 8/omega
    double settle = fmax(fmax(LGP.offsetDelay + 8.0 / LGP.omega, LGP.contentDelay + 8.0 / LGP.omega),
                         fmax(LGP.dotDelay + 8.0 / LGP.dotOmega, LGP.radDelay + 8.0 / LGP.radOmega));
    LGP.dur = fmin(fmax(settle, 0.5), 3.0);   // mặc định ra 0.5
}

// ------------------------------------------------------------------ tiện ích
static LGBox LGBoxOf(CGRect r) { return (LGBox){ r.origin.x, r.origin.y, r.size.width, r.size.height }; }
static CGRect LGWinRect(UIView *v) { return [v convertRect:v.bounds toView:nil]; }

static void sMove(void *c, double x, double y) { CGPathMoveToPoint((CGMutablePathRef)c, NULL, x, y); }
static void sLine(void *c, double x, double y) { CGPathAddLineToPoint((CGMutablePathRef)c, NULL, x, y); }
static void sClose(void *c) { CGPathCloseSubpath((CGMutablePathRef)c); }

static void LGStrip(UIView *v) {
    [v.layer removeAllAnimations];
    for (UIView *s in v.subviews) LGStrip(s);
}

static void LGLabels(UIView *v, NSMutableArray<UILabel *> *out) {
    if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) [out addObject:(UILabel *)v];
    for (UIView *s in v.subviews) LGLabels(s, out);
}

static UIView *LGLCAOf(NSArray<UIView *> *views) {
    for (UIView *cur = views.firstObject; cur; cur = cur.superview) {
        BOOL all = YES;
        for (UIView *v in views) if (![v isDescendantOfView:cur]) { all = NO; break; }
        if (all) return cur;
    }
    return nil;
}

static NSString *LGLabelSig(UIView *root) {
    NSMutableArray<UILabel *> *ls = [NSMutableArray new];
    LGLabels(root, ls);
    NSMutableString *s = [NSMutableString string];
    for (UILabel *l in ls) { [s appendFormat:@"%@@%.0fx%.0f|", l.text, l.bounds.size.width, l.bounds.size.height]; }
    return s;
}

// UIVisualEffectView lớn nhất bên trong view (nền kính của menu thật), nil nếu không có
static UIVisualEffectView *LGFindFX(UIView *root, int depth) {
    UIVisualEffectView *best = nil;
    if ([root isKindOfClass:UIVisualEffectView.class]) best = (UIVisualEffectView *)root;
    if (depth < 5)
        for (UIView *s in root.subviews) {
            UIVisualEffectView *c = LGFindFX(s, depth + 1);
            if (c && (!best || c.bounds.size.width * c.bounds.size.height > best.bounds.size.width * best.bounds.size.height)) best = c;
        }
    return best;
}

// bo góc của menu thật: cornerRadius đầu tiên > 1 trong thân, hậu duệ gần, hoặc tổ tiên tới container
static double LGCornerOf(UIView *body, UIView *container, double maxR) {
    NSMutableArray<UIView *> *q = [NSMutableArray arrayWithObject:body];
    for (int d = 0; d < 4 && q.count; d++) {
        NSMutableArray<UIView *> *next = [NSMutableArray new];
        for (UIView *v in q) {
            double r = v.layer.cornerRadius;
            if (r > 1 && r <= maxR) return r;
            [next addObjectsFromArray:v.subviews];
        }
        q = next;
    }
    for (UIView *a = body.superview; a; a = a.superview) {
        double r = a.layer.cornerRadius;
        if (r > 1 && r <= maxR) return r;
        if (a == container) break;
    }
    return fmin(14.0, maxR);
}

static UIImage *LGImageOf(UIView *v, CGFloat scale) {
    CGSize sz = v.bounds.size;
    if (sz.width < 1 || sz.height < 1 || sz.width > 2000 || sz.height > 2000) return nil;
    UIGraphicsImageRendererFormat *fm = [UIGraphicsImageRendererFormat preferredFormat];
    fm.opaque = NO;
    fm.scale = scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:fm];
    // renderInContext: vẽ thẳng cây layer của view bằng CPU (trạng thái model): không cần view đang hiện trên màn hình,
    // nên vẫn chụp được khi container đang bị ẩn bằng layer.hidden để không lộ khung hình của menu hệ thống.
    return [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [v.layer renderInContext:c.CGContext];
    }];
}

// Tỉ lệ ô có "mực" (alpha > 0) của ảnh, để log biết ảnh chụp có bị trống không.
static double LGInk(UIImage *img) {
    if (!img.CGImage) return 0;
    enum { W = 48, H = 48 };
    uint8_t buf[W * H];
    memset(buf, 0, sizeof buf);
    CGContextRef c = CGBitmapContextCreate(buf, W, H, 8, W, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!c) return 0;
    CGContextSetInterpolationQuality(c, kCGInterpolationMedium);
    CGContextDrawImage(c, CGRectMake(0, 0, W, H), img.CGImage);
    CGContextRelease(c);
    int n = 0;
    for (int i = 0; i < W * H; i++) if (buf[i]) n++;
    return (double)n / (W * H);
}

static CIContext *gCI;
static UIImage *LGBlurred(UIImage *img, double sigmaPt) {
    if (!img.CGImage) return nil;
    if (!gCI) gCI = [CIContext contextWithOptions:nil];
    CIImage *in = [CIImage imageWithCGImage:img.CGImage];
    CGRect ext = in.extent;
    CIFilter *f = [CIFilter filterWithName:@"CIGaussianBlur"];
    if (!f) return nil;
    [f setValue:[in imageByClampingToExtent] forKey:kCIInputImageKey];
    [f setValue:@(sigmaPt * img.scale) forKey:kCIInputRadiusKey];
    CIImage *out = [f.outputImage imageByCroppingToRect:ext];
    if (!out) return nil;
    CGImageRef cg = [gCI createCGImage:out fromRect:ext];
    if (!cg) return nil;
    UIImage *u = [UIImage imageWithCGImage:cg scale:img.scale orientation:UIImageOrientationUp];
    CGImageRelease(cg);
    return u;
}

// Vùng NHÌN THẤY của một hàng, tính cả chữ / icon tràn ra ngoài khung hàng (hàng có tiêu đề + phụ đề: chữ nằm lệch khỏi khung nên bị cắt mất nửa).
static CGRect LGRowVisual(UIView *v) {
    CGRect u = v.bounds;
    NSMutableArray<UIView *> *q = [NSMutableArray arrayWithObject:v];
    for (int d = 0; d < 5 && q.count; d++) {
        NSMutableArray<UIView *> *nx = [NSMutableArray new];
        for (UIView *a in q)
            for (UIView *s in a.subviews) {
                if (s.hidden || s.alpha < 0.01) continue;
                if ([s isKindOfClass:UILabel.class] || [s isKindOfClass:UIImageView.class]) u = CGRectUnion(u, [s convertRect:s.bounds toView:v]);
                [nx addObject:s];
            }
        q = nx;
    }
    return CGRectIntersection(u, CGRectInset(v.bounds, -24, -24));     // tràn tối đa 24 pt mỗi phía
}

// Chụp vùng `rv` (toạ độ của v) của cây layer v, kể cả phần tràn ngoài bounds, không dính hàng xóm.
static UIImage *LGImageOfRect(UIView *v, CGRect rv, CGFloat scale) {
    CGSize sz = rv.size;
    if (sz.width < 1 || sz.height < 1 || sz.width > 2000 || sz.height > 2000) return nil;
    UIGraphicsImageRendererFormat *fm = [UIGraphicsImageRendererFormat preferredFormat];
    fm.opaque = NO;
    fm.scale = scale;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:sz format:fm];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        CGContextTranslateCTM(c.CGContext, -rv.origin.x, -rv.origin.y);
        [v.layer renderInContext:c.CGContext];
    }];
}

// Các "hàng" của menu: tổ tiên gần nhất của mỗi UILabel mà rộng >= 85% thân và cao <= 75% thân.
static NSArray<UIView *> *LGRowViews(UIView *body, UIView *content) {
    NSMutableArray<UILabel *> *labels = [NSMutableArray new];
    LGLabels(body, labels);
    CGRect bw = LGWinRect(body);
    NSMutableArray<UIView *> *rows = [NSMutableArray new];
    for (UILabel *l in labels) {
        for (UIView *a = l.superview; a && a != body; a = a.superview) {
            CGRect r = LGWinRect(a);
            if (r.size.width >= bw.size.width * 0.85 && r.size.height <= bw.size.height * 0.75) {
                if (![rows containsObject:a]) [rows addObject:a];
                break;
            }
        }
    }
    if (rows.count == 0 || rows.count > 24) return @[ content ?: body ];
    [rows sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        double ya = CGRectGetMinY(LGWinRect(a)), yb = CGRectGetMinY(LGWinRect(b));
        return ya < yb ? NSOrderedAscending : (ya > yb ? NSOrderedDescending : NSOrderedSame);
    }];
    return rows;
}

// Đường viền của khung hình: chấm / thân / metaball. Toạ độ tính theo gốc (ox, oy).
static CGPathRef LGShapePath(const LGTimeFrame *f, double ox, double oy) {
    CGMutablePathRef p = CGPathCreateMutable();
    LGBox b = f->body, d = f->dot;
    b.x -= ox; b.y -= oy; d.x -= ox; d.y -= oy;
    if (f->mode == LGModeDot) {
        if (d.w > 0.5 && d.h > 0.5) CGPathAddRoundedRect(p, NULL, CGRectMake(d.x, d.y, d.w, d.h), f->dotR, f->dotR);
    } else if (f->mode == LGModeBody) {
        CGPathAddRoundedRect(p, NULL, CGRectMake(b.x, b.y, b.w, b.h), f->r, f->r);
    } else {
        LGSink s = { p, sMove, sLine, sClose };
        LGMetaballDot(b, f->r, d, f->dotR, f->k, 2.5, s);
        if (CGPathIsEmpty(p)) CGPathAddRoundedRect(p, NULL, CGRectMake(b.x, b.y, b.w, b.h), f->r, f->r);
    }
    return p;
}

// ------------------------------------------------------------------ phiên
typedef NS_ENUM(NSInteger, LGState) { LGStOpening, LGStOpen, LGStClosing, LGStBouncing, LGStSettling, LGStDone };

@interface LGRow : NSObject
@property (nonatomic) CGRect rect;                 // khung cuối (toạ độ window, đã tính phần dời menu)
@property (nonatomic, strong) CALayer *holder, *sharp, *blur;
@end
@implementation LGRow
@end

static LGMenuMorph *gSession;
static NSMapTable<UITouch *, NSNumber *> *gTouches;   // chạm -> bắt đầu bên trong thân menu?

@interface LGMenuMorph () {
    LGTimeSpec _spec;
    LGTimeGeom _geom;
    CGRect _F;            // khung cuối của menu thật (toạ độ window, sau khi dời)
    CGRect _src;          // khung nút / viên thuốc nguồn
    CGRect _R;            // vùng của view phủ
    CGRect _contentF;     // khung cuối của nội dung
    CGSize _bodySize;     // bounds.size của thân lúc quan sát gần nhất (phát hiện đổi nội dung)
    double _tau;
    CFTimeInterval _lastT, _settleT;
    int _ticks, _pinFix;
    double _baseA, _baseS;
    CGPoint _bdir;        // hướng nảy khi đóng (vector đơn vị chéo): NGƯỢC phía menu mở ra
    double _bt, _bdur;    // thời gian đã nảy / tổng thời gian nảy (s)
    BOOL _skipClose;      // app đã present bảng khác sau khi chạm mục menu: đóng không animation
    CFTimeInterval _insideEndT;   // lần nhả tay gần nhất bên trong menu
    NSString *_sig, *_lastWatch, *_labelSig;
}
@property (nonatomic, weak) UIView *container, *body, *content;
@property (nonatomic, strong) NSArray<UIView *> *sources;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *srcAlpha;
@property (nonatomic, strong) NSMutableArray<UIView *> *iconSnaps;
@property (nonatomic, strong) UIView *ow;      // UIWindow riêng, hoặc view phủ kín trong cửa sổ menu (xem LGMakeOverlay)
@property (nonatomic, strong) UIView *reg, *clip, *fullSnap;
@property (nonatomic, strong) UIVisualEffectView *fx;
@property (nonatomic, strong) CAShapeLayer *shadowL, *shadowMask, *fxMask, *tintL, *clipMask, *rimL;
@property (nonatomic, strong) NSMutableArray<LGRow *> *rows;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) LGState state;
@end

@implementation LGMenuMorph

+ (BOOL)isActive { return gSession && gSession.state != LGStDone; }
+ (UIView *)activeContainer { return gSession.container; }
+ (void)cancelAll { [gSession abort:@"cancelAll"]; }

+ (void)modalPresented {
    LGMenuMorph *m = gSession;
    if (!m || m.state == LGStDone) return;
    double age = CACurrentMediaTime() - m->_insideEndT;
    if (m->_insideEndT > 0 && age < 1.5 && (m.state == LGStOpening || m.state == LGStOpen)) {
        m->_skipClose = YES;
        LGLog(@"app present bảng khác %.2f s sau khi chạm mục menu -> sẽ bỏ animation đóng", age);
    }
}

+ (void)beginWithContainer:(UIView *)container body:(UIView *)body sources:(NSArray<UIView *> *)sources fallbackRect:(CGRect)fb {
    if (gSession) {
        if (gSession.container == container) return;
        [gSession abort:@"có menu mới xuất hiện"];
    }
    LGMenuMorph *m = [LGMenuMorph new];
    if (![m setupContainer:container body:body sources:sources fallback:fb]) { LGLog(@"setup thất bại -> bỏ qua morph"); return; }
    gSession = m;
    [m start];
}

// ---------------------------------------------------------------- chuẩn bị (chưa đổi gì nhìn thấy được)
- (BOOL)setupContainer:(UIView *)container body:(UIView *)body sources:(NSArray<UIView *> *)sources fallback:(CGRect)fb {
    UIWindow *win = body.window;
    UIView *host = body.superview;
    if (!win || !host) return NO;
    self.container = container;
    self.body = body;
    self.state = LGStOpening;
    self.rows = [NSMutableArray new];
    self.iconSnaps = [NSMutableArray new];

    LGStrip(body);
    if (!CGAffineTransformIsIdentity(body.transform)) {
        LGLog(@"body.transform != identity (%@) -> đặt lại", NSStringFromCGAffineTransform(body.transform));
        body.transform = CGAffineTransformIdentity;
    }
    [body layoutIfNeeded];
    _bodySize = body.bounds.size;
    if (_bodySize.width < 20 || _bodySize.height < 20) return NO;
    CGRect F0 = LGWinRect(body);

    CGRect src = CGRectNull;
    NSMutableArray<UIView *> *srcs = [NSMutableArray new];
    for (UIView *v in sources) {
        if (!v.window) continue;
        CGRect r = LGSrcRect(v);     // khung NHÌN THẤY (căn theo icon/chữ + đệm + cách lề) — trùng với vòng cố định
        if (CGRectIsEmpty(r) || r.size.width > 200 || r.size.height > 100) continue;
        src = CGRectUnion(src, r);
        [srcs addObject:v];
    }
    if (CGRectIsNull(src) || CGRectIsEmpty(src)) {
        if (CGRectIsEmpty(fb)) return NO;
        src = fb;
    }
    self.sources = srcs;
    _src = src;

    CGRect scr = win.bounds;
    LGPlan pl = LGPlanGeometry(LGBoxOf(src), LGBoxOf(F0), LGBoxOf(scr), LGP.coverButton);
    _F = CGRectOffset(F0, pl.dx, pl.dy);

    _spec = (LGTimeSpec){ LGP.omega, LGP.offsetDelay, LGP.contentDelay, LGP.dotOmega, LGP.dotDelay,
                          LGP.radOmega, LGP.radDelay, LGP.blend, LGP.dur, LGP.style, LGP.liquidDrop };
    if (LGP.style == 1) _spec.dur = 0.36;      // kiểu Liquid lắng xuống nhanh hơn (đo từ video)
    double maxR = fmin(_F.size.width, _F.size.height) / 2;
    _geom = (LGTimeGeom){ _F.size.width, _F.size.height, pl.ax, pl.ay, pl.a0x, pl.a0y, pl.a1x, pl.a1y,
                          LGCornerOf(body, container, maxR), LGBoxOf(src) };

    // hướng nảy khi đóng: menu neo ở góc (ax, ay) và mở về phía đối diện, nên nảy về phía ngoài góc neo
    // (neo trên-phải -> menu mở xuống dưới-trái -> nảy lên trên-phải)
    _bdir = CGPointMake((pl.ax >= 0.5 ? 1.0 : -1.0) * M_SQRT1_2, (pl.ay >= 0.5 ? 1.0 : -1.0) * M_SQRT1_2);

    // nội dung
    NSMutableArray<UILabel *> *labels = [NSMutableArray new];
    LGLabels(body, labels);
    UIView *content = labels.count ? LGLCAOf(labels) : nil;
    if (!content || content == container) content = body;
    self.content = content;
    _labelSig = LGLabelSig(body);

    LGLog(@"BẮT ĐẦU container=%s body=%s content=%s", object_getClassName(container), object_getClassName(body), object_getClassName(content));
    LGLog(@"  nút/viên thuốc=%@ (%lu view)  menu=%@ -> dời (%+.1f,%+.1f) F=%@", NSStringFromCGRect(src), (unsigned long)srcs.count,
          NSStringFromCGRect(F0), pl.dx, pl.dy, NSStringFromCGRect(_F));
    LGLog(@"  neo=(%.0f,%.0f) a0=(%.1f,%.1f) a1=(%.1f,%.1f) bo góc cuối=%.1f dur=%.3f closeDur=%.3f", pl.ax, pl.ay, pl.a0x, pl.a0y, pl.a1x, pl.a1y,
          _geom.rFinal, _spec.dur, LGP.closeDur);

    [self buildOverlayFor:win];
    [self buildContent];
    return YES;
}

- (UIVisualEffect *)makeEffect {
    if (LGP.useGlass) {
        Class g = NSClassFromString(@"UIGlassEffect");   // iOS 26+
        if (g) {
            id e = [g new];
            if ([e isKindOfClass:UIVisualEffect.class]) return e;
        }
    }
    if (LGP.material < 0) {
        UIVisualEffectView *real = self.body ? LGFindFX(self.body, 0) : nil;
        if (!real && self.container) real = LGFindFX(self.container, 0);
        LGLog(@"  nền thật: %s effect=%@", real ? object_getClassName(real) : "(không có UIVisualEffectView)", real.effect);
        if (real.effect) return real.effect;
    }
    UIBlurEffectStyle styles[5] = { UIBlurEffectStyleSystemUltraThinMaterial, UIBlurEffectStyleSystemThinMaterial, UIBlurEffectStyleSystemMaterial,
                                    UIBlurEffectStyleSystemThickMaterial, UIBlurEffectStyleSystemChromeMaterial };
    int i = LGP.material >= 0 && LGP.material <= 4 ? LGP.material : 4;
    return [UIBlurEffect effectWithStyle:styles[i]];
}

- (void)buildOverlayFor:(UIWindow *)win {
    UIView *ow = LGMakeOverlay(win);
    self.ow = ow;

    _R = CGRectInset(CGRectUnion(_F, _src), -56, -56);
    UIView *reg = [[UIView alloc] initWithFrame:_R];
    reg.userInteractionEnabled = NO;
    reg.backgroundColor = UIColor.clearColor;
    [ow addSubview:reg];
    self.reg = reg;
    UITraitCollection *tc = win.traitCollection;

    // 1) bóng (chỉ phần ngoài hình dạng: mask even-odd)
    CAShapeLayer *sh = [CAShapeLayer layer];
    sh.frame = reg.bounds;
    sh.fillColor = nil;
    sh.shadowColor = UIColor.blackColor.CGColor;
    sh.shadowOpacity = (float)LGP.shadow;
    sh.shadowRadius = 16;
    sh.shadowOffset = CGSizeMake(0, 6);
    CAShapeLayer *shm = [CAShapeLayer layer];
    shm.frame = reg.bounds;
    shm.fillColor = UIColor.blackColor.CGColor;
    shm.fillRule = kCAFillRuleEvenOdd;
    sh.mask = shm;
    [reg.layer addSublayer:sh];
    self.shadowL = sh;
    self.shadowMask = shm;

    // 2) nền kính: mask đặt thẳng lên UIVisualEffectView (tổ tiên có mask làm hiệu ứng hỏng)
    UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:[self makeEffect]];
    fx.frame = reg.bounds;
    fx.userInteractionEnabled = NO;
    CAShapeLayer *fm = [CAShapeLayer layer];
    fm.frame = reg.bounds;
    fm.fillColor = UIColor.blackColor.CGColor;
    fx.layer.mask = fm;
    [reg addSubview:fx];
    self.fx = fx;
    self.fxMask = fm;

    // 3) lớp phủ màu nhẹ để nhìn thấy khối kính trên nền trắng
    CAShapeLayer *tl = [CAShapeLayer layer];
    tl.frame = reg.bounds;
    tl.fillColor = [[UIColor.secondarySystemBackgroundColor resolvedColorWithTraitCollection:tc] colorWithAlphaComponent:LGP.tint].CGColor;
    [reg.layer addSublayer:tl];
    self.tintL = tl;

    // 4) nội dung (từng hàng, ảnh chụp thật, icon nút), cắt theo hình dạng
    UIView *clip = [[UIView alloc] initWithFrame:reg.bounds];
    clip.userInteractionEnabled = NO;
    clip.backgroundColor = UIColor.clearColor;
    CAShapeLayer *cm = [CAShapeLayer layer];
    cm.frame = reg.bounds;
    cm.fillColor = UIColor.blackColor.CGColor;
    clip.layer.mask = cm;
    [reg addSubview:clip];
    self.clip = clip;
    self.clipMask = cm;

    // 5) viền mảnh
    CAShapeLayer *rl = [CAShapeLayer layer];
    rl.frame = reg.bounds;
    rl.fillColor = nil;
    rl.lineWidth = 0.8;
    rl.strokeColor = [[UIColor.labelColor resolvedColorWithTraitCollection:tc] colorWithAlphaComponent:LGP.rim].CGColor;
    [reg.layer addSublayer:rl];
    self.rimL = rl;
}

// Ảnh toàn bộ nội dung menu thật (không gồm nền kính), đặt đúng khung cuối trong hệ toạ độ của `clip`.
- (UIView *)contentImageView {
    UIView *content = self.content;
    if (!content) return nil;
    CGFloat scale = content.window.screen.scale ?: UIScreen.mainScreen.scale;
    UIImage *img = LGImageOf(content, scale);
    if (!img) return nil;
    LGLog(@"  ảnh toàn bộ nội dung %@ mực=%.3f", NSStringFromCGSize(content.bounds.size), LGInk(img));
    UIImageView *iv = [[UIImageView alloc] initWithImage:img];
    iv.userInteractionEnabled = NO;
    iv.alpha = 0;
    return iv;
}

// Chụp nội dung thật (hàng, ảnh toàn bộ). Không cần menu đang hiện trên màn hình (chụp bằng CPU).
- (void)buildContent {
    UIView *body = self.body, *content = self.content;
    if (!body || !content) return;
    CGFloat scale = body.window.screen.scale ?: UIScreen.mainScreen.scale;

    // ảnh toàn bộ nội dung: dùng để bàn giao sang menu thật không bị giật (và làm khung đầu của lúc đóng)
    [body layoutIfNeeded];
    UIView *snap = [self contentImageView];
    [self.fullSnap removeFromSuperview];
    self.fullSnap = snap;
    CGRect bodyW = LGWinRect(body);
    CGPoint off = CGPointMake(_F.origin.x - bodyW.origin.x, _F.origin.y - bodyW.origin.y);
    CGRect cw = LGWinRect(content);
    _contentF = CGRectOffset(cw, off.x, off.y);
    if (snap) {
        snap.frame = CGRectOffset(_contentF, -_R.origin.x, -_R.origin.y);
        snap.alpha = 0;
        [self.clip addSubview:snap];
    }

    // từng hàng
    for (LGRow *r in self.rows) [r.holder removeFromSuperlayer];
    [self.rows removeAllObjects];
    for (UIView *v in LGRowViews(body, content)) {
        CGRect rv = LGRowVisual(v);
        UIImage *img = LGImageOfRect(v, rv, scale);
        if (!img.CGImage) continue;
        double ink = LGInk(img);
        if (ink < 0.0005) LGLog(@"  ẢNH HÀNG TRỐNG (%s %@)", object_getClassName(v), NSStringFromCGSize(v.bounds.size));
        LGRow *row = [LGRow new];
        row.rect = CGRectOffset([v convertRect:rv toView:nil], off.x, off.y);
        CALayer *h = [CALayer layer];
        h.bounds = CGRectMake(0, 0, row.rect.size.width, row.rect.size.height);
        h.hidden = YES;
        CALayer *s = [CALayer layer];
        s.frame = h.bounds;
        s.contents = (__bridge id)img.CGImage;
        s.contentsScale = img.scale;
        [h addSublayer:s];
        row.sharp = s;
        if (LGP.blurText) {
            UIImage *bl = LGBlurred(img, 3.0);
            if (bl.CGImage) {
                CALayer *b = [CALayer layer];
                b.frame = h.bounds;
                b.contents = (__bridge id)bl.CGImage;
                b.contentsScale = bl.scale;
                b.opacity = 0;
                [h addSublayer:b];
                row.blur = b;
            }
        }
        row.holder = h;
        [self.clip.layer insertSublayer:h atIndex:0];   // dưới fullSnap và icon
        [self.rows addObject:row];
    }
    LGLog(@"  nội dung: %lu hàng, ảnh toàn bộ=%@ contentF=%@", (unsigned long)self.rows.count, snap ? @"có" : @"KHÔNG", NSStringFromCGRect(_contentF));
}

// ---------------------------------------------------------------- bắt đầu (đổi thứ nhìn thấy được)
- (void)start {
    UIView *body = self.body;
    // vòng cố định quanh nút: ẩn trong suốt phiên (lớp phủ tự vẽ lại đúng hình đó); ẩn TRƯỚC khi chụp icon
    // để ảnh chụp không dính vòng (có vòng thì phải chờ cập nhật màn hình mới chụp được trạng thái mới).
    BOOL hadRing = LGRingHide(self.sources, YES);
    // icon các nút nguồn: chụp trước khi ẩn
    for (UIView *v in self.sources) {
        UIView *s = [v snapshotViewAfterScreenUpdates:hadRing];
        if (s) {
            s.frame = CGRectOffset(LGWinRect(v), -_R.origin.x, -_R.origin.y);
            [self.clip addSubview:s];
            [self.iconSnaps addObject:s];
        }
    }
    // dời menu thật tới chỗ đã tính (đè lên nút) rồi ẩn: lớp phủ của ta thay thế nó trong lúc morph
    [self pinBody];
    body.hidden = YES;
    self.container.layer.hidden = NO;     // Tweak.x đã ẩn container ngay lúc nó xuất hiện (để không lộ menu hệ thống); từ giờ chỉ ẩn thân menu
    if (LGP.hideSource) {
        self.srcAlpha = [NSMutableArray new];
        for (UIView *v in self.sources) {
            // nút đang được nhấn thì alpha tạm bị làm mờ: khi trả lại phải là 1, không phải giá trị mờ đó
            BOOL pressed = [v isKindOfClass:UIControl.class] && ((UIControl *)v).highlighted;
            [self.srcAlpha addObject:@((v.alpha < 0.05 || pressed) ? 1.0 : v.alpha)];
            LGLog(@"  ẩn nút %s alpha=%.2f highlighted=%d", object_getClassName(v), v.alpha, (int)pressed);
            [v.layer removeAllAnimations];
            v.alpha = 0;
        }
    }
    _tau = 0;
    [self renderAt:0];
    LGOverlayShow(self.ow);
    _lastT = CACurrentMediaTime();
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    LGLog(@"  morph bắt đầu; body sau khi dời: rect=%@ anchorPoint=%@ F=%@ cửa sổ menu level=%.0f", NSStringFromCGRect(LGWinRect(body)),
          NSStringFromCGPoint(body.layer.anchorPoint), NSStringFromCGRect(_F), (double)body.window.windowLevel);
    if (LGP.dump) {
        // ghi cây view SAU khung hình đầu để không làm chậm animation (thân menu hiện đang HIDDEN do ta ẩn)
        __weak LGMenuMorph *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            LGMenuMorph *m = weakSelf;
            if (!m || !m.container) return;
            LGLogTree(@"menu (container) - thân đã bị ta ẩn", m.container);
            UIView *s0 = m.sources.firstObject;
            if (s0) LGLogTree(@"nút nguồn (cha của nút)", s0.superview ?: s0);
        });
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ LGLogClassesOnce(); });
    }
}

// ---------------------------------------------------------------- khung hình
- (void)renderAt:(double)tau {
    LGTimeFrame f = LGTimelineAt(&_spec, &_geom, tau);
    CGPathRef P = LGShapePath(&f, _R.origin.x, _R.origin.y);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyPath:P];

    for (UIView *s in self.iconSnaps) s.alpha = (CGFloat)f.iconAlpha;
    self.fullSnap.alpha = (CGFloat)f.full;

    BOOL show = f.op >= 0.01 && f.body.w >= 90 && f.body.h > 1;
    double pc = fmax(f.pc, 0.001);
    double bcx = f.body.x + f.body.w / 2;
    double ay = f.rowAy;
    double anchorY = f.body.y + ay * f.body.h;
    double fcx = CGRectGetMidX(_F);
    for (LGRow *r in self.rows) {
        r.holder.hidden = !show;
        if (!show) continue;
        // hàng giữ nguyên khoảng cách tới điểm neo của thân, và nằm chính giữa bề rộng thân hiện tại (như bản Flutter)
        double cx = bcx + (CGRectGetMidX(r.rect) - fcx) * f.rowK - _R.origin.x;
        double cy = anchorY + (CGRectGetMidY(r.rect) - f.rowA1y) * f.rowK - _R.origin.y;
        r.holder.position = CGPointMake(cx, cy);
        r.holder.transform = CATransform3DMakeScale(pc, pc, 1);
        double all = f.op * (1 - f.full);
        if (r.blur) {
            r.sharp.opacity = (float)(all * (1 - f.blurMix));
            r.blur.opacity = (float)(all * f.blurMix);
        } else {
            r.sharp.opacity = (float)all;
        }
    }
    [CATransaction commit];
    CGPathRelease(P);
}

// Gán đường viền cho mọi lớp tạo nên khối kính (gọi bên trong CATransaction đã tắt action).
- (void)applyPath:(CGPathRef)P {
    CGMutablePathRef outside = CGPathCreateMutable();
    CGPathAddRect(outside, NULL, self.reg.bounds);
    CGPathAddPath(outside, NULL, P);
    self.fxMask.path = P;
    self.tintL.path = P;
    self.clipMask.path = P;
    self.rimL.path = P;
    self.shadowL.shadowPath = P;
    self.shadowMask.path = outside;
    CGPathRelease(outside);
}

// Khung hình của pha NẢY: viên kính (hình xuất phát = nút/viên thuốc) + icon trượt chéo theo lò xo rồi về đúng chỗ nút.
- (void)renderBounce:(double)t {
    double a = LGP.bounceAmp * lgtl_bounce(t, LGP.bounceOmega, LGP.bounceZeta);
    double dx = _bdir.x * a, dy = _bdir.y * a;
    LGTimeFrame f = LGTimelineAt(&_spec, &_geom, 0);          // tau = 0: chỉ còn viên kính của nút
    CGPathRef P = LGShapePath(&f, _R.origin.x - dx, _R.origin.y - dy);   // gốc lệch (-dx,-dy) => hình dời (+dx,+dy)
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self applyPath:P];
    for (UIView *s in self.iconSnaps) {
        s.alpha = 1;
        s.transform = CGAffineTransformMakeTranslation((CGFloat)dx, (CGFloat)dy);
    }
    self.fullSnap.alpha = 0;
    for (LGRow *r in self.rows) r.holder.hidden = YES;
    [CATransaction commit];
    CGPathRelease(P);
}

// ---------------------------------------------------------------- đồng hồ
- (void)tick:(CADisplayLink *)l {
    @try { [self tickImpl:l]; }
    @catch (NSException *ex) { LGLog(@"NGOẠI LỆ trong tick: %@ %@", ex.name, ex.reason); [self abort:@"ngoại lệ"]; }
}

- (void)tickImpl:(CADisplayLink *)l {
    if (self != gSession) { [l invalidate]; return; }
    CFTimeInterval now = CACurrentMediaTime();
    double dt = fmin(fmax(now - _lastT, 0), 0.05);
    _lastT = now;
    _ticks++;
    BOOL alive = self.container.window && self.body.window;
    if (self.state != LGStSettling) [self keepSourcesHidden];

    switch (self.state) {
        case LGStOpening:
            if (!alive) { [self startClose:@"menu biến mất khi đang mở"]; return; }
            _tau += dt * LGP.speed;
            [self pinBody];
            if (_tau >= _spec.dur) {
                // vừa mở xong mà hệ thống đã đang đóng menu (người dùng ấn trong lúc mở): KHÔNG trả menu thật (sẽ lộ cả dòng kẻ phân cách) mà đóng tiếp luôn
                if ([self systemDismissing]) { _tau = _spec.dur; [self renderAt:_tau]; [self startClose:@"hệ thống đã đóng khi vừa mở xong"]; return; }
                [self finishOpen];
                return;
            }
            [self renderAt:_tau];
            break;
        case LGStOpen:
            if (!alive) { [self startClose:@"menu bị gỡ khỏi window"]; return; }
            if ([self systemDismissing]) {
                // menu mở ra bảng khác (bảng chọn tệp...) thì menu thật nằm lại khá lâu rồi mới đóng: chạy animation đóng ở lúc đó trông rất lạ -> bỏ
                double age = now - _insideEndT;
                if (_skipClose || (_insideEndT > 0 && age > 0.45 && age < 4.0)) {
                    LGLog(@"BỎ animation đóng: %@ (nhả tay trong menu cách đây %.2f s)", _skipClose ? @"app vừa present bảng khác" : @"menu đóng muộn bất thường", age);
                    self.body.hidden = NO;
                    [self finishAll:@"bỏ animation đóng (menu mở ra thứ khác)"];
                    return;
                }
                [self startClose:@"hệ thống đang đóng menu"];
                return;
            }
            [self checkContent];
            [self pinBody];
            break;
        case LGStClosing:
            _tau -= dt * LGP.speed * _spec.dur / LGP.closeDur;
            if (_tau <= 0) { [self finishClose]; return; }
            [self renderAt:_tau];
            break;
        case LGStBouncing:
            _bt += dt * LGP.speed;
            if (_bt >= _bdur) { [self settleAfterClose]; return; }
            [self renderBounce:_bt];
            break;
        case LGStSettling: {
            if (!self.container.window) { [self finishAll:@"menu đã gỡ hẳn"]; return; }
            double a, sc;
            [self measureAlpha:&a scale:&sc];
            // menu vẫn nằm trong window nhưng đã mờ hẳn (hệ thống không gỡ mà chỉ ẩn) = đã đóng
            if (a < 0.05) { [self finishAll:@"menu đã mờ hẳn (còn trong window)"]; return; }
            if (now - _settleT > 0.7) { [self resumeOpen]; return; }
            break;
        }
        case LGStDone:
            [l invalidate];
            break;
    }
}

- (void)keepSourcesHidden {
    if (!LGP.hideSource) return;
    for (UIView *v in self.sources) {
        CALayer *pl = v.layer.presentationLayer;
        if (v.alpha > 0.001 || (pl && pl.opacity > 0.01)) {
            [v.layer removeAllAnimations];
            v.alpha = 0;
        }
    }
}

- (void)restoreSources {
    LGRingHide(self.sources, NO);     // vòng cố định hiện lại cùng lúc nút được trả
    if (!LGP.hideSource) return;
    for (NSUInteger i = 0; i < self.sources.count && i < self.srcAlpha.count; i++) self.sources[i].alpha = (CGFloat)self.srcAlpha[i].doubleValue;
}

// Giữ menu thật đúng chỗ đã dời (hệ thống có thể đặt lại vị trí khi chạm / kéo).
- (void)pinBody {
    UIView *b = self.body;
    UIView *host = b.superview;
    if (!b || !host) return;
    // b.center = layer.position = vị trí của ĐIỂM NEO (anchorPoint) chứ không nhất thiết là tâm hình học:
    // hệ thống có thể đặt anchorPoint ở góc (vd (1,0)) để menu bung ra từ góc. Vì vậy so điểm neo với điểm neo.
    CGPoint ap = b.layer.anchorPoint;
    CGPoint cur = [host convertPoint:b.center toView:nil];
    CGPoint tgt = CGPointMake(_F.origin.x + ap.x * _F.size.width, _F.origin.y + ap.y * _F.size.height);
    double dx = tgt.x - cur.x, dy = tgt.y - cur.y;
    if (fabs(dx) < 0.5 && fabs(dy) < 0.5) return;
    CGPoint a = [host convertPoint:CGPointZero fromView:nil];
    CGPoint c = [host convertPoint:CGPointMake(dx, dy) fromView:nil];
    b.center = CGPointMake(b.center.x + (c.x - a.x), b.center.y + (c.y - a.y));
    _pinFix++;
    if (_pinFix <= 6 || _pinFix % 120 == 0)
        LGLog(@"pin: lệch (%+.1f,%+.1f) -> chỉnh lại (lần %d, state=%ld) anchorPoint=%@ F=%@ rect thật sau chỉnh=%@", dx, dy, _pinFix,
              (long)self.state, NSStringFromCGPoint(ap), NSStringFromCGRect(_F), NSStringFromCGRect(LGWinRect(b)));
}

// Nội dung menu đổi (vd mở menu con): ghi log + chụp lại, cập nhật khung cho lúc đóng.
- (void)checkContent {
    if (_ticks % 3) return;
    UIView *b = self.body;
    if (!b) return;
    NSString *sig = LGLabelSig(b);
    CGSize sz = b.bounds.size;
    BOOL sizeChanged = fabs(sz.width - _bodySize.width) > 1 || fabs(sz.height - _bodySize.height) > 1;
    if ([sig isEqualToString:_labelSig] && !sizeChanged) return;
    LGLog(@"NỘI DUNG ĐỔI: size %@ -> %@, chữ: %@", NSStringFromCGSize(_bodySize), NSStringFromCGSize(sz), sig);
    _bodySize = sz;
    _labelSig = sig;
    CGPoint ap = b.layer.anchorPoint;
    CGPoint cur = [b.superview convertPoint:b.center toView:nil];
    _F = CGRectMake(cur.x - ap.x * sz.width, cur.y - ap.y * sz.height, sz.width, sz.height);
    _geom.W = sz.width;
    _geom.H = sz.height;
    _geom.a1x = _F.origin.x + _geom.ax * _F.size.width;
    _geom.a1y = _F.origin.y + _geom.ay * _F.size.height;
    [b layoutIfNeeded];
    NSMutableArray<UILabel *> *labels = [NSMutableArray new];
    LGLabels(b, labels);
    UIView *content = labels.count ? LGLCAOf(labels) : nil;
    if (!content || content == self.container) content = b;
    self.content = content;
    [self buildContent];
    if (LGP.dump) LGLogTree(@"menu sau khi đổi nội dung", self.container);
    [self captureBaseline];
}

// ---------------------------------------------------------------- phát hiện hệ thống đóng menu
- (void)measureAlpha:(double *)aOut scale:(double *)sOut {
    double minA = 1, minS = 1;
    for (UIView *v = self.body; v && ![v isKindOfClass:UIWindow.class]; v = v.superview) {
        CALayer *pl = v.layer.presentationLayer ?: v.layer;
        double al = fmin((double)pl.opacity, (double)v.alpha);
        if (v.hidden && v != self.body) al = 0;     // body.hidden do chính ta điều khiển nên không tính
        minA = fmin(minA, al);
        CGAffineTransform t = pl.affineTransform;
        minS = fmin(minS, hypot(t.a, t.b));
    }
    *aOut = minA;
    *sOut = minS;
}

- (void)captureBaseline {
    [self measureAlpha:&_baseA scale:&_baseS];
}

- (NSUInteger)insideTouchCount {
    NSUInteger n = 0;
    for (UITouch *t in gTouches.keyEnumerator) if ([[gTouches objectForKey:t] boolValue]) n++;
    return n;
}

- (BOOL)systemDismissing {
    double a, s;
    [self measureAlpha:&a scale:&s];
    NSString *sig = [NSString stringWithFormat:@"A=%.2f S=%.2f", a, s];
    if (LGP.debug && ![sig isEqualToString:_lastWatch]) {
        LGLog(@"theo dõi: %@ (nền %.2f / %.2f)", sig, _baseA, _baseS);
        _lastWatch = sig;
    }
    if ([self insideTouchCount] > 0) return NO;
    return a < _baseA - 0.08 || s < _baseS - 0.04;
}

// ---------------------------------------------------------------- chuyển trạng thái
- (void)finishOpen {
    _tau = _spec.dur;
    [self renderAt:_tau];
    self.body.hidden = NO;       // cùng một khung hình: lớp phủ tắt, menu thật hiện
    self.ow.hidden = YES;
    self.state = LGStOpen;
    [self captureBaseline];
    LGLog(@"MỞ XONG (menu thật hiện lại) nền A=%.2f S=%.2f pin=%d", _baseA, _baseS, _pinFix);
}

- (void)startClose:(NSString *)why {
    if (self.state != LGStOpening && self.state != LGStOpen) return;
    LGLog(@"ĐÓNG: %@ (tau=%.3f)", why, _tau);
    if (!LGP.closeAnim || !self.ow) { [self finishClose]; return; }
    if (self.state == LGStOpen) {
        _tau = _spec.dur;
        [self renderAt:_tau];
        LGOverlayShow(self.ow);
    }
    self.body.hidden = YES;      // (menu thật đang bị hệ thống đóng, lớp phủ của ta thay thế nó)
    self.state = LGStClosing;
    _lastT = CACurrentMediaTime();
}

// Hết animation đóng: nếu bật thì NẢY chéo trước, rồi mới trả nút. Gọi từ startClose (khi không có animation) thì bỏ qua nảy.
- (void)finishClose {
    if (LGP.bounce && LGP.bounceAmp > 0.01 && self.ow && self.state == LGStClosing) { [self startBounce]; return; }
    [self settleAfterClose];
}

- (void)startBounce {
    _bt = 0;
    _bdur = lgtl_bounce_dur(LGP.bounceOmega, LGP.bounceZeta, LGP.bounceAmp);
    self.state = LGStBouncing;
    _lastT = CACurrentMediaTime();
    LGLog(@"NẢY: hướng (%+.2f,%+.2f) biên độ=%.1f pt omega=%.1f zeta=%.2f dur=%.3f", _bdir.x, _bdir.y, LGP.bounceAmp, LGP.bounceOmega, LGP.bounceZeta, _bdur);
    [self renderBounce:0];
}

- (void)settleAfterClose {
    [self restoreSources];
    self.ow.hidden = YES;
    self.state = LGStSettling;
    _settleT = CACurrentMediaTime();
    LGLog(@"ĐÓNG XONG (trả lại nút), container %@", self.container.window ? @"còn trong window (chờ hệ thống gỡ)" : @"đã gỡ");
    if (!self.container.window) [self finishAll:@"menu đã gỡ"];
}

// Hệ thống không gỡ menu sau khi ta đóng xong (chạm ngoài mà menu vẫn mở): trả menu lại như cũ.
- (void)resumeOpen {
    UIView *b = self.body;
    LGLog(@"menu vẫn còn sau %.1f s -> khôi phục trạng thái mở", CACurrentMediaTime() - _settleT);
    if (!b || !b.window) { [self finishAll:@"không còn menu"]; return; }
    double a, sc;
    [self measureAlpha:&a scale:&sc];
    if (a < 0.5) {     // menu còn trong cây view nhưng không nhìn thấy: không được ẩn nút nữa
        [self finishAll:[NSString stringWithFormat:@"menu còn trong window nhưng mờ (alpha=%.2f)", a]];
        return;
    }
    if (LGP.hideSource) {
        for (UIView *v in self.sources) { [v.layer removeAllAnimations]; v.alpha = 0; }
    }
    LGRingHide(self.sources, YES);
    b.hidden = NO;
    [self pinBody];
    self.state = LGStOpen;
    [self captureBaseline];
}

- (void)finishAll:(NSString *)why {
    if (self.state == LGStDone) return;
    LGLog(@"KẾT THÚC phiên: %@", why);
    [self.link invalidate];
    self.link = nil;
    [self restoreSources];
    LGOverlayDrop(self.ow);
    self.ow = nil;
    self.reg = nil;
    self.state = LGStDone;
    [gTouches removeAllObjects];
    if (gSession == self) gSession = nil;
}

// Dừng ngay không animation, trả mọi thứ về nguyên trạng.
- (void)abort:(NSString *)why {
    if (self.state == LGStDone) return;
    LGLog(@"HỦY phiên: %@ (state=%ld)", why, (long)self.state);
    if (self.state == LGStOpening || self.state == LGStOpen) self.body.hidden = NO;
    [self finishAll:why];
}

// ---------------------------------------------------------------- chạm
+ (void)touch:(UITouch *)t {
    LGMenuMorph *m = gSession;
    if (!m || m.state == LGStDone) return;
    @try { [m handleTouch:t]; }
    @catch (NSException *ex) { LGLog(@"NGOẠI LỆ trong handleTouch: %@ %@", ex.name, ex.reason); [m abort:@"ngoại lệ"]; }
}

- (void)handleTouch:(UITouch *)t {
    if (!gTouches) gTouches = [NSMapTable weakToStrongObjectsMapTable];
    CGPoint p = [t locationInView:nil];
    switch (t.phase) {
        case UITouchPhaseBegan: {
            BOOL inside = CGRectContainsPoint(_F, p);
            [gTouches setObject:@(inside) forKey:t];
            LGLog(@"chạm xuống %@ (%@) state=%ld", NSStringFromCGPoint(p), inside ? @"trong menu" : @"ngoài menu", (long)self.state);
            if (self.state == LGStOpen && self.container.window && self.content.window && ![self systemDismissing]) {
                // chụp lại nội dung đúng lúc này (trước khi hệ thống kịp đóng) để dùng làm khung đầu của animation đóng
                UIView *s = [self contentImageView];
                if (s) {
                    [self.fullSnap removeFromSuperview];
                    s.frame = CGRectOffset(_contentF, -_R.origin.x, -_R.origin.y);
                    [self.clip addSubview:s];
                    self.fullSnap = s;
                }
            }
            break;
        }
        case UITouchPhaseEnded:
        case UITouchPhaseCancelled: {
            NSNumber *was = [gTouches objectForKey:t];
            [gTouches removeObjectForKey:t];
            if (!was) break;
            LGLog(@"chạm lên %@ (bắt đầu %@) phase=%ld", NSStringFromCGPoint(p), was.boolValue ? @"trong menu" : @"ngoài menu", (long)t.phase);
            if (was.boolValue) _insideEndT = CACurrentMediaTime();
            if (self.state == LGStOpening && t.phase == UITouchPhaseEnded) {
                // ấn trong lúc đang mở (menu thật đang bị ẩn nên không có mục nào nhận được cú ấn): đảo ngược animation từ khung hình hiện tại
                [self startClose:@"chạm khi đang mở"];
                break;
            }
            if (!was.boolValue && t.phase == UITouchPhaseEnded) [self startClose:@"chạm ngoài menu"];
            break;
        }
        default: break;
    }
}

@end
