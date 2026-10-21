#import "LMAppsListController.h"
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>

#define kDomain @"com.fujb-2009.liquidmenu"
#define kReloadNote @"com.fujb-2009.liquidmenu/reload"

@interface UIImage (LMPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(CGFloat)scale;
@end

@implementation LMAppsListController

// Liệt kê ứng dụng qua LSApplicationWorkspace (API riêng, tra bằng runtime nên không cần link thêm framework).
- (NSArray<NSDictionary *> *)installedApps {
    NSMutableArray<NSDictionary *> *out = [NSMutableArray new];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defSel = NSSelectorFromString(@"defaultWorkspace"), allSel = NSSelectorFromString(@"allInstalledApplications");
    if (!wsClass || ![wsClass respondsToSelector:defSel]) return out;
    id ws = ((id (*)(id, SEL))objc_msgSend)(wsClass, defSel);
    if (![ws respondsToSelector:allSel]) return out;
    NSArray *proxies = ((id (*)(id, SEL))objc_msgSend)(ws, allSel);
    for (id px in proxies) {
        @try {
            NSString *bid = [px valueForKey:@"applicationIdentifier"];
            NSString *name = [px valueForKey:@"localizedName"];
            NSString *type = [px valueForKey:@"applicationType"];
            if (![bid isKindOfClass:NSString.class] || ![name isKindOfClass:NSString.class] || !bid.length || !name.length) continue;
            if (![type isEqualToString:@"User"] && ![type isEqualToString:@"System"]) continue;
            NSArray *tags = [px respondsToSelector:NSSelectorFromString(@"appTags")] ? [px valueForKey:@"appTags"] : nil;
            if ([tags isKindOfClass:NSArray.class] && [tags containsObject:@"hidden"]) continue;
            if ([seen containsObject:bid]) continue;
            [seen addObject:bid];
            [out addObject:@{ @"bid": bid, @"name": name }];
        } @catch (NSException *ex) { continue; }
    }
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return out;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray new];
        PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"Ứng dụng"];
        [g setProperty:@"Bật = ứng dụng đó không dùng animation." forKey:@"footerText"];
        [specs addObject:g];
        CGFloat scale = UIScreen.mainScreen.scale;
        for (NSDictionary *app in [self installedApps]) {
            PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:app[@"name"]
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSwitchCell
                                                              edit:nil];
            [s setProperty:[@"ex." stringByAppendingString:app[@"bid"]] forKey:@"key"];
            [s setProperty:@NO forKey:@"default"];
            [s setProperty:kDomain forKey:@"defaults"];
            [s setProperty:kReloadNote forKey:@"PostNotification"];
            if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)]) {
                UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:app[@"bid"] format:0 scale:scale];
                if (icon) [s setProperty:icon forKey:@"iconImage"];
            }
            [specs addObject:s];
        }
        _specifiers = specs;
    }
    return _specifiers;
}

@end
