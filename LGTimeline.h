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
} LGTimeFrame;

static inline double lgtl_clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
static inline double lgtl_lerp(double a, double b, double t) { return a + (b - a) * t; }
// Spring tới hạn (zeta = 1) dạng đóng: 0 -> 1 kể từ t = 0. t <= 0 -> 0.
static inline double lgtl_sp(double t, double w) { return t <= 0 ? 0 : 1 - (1 + w * t) * exp(-w * t); }

static inline LGTimeFrame LGTimelineAt(const LGTimeSpec *sp, const LGTimeGeom *g, double tau) {
    LGTimeFrame f;
    tau = lgtl_clamp(tau, 0, sp->dur);
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
    return f;
}
#endif
