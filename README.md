# LiquidMenu (Theos tweak)

Animation mở menu kiểu metaball: nút "…" tách thành giọt, thân menu lớn ra từ nút, nội dung phóng to sau.

## Build bằng GitHub Actions (không cần máy Mac)
1. Tạo repo mới trên github.com, đưa **toàn bộ file trong thư mục này** lên (Makefile nằm ở gốc repo, cạnh `Tweak.x`).
   Thư mục `.github` là thư mục ẩn (bắt đầu bằng dấu chấm) nên Finder/trình duyệt hay không hiện hoặc không kéo thả được.
   Nếu thiếu, tạo tay: **Add file → Create new file**, gõ tên `.github/workflows/build.yml` (gõ dấu `/` sẽ tự tạo thư mục) rồi dán nội dung file đó vào.
2. Vào tab **Actions**. Workflow **Build .deb** tự chạy mỗi lần push, hoặc bấm **Run workflow** để chạy tay.
3. Chạy xong (vài phút) mở lần chạy đó, kéo xuống **Artifacts**:
   - `LiquidMenu-rootless`: cho jailbreak rootless (Dopamine, palera1n rootless...).
   - `LiquidMenu-rootful`: cho jailbreak rootful (checkra1n, unc0ver, Taurine...).
   Mỗi artifact là một file zip chứa file `.deb`.
4. Muốn tải thẳng `.deb` từ iPhone không cần đăng nhập: đẩy một tag dạng `v0.1.0`
   (`git tag v0.1.0 && git push origin v0.1.0`, hoặc **Releases → Draft a new release** và đặt tag). `.deb` sẽ được đính vào trang Releases.
5. Cài `.deb` bằng Sileo/Filza/`dpkg -i`, rồi mở lại app đích.

Workflow không build RootHide. Nếu lỗi biên dịch, mở bước **Build** trong log và gửi nội dung lỗi.

## Build tay trên máy có Theos
1. Cài Theos (có `$THEOS`), SDK iOS.
2. `make clean package` -> file .deb trong `packages/` (mặc định rootless).
   Rootful: đổi `Architecture` trong `control` thành `iphoneos-arm`, rồi `make clean package THEOS_PACKAGE_SCHEME=`.
3. (Tuỳ chọn) đổi `com.yourname.liquidmenu` trong `control` và `kPrefs` trong `Tweak.x`. Hai chỗ này không bắt buộc để build, chỉ cần khớp nhau nếu bạn dùng file plist cấu hình bên dưới.

## Cách hoạt động
- Hook `-[UIApplication sendEvent:]` để biết nút nào vừa được chạm.
- Hook `-[UIView didMoveToWindow]`: khi view có tên class chứa một chuỗi trong `hints` xuất hiện ngay sau lúc chạm
  -> coi là menu. Lấy view NGOÀI CÙNG vẫn khớp `hints` làm container, rồi tìm thân menu (tổ tiên chung của các UILabel).
- Ẩn menu thật, dựng vỏ kính riêng (UIGlassEffect nếu có, không thì blur), cắt bằng mask metaball do CADisplayLink cập nhật mỗi khung.
- Cuối animation hiện lại menu thật (vẫn bấm được).
- Mặc định chỉ inject vào app Ghi chú (xem `LiquidMenu.plist`) để thử an toàn.

## Tên class private KHÔNG được kiểm chứng
Mặc định dò theo chuỗi `ContextMenu`, `_UIMenu`, `MenuContainer`. Nếu không thấy gì xảy ra:
1. Tạo `/var/jb/var/mobile/Library/Preferences/com.yourname.liquidmenu.plist` (rootful: `/var/mobile/Library/Preferences/...`) với `debug = true`.
2. Mở app, bấm nút "…", xem log (`oslog`/Console) lọc `LiquidMenu`:
   - các dòng `+ClassName` là mọi view vừa xuất hiện;
   - dòng `morph container=… body=…` cho biết view nào được chọn làm container / thân menu;
   - dòng `bỏ qua: container=… content=… body=…` cho biết vì sao không morph (không tìm được thân menu);
   - dòng `body.transform != identity` nghĩa là hệ thống để menu ở trạng thái đầu lúc ta chụp, và đã được reset về identity.
3. Đưa tên class đúng của view ngoài cùng của menu vào mảng `hints` trong plist.
   `hints` cũng quyết định chạm nào được coi là "chạm trong menu" (không được tính là nút nguồn).

## Plist tuỳ chọn (không cần build lại)
enabled, springboard (bool), debug (bool), hints (array string), useGlass (bool),
omega, offsetDelay, contentDelay, dotOmega, dotDelay, radOmega, radDelay, blend, speed (số; speed 0.2 = chậm 5 lần để soi từng khung).

Giá trị sai kiểu bị bỏ qua thay vì làm crash app đích. `hints` chỉ nhận chuỗi không rỗng (rỗng thì dùng mặc định).
Số bị chặn về khoảng hợp lệ: `speed` 0.05–10, `omega`/`dotOmega`/`radOmega` ≥ 1, các delay và `blend` ≥ 0.
Thời lượng tổng `dur` được tính từ các spring (delay + 8/omega, tối thiểu 0.5 s, tối đa 3 s), nên đổi `omega` thì menu thật không bị nhảy lúc hiện lại.

## Hạn chế
- Chỉ animation mở; đóng menu vẫn là của hệ thống.
- Nội dung scale cả khối (bản Flutter scale từng hàng và xuống dòng lại).
- Bóng đổ của menu thật bị ẩn trong lúc morph.
- Chưa được thử trên thiết bị: tên class private, thứ tự gọi `didMoveToWindow` và việc xoá animation hệ thống (`removeAllAnimations`) cần kiểm bằng `debug = true`.
- `UIGlassEffect` đặt trên view cao bằng cả host rồi cắt bằng mask: viền và khúc xạ kính tính theo khung cả view, không theo hình morph, nên có thể trông phẳng hơn kính thật (đã có viền `rim` bù).
