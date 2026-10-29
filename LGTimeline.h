// Timeline của animation "Menu Liquid Glass", port nguyên văn từ bản mẫu HTML (khung 480x512 đo từ video).
// C thuần (không UIKit/CoreGraphics) nên test được trên máy tính.
//
// Một khối kính duy nhất vừa là nút "…" vừa là menu (không còn chấm / metaball như bản cũ):
//   MỞ    = 4 lò xo tắt dần (tâm x, tâm y, rộng, cao) từ khung nút tới khung menu, mỗi lò xo có "lực bắn" ban đầu
//           (menu lao xuống rồi mới lắng lại). Giải tích nên ổn định ở mọi bước thời gian.
//   ĐÓNG  = bảng khung đo trực tiếp từ video, nội suy PCHIP: hình lao xuống (lấy đà), co lại, vọt qua nút rồi lắng xuống.
//           Bắt đầu từ khung hình hiện tại (đóng khi đang mở dở): độ lệch so với menu tắt dần trong 0,16 s.
//   bo góc = VIÊN THUỐC tròn đều (bán kính = nửa cạnh ngắn, hai đầu bán nguyệt) -> bo góc cuối. Menu ngắn / rộng: một góc (góc neo, phía nút)
//           giữ độ cong của nút nên khối là "giọt nước"; menu DÀI: bỏ góc neo, khối là viên thuốc rồi bung ra, không nhọn ở góc nào.
//   góc neo = góc của menu trùng với góc của nút (theo vị trí nút trên màn hình: trên/dưới, trái/phải), không cố định ở trên-phải.
//   bám nút = khối không được tách khỏi nút quá ~1,25 cạnh nút trong lúc lò xo "bắn" (menu dài thì quãng bắn lớn hơn nhiều).
//
// Bản mẫu làm việc theo toạ độ px của khung đo; ở đây mọi đại lượng được CHUẨN HOÁ theo quãng đường nút -> menu
// (q = 0 tại nút, q = 1 tại menu) nên dùng được cho bất kỳ vị trí / kích thước nút và menu nào.
#ifndef LGTIMELINE_H
#define LGTIMELINE_H
#include <math.h>
#include "LGPlan.h"   // LGBox

#define LGMORPH_OPEN_DUR 0.60     // lò xo lắng xuống tới < 0,1 pt (bản mẫu: >= 0,5 s)
#define LGMORPH_CLOSE_T  0.545    // thời gian pha đóng ở tốc độ 1 (khung cuối của bảng đo)

typedef struct {
    LGBox src;          // khung nút (hoặc cả viên thuốc) = hình xuất phát / kết thúc
    LGBox dst;          // khung menu cuối (sau khi dời)
    double R;           // bo góc cuối của menu
    double rAnchor;     // độ cong giữ lại ở góc neo lúc biến hình (= độ cong của nút)
    int ax, ay;         // góc neo của menu: ax = 1 -> neo phải, 0 -> trái; ay = 1 -> neo dưới (menu bung lên), 0 -> trên (menu bung xuống)
} LGMorphGeom;

// Độ lệch của khung hình đang chạy so với menu khi bắt đầu đóng (tâm x, tâm y, rộng, cao)
typedef struct { double cx, cy, w, h; } LGMorphOff;

typedef struct {
    LGBox rect;         // khối kính hiện tại
    double k;           // 1 = bầu dục (hình nút), 0 = bo góc cuối
    double cs;          // phóng to nội dung quanh tâm khối (1,28 -> 1)
    double blur;        // độ mờ nội dung 0..1 (0 = nét; 1 = mờ như blur 11 px của bản mẫu)
    double ca;          // độ rõ nội dung 0..1
    double dots;        // độ rõ icon "…" của nút 0..1
    double alpha;       // độ đặc của khối kính (1; hạ xuống 0,667 ở cuối pha đóng để hoà vào nút thật)
    double pull;        // 0..1: mức khối bị HÚT méo về phía nút (pha đóng): góc neo thót lại, thân hơi dài ra -> hình quả trứng / giọt nước méo
    double btn;         // cỡ icon của nút (1 = bình thường): lúc đóng nút nhỏ, chờ khối nước chạm tới thì phình ra
    double pin;         // 0 = icon đi theo khối (pha mở), 1 = icon đứng yên tại nút (pha đóng)
} LGMorphFrame;

// Bán kính 4 góc (elip) sau khi áp luật CSS border-radius
typedef struct { double tlx, tly, trx, try_, brx, bry, blx, bly; } LGRadii;

static inline double lgtl_clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
static inline double lgtl_lerp(double a, double b, double t) { return a + (b - a) * t; }
static inline double lgtl_ss(double a, double b, double x) { double t = lgtl_clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }

// ---- lò xo mở (fit từ các khung hình của video, sai số ~3,6 px) ----
// p(t): 1 tại nút -> 0 tại menu (nhô qua 0 nếu thiếu giảm chấn). w = tần số góc, z = giảm chấn,
// v = vận tốc ban đầu CHUẨN HOÁ (1/s) = vận tốc px/s của bản mẫu chia cho quãng đường (âm = đang đi tới menu).
typedef struct { double w, z, v; } LGSpring;
static const LGSpring LGSP_CX = { 14.2, 0.97, -19.9053 };    // bản mẫu: v = -3364 px/s trên 169 px
static const LGSpring LGSP_CY = { 19.5, 0.72, -42.5076 };    //          v = +5611 px/s trên -132 px
static const LGSpring LGSP_W  = { 17.0, 0.79, -11.9915 };    //          v = +4221 px/s trên -352 px
static const LGSpring LGSP_H  = { 16.4, 0.88, -15.7331 };    //          v = +4185 px/s trên -266 px

static inline double lgtl_spring(const LGSpring *s, double t) {
    if (t <= 0) return 1;
    double z = lgtl_clamp(s->z, 0.01, 0.999), w = s->w, wd = w * sqrt(1 - z * z);
    double e = exp(-z * w * t);
    return e * (cos(wd * t) + ((s->v + z * w) / wd) * sin(wd * t));
}

// ---- bảng khung đóng (t, q) chuẩn hoá: q = (giá trị - nút) / (menu - nút) từ bảng đo của bản mẫu ----
#define LGCLOSE_N 14
static const double LGCL_T[LGCLOSE_N]  = { 0.000, 0.045, 0.087, 0.128, 0.170, 0.212, 0.253, 0.295, 0.337, 0.378, 0.420, 0.462, 0.503, 0.545 };
static const double LGCL_CX[LGCLOSE_N] = { 1.00000, 0.90828, 0.66864, 0.57692, 0.41420, 0.16864, 0.06509, 0.01479, 0.00592, 0, 0, 0, 0, 0 };
static const double LGCL_CY[LGCLOSE_N] = { 1.00000, 1.35227, 1.28788, 1.14015, 0.76894, 0.13258, -0.00758, -0.07955, -0.10606, -0.05303, -0.03030, -0.01515, -0.00758, 0 };
static const double LGCL_W[LGCLOSE_N]  = { 1.00000, 0.91193, 0.63068, 0.52557, 0.33523, 0.05966, 0.00568, -0.01420, -0.00568, 0, 0, 0, 0, 0 };
static const double LGCL_H[LGCLOSE_N]  = { 1.00000, 0.92857, 0.71429, 0.62030, 0.44737, 0.23684, 0.12782, 0.04135, -0.00752, 0, 0, 0, 0, 0 };

// Nội suy Hermite đơn điệu (PCHIP), vận tốc 0 ở hai đầu
static inline double lgtl_pchip(const double *xs, const double *ys, int n, double t) {
    if (t <= xs[0]) return ys[0];
    if (t >= xs[n - 1]) return ys[n - 1];
    double d[LGCLOSE_N], m[LGCLOSE_N];
    for (int i = 0; i < n - 1; i++) d[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]);
    for (int i = 0; i < n; i++) m[i] = 0;
    for (int i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : 2 * d[i - 1] * d[i] / (d[i - 1] + d[i]);
    int i = 0;
    while (t > xs[i + 1]) i++;
    double h = xs[i + 1] - xs[i], s = (t - xs[i]) / h, s2 = s * s, s3 = s2 * s;
    return (2 * s3 - 3 * s2 + 1) * ys[i] + (s3 - 2 * s2 + s) * h * m[i] + (-2 * s3 + 3 * s2) * ys[i + 1] + (s3 - s2) * h * m[i + 1];
}

// Trọng số góc neo theo độ dài menu: 1 = menu ngắn / rộng (giữ góc neo, hình giọt nước), 0 = menu dài (không có góc nhọn nào).
static inline double lgtl_anchor_weight(const LGMorphGeom *g) {
    double asp = g->dst.w > 1 ? g->dst.h / g->dst.w : 1;
    return 1 - lgtl_ss(1.05, 1.45, asp);
}

static inline LGBox lgtl_box_cwh(double cx, double cy, double w, double h) { LGBox b = { cx - w / 2, cy - h / 2, w, h }; return b; }
static inline double lgtl_cx(LGBox b) { return b.x + b.w / 2; }
static inline double lgtl_cy(LGBox b) { return b.y + b.h / 2; }

// nút -> menu theo chuẩn hoá q của từng trục
static inline LGBox lgtl_mix(const LGMorphGeom *g, double qcx, double qcy, double qw, double qh) {
    double sx = lgtl_cx(g->src), sy = lgtl_cy(g->src), dx = lgtl_cx(g->dst), dy = lgtl_cy(g->dst);
    return lgtl_box_cwh(sx + qcx * (dx - sx), sy + qcy * (dy - sy), g->src.w + qw * (g->dst.w - g->src.w), g->src.h + qh * (g->dst.h - g->src.h));
}

// Khối pha ĐÓNG: kích thước theo q = trung bình hai trục của bảng khung, nhưng TỈ LỆ CẠNH đi từ tỉ lệ của nút (tròn) lúc nhỏ tới tỉ lệ của menu lúc lớn.
// Bảng khung gốc (bản mẫu) để chiều cao co chậm hơn chiều rộng nên cuối pha đóng khối thành bầu dục dọc hẹp rồi mới về nút -> nút tròn mà khối thu lại thành bầu dục
// trông sai. Ở đây khối thu về hình TRÒN (giọt nước) cỡ nút, lớn dần mới giãn ra theo tỉ lệ menu.
static inline LGBox lgtl_mix_close(const LGMorphGeom *g, double qcx, double qcy, double qw, double qh, double pull) {
    double sx = lgtl_cx(g->src), sy = lgtl_cy(g->src), dx = lgtl_cx(g->dst), dy = lgtl_cy(g->dst);
    double q = fmax(0.5 * (qw + qh), -0.02);
    double As = g->src.w > 1 ? g->src.h / g->src.w : 1, A = g->dst.w > 1 ? g->dst.h / g->dst.w : 1;
    double asp = lgtl_lerp(As, A, lgtl_ss(0.30, 0.85, q)) * (1 + 0.20 * pull);   // bị hút thì thân dài ra theo hướng nút (quả trứng)
    double w, h;
    if (A >= 1) { w = g->src.w + q * (g->dst.w - g->src.w); h = w * asp; }          // menu cao: bề rộng dẫn, bề cao theo tỉ lệ
    else        { h = g->src.h + q * (g->dst.h - g->src.h); w = h / asp; }          // menu rộng: bề cao dẫn
    return lgtl_box_cwh(sx + qcx * (dx - sx), sy + qcy * (dy - sy), w, h);
}

// Giữ khối BÁM vào nút: quãng khối rơi xa khỏi cạnh neo của nút (mép trên nút nếu menu bung xuống, mép dưới nếu bung lên; mép phải / trái tương tự)
// vượt 1,25 cạnh nút thì phần vượt chỉ còn 30% (mềm, không bị khựng). Menu càng dài lò xo "bắn" càng xa -> không có chặn này khối sẽ lơ lửng tách khỏi nút.
static inline double lgtl_softcap(double gap, double c0) { return gap <= c0 ? gap : c0 + (gap - c0) * 0.3; }
static inline LGBox lgtl_attach(const LGMorphGeom *g, LGBox r) {
    double ch = g->src.h * 1.25, cw = g->src.w * 1.25;
    if (!g->ay) { double gap = r.y - g->src.y; if (gap > ch) r.y = g->src.y + lgtl_softcap(gap, ch); }
    else { double gap = (g->src.y + g->src.h) - (r.y + r.h); if (gap > ch) r.y += gap - lgtl_softcap(gap, ch); }
    if (!g->ax) { double gap = r.x - g->src.x; if (gap > cw) r.x = g->src.x + lgtl_softcap(gap, cw); }
    else { double gap = (g->src.x + g->src.w) - (r.x + r.w); if (gap > cw) r.x += gap - lgtl_softcap(gap, cw); }
    return r;
}

// Pha đóng: khối nước bị hút VÀO nút, không được trồi ra quá mép nút phía neo (bảng khung gốc cho cy "vọt" qua nút) quá 12% cạnh nút.
static inline LGBox lgtl_no_overshoot(const LGMorphGeom *g, LGBox r) {
    double ox = 0.12 * g->src.w, oy = 0.12 * g->src.h;
    if (!g->ay) { if (r.y < g->src.y - oy) r.y = g->src.y - oy; } else if (r.y + r.h > g->src.y + g->src.h + oy) r.y = g->src.y + g->src.h + oy - r.h;
    if (g->ax)  { if (r.x + r.w > g->src.x + g->src.w + ox) r.x = g->src.x + g->src.w + ox - r.w; } else if (r.x < g->src.x - ox) r.x = g->src.x - ox;
    return r;
}

// Pha đóng: khối nước bị hút tới nút nhưng nằm Ở PHÍA DƯỚI nút (phía menu), chỉ chạm nhẹ đầu nhọn vào nút, KHÔNG phủ lên nút. Mép khối phía nút không được
// vượt qua (mép nút phía menu) - ov * cạnh nút; ov tăng 0,25 -> 1 khi khối "chui" vào nút (nút phình ra đón).
static inline double lgtl_absorb(double t) { return 0.25 + 0.75 * lgtl_ss(0.28, 0.42, t); }
static inline LGBox lgtl_below_button(const LGMorphGeom *g, LGBox r, double t) {
    double ov = lgtl_absorb(t), cw = lgtl_ss(0.09, 0.17, t);     // cw: chỉ áp dụng khi khối đã nhỏ lại, menu to vừa rời đi thì không bị đẩy
    if (!g->ay) { double lim = g->src.y + g->src.h * (1 - ov); if (r.y < lim) r.y = lgtl_lerp(r.y, lim, cw); }
    else        { double lim = g->src.y + g->src.h * ov;       if (r.y + r.h > lim) r.y = lgtl_lerp(r.y, lim - r.h, cw); }
    return r;
}

/// Khung hình pha MỞ tại t giây kể từ lúc menu hiện (0 .. LGMORPH_OPEN_DUR). t >= dur: đúng khung menu.
static inline LGMorphFrame LGMorphOpen(const LGMorphGeom *g, double t) {
    LGMorphFrame f;
    if (t >= LGMORPH_OPEN_DUR) {
        f.rect = g->dst; f.k = 0; f.cs = 1; f.blur = 0; f.ca = 1; f.dots = 0; f.alpha = 1; f.pull = 0; f.btn = 1; f.pin = 0;
        return f;
    }
    if (t < 0) t = 0;
    // lò xo cho p = 1 tại nút -> 0 tại menu; lgtl_mix dùng q = 0 tại nút -> 1 tại menu, nên q = 1 - p
    f.rect = lgtl_attach(g, lgtl_mix(g, 1 - lgtl_spring(&LGSP_CX, t), 1 - lgtl_spring(&LGSP_CY, t), 1 - lgtl_spring(&LGSP_W, t), 1 - lgtl_spring(&LGSP_H, t)));
    f.k = (1 - lgtl_ss(0.08, 0.20, t)) * 0.9 + 0.1 * (1 - lgtl_ss(0.2, 0.4, t));
    f.cs = 1 + 0.28 * (1 - lgtl_ss(0.10, 0.24, t));
    f.blur = (1 - lgtl_ss(0.02, 0.20, t));
    f.ca = lgtl_ss(0, 0.14, t);
    f.dots = 1 - lgtl_ss(0, 0.04, t);
    f.alpha = 1; f.pull = 0; f.btn = 1; f.pin = 0;
    return f;
}

/// Độ lệch của khung hình hiện tại so với menu, để pha đóng bắt đầu đúng từ đó.
static inline LGMorphOff LGMorphOffsetFrom(const LGMorphGeom *g, LGBox cur) {
    LGMorphOff o = { lgtl_cx(cur) - lgtl_cx(g->dst), lgtl_cy(cur) - lgtl_cy(g->dst), cur.w - g->dst.w, cur.h - g->dst.h };
    return o;
}

/// Khung hình pha ĐÓNG tại t giây (đã nhân tốc độ) kể từ lúc bắt đầu đóng; off = LGMorphOffsetFrom (0 nếu đóng từ menu đã mở xong).
static inline LGMorphFrame LGMorphClose(const LGMorphGeom *g, LGMorphOff off, double t) {
    LGMorphFrame f;
    double tc = lgtl_clamp(t, 0, LGMORPH_CLOSE_T);
    double u = 1 - lgtl_ss(0, 0.16, t);
    f.pull = lgtl_ss(0.09, 0.17, t) * (1 - lgtl_ss(0.30, 0.42, t));
    LGBox r = lgtl_below_button(g, lgtl_no_overshoot(g, lgtl_attach(g, lgtl_mix_close(g, lgtl_pchip(LGCL_T, LGCL_CX, LGCLOSE_N, tc), lgtl_pchip(LGCL_T, LGCL_CY, LGCLOSE_N, tc),
                                               lgtl_pchip(LGCL_T, LGCL_W, LGCLOSE_N, tc), lgtl_pchip(LGCL_T, LGCL_H, LGCLOSE_N, tc), f.pull))), t);
    f.rect = lgtl_box_cwh(lgtl_cx(r) + off.cx * u, lgtl_cy(r) + off.cy * u, r.w + off.w * u, r.h + off.h * u);
    f.k = lgtl_ss(0.02, 0.13, t);
    f.ca = 1 - lgtl_ss(0.02, 0.15, t);
    f.blur = 8.0 / 11.0 * lgtl_ss(0, 0.14, t);
    f.cs = 1 + 0.08 * lgtl_ss(0, 0.05, t);
    // nút: hiện NHỎ (0,72) đứng yên tại chỗ lúc khối nước đang bị hút tới; khối chạm tới thì nút phình ra (nhún nhẹ) về cỡ thật
    f.pin = 1;
    f.dots = lgtl_ss(0.05, 0.12, t);
    f.btn = 0.72 + 0.28 * lgtl_ss(0.30, 0.47, t) + 0.025 * sin(M_PI * lgtl_ss(0.38, 0.54, t));
    double s = lgtl_ss(0, 0.04, t) * (1 - lgtl_ss(0.3, 0.5, t));
    f.alpha = lgtl_lerp(1, 0.667, s);
    return f;
}

/// Bán kính 4 góc (tròn đều): viên thuốc (nửa cạnh ngắn) <-> bo góc cuối R theo k. Góc neo (theo vị trí nút) giữ độ cong của nút lúc k = 1,
/// nhưng chỉ với menu ngắn / rộng; menu dài thì không có góc nào khác biệt. Vẫn áp luật CSS border-radius (co tất cả nếu hai bán kính kề nhau vượt cạnh).
static inline LGRadii LGMorphRadii(const LGMorphGeom *g, const LGMorphFrame *f) {
    double w = fmax(f->rect.w, 0), h = fmax(f->rect.h, 0), rcap = fmin(w, h) / 2;
    double a = lgtl_anchor_weight(g);
    double rb = fmin(lgtl_lerp(g->R, rcap, f->k), rcap);
    double ra = fmin(lgtl_lerp(g->R, lgtl_lerp(rcap, fmin(g->rAnchor, rcap), a), f->k), rcap);
    double c[4] = { rb, rb, rb, rb };          // TL, TR, BR, BL
    int ai = g->ay ? (g->ax ? 2 : 3) : (g->ax ? 1 : 0);
    c[ai] = fmin(ra, rcap * (1 - 0.58 * f->pull));     // bị hút: góc phía nút thót lại, các góc còn lại vẫn tròn đầy
    if (f->pull <= 0) c[ai] = ra;
    LGRadii r = { c[0], c[0], c[1], c[1], c[2], c[2], c[3], c[3] };
    double s = 1;
    if (r.tlx + r.trx > w && r.tlx + r.trx > 0) s = fmin(s, w / (r.tlx + r.trx));
    if (r.brx + r.blx > w && r.brx + r.blx > 0) s = fmin(s, w / (r.brx + r.blx));
    if (r.try_ + r.bry > h && r.try_ + r.bry > 0) s = fmin(s, h / (r.try_ + r.bry));
    if (r.tly + r.bly > h && r.tly + r.bly > 0) s = fmin(s, h / (r.tly + r.bly));
    if (s < 1) { r.tlx *= s; r.tly *= s; r.trx *= s; r.try_ *= s; r.brx *= s; r.bry *= s; r.blx *= s; r.bly *= s; }
    return r;
}

// Ấn nút (lóe sáng + phóng to), đo từ video demo (24 fps, nút 189 px):
//   phóng to: lò xo thiếu giảm chấn 1 -> target (demo: đỉnh ~1,34 ở ~100 ms rồi nhích về ~1,29)
//   lóe sáng: tiến về 1 theo hàm mũ, hằng số thời gian ~30 ms (độ sáng nền 19 -> 131 trong ~100 ms)
static inline double lgtl_press_scale(double t, double target, double w, double zeta) {
    if (t <= 0) return 1;
    double z = lgtl_clamp(zeta, 0.01, 0.99);
    double wd = w * sqrt(1 - z * z);
    double u = 1 - exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t));
    return 1 + (target - 1) * u;
}
static inline double lgtl_press_flash(double t, double tau) { return t <= 0 ? 0 : 1 - exp(-t / fmax(tau, 1e-3)); }
#endif
