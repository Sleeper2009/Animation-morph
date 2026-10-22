#import "LMRootListController.h"
#import <rootless.h>
#import <spawn.h>
#import <unistd.h>

extern char **environ;

@implementation LMRootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

// Nút Respring nằm trên thanh tiêu đề, cạnh chữ "LiquidMenu".
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Respring" style:UIBarButtonItemStylePlain
                                                                             target:self action:@selector(respring)];
}

// Respring: ưu tiên sbreload, không có thì killall SpringBoard (đường dẫn rootless /var/jb tự thêm qua ROOT_PATH).
- (void)respring {
    const char *sbreload[] = { ROOT_PATH("/usr/bin/sbreload"), "/usr/bin/sbreload", NULL };
    for (int i = 0; sbreload[i]; i++) {
        if (access(sbreload[i], X_OK) != 0) continue;
        pid_t pid;
        char *argv[] = { "sbreload", NULL };
        if (posix_spawn(&pid, sbreload[i], NULL, NULL, argv, environ) == 0) return;
    }
    const char *killall[] = { ROOT_PATH("/usr/bin/killall"), "/usr/bin/killall", NULL };
    for (int i = 0; killall[i]; i++) {
        if (access(killall[i], X_OK) != 0) continue;
        pid_t pid;
        char *argv[] = { "killall", "-9", "SpringBoard", NULL };
        if (posix_spawn(&pid, killall[i], NULL, NULL, argv, environ) == 0) return;
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Không respring được"
                                                               message:@"Hãy respring bằng cách khác."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
