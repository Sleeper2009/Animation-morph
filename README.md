# LiquidMenu (Theos tweak) — bản thử nghiệm

Thay animation mở/đóng menu của nút (UIButton menu) bằng animation **"Menu Liquid Glass"**: nút "…" biến hình thành menu rồi co lại thành nút (port từ bản mẫu HTML, đo từ video).
Từ v3.2 chạy **toàn hệ thống**: `LiquidMenu.plist` lọc `com.apple.UIKit` nên tweak được nạp vào mọi app dùng UIKit
(SpringBoard mặc định TẮT, xem bên dưới). Chưa kiểm thử ngoài Ghi chú: nếu một app lỗi, thêm bundle id của app đó vào `excludeApps`.
Muốn quay lại chỉ thử Ghi chú: sửa `LiquidMenu.plist` theo chú thích trong file, hoặc đặt `onlyApps = [com.apple.mobilenotes]` trong plist tuỳ chọn.

## Build bằng GitHub Actions
Giống bản trước: đưa **toàn bộ file** lên repo (Makefile nằm ở gốc, cạnh `Tweak.x`), workflow `.github/workflows/build.yml`
tự build; tải `.deb` ở **Actions → Artifacts** (`LiquidMenu-rootless`). Cài bằng Sileo/Filza rồi mở lại Ghi chú.

**File đổi so với bản trước**: `LGTimeline.h` (viết lại hoàn toàn), `LGPlan.h`, `LGMenuMorph.h`, `LGMenuMorph.m`, `LGGlass.h`, `LGGlass.m`, `Tweak.x`,
`Makefile`, `liquidmenuprefs/Resources/Root.plist`, `README.md`. **File XOÁ**: `LGMetaball.h`, `LGMetaball.c` (không còn metaball; nhớ xoá khỏi repo).

## Animation (một kiểu duy nhất)
Kiểu Morph / metaball cũ, kiểu Liquid, hiệu ứng nảy khi đóng và mục "Kiểm tra kính" đều đã bị thay bằng animation mới
(các khoá plist `style`, `liquidDrop`, `glassDebug`, `bounce*`, `omega`, `offsetDelay`, `contentDelay`, `dotOmega`, `dotDelay`, `radOmega`, `radDelay`, `blend` không còn tác dụng).

**Một khối kính duy nhất** vừa là nút "…" vừa là menu (không còn chấm / cầu nối metaball). Timeline nằm trong `LGTimeline.h`, giữ đúng bản mẫu:
- **Mở**: bốn lò xo tắt dần (tâm x, tâm y, rộng, cao) từ khung nút tới khung menu, mỗi lò xo có "lực bắn" ban đầu nên menu **lao xuống rồi lắng lại**
  (ω = 14,2 / 19,5 / 17,0 / 16,4; ζ = 0,97 / 0,72 / 0,79 / 0,88). Lắng xong trong 0,6 s.
- **Bo góc**: khối bắt đầu là viên thuốc tròn đều (hai đầu bán nguyệt, không nhọn), rồi co về bo góc cuối của menu thật (k: 1 → 0 trong ~0,4 s). Với menu ngắn / rộng, MỘT góc (góc neo) giữ độ cong của nút nên khối là giọt nước; **góc neo nằm theo vị trí nút** (nút trái-dưới → góc trái-dưới, nút phải-trên → góc phải-trên…). Với menu **dài** (cao ≳ 1,45 × rộng) bỏ hẳn góc neo: viên thuốc rồi bung ra, không nhọn ở góc nào (như iOS 26).
  Khối luôn bám nút: quãng "bắn" của lò xo xa khỏi nút bị giới hạn mềm ~1,25 cạnh nút, nên menu dài không bị lơ lửng tách khỏi nút. Icon của nút trôi về phía nút (lên nếu menu bung xuống, xuống nếu bung lên).
  Bán kính bốn góc bị co theo luật CSS `border-radius` giống trình duyệt.
- **Nội dung** là một khối nằm giữa khối kính: phóng 1,28 → 1, mờ → nét, nhạt → rõ trong 0,14 s; icon "…" của nút biến mất trong 40 ms và trôi lên theo bề cao khối.
- **Đóng**: bảng 14 khung đo từ video (nội suy PCHIP): khối lao xuống lấy đà, co lại, **vọt qua nút ~14 px rồi lắng xuống** (thay cho hiệu ứng nảy cũ); 0,545 s (khoá `closeDur`).
  Đóng khi đang mở dở thì độ lệch so với menu tắt dần trong 0,16 s.
- Mọi đại lượng được **chuẩn hoá theo quãng đường nút → menu** nên chạy đúng với mọi vị trí / kích thước nút và menu (kể cả viên thuốc hai nút).
- Kiểm tra bằng máy tính: timeline C khớp với vật lý của bản mẫu HTML (lệch ≤ 0,11 pt ở khung chốt cuối của pha mở, ≤ 0,002 pt ở pha đóng; bán kính góc khớp hoàn toàn).

**Kính Liquid Glass** (công tắc `glass`, mặc định TẮT; bật trong Cài đặt → LiquidMenu → Kính):
- Khối kính là MỘT `MTMaterialView` trong `LMGlassHost`, hình dạng là **mặt nạ path** (bốn góc bầu dục khác nhau); lớp blur + màu phủ + viền cũ tắt đi.
- Muốn kính kiểu iOS 26 cần tweak **Liquid (Gl)ass** với luật Custom Views: `Target Class = MTMaterialView`, `Ancestor Class = LMGlassHost`.
  Không có tweak đó thì `MTMaterialView` hiện như kính mờ gốc. Máy không có MaterialKit thì tự quay về blur.
- Chưa kiểm thử trên máy thật: cần xem mặt nạ path trên `MTMaterialView` có giữ được blur / hiệu ứng kính không (nếu mất, báo lại để chuyển sang cách khác).

## Cách hoạt động chung
- **Hai nút liền nhau** (vd chia sẻ + "…") gộp thành **một viên thuốc** làm hình xuất phát; menu neo vào góc trên-phải của viên thuốc (menu cuối đè lên nút).
  Mọi nút trong nhóm bị ẩn suốt lúc menu mở.
- **Cách đóng**: chạm bất cứ đâu ngoài các mục; chạm một mục (kể cả mục mở trang khác như "Xem tệp đính kèm"); hoặc hệ thống tự đóng
  → đều chạy animation đóng. Nút chỉ hiện lại ở khung cuối.
- Khối kính dựng trong **một UIWindow riêng** nằm trên cùng (nên animation đóng vẫn chạy khi hệ thống đã gỡ menu), có blur + lớp phủ màu + bóng + viền mảnh
  để nhìn thấy cả trên nền trắng của Ghi chú. Menu thật bị ẩn trong lúc animation và hiện lại ở khung cuối (nội dung lớp phủ là ảnh chụp đúng menu thật nên không giật).
- Menu thật được giữ đúng chỗ (`center` + kiểm tra mỗi khung hình), nên chạm nhẹ không làm tấm menu bị tụt xuống.
- Chỉ menu mở từ **nút** mới có animation; menu nhấn giữ lên ghi chú/thư mục (không bắt đầu từ nút) thì bỏ qua.

## Chưa làm (vòng sau)
- **Menu con** (chạm một mục mở menu khác: ẩn menu trước, hiện menu mới lên trên, đóng bằng animation đóng). Bản này **chỉ ghi log**
  khi nội dung menu đổi (dòng `NỘI DUNG ĐỔI` + cây view) để vòng sau làm cho đúng.
- SpringBoard (Trung tâm điều khiển, menu màn hình khoá...) chưa hỗ trợ; Tweak mặc định không đụng tới nó.
- Nội dung là một ảnh chụp (phóng / mờ theo timeline) nên chữ không tự xuống dòng theo bề rộng lúc còn hẹp; ảnh bị cắt theo hình khối.

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
`/var/jb/var/mobile/Library/Preferences/com.fujb-2009.liquidmenu.plist` (đường dẫn qua `ROOT_PATH_NS`; không có file thì dùng mặc định).
- bool: `enabled`, `springboard`, `debug` (log), `dump` (ghi cây view/class), `glass` (kính Liquid Glass), `useGlass`, `coverButton`, `hideSource`, `groupButtons`, `blurText`, `closeAnim`
- số: `closeDur` (giây, mặc định 0,545), `speed` (hệ số tốc độ chung, 0,4–3),
  `tint`, `shadow`, `rim` (độ đậm lớp phủ / bóng / viền, 0–1), `material` (−1 = chép nền kính của menu thật; 0–4 = UltraThin…Chrome)
- `onlyApps` (mảng bundle id: chỉ chạy trong các app này), `excludeApps` (mảng bundle id: bỏ qua các app này), `springboard` (bool, mặc định false)
- `hints`: mảng chuỗi — tên class private của view menu (mặc định `ContextMenu`, `_UIMenu`, `MenuContainer`)

Giá trị sai kiểu bị bỏ qua thay vì làm crash app đích; số bị chặn về khoảng hợp lệ.

## Các file
`Tweak.x` (hook, nhận ra menu và nút nguồn, nhóm nút), `LGMenuMorph.h/.m` (phiên animation: cửa sổ phủ, khối kính, nội dung, mở/đóng, giữ vị trí, phát hiện hệ thống đóng),
`LGTimeline.h` (timeline Liquid Glass: lò xo mở, bảng khung đóng, bo góc; C thuần), `LGPlan.h` (hình học dời menu),
`LGLog.h/.m` (ghi log ra file), `LGRing.h/.m` (vòng quanh nút + hiệu ứng ấn), `LGGlass.h/.m` (viên kính MTMaterialView), `liquidmenuprefs/` (bảng Cài đặt), `LiquidMenu.plist` (filter app), `control`, `Makefile`.

## Những điều chưa kiểm chứng được (không có thiết bị ở đây)
Tên class private trên iOS 16.7.7; việc dời menu bằng `center` có giữ được khi hệ thống layout lại; hệ thống đóng menu có phát hiện được qua độ mờ/thu nhỏ không;
UIVisualEffectView bị mask có blur mượt trên iPhone 8 Plus; cửa sổ phủ có blur được nền phía dưới. Bản này CHƯA biên dịch với SDK iOS thật (chỉ kiểm tra cú pháp bằng khai báo giả); phần toán
(timeline, bán kính góc, hình học) đã test số học trên máy tính, nhưng hành vi trên máy thật phải dựa vào log vòng sau.
