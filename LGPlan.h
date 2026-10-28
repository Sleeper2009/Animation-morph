// Hình học của animation mở, theo bản Flutter. C thuần (không CoreGraphics) nên test được trên máy tính.
//
// Bản Flutter: thân menu neo ở GÓC TRÊN-PHẢI, bắt đầu từ a0 = tâm nút + (1, 7), trượt tới
// a1 = GÓC TRÊN-PHẢI CỦA NÚT; menu cuối cùng nằm ĐÈ LÊN nút.
// iOS lại đặt menu thật bên dưới nút. Nếu cứ trượt tới menu thật thì thân đi XUỐNG (ngược hướng bản Flutter).
// cover = 1: dời menu thật lên sao cho góc neo của nó trùng góc neo của nút (giống bản Flutter).
// cover = 0: giữ menu ở chỗ hệ thống, neo vào điểm của menu gần tâm nút nhất (hành vi cũ).
#ifndef LGPLAN_H
#define LGPLAN_H
typedef struct { double x, y, w, h; } LGBox;   // khung: gốc trái-trên + kích thước

typedef struct {
    double ax, ay;       // góc neo của thân (0 hoặc 1; ở chế độ cover=0 là tỉ lệ bất kỳ trong [0,1])
    double a0x, a0y;     // điểm neo lúc bắt đầu (thân còn bằng 0)
    double a1x, a1y;     // điểm neo lúc kết thúc (= góc neo của menu sau khi dời)
    double dx, dy;       // cần dời menu thật bao nhiêu (cover=1), cộng vào frame hiện tại
} LGPlan;

static inline double lgplan_clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

/// src: khung nút | F0: khung menu thật hiện tại | scr: vùng màn hình (cùng hệ toạ độ) | cover: xem trên
static inline LGPlan LGPlanGeometry(LGBox src, LGBox F0, LGBox scr, int cover) {
    LGPlan p = {0};
    double cx = src.x + src.w / 2, cy = src.y + src.h / 2;
    if (!cover) {
        double nx = lgplan_clamp(cx, F0.x, F0.x + F0.w), ny = lgplan_clamp(cy, F0.y, F0.y + F0.h);
        p.ax = lgplan_clamp((nx - F0.x) / F0.w, 0, 1);  p.ay = lgplan_clamp((ny - F0.y) / F0.h, 0, 1);
        p.a0x = cx; p.a0y = cy; p.a1x = nx; p.a1y = ny;
        return p;
    }
    p.ax = cx > scr.x + scr.w / 2 ? 1 : 0;      // nút nằm nửa phải -> neo góc phải
    p.ay = cy > scr.y + scr.h / 2 ? 1 : 0;      // nút nằm nửa dưới -> neo góc dưới
    double tx = (p.ax ? src.x + src.w : src.x) - p.ax * F0.w;   // góc trái-trên của menu sau khi dời
    double ty = (p.ay ? src.y + src.h : src.y) - p.ay * F0.h;
    // giữ menu trong màn hình (lề 8 pt) nếu nó vừa; không vừa thì để nguyên
    if (F0.w <= scr.w - 16) tx = lgplan_clamp(tx, scr.x + 8, scr.x + scr.w - 8 - F0.w);
    if (F0.h <= scr.h - 16) ty = lgplan_clamp(ty, scr.y + 8, scr.y + scr.h - 8 - F0.h);
    p.dx = tx - F0.x;  p.dy = ty - F0.y;
    p.a1x = tx + p.ax * F0.w;  p.a1y = ty + p.ay * F0.h;
    p.a0x = cx + (p.ax ? 1 : -1);  p.a0y = cy + (p.ay ? -7 : 7);
    return p;
}
#endif
