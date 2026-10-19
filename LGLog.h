#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Bật/tắt log (gán từ plist). Log vừa ra NSLog (oslog) vừa ghi vào file.
extern BOOL LGLogOn;

/// Một dòng log. Không làm gì nếu LGLogOn = NO.
void LGLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);

/// Ghi nguyên khối văn bản (nhiều dòng) vào file, không qua NSLog (NSLog cắt ngắn chuỗi dài).
void LGLogBlock(NSString *title, NSString *text);

/// Ghi cây view: class, khung (toạ độ window), alpha, hidden, số animation, bo góc, chữ của UILabel.
void LGLogTree(NSString *title, UIView *root);

/// Ghi danh sách class có tên chứa ContextMenu / _UIMenu / MenuContainer và các method liên quan tới
/// present/dismiss/animate/transition của chúng (chỉ chạy một lần mỗi tiến trình).
void LGLogClassesOnce(void);

/// Những đường dẫn file log đang ghi được (để hiện trong README / log đầu tiên).
NSString *LGLogPaths(void);

#ifdef __cplusplus
}
#endif
