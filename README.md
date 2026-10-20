# LiquidMenu v3 (Theos tweak) — bản thử nghiệm

Thay animation mở/đóng menu của nút (UIButton menu) bằng morph kiểu metaball theo bản Flutter mẫu.
Từ v3.2 chạy **toàn hệ thống**: `LiquidMenu.plist` lọc `com.apple.UIKit` nên tweak được nạp vào mọi app dùng UIKit
(SpringBoard mặc định TẮT, xem bên dưới). Chưa kiểm thử ngoài Ghi chú: nếu một app lỗi, thêm bundle id của app đó vào `excludeApps`.
Muốn quay lại chỉ thử Ghi chú: sửa `LiquidMenu.plist` theo chú thích trong file, hoặc đặt `onlyApps = [com.apple.mobilenotes]` trong plist tuỳ chọn.

## Build bằng GitHub Actions
Giống bản trước: đưa **toàn bộ file** lên repo (Makefile nằm ở gốc, cạnh `Tweak.x`), workflow `.github/workflows/build.yml`
tự build; tải `.deb` ở **Actions → Artifacts** (`LiquidMenu-rootless`). Cài bằng Sileo/Filza rồi mở lại Ghi chú.

**File MỚI so với v2** (phải thêm vào repo): `LGTimeline.h`, `LGLog.h`, `LGLog.m`.
**File đổi**: `Tweak.x`, `LGMenuMorph.h`, `LGMenuMorph.m`, `LGMetaball.h`, `LGMetaball.c`, `Makefile`, `README.md`
(`LGPlan.h` giữ nguyên nội dung, đưa lên lại cũng được).

## Đã làm trong bản này
- **Mở** đúng timeline Flutter: icon nút biến mất ~12 ms và thay bằng khối kính; thân neo góc trên-phải, lớn lên bằng spring (ω=29),
  điểm neo đứng yên ~124 ms rồi trượt về góc trên-phải của nút (menu cuối đè lên nút); chấm nút co lại và dính vào thân bằng metaball
  (độ dính 24 → 0 tới 0,24 s); bo góc 150 → bo cuối; **từng hàng** phóng 0 → 1 quanh tâm hàng, chữ hiện từ mờ sang nét.
- **Đóng** = timeline mở chạy ngược, 380 ms. Nút chỉ hiện lại ở khung cuối.
- **Hai nút liền nhau** (vd chia sẻ + "…") gộp thành **một viên thuốc** làm hình xuất phát; menu neo vào góc trên-phải của viên thuốc.
  Mọi nút trong nhóm bị ẩn suốt lúc menu mở.
- **Cách đóng**: chạm bất cứ đâu ngoài các mục; chạm một mục (kể cả mục mở trang khác như "Xem tệp đính kèm"); hoặc hệ thống tự đóng
  → đều chạy animation đóng.
- Khối kính dựng trong **một UIWindow riêng** nằm trên cùng (nên animation đóng vẫn chạy khi hệ thống đã gỡ menu), có blur + lớp phủ màu + bóng + viền mảnh
  để nhìn thấy cả trên nền trắng của Ghi chú. Menu thật bị ẩn trong lúc morph và hiện lại ở khung cuối (có bước chuyển mờ từ ảnh chụp để không giật).
- Menu thật được giữ đúng chỗ (`center` + kiểm tra mỗi khung hình), nên chạm nhẹ không làm tấm menu bị tụt xuống.
- Chỉ menu mở từ **nút** mới có animation; menu nhấn giữ lên ghi chú/thư mục (không bắt đầu từ nút) thì bỏ qua.

## Chưa làm (vòng sau)
- **Menu con** (chạm một mục mở menu khác: ẩn menu trước, hiện menu mới lên trên, đóng bằng animation đóng). Bản này **chỉ ghi log**
  khi nội dung menu đổi (dòng `NỘI DUNG ĐỔI` + cây view) để vòng sau làm cho đúng.
- SpringBoard (Trung tâm điều khiển, menu màn hình khoá...) chưa hỗ trợ; Tweak mặc định không đụng tới nó.
- Nội dung là ảnh chụp từng hàng nên chữ không tự xuống dòng theo bề rộng lúc còn hẹp như bản Flutter (bị cắt theo hình khối).

## LOG (quan trọng cho vòng sau)
Bản này **bật log sẵn** (không cần plist); log chỉ được ghi khi có sự kiện menu, mỗi dòng có bundle id của app. Cây view/danh sách class (nặng) mặc định chỉ ghi ở Ghi chú; app khác muốn ghi thì đặt `dump = true`. Tweak ghi nhật ký vào tối đa 3 file tên `LiquidMenu.log` ở những chỗ ghi được trong Ghi chú:
thư mục `tmp` và `Library/Caches` của chính app Ghi chú, `/var/mobile/Library/Caches/`, `/var/mobile/Documents/`, `/var/tmp/`, `/tmp/`.
Đường dẫn thật được ghi ở **dòng đầu tiên của log** (`LiquidMenu v3 khởi động … log: …`) và cả trong oslog.

Cách tìm bằng Filza: vào `/var/mobile/Containers/Data/Application/` rồi dùng ô tìm kiếm với từ khoá `LiquidMenu.log`
(hoặc xem thẳng `/var/mobile/Library/Caches/LiquidMenu.log`, `/var/tmp/LiquidMenu.log`). Lấy file mới nhất, gửi cả file.
Log có: cây view của menu và của nút ngay khi xuất hiện, danh sách class/method liên quan menu, mọi lần chạm, từng chuyển trạng thái
(BẮT ĐẦU → MỞ XONG → ĐÓNG: lý do → ĐÓNG XONG → KẾT THÚC), các lần chỉnh vị trí menu (`pin`), và `theo dõi: A=… S=…`
(độ mờ/độ thu nhỏ của menu thật khi hệ thống đóng nó).

Mỗi lần thử nên: mở Ghi chú → mở menu "…" → đợi một chút → đóng (chạm ra ngoài) → mở lại → chạm một mục (vd Xem tệp đính kèm),
rồi gửi log và video quay màn hình (nói rõ tweak kính iOS 26 đang bật hay tắt).

## Plist tuỳ chọn (không cần build lại)
`/var/jb/var/mobile/Library/Preferences/com.yourname.liquidmenu.plist` (đường dẫn qua `ROOT_PATH_NS`; không có file thì dùng mặc định).
- bool: `enabled`, `springboard`, `debug` (log), `dump` (ghi cây view/class), `useGlass`, `coverButton`, `hideSource`, `groupButtons`, `blurText`, `closeAnim`
- số: `omega`, `offsetDelay`, `contentDelay`, `dotOmega`, `dotDelay`, `radOmega`, `radDelay`, `blend`, `closeDur`, `speed` (0,2 = chậm 5 lần),
  `tint`, `shadow`, `rim` (độ đậm lớp phủ / bóng / viền, 0–1), `material` (−1 = chép nền kính của menu thật; 0–4 = UltraThin…Chrome)
- `onlyApps` (mảng bundle id: chỉ chạy trong các app này), `excludeApps` (mảng bundle id: bỏ qua các app này), `springboard` (bool, mặc định false)
- `hints`: mảng chuỗi — tên class private của view menu (mặc định `ContextMenu`, `_UIMenu`, `MenuContainer`)

Giá trị sai kiểu bị bỏ qua thay vì làm crash app đích; số bị chặn về khoảng hợp lệ.

## Các file
`Tweak.x` (hook, nhận ra menu và nút nguồn, nhóm nút), `LGMenuMorph.h/.m` (phiên animation: cửa sổ phủ, khối kính, hàng, mở/đóng, giữ vị trí, phát hiện hệ thống đóng),
`LGTimeline.h` (timeline Flutter, C thuần), `LGPlan.h` (hình học neo/dời menu), `LGMetaball.h/.c` (đường viền metaball cho cả viên thuốc),
`LGLog.h/.m` (ghi log ra file), `LiquidMenu.plist` (filter app), `control`, `Makefile`.

## Những điều chưa kiểm chứng được (không có thiết bị ở đây)
Tên class private trên iOS 16.7.7; việc dời menu bằng `center` có giữ được khi hệ thống layout lại; hệ thống đóng menu có phát hiện được qua độ mờ/thu nhỏ không;
UIVisualEffectView bị mask có blur mượt trên iPhone 8 Plus; cửa sổ phủ có blur được nền phía dưới. Toàn bộ mã đã biên dịch sạch với SDK iOS 16.5 thật và phần toán
(timeline, metaball, hình học) đã test số học trên máy tính, nhưng hành vi trên máy thật phải dựa vào log vòng sau.
