#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <rootless.h>
#import "LGMenuMorph.h"

#define kPrefs @"/var/mobile/Library/Preferences/com.yourname.liquidmenu.plist"

static NSArray<NSString *> *gHints;       // chuỗi con trong tên class private của menu (đã lọc: toàn NSString không rỗng)
static BOOL gEnabled = YES, gDebug = NO, gBusy = NO;
static __weak UIView *gSource;            // nút vừa được chạm
static CGPoint gTouch;                    // vị trí chạm (toạ độ window)
static CFTimeInterval gSourceT;

static BOOL LGNameHas(id obj, const char *s) { return obj && strstr(object_getClassName(obj), s) != NULL; }

// MỘT định nghĩa duy nhất của "view này thuộc menu" — dùng cho cả LGInMenu lẫn didMoveToWindow,
// nên đổi `hints` trong plist thì mọi chỗ cùng đổi theo.
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
// không lấy view khớp đầu tiên, mà lấy view NGOÀI CÙNG vẫn khớp (không tính UIWindow).
static UIView *LGOutermost(UIView *v) {
    UIView *top = v;
    for (UIView *c = v.superview; c && ![c isKindOfClass:UIWindow.class]; c = c.superview)
        if (LGMatch(c)) top = c;
    return top;
}

// Từ view bị chạm đi lên tìm "nút" (UIControl hoặc class có chữ Button)
static UIView *LGPickSource(UIView *v) {
    for (UIView *c = v; c && c.bounds.size.width < 120; c = c.superview)
        if ([c isKindOfClass:UIControl.class] || LGNameHas(c, "Button")) return c;
    return v;
}

static void LGLabels(UIView *v, NSMutableArray *out) {
    if ([v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) [out addObject:v];
    for (UIView *s in v.subviews) LGLabels(s, out);
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
    if (!container.window) { gBusy = NO; return; }
    NSMutableArray *labels = [NSMutableArray new];
    LGLabels(container, labels);
    if (!labels.count) {   // menu chưa dựng xong nội dung -> thử lại vài lần
        if (attempt < 4) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ LGHandle(container, attempt + 1); });
        } else gBusy = NO;
        return;
    }
    UIView *content = LGLCA(labels);
    UIView *body = content;   // leo lên đến view "thân menu" (nhỏ hơn ~90% bề rộng container)
    while (body.superview && body.superview != container &&
           body.superview.bounds.size.width < container.bounds.size.width * 0.9) body = body.superview;
    if (!content || body == container || !body.superview) {
        if (gDebug) NSLog(@"[LiquidMenu] bỏ qua: container=%s content=%s body=%s", object_getClassName(container),
                          content ? object_getClassName(content) : "nil", body ? object_getClassName(body) : "nil");
        gBusy = NO;
        return;
    }

    UIView *host = body.superview;
    UIView *s = gSource;
    CGRect src = CGRectZero;
    BOOL fromView = NO;      // src lấy từ khung của nút thật (true) hay chỉ là ô ước lượng quanh chỗ chạm (false)
    if (s.window) {
        src = [s convertRect:s.bounds toView:host];
        fromView = !(CGRectIsEmpty(src) || src.size.width > 120 || src.size.height > 120);
    }
    if (!fromView) src = [host convertRect:CGRectMake(gTouch.x - 22, gTouch.y - 22, 44, 44) fromView:nil];
    if (gDebug) NSLog(@"[LiquidMenu] morph container=%s body=%s %@ content=%s src=%@ (%@)", object_getClassName(container),
                      object_getClassName(body), NSStringFromCGRect(body.frame), object_getClassName(content), NSStringFromCGRect(src),
                      fromView ? @"khung nút thật" : @"ô ước lượng quanh chỗ chạm");
    [LGMenuMorph runForBody:body content:content source:src sourceView:(fromView ? s : nil) done:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ gBusy = NO; });
    }];
}

%hook UIApplication
- (void)sendEvent:(UIEvent *)e {
    if (gEnabled && e.type == UIEventTypeTouches) {
        for (UITouch *t in e.allTouches) {
            if (t.phase != UITouchPhaseBegan) continue;
            // Menu thật đang bị ẩn trong lúc morph -> chạm mới (vd chạm ra ngoài để đóng) phải
            // kết thúc morph ngay, nếu không vỏ kính còn nằm đó tới 0.5 s sau khi menu đã đóng.
            [LGMenuMorph cancelActive];
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
    // debug: ghi lại view của menu bị gỡ khỏi window (để biết lúc nào menu đóng xong)
    if (gDebug && !self.window && LGMatchName(n)) NSLog(@"[LiquidMenu] -%s (bị gỡ khỏi window)", n);
    if (!self.window || CACurrentMediaTime() - gSourceT > 1.5) return;
    if (gDebug) NSLog(@"[LiquidMenu] +%s frame=%@ window=%s", n, NSStringFromCGRect(self.frame), object_getClassName(self.window));
    if (gBusy || !LGMatchName(n)) return;
    gBusy = YES;
    UIView *top = LGOutermost(self);
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
        gDebug = LGBoolOf(p[@"debug"], NO);
        LGP.debug = gDebug;

        // hints: chỉ nhận NSString không rỗng ("" sẽ khớp mọi view; NSNumber sẽ crash ở UTF8String)
        NSMutableArray<NSString *> *hs = [NSMutableArray new];
        id raw = p[@"hints"];
        if ([raw isKindOfClass:NSArray.class])
            for (id h in (NSArray *)raw) if ([h isKindOfClass:NSString.class] && ((NSString *)h).length) [hs addObject:h];
        gHints = hs.count ? [hs copy] : @[@"ContextMenu", @"_UIMenu", @"MenuContainer"];

        LGNUM(@"omega", omega) LGNUM(@"offsetDelay", offsetDelay) LGNUM(@"contentDelay", contentDelay)
        LGNUM(@"dotOmega", dotOmega) LGNUM(@"dotDelay", dotDelay) LGNUM(@"radOmega", radOmega)
        LGNUM(@"radDelay", radDelay) LGNUM(@"blend", blend) LGNUM(@"speed", speed)
        LGP.useGlass = LGBoolOf(p[@"useGlass"], LGP.useGlass);
        LGP.coverButton = LGBoolOf(p[@"coverButton"], LGP.coverButton);
        LGP.hideSource = LGBoolOf(p[@"hideSource"], LGP.hideSource);
        LGParamsFinalize();
    }
}
