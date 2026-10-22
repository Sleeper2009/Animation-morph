// Timeline của animation, đúng công thức bản Flutter (xem _overlay / _content trong file mẫu).
// C thuần (không UIKit/CoreGraphics) nên test được trên máy tính.
//
//   tau = giây kể từ lúc chạm, 0 .. dur.  Mở = tau chạy 0 -> dur;  Đóng = tau chạy ngược dur -> 0
//   (bản Flutter: c.forward() 500 ms, c.reverse() 380 ms, c.value tuyến tính, tau = c.value * 0.5,
//   nên khung hình lúc đóng là đúng khung hình lúc mở nhưng xem ngược).
#ifndef LGTIMELINE_H
#define LGTIMELINE_H
#include <math.h>
#include "LGMetaball.h"   // LGBox

typedef struct {
    double omega, offsetDelay, contentDelay;   // spring tới hạn: kích thước thân / trượt về góc nút / nội dung
    double dotOmega, dotDelay;                 // chấm "nút gốc" co lại
    double radOmega, radDelay;                 // bo góc: viên thuốc -> bo cuối
    double blend;                              // độ dính metaball (pt)
    double dur;                                // tổng timeline (s)
    int style;                                 // 0 = morph metaball (bản Flutter), 1 = giọt lỏng (đo từ video iOS 26)
} LGTimeSpec;

typedef struct {
    double W, H;                 // kích thước menu cuối
    double ax, ay;               // góc neo của thân (0/1, hoặc tỉ lệ 0..1)
    double a0x, a0y, a1x, a1y;   // điểm neo lúc đầu / lúc cuối
    double rFinal;               // bo góc cuối
    LGBox dot;                   // hộp của nút (hoặc của cả cặp nút) = hình xuất phát
} LGTimeGeom;

typedef enum { LGModeDot = 0, LGModeBody = 1, LGModeMeta = 2 } LGMode;

typedef struct {
    LGMode mode;            // chỉ có chấm / chỉ có thân / thân dính chấm (metaball)
    LGBox body;  double r;  // thân và bo góc
    LGBox dot;   double dotR;   // chấm (co dần về tâm) và bo góc của nó (= viên thuốc)
    double k;               // độ dính hiện tại
    double ps, po, pc, pd, pr;  // tiến độ các spring (để test)
    double op;              // độ rõ của chữ 0..1
    double blurMix;         // 0 = nét, 1 = mờ nhất (Flutter: sigma = (1 - op) * 3)
    double iconAlpha;       // icon nút gốc: biến mất trong 12 ms đầu
    double full;            // 0..1: pha trộn sang ảnh chụp menu thật ở 60 ms cuối (để bàn giao không giật)
    double rowK, rowAy, rowA1y;  // cách đặt các hàng chữ: khoảng cách tới điểm neo nhân rowK; điểm neo = rowAy của thân; rowA1y = toạ độ y neo lúc cuối
} LGTimeFrame;

static inline double lgtl_clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
static inline double lgtl_lerp(double a, double b, double t) { return a + (b - a) * t; }
// Spring tới hạn (zeta = 1) dạng đóng: 0 -> 1 kể từ t = 0. t <= 0 -> 0.
static inline double lgtl_sp(double t, double w) { return t <= 0 ? 0 : 1 - (1 + w * t) * exp(-w * t); }

// Nảy khi đóng: dao động tắt dần (lò xo thiếu giảm chấn) CHUẨN HOÁ để đỉnh đầu tiên = 1.
//   t = giây kể từ lúc animation đóng chạm đáy; w = tần số góc (rad/s); zeta = hệ số giảm chấn (0..1, càng nhỏ càng nảy nhiều).
//   Giá trị: 0 lúc t = 0 -> vọt lên 1 (đỉnh) -> xuống hơi âm (lò xo kéo ngược lại) -> tắt dần về 0.
//   Độ dời thực = hướng * biên độ(pt) * lgtl_bounce(...).
static inline double lgtl_bounce(double t, double w, double zeta) {
    if (t <= 0) return 0;
    double z = lgtl_clamp(zeta, 0.01, 0.99);
    double wd = w * sqrt(1 - z * z);
    double tp = atan2(wd, z * w) / wd;                 // thời điểm đỉnh đầu tiên
    double peak = exp(-z * w * tp) * sin(wd * tp);
    return exp(-z * w * t) * sin(wd * t) / peak;
}
// Thời gian để đường bao biên độ tắt xuống còn ~0,5 pt (sau đó nhìn không ra nữa).
static inline double lgtl_bounce_dur(double w, double zeta, double amp) {
    double z = lgtl_clamp(zeta, 0.01, 0.99);
    return lgtl_clamp(log(fmax(amp / 0.5, 1.01)) / (z * w), 0.1, 1.5);
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

// Lò xo thiếu giảm chấn 0 -> 1 (có thể nhô quá 1). t <= 0 -> 0.
static inline double lgtl_step(double t, double w, double zeta) {
    if (t <= 0) return 0;
    double z = lgtl_clamp(zeta, 0.01, 0.999), wd = w * sqrt(1 - z * z);
    return 1 - exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t));
}
// Xung tới hạn chuẩn hoá: 0 -> đỉnh 1 tại t = 1/w -> tắt dần về 0 (không dao động ngược).
static inline double lgtl_kick(double t, double w) { return t <= 0 ? 0 : (w * t) * exp(1 - w * t); }

// ---- Kiểu 2: "giọt lỏng" (đo từ video iOS 26, 24 fps; khớp mép trên/dưới của menu sai số <= 4 px trên 8 khung) ----
//   * khối menu xuất phát từ NÚT dưới dạng giọt rất nhỏ rồi lao tới đúng vị trí cuối trong ~50 ms (không bay chậm từ góc như kiểu 1)
//   * chiều cao: lò xo gần tới hạn (ω = 28, ζ = 0,9) từ 20% -> 100%; chiều rộng nở nhanh hơn (ω = 55) từ 5% -> 100%
//   * "rơi": sau ~75 ms khối bị đẩy xuống thêm ~20% chiều cao rồi trượt về (xung tới hạn ω = 26, không dao động ngược)
//   * chữ mờ mạnh (blur) trong ~30 ms đầu, nét dần tới ~220 ms; bo góc tròn dần về bo cuối
//   * đóng = xem ngược timeline này (khớp video: lúc đóng khối cũng tụt xuống rồi co về nút thành giọt)
#define LGLIQ_H0 0.20
#define LGLIQ_HW 28.0
#define LGLIQ_HZ 0.90
#define LGLIQ_W0 0.05
#define LGLIQ_WW 55.0
#define LGLIQ_WZ 0.90
#define LGLIQ_MOVE_DELAY 0.008
#define LGLIQ_MOVE_W 100.0
#define LGLIQ_DROP 0.205
#define LGLIQ_DROP_DELAY 0.075
#define LGLIQ_DROP_W 26.0

static inline LGTimeFrame LGTimelineLiquid(const LGTimeSpec *sp, const LGTimeGeom *g, double tau) {
    LGTimeFrame f;
    double t = tau;
    double fcx = g->a1x - g->ax * g->W + g->W / 2, fcy = g->a1y - g->ay * g->H + g->H / 2;   // tâm menu cuối
    double bcx = g->dot.x + g->dot.w / 2, bcy = g->dot.y + g->dot.h / 2;                      // tâm nút
    double uh = lgtl_step(t, LGLIQ_HW, LGLIQ_HZ), uw = lgtl_step(t, LGLIQ_WW, LGLIQ_WZ);
    double hf = lgtl_lerp(LGLIQ_H0, 1.0, uh), wf = lgtl_lerp(LGLIQ_W0, 1.0, uw);
    double pm = lgtl_sp(t - LGLIQ_MOVE_DELAY, LGLIQ_MOVE_W);                                  // lao từ nút tới vị trí cuối
    double dir = g->ay >= 0.5 ? -1.0 : 1.0;                                                   // rơi theo hướng menu mở ra
    double cx = lgtl_lerp(bcx, fcx, pm);
    double cy = lgtl_lerp(bcy, fcy, pm) + dir * LGLIQ_DROP * g->H * lgtl_kick(t - LGLIQ_DROP_DELAY, LGLIQ_DROP_W);
    // lúc tau -> 0 (cuối animation đóng) khối co hẳn về 0 để chỉ còn lại nút
    double vis = lgtl_clamp(t / 0.03, 0, 1);
    double w = g->W * wf * vis, h = g->H * hf * vis;
    f.ps = uh; f.po = pm; f.pc = uh; f.pd = pm; f.pr = lgtl_sp(t, 20.0);
    f.body.x = cx - w / 2; f.body.y = cy - h / 2; f.body.w = w; f.body.h = h;
    f.r = fmin(lgtl_lerp(fmin(w, h) / 2, g->rFinal, f.pr), fmin(w, h) / 2);

    // nút gốc: co thành giọt 0,75 trong 20 ms rồi hoà vào khối
    double sc = t < 0.02 ? 1 - 0.25 * (t / 0.02) : 0.75 * (1 - lgtl_sp(t - 0.02, 40.0));
    double dcx = g->dot.x + g->dot.w / 2, dcy = g->dot.y + g->dot.h / 2;
    f.dot.w = g->dot.w * sc; f.dot.h = g->dot.h * sc;
    f.dot.x = dcx - f.dot.w / 2; f.dot.y = dcy - f.dot.h / 2;
    f.dotR = fmin(f.dot.w, f.dot.h) / 2;

    f.k = sp->blend * lgtl_clamp((0.10 - t) / 0.06, 0, 1);
    if (w < 1 || h < 1) f.mode = LGModeDot;
    else if (f.k < 0.5) f.mode = LGModeBody;
    else f.mode = LGModeMeta;

    f.op = lgtl_clamp(t / 0.08, 0, 1);
    f.blurMix = 1 - lgtl_clamp((t - 0.03) / 0.19, 0, 1);
    f.iconAlpha = lgtl_clamp(1 - t / 0.012, 0, 1);
    f.full = lgtl_clamp((tau - (sp->dur - 0.06)) / 0.06, 0, 1);
    f.rowK = lgtl_lerp(0.85, 1.0, uh);                  // chữ co theo khối
    f.rowAy = 0.5;                                      // hàng bám theo TÂM khối (kiểu 1: bám cạnh neo)
    f.rowA1y = fcy;
    return f;
}

static inline LGTimeFrame LGTimelineAt(const LGTimeSpec *sp, const LGTimeGeom *g, double tau) {
    LGTimeFrame f;
    tau = lgtl_clamp(tau, 0, sp->dur);
    if (sp->style == 1) return LGTimelineLiquid(sp, g, tau);
    f.ps = lgtl_sp(tau, sp->omega);
    f.po = lgtl_sp(tau - sp->offsetDelay, sp->omega);
    f.pc = lgtl_sp(tau - sp->contentDelay, sp->omega);
    f.pd = lgtl_sp(tau - sp->dotDelay, sp->dotOmega);
    f.pr = lgtl_sp(tau - sp->radDelay, sp->radOmega);

    double axp = lgtl_lerp(g->a0x, g->a1x, f.po), ayp = lgtl_lerp(g->a0y, g->a1y, f.po);
    double w = g->W * f.ps, h = g->H * f.ps;
    f.body.x = axp - g->ax * w;
    f.body.y = ayp - g->ay * h;
    f.body.w = w;
    f.body.h = h;
    f.r = fmin(lgtl_lerp(150.0, g->rFinal, f.pr), fmin(w, h) / 2);

    // chấm = chính hộp của nút, co về tâm theo (1 - pd); bo góc = nửa cạnh ngắn (tròn nếu vuông, viên thuốc nếu dài)
    double dcx = g->dot.x + g->dot.w / 2, dcy = g->dot.y + g->dot.h / 2, sc = 1 - f.pd;
    f.dot.w = g->dot.w * sc;
    f.dot.h = g->dot.h * sc;
    f.dot.x = dcx - f.dot.w / 2;
    f.dot.y = dcy - f.dot.h / 2;
    f.dotR = fmin(f.dot.w, f.dot.h) / 2;

    f.k = sp->blend * lgtl_clamp((0.24 - tau) / 0.08, 0, 1);
    if (w < 1 || h < 1) f.mode = LGModeDot;
    else if (f.k < 0.5) f.mode = LGModeBody;
    else f.mode = LGModeMeta;

    f.op = lgtl_clamp((f.pc - 0.35) / 0.5, 0, 1);
    f.blurMix = 1 - f.op;
    f.iconAlpha = lgtl_clamp(1 - tau / 0.012, 0, 1);
    f.full = lgtl_clamp((tau - (sp->dur - 0.06)) / 0.06, 0, 1);
    f.rowK = 1.0;
    f.rowAy = g->ay;
    f.rowA1y = g->a1y;
    return f;
}
#endif
