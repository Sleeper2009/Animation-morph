#import <Preferences/PSListController.h>

// Danh sách ứng dụng đã cài, mỗi ứng dụng một công tắc: BẬT = ứng dụng đó KHÔNG dùng animation của LiquidMenu.
// Lưu vào khoá "ex.<bundle id>" trong domain com.fujb-2009.liquidmenu (Tweak.x đọc đúng khoá này).
@interface LMAppsListController : PSListController
@end
