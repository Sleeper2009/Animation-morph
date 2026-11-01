#import "LMExperimentalListController.h"

@implementation LMExperimentalListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Experimental" target:self];
    return _specifiers;
}

@end
