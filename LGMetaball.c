#include "LGMetaball.h"
#include <math.h>
#include <stdlib.h>

static double smin_(double a, double b, double k) {
    double h = fmax(k - fabs(a - b), 0.0) / k;
    return fmin(a, b) - h * h * k * 0.25;
}

static double sd_rrect(double px, double py, LGBox b, double r) {
    double dx = fabs(px - (b.x + b.w * 0.5)) - b.w * 0.5 + r;
    double dy = fabs(py - (b.y + b.h * 0.5)) - b.h * 0.5 + r;
    double ax = fmax(dx, 0.0), ay = fmax(dy, 0.0);
    return sqrt(ax * ax + ay * ay) + fmin(fmax(dx, dy), 0.0) - r;
}

// cạnh ô: 0=trên 1=phải 2=dưới 3=trái. Mỗi case = các cặp cạnh nối nhau (-1 kết thúc)
static const signed char TBL[16][5] = {
    {-1}, {3,0,-1}, {0,1,-1}, {3,1,-1}, {1,2,-1}, {3,0,1,2,-1}, {0,2,-1}, {3,2,-1},
    {3,2,-1}, {0,2,-1}, {0,1,3,2,-1}, {1,2,-1}, {3,1,-1}, {0,1,-1}, {3,0,-1}, {-1}
};

typedef struct { const double *v; int cols; double ox, oy, s; } Grid;

// id cạnh: node*2 (+0: cạnh ngang node->node+1, +1: cạnh dọc node->node+cols)
static void edge_pt(const Grid *g, int id, double *x, double *y) {
    int n = id >> 1, horiz = !(id & 1);
    int o = horiz ? n + 1 : n + g->cols;
    double t = g->v[n] / (g->v[n] - g->v[o]);
    double bx = g->ox + (n % g->cols) * g->s, by = g->oy + (n / g->cols) * g->s;
    if (horiz) { *x = bx + t * g->s; *y = by; } else { *x = bx; *y = by + t * g->s; }
}

static void link_(int *nb, int a, int b) {
    if (nb[a * 2] < 0) nb[a * 2] = b; else nb[a * 2 + 1] = b;
}

void LGMetaball(LGBox body, double r, double cx, double cy, double rd, double k, double step, LGSink sink) {
    double rr = fmax(rd, 1.0), pad = k + 3.0;
    double l = fmin(body.x, cx - rr) - pad, t = fmin(body.y, cy - rr) - pad;
    double rgt = fmax(body.x + body.w, cx + rr) + pad, btm = fmax(body.y + body.h, cy + rr) + pad;
    int nx = (int)ceil((rgt - l) / step), ny = (int)ceil((btm - t) / step);
    int cols = nx + 1, rows = ny + 1, nn = cols * rows;
    double *v = malloc(sizeof(double) * nn);
    int *nb = malloc(sizeof(int) * nn * 4);
    char *seen = calloc((size_t)nn * 2, 1);
    if (!v || !nb || !seen) { free(v); free(nb); free(seen); return; }

    for (int n = 0; n < nn; n++) {
        double px = l + (n % cols) * step, py = t + (n / cols) * step;
        v[n] = smin_(sd_rrect(px, py, body, r), hypot(px - cx, py - cy) - rd, k);
        nb[n * 4] = nb[n * 4 + 1] = nb[n * 4 + 2] = nb[n * 4 + 3] = -1;
    }
    for (int j = 0; j < ny; j++) {
        for (int i = 0; i < nx; i++) {
            int a = j * cols + i, b = a + 1, d = a + cols, e = d + 1;
            int m = (v[a] < 0 ? 1 : 0) | (v[b] < 0 ? 2 : 0) | (v[e] < 0 ? 4 : 0) | (v[d] < 0 ? 8 : 0);
            const signed char *tb = TBL[m];
            int ids[4] = { a * 2, b * 2 + 1, d * 2, a * 2 + 1 }; // trên, phải, dưới, trái
            for (int q = 0; tb[q] >= 0; q += 2) {
                int p = ids[(int)tb[q]], s = ids[(int)tb[q + 1]];
                link_(nb, p, s); link_(nb, s, p);
            }
        }
    }
    Grid g = { v, cols, l, t, step };
    for (int id = 0; id < nn * 2; id++) {
        if (seen[id] || nb[id * 2] < 0) continue;
        int cur = id; double x, y;
        edge_pt(&g, cur, &x, &y); sink.move(sink.ctx, x, y);
        for (;;) {
            seen[cur] = 1;
            int nxt = -1;
            for (int q = 0; q < 2; q++) {
                int e = nb[cur * 2 + q];
                if (e >= 0 && !seen[e]) { nxt = e; break; }
            }
            if (nxt < 0) break;
            cur = nxt; edge_pt(&g, cur, &x, &y); sink.line(sink.ctx, x, y);
        }
        sink.close(sink.ctx);
    }
    (void)rows;
    free(v); free(nb); free(seen);
}
