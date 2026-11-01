#import "LGBarIcons.h"
#import "LGMenuMorph.h"
#import "LGLog.h"
#import <objc/runtime.h>

static const void *kKindKey = &kKindKey, *kStateKey = &kStateKey, *kLabelKey = &kLabelKey;
static const CGFloat kCanvas = 44, kInset = 2;     // ảnh 44 pt, hình tròn đường kính 40 pt

static NSString *LGNorm(NSString *s) {
    return [[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
}

LGBarIconKind LGBarIconKindForTitle(NSString *title) {
    if (![title isKindOfClass:NSString.class] || !title.length) return LGBarIconNone;
    static NSSet<NSString *> *cancel, *done;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cancel = [NSSet setWithArray:@[ @"hủy", @"huỷ", @"cancel" ]];
        done = [NSSet setWithArray:@[ @"xong", @"done", @"kết nối", @"join", @"connect" ]];
    });
    NSString *n = LGNorm(title);
    if ([cancel containsObject:n]) return LGBarIconCancel;
    if ([done containsObject:n]) return LGBarIconDone;
    return LGBarIconNone;
}

BOOL LGBarIconWanted(LGBarIconKind kind) {
    return kind == LGBarIconCancel ? LGP.iconCancel : (kind == LGBarIconDone ? LGP.iconDone : NO);
}

// ------------------------------------------------------------------ vẽ ảnh
static UIColor *RGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return [UIColor colorWithRed:r green:g blue:b alpha:a]; }

static void LGStrokeX(CGContextRef c, CGRect r, UIColor *col) {
    CGFloat s = r.size.width, m = s * 0.31;
    CGContextSetStrokeColorWithColor(c, col.CGColor);
    CGContextSetLineWidth(c, 2.4);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextMoveToPoint(c, CGRectGetMinX(r) + m, CGRectGetMinY(r) + m);
    CGContextAddLineToPoint(c, CGRectGetMaxX(r) - m, CGRectGetMaxY(r) - m);
    CGContextMoveToPoint(c, CGRectGetMaxX(r) - m, CGRectGetMinY(r) + m);
    CGContextAddLineToPoint(c, CGRectGetMinX(r) + m, CGRectGetMaxY(r) - m);
    CGContextStrokePath(c);
}

static void LGStrokeCheck(CGContextRef c, CGRect r, UIColor *col) {
    CGFloat s = r.size.width, x = r.origin.x, y = r.origin.y;
    CGContextSetStrokeColorWithColor(c, col.CGColor);
    CGContextSetLineWidth(c, 2.7);
    CGContextSetLineCap(c, kCGLineCapRound);
    CGContextSetLineJoin(c, kCGLineJoinRound);
    CGContextMoveToPoint(c, x + s * 0.285, y + s * 0.515);
    CGContextAddLineToPoint(c, x + s * 0.43, y + s * 0.655);
    CGContextAddLineToPoint(c, x + s * 0.725, y + s * 0.345);
    CGContextStrokePath(c);
}

static UIImage *LGRender(LGBarIconKind kind, BOOL enabled, BOOL dark) {
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *rd = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kCanvas, kCanvas) format:fmt];
    return [rd imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextRef c = ctx.CGContext;
        CGRect box = CGRectMake(0, 0, kCanvas, kCanvas);
        CGRect disc = CGRectInset(box, kInset, kInset);
        if (kind == LGBarIconCancel) {
            // nền trắng (tối: xám đậm) có bóng nhẹ, dấu X đen (tối: trắng)
            CGContextSaveGState(c);
            CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 3, RGB(0, 0, 0, dark ? 0.35 : 0.12).CGColor);
            [(dark ? RGB(0.17, 0.17, 0.18, 1) : RGB(0.99, 0.99, 1.0, 1)) setFill];
            CGContextFillEllipseInRect(c, disc);
            CGContextRestoreGState(c);
            LGStrokeX(c, disc, dark ? RGB(1, 1, 1, 0.95) : RGB(0.07, 0.07, 0.09, 1));
        } else if (!enabled) {
            // ✓ nền xám (không bấm được)
            [(dark ? RGB(0.28, 0.28, 0.30, 1) : RGB(0.80, 0.80, 0.82, 1)) setFill];
            CGContextFillEllipseInRect(c, disc);
            LGStrokeCheck(c, disc, dark ? RGB(1, 1, 1, 0.45) : RGB(1, 1, 1, 0.95));
        } else {
            // ✓ nền xanh có viền sáng mảnh, dấu ✓ xanh ngọc nhạt (như ảnh mẫu)
            CGContextSaveGState(c);
            CGContextSetShadowWithColor(c, CGSizeMake(0, 1), 3, RGB(0.10, 0.35, 0.95, 0.35).CGColor);
            [RGB(0.20, 0.47, 0.96, 1) setFill];
            CGContextFillEllipseInRect(c, disc);
            CGContextRestoreGState(c);
            CGContextSetStrokeColorWithColor(c, RGB(0.55, 0.85, 1.0, 0.75).CGColor);
            CGContextSetLineWidth(c, 1.2);
            CGContextStrokeEllipseInRect(c, CGRectInset(disc, 0.8, 0.8));
            LGStrokeCheck(c, disc, RGB(0.66, 0.96, 1.0, 1));
        }
    }];
}

UIImage *LGBarIconImage(LGBarIconKind kind, BOOL enabled) {
    if (kind == LGBarIconNone) return nil;
    if (kind == LGBarIconCancel) enabled = YES;
    static NSMutableDictionary<NSNumber *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSMutableDictionary new]; });
    NSNumber *key = @(kind * 2 + (enabled ? 1 : 0));
    UIImage *hit = cache[key];
    if (hit) return hit;
    UIImage *light = LGRender(kind, enabled, NO);
    UIImage *dark = LGRender(kind, enabled, YES);
    [light.imageAsset registerImage:dark withTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]];
    UIImage *out = [light imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    cache[key] = out;
    return out;
}

// ------------------------------------------------------------------ áp vào UIBarButtonItem
void LGBarIconSetKind(UIBarButtonItem *item, LGBarIconKind kind) {
    objc_setAssociatedObject(item, kKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSString *LGDefaultLabel(LGBarIconKind kind) {
    return kind == LGBarIconCancel ? @"Hủy" : @"Xong";
}

void LGBarIconApply(UIBarButtonItem *item) {
    if (!item) return;
    NSNumber *k = objc_getAssociatedObject(item, kKindKey);
    LGBarIconKind kind = k ? (LGBarIconKind)k.integerValue : LGBarIconKindForTitle(item.title);
    if (kind == LGBarIconNone || !LGBarIconWanted(kind)) return;
    if (!k) LGBarIconSetKind(item, kind);
    BOOL en = kind == LGBarIconDone ? item.isEnabled : YES;
    NSNumber *last = objc_getAssociatedObject(item, kStateKey);
    if (last && last.boolValue == en && item.image) return;             // đã áp đúng trạng thái này rồi
    if (!objc_getAssociatedObject(item, kLabelKey)) {                   // nhớ chữ gốc làm nhãn trợ năng (nút ảnh không có chữ)
        NSString *t = item.title.length ? item.title : LGDefaultLabel(kind);
        objc_setAssociatedObject(item, kLabelKey, t, OBJC_ASSOCIATION_COPY_NONATOMIC);
        if (!item.accessibilityLabel.length) item.accessibilityLabel = t;
    }
    objc_setAssociatedObject(item, kStateKey, @(en), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    item.image = LGBarIconImage(kind, en);
    LGLog(@"nút biểu tượng: %@ '%@' enabled=%d", kind == LGBarIconCancel ? @"X" : @"✓", item.title ?: @"", en);
}
