#import "LGLog.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <stdio.h>
#import <string.h>
#import <sys/stat.h>
#import <unistd.h>

BOOL LGLogOn = YES;

static dispatch_queue_t gQ;
static NSMutableArray<NSString *> *gPaths;   // các file ghi được (tối đa 3)
static CFAbsoluteTime gWall0;
static CFTimeInterval gMono0;

// App hệ thống như Ghi chú bị sandbox: không chắc chỗ nào ghi được, nên thử nhiều chỗ và ghi vào tối đa 3 chỗ.
static void LGLogInit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gQ = dispatch_queue_create("liquidmenu.log", DISPATCH_QUEUE_SERIAL);
        gPaths = [NSMutableArray new];
        gWall0 = CFAbsoluteTimeGetCurrent();
        gMono0 = CACurrentMediaTime();
        NSMutableArray<NSString *> *cands = [NSMutableArray new];
        // Tên file có bundle id của app để tìm bằng Filza là biết ngay file nào của app nào (trước đây mọi app đều tên LiquidMenu.log).
        NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
        NSString *fn = [NSString stringWithFormat:@"LiquidMenu-%@.log", bid];
        NSString *tmp = NSTemporaryDirectory();
        if (tmp.length) [cands addObject:[tmp stringByAppendingPathComponent:fn]];
        NSArray<NSString *> *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        if (caches.firstObject.length) [cands addObject:[caches.firstObject stringByAppendingPathComponent:fn]];
        for (NSString *dir in @[ @"/var/mobile/Library/Caches", @"/var/mobile/Documents", @"/var/tmp", @"/tmp" ])
            [cands addObject:[dir stringByAppendingPathComponent:fn]];
        for (NSString *p in cands) {
            const char *cp = p.fileSystemRepresentation;
            struct stat st;
            BOOL big = (stat(cp, &st) == 0 && st.st_size > 600 * 1024);
            FILE *f = fopen(cp, big ? "w" : "a");     // file quá lớn thì cắt đi viết lại
            if (!f) continue;
            fclose(f);
            [gPaths addObject:p];
            if (gPaths.count >= 3) break;
        }
    });
}

NSString *LGLogPaths(void) {
    LGLogInit();
    return gPaths.count ? [gPaths componentsJoinedByString:@"  |  "] : @"(không ghi được file nào)";
}

static void LGAppend(NSString *s) {
    LGLogInit();
    NSArray<NSString *> *paths = [gPaths copy];
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_async(gQ, ^{
        for (NSString *p in paths) {
            FILE *f = fopen(p.fileSystemRepresentation, "a");
            if (!f) continue;
            fwrite(d.bytes, 1, d.length, f);
            fclose(f);
        }
    });
}

static NSString *LGStamp(void) {
    LGLogInit();
    double dt = CACurrentMediaTime() - gMono0;
    NSDate *d = [NSDate dateWithTimeIntervalSinceReferenceDate:gWall0 + dt];
    static NSDateFormatter *fmt;
    if (!fmt) { fmt = [NSDateFormatter new]; fmt.dateFormat = @"HH:mm:ss.SSS"; }
    return [NSString stringWithFormat:@"%@ [%d %@]", [fmt stringFromDate:d], (int)getpid(), NSBundle.mainBundle.bundleIdentifier ?: @"?"];
}

void LGLog(NSString *fmt, ...) {
    if (!LGLogOn) return;
    va_list ap;
    va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[LiquidMenu] %@", s);
    LGAppend([NSString stringWithFormat:@"%@ %@\n", LGStamp(), s]);
}

void LGLogBlock(NSString *title, NSString *text) {
    if (!LGLogOn) return;
    LGAppend([NSString stringWithFormat:@"%@ ===== %@ =====\n%@\n===== hết %@ =====\n", LGStamp(), title, text, title]);
}

// ---------------------------------------------------------------- cây view
static void LGDumpNode(UIView *v, int depth, NSMutableString *out, int *count) {
    if (*count >= 600 || depth > 16) return;
    (*count)++;
    CGRect fr = [v convertRect:v.bounds toView:nil];
    NSMutableString *line = [NSMutableString string];
    for (int i = 0; i < depth; i++) [line appendString:@"  "];
    [line appendFormat:@"%s frame=%@", object_getClassName(v), NSStringFromCGRect(fr)];
    if (v.alpha < 0.999) [line appendFormat:@" alpha=%.2f", v.alpha];
    if (v.hidden) [line appendString:@" HIDDEN"];
    if (!v.userInteractionEnabled) [line appendString:@" noUI"];
    if (v.clipsToBounds) [line appendString:@" clip"];
    if (v.layer.cornerRadius > 0.5) [line appendFormat:@" rad=%.1f", v.layer.cornerRadius];
    if (v.layer.mask) [line appendString:@" mask"];
    if (!CGAffineTransformIsIdentity(v.transform)) [line appendFormat:@" T=%@", NSStringFromCGAffineTransform(v.transform)];
    NSUInteger an = v.layer.animationKeys.count;
    if (an) [line appendFormat:@" anim=%lu(%@)", (unsigned long)an, [v.layer.animationKeys componentsJoinedByString:@","]];
    if ([v isKindOfClass:UILabel.class]) {
        NSString *t = ((UILabel *)v).text ?: @"";
        if (t.length > 32) t = [[t substringToIndex:32] stringByAppendingString:@"…"];
        [line appendFormat:@" text=\"%@\"", t];
    }
    [line appendString:@"\n"];
    [out appendString:line];
    for (UIView *s in v.subviews) LGDumpNode(s, depth + 1, out, count);
}

void LGLogTree(NSString *title, UIView *root) {
    if (!LGLogOn || !root) return;
    NSMutableString *out = [NSMutableString string];
    int count = 0;
    // chuỗi tổ tiên (từ window xuống) để biết menu nằm ở đâu trong cây
    NSMutableArray<NSString *> *chain = [NSMutableArray new];
    for (UIView *a = root.superview; a; a = a.superview) [chain insertObject:[NSString stringWithUTF8String:object_getClassName(a)] atIndex:0];
    UIWindow *w = root.window;
    [out appendFormat:@"window=%s level=%.0f frame=%@ tổ tiên: %@\n", w ? object_getClassName(w) : "nil", w ? (double)w.windowLevel : 0.0,
                       w ? NSStringFromCGRect(w.frame) : @"-", [chain componentsJoinedByString:@" > "]];
    LGDumpNode(root, 0, out, &count);
    if (count >= 600) [out appendString:@"… (cắt ở 600 view)\n"];
    LGLogBlock(title, out);
}

// ---------------------------------------------------------------- class / method
void LGLogClassesOnce(void) {
    static BOOL done;
    if (done || !LGLogOn) return;
    done = YES;
    unsigned int n = 0;
    Class *list = objc_copyClassList(&n);
    if (!list) return;
    NSArray<NSString *> *keys = @[ @"ContextMenu", @"_UIMenu", @"MenuContainer", @"UIMenuController" ];
    NSArray<NSString *> *mk = @[ @"dismiss", @"present", @"animat", @"transition", @"appear", @"collapse", @"expand",
                                 @"submenu", @"hide", @"show", @"push", @"pop" ];
    NSMutableString *out = [NSMutableString stringWithFormat:@"%u class trong tiến trình\n", n];
    int shown = 0;
    for (unsigned int i = 0; i < n && out.length < 160000; i++) {
        const char *cn = class_getName(list[i]);
        if (!cn) continue;
        BOOL hit = NO;
        for (NSString *k in keys) if (strstr(cn, k.UTF8String)) { hit = YES; break; }
        if (!hit) continue;
        shown++;
        Class sup = class_getSuperclass(list[i]);
        [out appendFormat:@"%s : %s\n", cn, sup ? class_getName(sup) : "-"];
        unsigned int mc = 0;
        Method *ms = class_copyMethodList(list[i], &mc);
        int printed = 0;
        for (unsigned int j = 0; j < mc && printed < 60; j++) {
            const char *sn = sel_getName(method_getName(ms[j]));
            if (!sn) continue;
            NSString *s = [NSString stringWithUTF8String:sn];
            BOOL m = NO;
            for (NSString *k in mk) if ([s rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) { m = YES; break; }
            if (m) { [out appendFormat:@"    - %@\n", s]; printed++; }
        }
        free(ms);
    }
    free(list);
    [out appendFormat:@"(%d class khớp)\n", shown];
    LGLogBlock(@"class liên quan menu", out);
}
