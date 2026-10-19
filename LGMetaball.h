// Smooth-union (metaball) của hình chữ nhật bo góc + một hình "chấm" (tròn hoặc bầu dục) -> đường viền (marching squares).
// C thuần, không phụ thuộc CoreGraphics nên test được trên máy tính.
#ifndef LGMETABALL_H
#define LGMETABALL_H
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { double x, y, w, h; } LGBox;
typedef struct {
    void *ctx;
    void (*move)(void *ctx, double x, double y);
    void (*line)(void *ctx, double x, double y);
    void (*close)(void *ctx);
} LGSink;
// body: thân menu, r: bo góc thân, dot: hộp của "nút gốc", dotR: bo góc của dot (= min(w,h)/2 thì dot là hình tròn/viên thuốc),
// k: độ dính, step: bước lưới (pt)
void LGMetaballDot(LGBox body, double r, LGBox dot, double dotR, double k, double step, LGSink sink);
// Dạng cũ: chấm tròn tâm (cx,cy) bán kính rd
void LGMetaball(LGBox body, double r, double cx, double cy, double rd, double k, double step, LGSink sink);
#ifdef __cplusplus
}
#endif
#endif
