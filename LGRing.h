#import <UIKit/UIKit.h>

// Vòng tròn / viên thuốc CỐ ĐỊNH quanh nút mở menu (luôn hiện, kể cả khi không chạm).
// Hình học = đúng hình xuất phát của animation mở: khung nút (hoặc cả nhóm nút liền nhau gộp thành một),
// bo góc = min(rộng, cao) / 2 -> một nút là hình tròn, hai nút liền nhau là viên thuốc. Nền/viền/màu phủ dùng cùng tham số
// (tint, rim, material) với khối kính của animation nên lúc bàn giao không bị nhảy.

// Hai hàm này được định nghĩa trong Tweak.x (dùng chung).
NSArray<UIView *> *LGGroupFor(UIView *src);
BOOL LGButtonLike(UIView *v);

/// Cửa sổ phủ dùng chung cho hiệu ứng ấn và morph: UIWindow riêng, hoặc (trong extension / remote view service, nơi cửa sổ riêng không hiển thị)
/// một view phủ kín trong cửa sổ `win`. LGOverlayShow bỏ ẩn + đưa lên trên cùng; LGOverlayDrop ẩn và gỡ.
UIView *LGMakeOverlay(UIWindow *win);
void LGOverlayShow(UIView *ov);
void LGOverlayDrop(UIView *ov);

/// View có UIContextMenuInteraction / UIButton.menu không (= nút sinh ra menu).
BOOL LGHasMenuInteraction(UIView *v);
/// View (hoặc tổ tiên gần) là nút "quay lại" của thanh điều hướng.
BOOL LGIsBackButton(UIView *v);
/// Ứng viên cho hiệu ứng ấn (như LGRingIsCandidate nhưng không phụ thuộc công tắc ringBack).
BOOL LGPressIsCandidate(UIView *v);
/// Quét lại mọi cửa sổ để dựng / gỡ vòng ngay (khi đổi công tắc trong Cài đặt). enabled = NO: gỡ hết.
void LGRingRescanAll(BOOL enabled);

/// Khung NHÌN THẤY của nút trong toạ độ cửa sổ: căn theo vùng nội dung (icon/chữ) chứ không theo khung kỹ thuật của nút,
/// nút chữ -> viên thuốc (chữ + đệm hai bên), nút icon -> hình tròn; cách mép cửa sổ ít nhất `ringMargin`. Dùng chung cho vòng, hiệu ứng ấn và morph.
CGRect LGSrcRect(UIView *v);

/// View này có phải nút cần vẽ vòng không (nút có menu; hoặc mọi UIButton nhỏ nếu ringAll). Chỉ nhận nút SÂU NHẤT.
BOOL LGRingIsCandidate(UIView *v);
/// Lên lịch dựng / cập nhật vòng cho nút (chờ layout xong; gọi lại sau khi nút vào window).
void LGRingSchedule(UIView *v);
/// Gỡ vòng của nút khi nó rời window.
void LGRingDetach(UIView *v);
/// Ẩn / hiện vòng của các nút (trong lúc morph chạy). Trả về YES nếu có vòng nào bị đổi.
BOOL LGRingHide(NSArray<UIView *> *views, BOOL hide);

// ---- Hiệu ứng ẤN nút (lóe sáng + phóng to), theo video demo ----
// Vẽ trong một UIWindow riêng nằm trên cùng: viên kính (đúng hình vòng cố định) phóng to bằng lò xo và sáng lên; nút thật + vòng bị ẩn tạm.
/// Chạm xuống nút (gọi TRƯỚC khi hệ thống xử lý chạm, để chụp icon lúc nút chưa bị làm mờ vì highlight).
void LGPressBegin(NSArray<UIView *> *sources);
/// Nhả tay: nếu menu không hiện trong ~0,25 s thì hiệu ứng thu về chỗ cũ.
void LGPressRelease(void);
/// Trả nút thật + vòng về nguyên trạng NHƯNG giữ cửa sổ phủ của hiệu ứng ấn (che khung hình trung gian); LGPressFinish tắt nốt sau khi morph đã hiện.
void LGPressRestoreSources(void);
/// Dừng NGAY, trả nút/vòng về nguyên trạng (gọi ngay trước khi morph bắt đầu hoặc khi bỏ qua menu).
void LGPressFinish(void);
/// Còn bao nhiêu giây nữa mới đủ thời gian giữ tối thiểu `pressHold` kể từ lúc chạm (0 nếu không có hiệu ứng đang chạy).
double LGPressRemaining(void);
