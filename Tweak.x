#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <rootless.h>
#import "LGMenuMorph.h"
#import "LGLog.h"
#import "LGRing.h"

// Cài đặt: domain CFPreferences do bảng Cài đặt (LiquidMenuPrefs) ghi; file plist cùng tên vẫn đọc được để chỉnh tay (khoá nâng cao như omega, hints...).
#define kDomain @"com.fujb-2009.liquidmenu"
#define kPrefs @"/var/mobile/Library/Preferences/com.fujb-2009.liquidmenu.plist"
#define kOldPrefs @"/var/mobile/Library/Preferences/com.yourname.liquidmenu.plist"
#define kReloadNote CFSTR("com.fujb-2009.liquidmenu/reload")

static NSArray<NSString *> *gHints;       // chuỗi con trong tên class private của menu (đã lọc: toàn NSString không rỗng)
static BOOL gEnabled = YES, gBusy = NO;
static __weak UIView *gSource;            // nút vừa được chạm (nil nếu chạm vào chỗ không phải nút)
static CGPoint gTouch;                    // vị trí chạm (toạ độ window)
static CFTimeInterval gSourceT;
static __weak UIView *gHidden;            // container đang bị ẩn tạm (layer.hidden) để không lộ vài khung hình của menu hệ thống

// Trả container về hiển thị bình thường (phiên morph tự bật lại khi bắt đầu; gọi thêm ở mọi đường thoát cho chắc).
static void LGUnhide(void) {
    LGPressFinish();     // mọi đường thoát (kể cả sau khi morph đã bắt đầu): trả nút/vòng về nguyên trạng, tắt hiệu ứng ấn
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

BOOL LGButtonLike(UIView *v) { return [v isKindOfClass:UIControl.class] || LGNameHas(v, "Button"); }

// Từ view bị chạm đi lên tìm "nút". Không phải nút -> nil (menu mở bằng nhấn giữ vào ô/ghi chú... không có animation).
static UIView *LGPickSource(UIView *v) {
    for (UIView *c = v; c && c.bounds.size.width < 120; c = c.superview)
        if (LGButtonLike(c)) return c;
    // lượt 2: view SINH RA menu (có UIContextMenuInteraction / UIButton.menu) dù không phải UIControl hoặc hơi lớn (vd nút AA của Safari)
    // (giới hạn như lượt 1 và loại ô nhập văn bản: menu "Dán" / sửa văn bản không phải menu của một nút, trước đây bị morph sai)
    int n = 0;
    for (UIView *c = v; c && n < 8; c = c.superview, n++) {
        CGSize s = c.bounds.size;
        if ([c conformsToProtocol:@protocol(UITextInput)]) return nil;
        if (s.width < 120 && s.height < 80 && LGHasMenuInteraction(c)) return c;
    }
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
NSArray<UIView *> *LGGroupFor(UIView *src) {
    NSMutableArray<UIView *> *group = [NSMutableArray arrayWithObject:src];
    if (!LGP.groupButtons) return group;
    // Dùng khung NHÌN THẤY (LGSrcRect) chứ không phải khung kỹ thuật: nút thanh công cụ (vd chia sẻ / dấu trang / thẻ của Safari) có khung sát nhau
    // dù phần nhìn thấy cách xa nhau -> trước đây bị gộp thành một viên thuốc.
    CGRect u = LGSrcRect(src);
    for (int round = 0; round < 3; round++) {
        BOOL grew = NO;
        UIView *node = src;
        for (int level = 0; level < 4 && node.superview; level++, node = node.superview) {
            BOOL added = NO;
            for (UIView *sib in node.superview.subviews) {
                if (sib == node || sib.hidden || sib.alpha < 0.05) continue;
                UIView *b = LGFirstButton(sib, 0);
                if (!b || [group containsObject:b] || !b.window) continue;
                CGRect r = LGSrcRect(b);
                if (r.size.width > 120 || r.size.height > 80) continue;
                if (fabs(CGRectGetMidY(r) - CGRectGetMidY(u)) > 8 || fabs(r.size.height - u.size.height) > 12) continue;
                double gap = r.origin.x >= CGRectGetMaxX(u) ? r.origin.x - CGRectGetMaxX(u)
                           : (u.origin.x >= CGRectGetMaxX(r) ? u.origin.x - CGRectGetMaxX(r) : -1);
                if (gap < -2 || gap > LGP.groupGap) continue;
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

// Menu hiện từ một nút nhưng morph không chạy được (tiến trình lạ, setup thất bại...): trước đây menu hệ thống bị ẩn ~0,12 s rồi hiện cái bụp.
// Thay vào đó chạy một animation lò xo đơn giản: menu phóng ra từ chỗ nút. Gọi TRƯỚC LGUnhide.
static void LGFallback(UIView *container, UIView *body) {
    if (!LGP.fallbackAnim) return;
    UIView *s = gSource;
    UIView *v = body ?: container;
    if (!s.window || !v.window || !v.superview) return;
    CGRect f = [v convertRect:v.bounds toView:nil];
    CGRect sr = LGSrcRect(s);
    CGAffineTransform old = v.transform;
    CGFloat oldA = v.alpha;
    CGFloat dx = CGRectGetMidX(sr) - CGRectGetMidX(f), dy = CGRectGetMidY(sr) - CGRectGetMidY(f);
    v.alpha = 0;
    v.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.3, 0.3), CGAffineTransformMakeTranslation(dx, dy));
    LGLog(@"animation dự phòng cho menu %s (morph không chạy được)", object_getClassName(container));
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ v.transform = old; v.alpha = oldA; } completion:nil];
}

static NSString *gLastSig;     // chữ ký bố cục (chữ + khung) của lần thử trước, để biết menu đã dựng xong chưa

static void LGHandle(UIView *container, int attempt) {
    if (!container.window) { LGUnhide(); gBusy = NO; return; }
    if ([LGMenuMorph isActive] && [LGMenuMorph activeContainer] == container) { LGUnhide(); gBusy = NO; return; }
    [container layoutIfNeeded];
    NSMutableArray *labels = [NSMutableArray new];
    LGLabelsOf(container, labels);
    if (!labels.count) {   // menu chưa dựng xong nội dung -> thử lại vài lần
        if (attempt < 4) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ LGHandle(container, attempt + 1); });
        } else {
            LGLog(@"bỏ qua: menu %s không có chữ sau %d lần thử", object_getClassName(container), attempt);
            LGFallback(container, nil);
            LGUnhide();
            gBusy = NO;
        }
        return;
    }
    // Hàng có tiêu đề + phụ đề được dựng/đo muộn: chụp ảnh khi bố cục chưa xong sẽ ra chữ bị cắt và chồng lên nhau.
    // Chờ tới khi chữ + khung của mọi nhãn giống hệt lần thử trước (mỗi lần 25 ms, tối đa 6 lần).
    NSMutableString *sg = [NSMutableString stringWithFormat:@"%p#", container];
    for (UILabel *l in labels) {
        CGRect lr = [l convertRect:l.bounds toView:nil];
        [sg appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f|", l.text, lr.origin.x, lr.origin.y, lr.size.width, lr.size.height];
    }
    if (attempt < 6 && ![sg isEqualToString:gLastSig ?: @""]) {
        gLastSig = sg;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ LGHandle(container, attempt + 1); });
        return;
    }
    gLastSig = nil;
    UIView *content = LGLCA(labels);
    UIView *body = content;   // leo lên đến view "thân menu" (nhỏ hơn ~90% bề rộng container)
    while (body.superview && body.superview != container &&
           body.superview.bounds.size.width < container.bounds.size.width * 0.9) body = body.superview;
    if (!content || body == container || !body.superview) {
        LGLog(@"bỏ qua: container=%s content=%s body=%s", object_getClassName(container),
              content ? object_getClassName(content) : "nil", body ? object_getClassName(body) : "nil");
        LGFallback(container, nil);
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
    // Trả nút về trạng thái thật TRƯỚC khi dò nhóm nút (nút đang bị ẩn alpha = 0 sẽ bị LGGroupFor bỏ qua -> viên thuốc tụt thành một nút).
    // Cửa sổ phủ của hiệu ứng ấn vẫn che bên trên cho tới khi morph hiện (LGUnhide ở cuối LGHandle mới tắt nó).
    LGPressRestoreSources();
    NSArray<UIView *> *sources = LGGroupFor(s);
    NSMutableString *names = [NSMutableString string];
    for (UIView *v in sources) [names appendFormat:@"%s%@ ", object_getClassName(v), NSStringFromCGRect([v convertRect:v.bounds toView:nil])];
    LGLog(@"menu từ nút: %@", names);
    CGRect fb = CGRectMake(gTouch.x - 22, gTouch.y - 22, 44, 44);
    @try {
        [LGMenuMorph beginWithContainer:container body:body sources:sources fallbackRect:fb];
    } @catch (NSException *ex) {
        LGLog(@"NGOẠI LỆ khi bắt đầu morph: %@ %@ -> hủy, trả menu về nguyên trạng", ex.name, ex.reason);
        [LGMenuMorph cancelAll];
    }
    if (![LGMenuMorph isActive]) LGFallback(container, body);     // setup thất bại / ngoại lệ: không có phiên morph
    LGUnhide();
    gBusy = NO;
}

%group LGMain

%hook UIApplication
- (void)sendEvent:(UIEvent *)e {
    if (gEnabled && e.type == UIEventTypeTouches) {
        for (UITouch *t in e.allTouches) {
            [LGMenuMorph touch:t];     // chạm ngoài menu -> đóng (làm TRƯỚC %orig để lớp phủ lên trước khi hệ thống kịp đóng)
            if (t.phase == UITouchPhaseEnded || t.phase == UITouchPhaseCancelled) LGPressRelease();
            if (t.phase != UITouchPhaseBegan) continue;
            if (t.view && !LGInMenu(t.view)) {
                gSource = LGPickSource(t.view);
                gTouch = [t locationInView:nil];
                gSourceT = CACurrentMediaTime();
                // lóe sáng + phóng to ngay khi chạm xuống nút (TRƯỚC %orig: nút chưa bị làm mờ vì highlight)
                if (LGP.press && gSource && ![LGMenuMorph isActive] && LGPressIsCandidate(gSource)) LGPressBegin(LGGroupFor(gSource));
            }
        }
    }
    %orig;
}
%end

// App present một view controller (bảng chọn tệp...) ngay sau khi người dùng chạm mục menu -> bỏ animation đóng (xem LGMenuMorph +modalPresented)
%hook UIViewController
- (void)presentViewController:(UIViewController *)vc animated:(BOOL)flag completion:(void (^)(void))completion {
    if (gEnabled && [LGMenuMorph isActive]) [LGMenuMorph modalPresented];
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
        if (LGButtonLike(self)) LGRingDetach(self);
        return;
    }
    // vòng cố định quanh nút mở menu (độc lập với việc vừa chạm hay chưa)
    if (LGP.ring && LGButtonLike(self) && !LGInMenu(self) && LGRingIsCandidate(self)) LGRingSchedule(self);
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
    // chờ hệ thống dựng xong 1 vòng runloop; nếu hiệu ứng ấn chưa chạy đủ pressHold thì chờ thêm cho đủ (menu thật đang bị ẩn)
    double wait = LGPressRemaining();
    if (wait > 0.001) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LGHandle(top, 0); });
    else dispatch_async(dispatch_get_main_queue(), ^{ LGHandle(top, 0); });
}
%end

%end // group LGMain

// plist do người dùng sửa tay: kiểu dữ liệu sai không được làm crash app đích
#define LGNUM(key, field) if ([p[key] respondsToSelector:@selector(doubleValue)]) LGP.field = [p[key] doubleValue];
static BOOL LGBoolOf(id v, BOOL def) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def; }

static NSString *gBid = @"";
static BOOL gIsNotes = NO;

// Đọc cài đặt: nền là file plist (chỉnh tay / bản cũ), đè lên bằng domain CFPreferences do bảng Cài đặt ghi (đọc qua cfprefsd nên app bị sandbox vẫn đọc được).
static NSDictionary *LGReadPrefs(void) {
    NSMutableDictionary *d = [NSMutableDictionary new];
    for (NSString *path in @[ kOldPrefs, kPrefs ]) {
        NSDictionary *f = [NSDictionary dictionaryWithContentsOfFile:ROOT_PATH_NS(path)];
        if ([f isKindOfClass:NSDictionary.class]) [d addEntriesFromDictionary:f];
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    CFArrayRef keys = CFPreferencesCopyKeyList((__bridge CFStringRef)kDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (keys) {
        NSDictionary *m = (__bridge_transfer NSDictionary *)CFPreferencesCopyMultiple(keys, (__bridge CFStringRef)kDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if ([m isKindOfClass:NSDictionary.class]) [d addEntriesFromDictionary:m];
        CFRelease(keys);
    }
    NSUserDefaults *su = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
    NSDictionary *sd = [su persistentDomainForName:kDomain];
    if ([sd isKindOfClass:NSDictionary.class]) [d addEntriesFromDictionary:sd];
    return d;
}

static void LGApplyPrefs(NSDictionary *p) {
    BOOL isSB = [gBid isEqualToString:@"com.apple.springboard"];
    gEnabled = LGBoolOf(p[@"enabled"], YES);
    if (isSB && !LGBoolOf(p[@"springboard"], NO)) gEnabled = NO;
    // onlyApps: chỉ chạy trong các app này (rỗng/không có = mọi app). excludeApps: loại trừ. "ex.<bundle id>" = công tắc loại trừ trong Cài đặt.
    id only = p[@"onlyApps"], ex = p[@"excludeApps"];
    if ([only isKindOfClass:NSArray.class] && ((NSArray *)only).count && ![(NSArray *)only containsObject:gBid]) gEnabled = NO;
    if ([ex isKindOfClass:NSArray.class] && [(NSArray *)ex containsObject:gBid]) gEnabled = NO;
    if (LGBoolOf(p[[@"ex." stringByAppendingString:gBid]], NO)) gEnabled = NO;

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
    LGNUM(@"pressScale", pressScale) LGNUM(@"pressOmega", pressOmega) LGNUM(@"pressZeta", pressZeta)
    LGNUM(@"pressFlash", pressFlash) LGNUM(@"pressHold", pressHold)
    LGNUM(@"ringMargin", ringMargin) LGNUM(@"ringPadX", ringPadX) LGNUM(@"groupGap", groupGap) LGNUM(@"liquidDrop", liquidDrop)
    LGNUM(@"bounceAmp", bounceAmp) LGNUM(@"bounceOmega", bounceOmega) LGNUM(@"bounceZeta", bounceZeta)
    if ([p[@"material"] respondsToSelector:@selector(intValue)]) LGP.material = [p[@"material"] intValue];
    if ([p[@"overlayMode"] respondsToSelector:@selector(intValue)]) LGP.overlayMode = [p[@"overlayMode"] intValue];
    if ([p[@"style"] respondsToSelector:@selector(intValue)]) LGP.style = [p[@"style"] intValue];
    LGP.useGlass = LGBoolOf(p[@"useGlass"], LGP.useGlass);
    LGP.coverButton = LGBoolOf(p[@"coverButton"], LGP.coverButton);
    LGP.hideSource = LGBoolOf(p[@"hideSource"], LGP.hideSource);
    LGP.groupButtons = LGBoolOf(p[@"groupButtons"], LGP.groupButtons);
    LGP.blurText = LGBoolOf(p[@"blurText"], LGP.blurText);
    LGP.closeAnim = LGBoolOf(p[@"closeAnim"], LGP.closeAnim);
    LGP.bounce = LGBoolOf(p[@"bounce"], LGP.bounce);
    LGP.pressFlashOn = LGBoolOf(p[@"flash"], YES);
    LGP.pressZoomOn = LGBoolOf(p[@"zoom"], YES);
    LGP.press = LGP.pressFlashOn || LGP.pressZoomOn;
    LGP.ring = LGBoolOf(p[@"ring"], LGP.ring);
    LGP.ringAll = LGBoolOf(p[@"ringAll"], LGP.ringAll);
    LGP.ringBack = LGBoolOf(p[@"ringBack"], LGP.ringBack);
    LGP.fallbackAnim = LGBoolOf(p[@"fallbackAnim"], LGP.fallbackAnim);
    // Log chỉ ghi khi có sự kiện menu. Dump cây view/class (nặng) mặc định chỉ bật ở Ghi chú; app khác muốn dump thì đặt dump = true.
    LGP.dump = LGBoolOf(p[@"dump"], gIsNotes);
    LGP.debug = LGBoolOf(p[@"debug"], LGP.debug);
    LGParamsFinalize();
    LGLogOn = LGP.debug;
    LGLog(@"cài đặt [%@]: bật=%d vòng=%d vòngQuayLại=%d lóe=%d phóng=%d nảy=%d gộp=%d dựPhòng=%d", gBid, gEnabled, LGP.ring, LGP.ringBack,
          LGP.pressFlashOn, LGP.pressZoomOn, LGP.bounce, LGP.groupButtons, LGP.fallbackAnim);
}

// Bảng Cài đặt đổi công tắc -> Darwin notification -> mọi tiến trình đọc lại và dựng / gỡ vòng ngay, không cần mở lại app.
static void LGPrefsChanged(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef ui) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            LGApplyPrefs(LGReadPrefs());
            if (!gEnabled) { LGPressFinish(); [LGMenuMorph cancelAll]; }
            LGRingRescanAll(gEnabled);
        } @catch (NSException *ex) { LGLog(@"NGOẠI LỆ khi đọc lại cài đặt: %@ %@", ex.name, ex.reason); }
    });
}

%ctor {
    @autoreleasepool {
        NSDictionary *p = LGReadPrefs();
        gBid = NSBundle.mainBundle.bundleIdentifier ?: @"";
        gIsNotes = [gBid isEqualToString:@"com.apple.mobilenotes"];
        LGApplyPrefs(p);
        BOOL isSB = [gBid isEqualToString:@"com.apple.springboard"];
        if (gEnabled && (gIsNotes || p[@"debug"])) LGLog(@"LiquidMenu v3 khởi động trong %@ log: %@", gBid, LGLogPaths());
        // Luôn gắn hook (trừ SpringBoard khi springboard = false): các hook tự thoát sớm khi gEnabled = NO nên bật lại trong Cài đặt có hiệu lực ngay.
        if (!isSB || LGBoolOf(p[@"springboard"], NO)) {
            %init(LGMain);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LGPrefsChanged, kReloadNote, NULL,
                                            CFNotificationSuspensionBehaviorDeliverImmediately);
        }
    }
}
