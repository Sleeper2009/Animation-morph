#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <rootless.h>
#import "LGMenuMorph.h"
#import "LGLog.h"

#define kPrefs @"/var/mobile/Library/Preferences/com.yourname.liquidmenu.plist"

static NSArray<NSString *> *gHints;       // chuỗi con trong tên class private của menu (đã lọc: toàn NSString không rỗng)
static BOOL gEnabled = YES, gBusy = NO;
static __weak UIView *gSource;            // nút vừa được chạm (nil nếu chạm vào chỗ không phải nút)
static CGPoint gTouch;                    // vị trí chạm (toạ độ window)
static CFTimeInterval gSourceT;
static __weak UIView *gHidden;            // container đang bị ẩn tạm (layer.hidden) để không lộ vài khung hình của menu hệ thống

// Trả container về hiển thị bình thường (phiên morph tự bật lại khi bắt đầu; gọi thêm ở mọi đường thoát cho chắc).
static void LGUnhide(void) {
    UIView *c = gHidden;
    gHidden = nil;
    if (c) c.layer.hidden = NO;
}

static BOOL LGNameHas(id obj, const char *s) { return obj && strstr(object_getClassName(obj), s) != NULL; }

// MỘT định nghĩa duy nhất của "view này thuộc menu" — dùng cho cả LGInMenu lẫn didMoveToWindow.
static BOOL LGMatchName(const char *n) {
    if (!n) return NO;
    for (NSString *h in gHints) if (strstr(n, h.UTF8String)) return YES;
    return NO;
}
static BOOL LGMatch(id obj) { return obj && LGMatchName(object_getClassName(obj)); }

static BOOL LGInMenu(UIView *v) {
    for (UIView *c = v; c; c = c.superview)
        if (LGMatch(c)) return YES;
    return LGMatch(v.window);
}

// Nhiều class lồng nhau cùng khớp hints và UIKit gọi didMoveToWindow theo thứ tự không đảm bảo ->
// lấy view NGOÀI CÙNG vẫn khớp (không tính UIWindow).
static UIView *LGOutermost(UIView *v) {
    UIView *top = v;
    for (UIView *c = v.superview; c && ![c isKindOfClass:UIWindow.class]; c = c.superview)
        if (LGMatch(c)) top = c;
    return top;
}

static BOOL LGButtonLike(UIView *v) { return [v isKindOfClass:UIControl.class] || LGNameHas(v, "Button"); }

// Từ view bị chạm đi lên tìm "nút". Không phải nút -> nil (menu mở bằng nhấn giữ vào ô/ghi chú... không có animation).
static UIView *LGPickSource(UIView *v) {
    for (UIView *c = v; c && c.bounds.size.width < 120; c = c.superview)
        if (LGButtonLike(c)) return c;
    return nil;
}

// nút đầu tiên trong view (chính nó hoặc hậu duệ gần), kích thước như nút
static UIView *LGFirstButton(UIView *v, int depth) {
    if (LGButtonLike(v) && v.bounds.size.width < 120) return v;
    if (depth >= 3) return nil;
    for (UIView *s in v.subviews) {
        UIView *b = LGFirstButton(s, depth + 1);
        if (b) return b;
    }
    return nil;
}

// Nhóm nút liền nhau cùng hàng (vd chia sẻ + "…" trên thanh điều hướng) -> gộp thành một viên thuốc.
static NSArray<UIView *> *LGGroupFor(UIView *src) {
    NSMutableArray<UIView *> *group = [NSMutableArray arrayWithObject:src];
    if (!LGP.groupButtons) return group;
    CGRect u = [src convertRect:src.bounds toView:nil];
    for (int round = 0; round < 3; round++) {
        BOOL grew = NO;
        UIView *node = src;
        for (int level = 0; level < 4 && node.superview; level++, node = node.superview) {
            BOOL added = NO;
            for (UIView *sib in node.superview.subviews) {
                if (sib == node || sib.hidden || sib.alpha < 0.05) continue;
                UIView *b = LGFirstButton(sib, 0);
                if (!b || [group containsObject:b] || !b.window) continue;
                CGRect r = [b convertRect:b.bounds toView:nil];
                if (r.size.width > 120 || r.size.height > 80) continue;
                if (fabs(CGRectGetMidY(r) - CGRectGetMidY(u)) > 8 || fabs(r.size.height - u.size.height) > 12) continue;
                double gap = r.origin.x >= CGRectGetMaxX(u) ? r.origin.x - CGRectGetMaxX(u)
                           : (u.origin.x >= CGRectGetMaxX(r) ? u.origin.x - CGRectGetMaxX(r) : -1);
                if (gap < -2 || gap > 20) continue;
                [group addObject:b];
                u = CGRectUnion(u, r);
                added = YES;
            }
            if (added) { grew = YES; break; }
        }
        if (!grew) break;
    }
    return group;
}

static void LGLabelsOf(UIView *v, NSMutableArray *out) {
    if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) [out addObject:v];
    for (UIView *s in v.subviews) LGLabelsOf(s, out);
}

static UIView *LGLCA(NSArray<UIView *> *views) {
    for (UIView *cur = views.firstObject; cur; cur = cur.superview) {
        BOOL all = YES;
        for (UIView *v in views) if (![v isDescendantOfView:cur]) { all = NO; break; }
        if (all) return cur;
    }
    return nil;
}

static void LGHandle(UIView *container, int attempt) {
    if (!container.window) { LGUnhide(); gBusy = NO; return; }
    if ([LGMenuMorph isActive] && [LGMenuMorph activeContainer] == container) { LGUnhide(); gBusy = NO; return; }
    NSMutableArray *labels = [NSMutableArray new];
    LGLabelsOf(container, labels);
    if (!labels.count) {   // menu chưa dựng xong nội dung -> thử lại vài lần
        if (attempt < 4) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ LGHandle(container, attempt + 1); });
        } else {
            LGLog(@"bỏ qua: menu %s không có chữ sau %d lần thử", object_getClassName(container), attempt);
            LGUnhide();
            gBusy = NO;
        }
        return;
    }
    UIView *content = LGLCA(labels);
    UIView *body = content;   // leo lên đến view "thân menu" (nhỏ hơn ~90% bề rộng container)
    while (body.superview && body.superview != container &&
           body.superview.bounds.size.width < container.bounds.size.width * 0.9) body = body.superview;
    if (!content || body == container || !body.superview) {
        LGLog(@"bỏ qua: container=%s content=%s body=%s", object_getClassName(container),
              content ? object_getClassName(content) : "nil", body ? object_getClassName(body) : "nil");
        LGUnhide();
        gBusy = NO;
        return;
    }

    UIView *s = gSource;
    if (!s.window) {
        LGLog(@"bỏ qua: menu %s không xuất phát từ nút (lần chạm cuối không phải nút)", object_getClassName(container));
        LGUnhide();
        gBusy = NO;
        return;
    }
    NSArray<UIView *> *sources = LGGroupFor(s);
    NSMutableString *names = [NSMutableString string];
    for (UIView *v in sources) [names appendFormat:@"%s%@ ", object_getClassName(v), NSStringFromCGRect([v convertRect:v.bounds toView:nil])];
    LGLog(@"menu từ nút: %@", names);
    CGRect fb = CGRectMake(gTouch.x - 22, gTouch.y - 22, 44, 44);
    [LGMenuMorph beginWithContainer:container body:body sources:sources fallbackRect:fb];
    LGUnhide();
    gBusy = NO;
}

%hook UIApplication
- (void)sendEvent:(UIEvent *)e {
    if (gEnabled && e.type == UIEventTypeTouches) {
        for (UITouch *t in e.allTouches) {
            [LGMenuMorph touch:t];     // chạm ngoài menu -> đóng (làm TRƯỚC %orig để lớp phủ lên trước khi hệ thống kịp đóng)
            if (t.phase != UITouchPhaseBegan) continue;
            if (t.view && !LGInMenu(t.view)) {
                gSource = LGPickSource(t.view);
                gTouch = [t locationInView:nil];
                gSourceT = CACurrentMediaTime();
            }
        }
    }
    %orig;
}
%end

%hook UIView
- (void)didMoveToWindow {
    %orig;
    if (!gEnabled) return;
    const char *n = object_getClassName(self);
    if (!self.window) {
        if (LGLogOn && LGMatchName(n)) LGLog(@"-%s (bị gỡ khỏi window)", n);
        return;
    }
    if (CACurrentMediaTime() - gSourceT > 1.5) return;
    if (!LGMatchName(n)) return;
    UIView *top = LGOutermost(self);
    if ([LGMenuMorph isActive] && [LGMenuMorph activeContainer] == top) return;   // view con của menu đang được xử lý
    LGLog(@"+%s frame=%@ window=%s level=%.0f", n, NSStringFromCGRect(self.frame), object_getClassName(self.window), (double)self.window.windowLevel);
    if (gBusy) return;
    gBusy = YES;
    // Ẩn ngay container (chỉ layer.hidden: UIKit không đụng tới nó, còn cảm ứng vẫn hoạt động) TRƯỚC khung hình đầu tiên,
    // nếu không người dùng thấy menu hệ thống hiện ~4 khung rồi mới tới morph. Chỉ ẩn khi menu xuất phát từ một nút.
    if (gSource.window) {
        top.layer.hidden = YES;
        gHidden = top;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gHidden == top) { LGLog(@"chốt an toàn: container vẫn bị ẩn sau 1,5 s -> hiện lại"); LGUnhide(); }
        });
    }
    dispatch_async(dispatch_get_main_queue(), ^{ LGHandle(top, 0); });   // chờ hệ thống dựng xong 1 vòng runloop
}
%end

// plist do người dùng sửa tay: kiểu dữ liệu sai không được làm crash app đích
#define LGNUM(key, field) if ([p[key] respondsToSelector:@selector(doubleValue)]) LGP.field = [p[key] doubleValue];
static BOOL LGBoolOf(id v, BOOL def) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def; }

%ctor {
    @autoreleasepool {
        NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:ROOT_PATH_NS(kPrefs)] ?: @{};
        gEnabled = LGBoolOf(p[@"enabled"], YES);
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"] && !LGBoolOf(p[@"springboard"], NO))
            gEnabled = NO;

        // hints: chỉ nhận NSString không rỗng ("" sẽ khớp mọi view; NSNumber sẽ crash ở UTF8String)
        NSMutableArray<NSString *> *hs = [NSMutableArray new];
        id raw = p[@"hints"];
        if ([raw isKindOfClass:NSArray.class])
            for (id h in (NSArray *)raw) if ([h isKindOfClass:NSString.class] && ((NSString *)h).length) [hs addObject:h];
        gHints = hs.count ? [hs copy] : @[@"ContextMenu", @"_UIMenu", @"MenuContainer"];

        LGNUM(@"omega", omega) LGNUM(@"offsetDelay", offsetDelay) LGNUM(@"contentDelay", contentDelay)
        LGNUM(@"dotOmega", dotOmega) LGNUM(@"dotDelay", dotDelay) LGNUM(@"radOmega", radOmega)
        LGNUM(@"radDelay", radDelay) LGNUM(@"blend", blend) LGNUM(@"speed", speed) LGNUM(@"closeDur", closeDur)
        LGNUM(@"tint", tint) LGNUM(@"shadow", shadow) LGNUM(@"rim", rim)
        if ([p[@"material"] respondsToSelector:@selector(intValue)]) LGP.material = [p[@"material"] intValue];
        LGP.useGlass = LGBoolOf(p[@"useGlass"], LGP.useGlass);
        LGP.coverButton = LGBoolOf(p[@"coverButton"], LGP.coverButton);
        LGP.hideSource = LGBoolOf(p[@"hideSource"], LGP.hideSource);
        LGP.groupButtons = LGBoolOf(p[@"groupButtons"], LGP.groupButtons);
        LGP.blurText = LGBoolOf(p[@"blurText"], LGP.blurText);
        LGP.closeAnim = LGBoolOf(p[@"closeAnim"], LGP.closeAnim);
        LGP.dump = LGBoolOf(p[@"dump"], LGP.dump);
        LGP.debug = LGBoolOf(p[@"debug"], LGP.debug);
        LGParamsFinalize();
        LGLogOn = LGP.debug;
        LGLog(@"LiquidMenu v3 khởi động trong %@ (enabled=%d) log: %@", NSBundle.mainBundle.bundleIdentifier, (int)gEnabled, LGLogPaths());
    }
}
