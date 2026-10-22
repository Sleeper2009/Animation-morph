#import "LGRing.h"
#import "LGMenuMorph.h"
#import "LGLog.h"
#import <objc/runtime.h>
#include "LGTimeline.h"

static const void *kRingKey = &kRingKey;
static const void *kBBoxKey = &kBBoxKey;     // bộ nhớ đệm bbox điểm ảnh của nút tự vẽ nội dung

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

BOOL LGHasMenuInteraction(UIView *v) { return v && LGHasMenu(v); }

// Nút "quay lại" của thanh điều hướng: UIKit đặt accessibilityIdentifier = "BackButton" (lớp ngoài), và/hoặc tên class có "Back".
BOOL LGIsBackButton(UIView *v) {
    int n = 0;
    for (UIView *c = v; c && n < 4; c = c.superview, n++) {
        if ([c.accessibilityIdentifier isEqualToString:@"BackButton"]) return YES;
        if (strstr(object_getClassName(c), "Back") != NULL) return YES;
    }
    return NO;
}

// forRing = YES: dùng cho vòng cố định (tôn trọng công tắc ringBack); NO: dùng cho hiệu ứng ấn.
static BOOL LGRingBase(UIView *v, BOOL forRing) {
    if (!LGButtonLike(v) || v.hidden) return NO;
    CGSize s = v.bounds.size;
    if (s.width >= 120 || s.height >= 80) return NO;
    if (forRing && !LGP.ringBack && LGIsBackButton(v)) return NO;
    return LGHasMenu(v) || (LGP.ringAll && [v isKindOfClass:UIButton.class]);
}

static BOOL LGDescHasCandidate(UIView *v, int depth, BOOL forRing) {
    if (depth > 3) return NO;
    for (UIView *s in v.subviews)
        if (LGRingBase(s, forRing) || LGDescHasCandidate(s, depth + 1, forRing)) return YES;
    return NO;
}

BOOL LGRingIsCandidate(UIView *v) {
    return v && LGRingBase(v, YES) && !LGDescHasCandidate(v, 0, YES);
}

BOOL LGPressIsCandidate(UIView *v) {
    return v && LGRingBase(v, NO) && !LGDescHasCandidate(v, 0, NO);
}

// ------------------------------------------------------------------ lớp phủ (cửa sổ riêng hoặc view trong cửa sổ)
// Trong extension / remote view service (đuôi .appex, vd bảng chọn tệp) UIWindow riêng KHÔNG được hiển thị (nút bị ẩn mà không thấy lớp phủ đâu),
// nên ở đó dùng một view phủ kín ngay trong cửa sổ của menu / của nút, luôn đưa lên trên cùng.
UIView *LGMakeOverlay(UIWindow *win) {
    BOOL ext = [NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"appex"];
    BOOL asView = LGP.overlayMode == 2 || (LGP.overlayMode == 0 && ext);
    if (asView) {
        UIView *ov = [[UIView alloc] initWithFrame:win.bounds];
        ov.userInteractionEnabled = NO;
        ov.backgroundColor = UIColor.clearColor;
        ov.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        ov.hidden = YES;
        [win addSubview:ov];
        LGLog(@"lớp phủ: view trong cửa sổ %s (%@)", object_getClassName(win), ext ? @"extension" : @"theo overlayMode");
        return ov;
    }
    UIWindowScene *sc = win.windowScene;
    UIWindow *w = sc ? [[UIWindow alloc] initWithWindowScene:sc] : [[UIWindow alloc] initWithFrame:win.bounds];
    w.frame = win.frame;
    w.windowLevel = fmax(UIWindowLevelAlert + 100, win.windowLevel + 1);
    w.backgroundColor = UIColor.clearColor;
    w.userInteractionEnabled = NO;
    return w;
}

void LGOverlayShow(UIView *ov) {
    if (!ov) return;
    if (![ov isKindOfClass:UIWindow.class] && ov.superview) [ov.superview bringSubviewToFront:ov];
    ov.hidden = NO;
}

void LGOverlayDrop(UIView *ov) {
    if (!ov) return;
    ov.hidden = YES;
    if (![ov isKindOfClass:UIWindow.class]) [ov removeFromSuperview];
}

// ------------------------------------------------------------------ khung nhìn thấy của nút
// Gom khung các view con có nội dung thật (ảnh / chữ), bỏ qua vòng của ta.
static void LGCollect(UIView *v, int depth, CGRect *u, BOOL *text) {
    if (depth > 6) return;
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:LGRingView.class] || s.hidden || s.alpha < 0.05) continue;
        BOOL leaf = NO, isText = NO;
        if ([s isKindOfClass:UIImageView.class]) {
            UIImageView *iv = (UIImageView *)s;
            leaf = iv.image != nil || iv.highlightedImage != nil;
        } else if ([s isKindOfClass:UILabel.class]) {
            UILabel *l = (UILabel *)s;
            leaf = l.text.length > 0 || l.attributedText.length > 0;
            isText = leaf;
        }
        if (leaf) {
            CGRect r = [s convertRect:s.bounds toView:nil];
            if (r.size.width >= 2 && r.size.height >= 2 && r.size.width <= 200) {
                *u = CGRectUnion(*u, r);
                if (isText) *text = YES;
            }
        } else {
            LGCollect(s, depth + 1, u, text);
        }
    }
}

// Nút thanh điều hướng thường lồng nhau (_UIButtonBarButton > nút trong): tìm nội dung từ lớp NGOÀI CÙNG còn là nút nhỏ.
static UIView *LGSrcRoot(UIView *v) {
    UIView *root = v;
    while (root.superview && LGButtonLike(root.superview)) {
        CGSize a = root.bounds.size, b = root.superview.bounds.size;
        // chỉ leo khi lớp ngoài gần bằng lớp trong (vỏ của CÙNG một nút). Vỏ rộng hơn hẳn là vỏ chứa NHIỀU nút (vd Chia sẻ + "…"):
        // leo vào đó thì nội dung của cả hai gộp lại và vòng phình thành hình tròn to.
        if (b.width > a.width + 16 || b.height > a.height + 16 || b.width >= 120 || b.height >= 80) break;
        root = root.superview;
    }
    return root;
}

// Vùng nội dung nhìn thấy (toạ độ cửa sổ). Ưu tiên view con; nếu nút tự vẽ nội dung (không có ảnh/chữ con) thì đo bbox các điểm ảnh khác trong suốt.
static BOOL LGContentRect(UIView *v, CGRect *out, BOOL *text) {
    CGRect c = CGRectNull;
    BOOL t = NO;
    LGCollect(LGSrcRoot(v), 0, &c, &t);
    if (!CGRectIsNull(c) && !CGRectIsEmpty(c)) { *out = c; *text = t; return YES; }
    if (v.hidden || v.alpha < 0.05) return NO;
    CGSize sz = v.bounds.size;
    if (sz.width < 4 || sz.height < 4 || sz.width > 200 || sz.height > 100) return NO;
    // đo điểm ảnh khá tốn: nhớ kết quả (theo kích thước nút) 5 giây, bộ đếm giờ 10 Hz của vòng chỉ dùng lại kết quả
    NSDictionary *cache = objc_getAssociatedObject(v, kBBoxKey);
    NSString *szKey = NSStringFromCGSize(sz);
    if (cache && [cache[@"s"] isEqualToString:szKey] && CACurrentMediaTime() - [cache[@"t"] doubleValue] < 5.0) {
        NSValue *rv = cache[@"r"];
        if (!rv) return NO;
        *out = [v convertRect:rv.CGRectValue toView:nil];
        *text = out->size.width > out->size.height * 1.8;
        return YES;
    }
    const int S = 2;
    size_t w = (size_t)ceil(sz.width * S), h = (size_t)ceil(sz.height * S);
    uint8_t *buf = calloc(w * h, 1);
    if (!buf) return NO;
    CGContextRef g = CGBitmapContextCreate(buf, w, h, 8, w, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    if (!g) { free(buf); return NO; }
    CGContextTranslateCTM(g, 0, (CGFloat)h);
    CGContextScaleCTM(g, S, -S);
    [v.layer renderInContext:g];
    long x0 = (long)w, x1 = -1, y0 = (long)h, y1 = -1;
    for (size_t r = 0; r < h; r++)
        for (size_t col = 0; col < w; col++)
            if (buf[r * w + col] > 20) {
                if ((long)col < x0) x0 = (long)col;
                if ((long)col > x1) x1 = (long)col;
                if ((long)r < y0) y0 = (long)r;
                if ((long)r > y1) y1 = (long)r;
            }
    CGContextRelease(g);
    free(buf);
    if (x1 < x0 || y1 < y0) {
        objc_setAssociatedObject(v, kBBoxKey, @{ @"s": szKey, @"t": @(CACurrentMediaTime()) }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NO;
    }
    CGRect pr = CGRectMake(x0 / (CGFloat)S, y0 / (CGFloat)S, (x1 - x0 + 1) / (CGFloat)S, (y1 - y0 + 1) / (CGFloat)S);
    objc_setAssociatedObject(v, kBBoxKey, @{ @"s": szKey, @"t": @(CACurrentMediaTime()), @"r": [NSValue valueWithCGRect:pr] }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    *out = [v convertRect:pr toView:nil];
    *text = out->size.width > out->size.height * 1.8;     // không biết có chữ hay không: nội dung dẹt -> coi như chữ
    return YES;
}

CGRect LGSrcRect(UIView *v) {
    CGRect b = [v convertRect:v.bounds toView:nil];
    CGRect c;
    BOOL hasText = NO;
    if (!LGContentRect(v, &c, &hasText)) return b;       // không thấy nội dung: dùng khung nút
    double Wd = v.window ? v.window.bounds.size.width : 0;
    double H = fmin(fmax(b.size.height, 32), 48);
    double m = LGP.ringMargin, padX = LGP.ringPadX;
    CGRect r;
    if (hasText) {
        // nút chữ: viên thuốc = chữ + đệm hai bên; sát lề thì cắt bớt đệm phía lề, nhưng luôn chừa >= 4 pt quanh chữ
        double W = c.size.width + 2 * padX;
        r = CGRectMake(CGRectGetMidX(c) - W / 2, CGRectGetMidY(c) - H / 2, W, H);
        if (Wd > 0) {
            if (r.origin.x < m) { double d = m - r.origin.x; r.origin.x += d; r.size.width -= d; }
            if (CGRectGetMaxX(r) > Wd - m) r.size.width = Wd - m - r.origin.x;
        }
        r = CGRectUnion(r, CGRectInset(c, -4, 0));
    } else {
        // nút icon: hình tròn tâm đúng giữa icon (nội dung rộng thì viên thuốc, KHÔNG phình thành hình tròn to);
        // sát lề thì thu nhỏ đường kính (giữ nguyên tâm), nhưng không nhỏ hơn icon + 8 pt
        double cw = c.size.width, ch = c.size.height;
        double Hh = fmin(fmax(H, ch + 8), 56), W = fmax(Hh, cw + 12);
        if (W <= Hh + 0.5) {
            double D = Hh;
            if (Wd > 0) D = fmin(D, 2 * fmin(CGRectGetMidX(c) - m, Wd - m - CGRectGetMidX(c)));
            D = fmax(D, fmax(cw, ch) + 8);
            W = Hh = D;
        }
        r = CGRectMake(CGRectGetMidX(c) - W / 2, CGRectGetMidY(c) - Hh / 2, W, Hh);
        if (W > Hh + 0.5 && Wd > 0) {
            if (r.origin.x < m) { double d = m - r.origin.x; r.origin.x += d; r.size.width -= d; }
            if (CGRectGetMaxX(r) > Wd - m) r.size.width = Wd - m - r.origin.x;
            r = CGRectUnion(r, CGRectInset(c, -4, 0));
        }
    }
    return r;
}

// ------------------------------------------------------------------ dựng / cập nhật
// Vòng là view ANH EM nằm DƯỚI cùng của view cha (không phải view con của nút): view con của nút luôn vẽ đè lên nội dung riêng của nút
// (biểu tượng nút tự vẽ bị che mất). Vì không còn là con của nút nên không tự theo nút -> bộ đếm giờ 10 Hz đồng bộ khung/độ mờ.
static NSHashTable<UIView *> *gOwners;
static NSTimer *gTimer;
static void LGRingRefresh(UIView *v, int attempt, BOOL quiet);

static LGRingView *LGRingOf(UIView *v) { return objc_getAssociatedObject(v, kRingKey); }

static void LGRingRemove(UIView *v) {
    [gOwners removeObject:v];
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

// Độ mờ hiệu dụng từ view lên tới `stop` (không tính stop), theo trạng thái ĐANG chạy của animation (presentationLayer).
static CGFloat LGEffAlpha(UIView *v, UIView *stop) {
    CGFloat a = 1;
    for (UIView *cur = v; cur && cur != stop; cur = cur.superview) {
        if (cur.hidden) return 0;
        CALayer *pl = cur.layer.presentationLayer;
        a *= pl ? pl.opacity : cur.alpha;
    }
    return a;
}

static void LGRingTick(void) {
    for (UIView *o in gOwners.allObjects) {
        if (!o.window || !LGP.ring) { LGRingRemove(o); continue; }
        LGRingRefresh(o, 99, YES);
    }
    if (!gOwners.count) { [gTimer invalidate]; gTimer = nil; }
}

static void LGRingEnsureTimer(void) {
    if (gTimer) return;
    gTimer = [NSTimer timerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) { LGRingTick(); }];
    [NSRunLoop.mainRunLoop addTimer:gTimer forMode:NSRunLoopCommonModes];
}

static void LGRingRefresh(UIView *v, int attempt, BOOL quiet) {
    if (!v) return;
    if (!LGP.ring || !v.window || !LGRingIsCandidate(v)) { LGRingRemove(v); return; }
    CGRect r0 = [v convertRect:v.bounds toView:nil];
    if (r0.size.width < 8 || r0.size.height < 8) {      // chưa layout xong -> thử lại vài lần
        if (attempt < 4) {
            __weak UIView *w = v;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ LGRingRefresh(w, attempt + 1, NO); });
        }
        return;
    }

    // nhóm nút liền nhau (vd Sửa + "…") -> MỘT viên thuốc; nút ứng viên ngoài cùng bên trái giữ vòng
    NSArray<UIView *> *group = LGGroupFor(v);
    UIView *owner = nil;
    CGRect u = CGRectNull;
    double ownerX = 0;
    for (UIView *b in group) {
        if (!b.window) continue;
        CGRect br = [b convertRect:b.bounds toView:nil];
        u = CGRectUnion(u, LGSrcRect(b));
        if (LGRingIsCandidate(b) && (!owner || br.origin.x < ownerX)) { owner = b; ownerX = br.origin.x; }
    }
    if (!owner) owner = v;
    if (owner != v) LGRingRemove(v);
    if (CGRectIsNull(u)) u = LGSrcRect(v);

    UIView *parent = group.count <= 1 ? owner.superview : (LGCommonAncestor(group) ?: owner.superview);
    if (!parent) return;
    // view cha cắt nội dung (clipsToBounds) mà vòng tràn ra ngoài thì vòng bị cắt mất -> leo lên view cha ngoài (tối đa 3 bậc)
    for (int i = 0; i < 3 && parent.superview; i++) {
        CGRect t = [parent convertRect:u fromView:nil];
        BOOL clipped = (parent.clipsToBounds || parent.layer.masksToBounds) && !CGRectContainsRect(CGRectInset(parent.bounds, -0.5, -0.5), t);
        if (!clipped) break;
        parent = parent.superview;
    }
    LGRingView *ring = LGRingOf(owner);
    BOOL fresh = NO;
    if (!ring) {
        ring = [[LGRingView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(owner, kRingKey, ring, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        fresh = YES;
    }
    if (!gOwners) gOwners = [NSHashTable weakObjectsHashTable];
    [gOwners addObject:owner];
    LGRingEnsureTimer();

    if (ring.superview != parent) [parent insertSubview:ring atIndex:0];
    else if (parent.subviews.firstObject != ring) [parent sendSubviewToBack:ring];   // UIKit có thể đã chèn thứ gì đó xuống dưới
    CGRect target = [parent convertRect:u fromView:nil];
    BOOL moved = fabs(ring.frame.origin.x - target.origin.x) > 0.5 || fabs(ring.frame.origin.y - target.origin.y) > 0.5 ||
                 fabs(ring.frame.size.width - target.size.width) > 0.5 || fabs(ring.frame.size.height - target.size.height) > 0.5;
    if (moved) { ring.frame = target; [ring setNeedsLayout]; }
    ring.alpha = LGEffAlpha(owner, parent);     // nút mờ dần (chuyển trang…) thì vòng mờ theo
    if (fresh || (moved && !quiet))
        LGLog(@"vòng: %s %@ (%lu nút) bo=%.1f cha=%s", object_getClassName(owner), NSStringFromCGRect(u), (unsigned long)group.count,
              fmin(u.size.width, u.size.height) / 2, object_getClassName(parent));
}

// Quét lại mọi cửa sổ để dựng vòng cho các nút đã có sẵn (dùng khi người dùng bật công tắc vòng trong Cài đặt: không cần mở lại app).
static void LGRescanView(UIView *v, int depth) {
    if (depth > 30 || [v isKindOfClass:LGRingView.class]) return;
    if (LGButtonLike(v) && LGRingIsCandidate(v)) LGRingRefresh(v, 0, NO);
    for (UIView *s in v.subviews) LGRescanView(s, depth + 1);
}

void LGRingRescanAll(BOOL enabled) {
    if (!enabled || !LGP.ring) {           // tắt: gỡ hết vòng đang có
        for (UIView *o in gOwners.allObjects) LGRingRemove(o);
        return;
    }
    UIApplication *app = UIApplication.sharedApplication;
    for (UIWindow *w in app.windows) LGRescanView(w, 0);
}

void LGRingSchedule(UIView *v) {
    if (!LGP.ring || !v) return;
    __weak UIView *w = v;
    // lần 1: ngay sau layout đầu; lần 2: sau khi thanh điều hướng xếp xong (hiệu ứng push). Sau đó bộ đếm giờ 10 Hz lo phần còn lại.
    double delays[2] = { 0.05, 0.5 };
    for (int i = 0; i < 2; i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LGRingRefresh(w, 0, NO); });
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
        if (!hide) r.alpha = 1;     // hiện lại ngay cùng lúc nút (bộ đếm giờ sẽ chỉnh lại độ mờ thật sau tối đa 0,1 s)
        any = YES;
    }
    return any;
}

// ------------------------------------------------------------------ hiệu ứng ẤN (lóe sáng + phóng to)
// Tối ưu để không lag lúc chạm xuống (phần này chạy TRƯỚC khi hệ thống xử lý chạm):
//   - không chụp ảnh bằng afterScreenUpdates:YES (ép màn hình cập nhật đồng bộ, rất chậm): vòng cố định nay là view anh em nên ảnh chụp nút vốn đã sạch;
//   - viên kính dùng lớp màu đặc thay vì UIVisualEffectView (blur phải vẽ lại mỗi khung hình khi phóng to) và được rasterize;
//   - animation là CAKeyframeAnimation (lấy mẫu từ công thức lò xo) chạy trên render server, không còn CADisplayLink + CATransaction mỗi khung hình;
//   - cửa sổ phủ được dùng lại giữa các lần ấn.
@interface LGPress : NSObject
@property (nonatomic, strong) UIView *ow;
@property (nonatomic, strong) UIView *holder, *flash;
@property (nonatomic, strong) CALayer *glow, *base;
@property (nonatomic, strong) NSArray<UIView *> *sources;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *alphas;
@property (nonatomic, readonly) CFTimeInterval t0;
@property (nonatomic, readonly) BOOL released;
+ (void)beginWithSources:(NSArray<UIView *> *)sources;
- (void)release_;
- (void)restoreSources;
- (void)end;
@end

static LGPress *gPress;
static UIView *gPressHost;          // cửa sổ phủ dùng lại (nếu là UIWindow)
static __weak UIWindow *gPressHostWin;

@implementation LGPress {
    CFTimeInterval _t0;
    BOOL _released, _restored;
}
- (CFTimeInterval)t0 { return _t0; }
- (BOOL)released { return _released; }

+ (void)beginWithSources:(NSArray<UIView *> *)sources {
    [gPress end];
    CGRect u = CGRectNull;
    NSMutableArray<UIView *> *srcs = [NSMutableArray new];
    for (UIView *v in sources) {
        if (!v.window) continue;
        CGRect r = LGSrcRect(v);     // cùng khung với vòng cố định và morph
        if (CGRectIsEmpty(r) || r.size.width > 200 || r.size.height > 100) continue;
        u = CGRectUnion(u, r);
        [srcs addObject:v];
    }
    if (!srcs.count || CGRectIsNull(u)) return;
    UIWindow *win = srcs.firstObject.window;

    LGPress *p = [LGPress new];
    p.sources = srcs;

    UIView *ow;
    BOOL reusable = ![NSBundle.mainBundle.bundlePath.pathExtension isEqualToString:@"appex"] && LGP.overlayMode != 2;
    if (reusable && gPressHost && gPressHostWin == win) {
        ow = gPressHost;
    } else {
        ow = LGMakeOverlay(win);
        if (reusable && [ow isKindOfClass:UIWindow.class]) { gPressHost = ow; gPressHostWin = win; }
    }
    p.ow = ow;

    double rad = fmin(u.size.width, u.size.height) / 2;
    UIView *holder = [[UIView alloc] initWithFrame:u];
    holder.userInteractionEnabled = NO;
    holder.layer.shouldRasterize = YES;
    holder.layer.rasterizationScale = UIScreen.mainScreen.scale;
    [ow addSubview:holder];
    p.holder = holder;

    // nền viên kính: màu đặc gần giống vòng cố định (kính + màu phủ) nhưng không blur
    BOOL dark = win.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    CALayer *base = [CALayer layer];
    base.frame = holder.bounds;
    base.cornerRadius = rad;
    base.backgroundColor = (dark ? [UIColor colorWithWhite:0.12 alpha:0.96] : [UIColor colorWithWhite:0.93 alpha:0.96]).CGColor;
    base.borderWidth = 0.8;
    base.borderColor = (dark ? [UIColor colorWithWhite:1 alpha:0.14] : [UIColor colorWithWhite:0 alpha:0.14]).CGColor;
    [holder.layer addSublayer:base];
    p.base = base;

    // tối: lóe trắng (như video); sáng: lóe tối (trắng trên nền sáng không nhìn thấy)
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

    // ảnh icon nút: chụp KHÔNG chờ cập nhật màn hình (vòng nay là view anh em nên ảnh vốn đã sạch), rồi mới ẩn nút thật + vòng
    for (UIView *v in srcs) {
        UIView *s = [v snapshotViewAfterScreenUpdates:NO];
        if (!s) continue;
        CGRect r = [v convertRect:v.bounds toView:nil];
        s.frame = CGRectOffset(r, -u.origin.x, -u.origin.y);
        [holder addSubview:s];
    }
    LGRingHide(srcs, YES);
    p.alphas = [NSMutableArray new];
    for (UIView *v in srcs) {
        [p.alphas addObject:@(v.alpha < 0.05 ? 1.0 : v.alpha)];
        v.alpha = 0;
    }

    p->_t0 = CACurrentMediaTime();
    gPress = p;
    LGOverlayShow(ow);
    [p animateIn];
    // chốt an toàn: giữ quá lâu thì tự thu về
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (gPress == p) [p release_]; });
    LGLog(@"ẤN: %lu nút, khung %@ bo=%.1f %@", (unsigned long)srcs.count, NSStringFromCGRect(u), rad, dark ? @"(tối: lóe trắng)" : @"(sáng: lóe tối)");
}

// Lấy mẫu công thức lò xo thành keyframe chạy trên render server. Tốc độ animation (LGP.speed) co giãn thời gian.
static CAKeyframeAnimation *LGKeys(NSString *path, NSArray *values, double dur) {
    CAKeyframeAnimation *a = [CAKeyframeAnimation animationWithKeyPath:path];
    a.values = values;
    a.duration = dur;
    a.calculationMode = kCAAnimationLinear;
    a.removedOnCompletion = YES;
    return a;
}

- (void)animateIn {
    double sp = fmax(LGP.speed, 0.25);
    const int N = 24;
    double span = 0.32;                          // giây (chưa co giãn) đủ để lò xo lắng
    NSMutableArray *sv = [NSMutableArray new], *fv = [NSMutableArray new];
    double sEnd = 1, fEnd = 0;
    for (int i = 0; i <= N; i++) {
        double t = span * i / N;
        sEnd = LGP.pressZoomOn ? lgtl_press_scale(t, LGP.pressScale, LGP.pressOmega, LGP.pressZeta) : 1;
        fEnd = LGP.pressFlashOn ? lgtl_press_flash(t, 0.03) : 0;
        [sv addObject:@(sEnd)];
        [fv addObject:@(fEnd)];
    }
    double D = span / sp;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.holder.layer.transform = CATransform3DMakeScale((CGFloat)sEnd, (CGFloat)sEnd, 1);    // giá trị cuối; animation đè lên trong lúc chạy
    self.flash.layer.opacity = (float)fEnd;
    self.glow.opacity = (float)fEnd;
    [CATransaction commit];
    [self.holder.layer addAnimation:LGKeys(@"transform.scale", sv, D) forKey:@"in"];
    [self.flash.layer addAnimation:LGKeys(@"opacity", fv, D) forKey:@"in"];
    [self.glow addAnimation:LGKeys(@"opacity", fv, D) forKey:@"in"];
}

- (void)release_ {
    if (_released) return;
    _released = YES;
    CALayer *hp = self.holder.layer.presentationLayer ?: self.holder.layer;
    double s0 = [[hp valueForKeyPath:@"transform.scale"] doubleValue];
    double f0 = (self.flash.layer.presentationLayer ?: self.flash.layer).opacity;
    double sp = fmax(LGP.speed, 0.25);
    const int N = 16;
    double span = 0.20;
    NSMutableArray *sv = [NSMutableArray new], *fv = [NSMutableArray new];
    for (int i = 0; i <= N; i++) {
        double t = span * i / N, w = 30.0;
        [sv addObject:@(1 + (s0 - 1) * (1 + w * t) * exp(-w * t))];     // lò xo tới hạn, vận tốc đầu 0
        [fv addObject:@(f0 * exp(-t / 0.05))];
    }
    double D = span / sp;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self.holder.layer removeAllAnimations];
    [self.flash.layer removeAllAnimations];
    [self.glow removeAllAnimations];
    self.holder.layer.transform = CATransform3DIdentity;
    self.flash.layer.opacity = 0;
    self.glow.opacity = 0;
    [CATransaction commit];
    [self.holder.layer addAnimation:LGKeys(@"transform.scale", sv, D) forKey:@"out"];
    [self.flash.layer addAnimation:LGKeys(@"opacity", fv, D) forKey:@"out"];
    [self.glow addAnimation:LGKeys(@"opacity", fv, D) forKey:@"out"];
    LGPress *me = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((D + 0.03) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ if (gPress == me) [me end]; });
}

// Trả nút thật + vòng về nguyên trạng (một lần duy nhất: morph có thể đã ẩn chúng lại ngay sau đó, không được trả lần nữa).
- (void)restoreSources {
    if (_restored) return;
    _restored = YES;
    for (NSUInteger i = 0; i < self.sources.count && i < self.alphas.count; i++) self.sources[i].alpha = (CGFloat)self.alphas[i].doubleValue;
    LGRingHide(self.sources, NO);
}

- (void)end {
    [self restoreSources];
    BOOL window = [self.ow isKindOfClass:UIWindow.class];
    [self.holder removeFromSuperview];
    if (window && self.ow == gPressHost) self.ow.hidden = YES;     // cửa sổ được dùng lại: chỉ ẩn, không gỡ
    else LGOverlayDrop(self.ow);
    self.holder = nil;
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
