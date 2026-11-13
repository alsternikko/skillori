#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The light inside an accent block. The block itself is the body of light: a ramp of sixteen
// measured colours runs across the whole of it, with a slight arch, a soft bevel of light round
// the edge and a trace of grain. Nothing travels. What changes, slowly, is the gradient's own range.
// The same shader, in GLSL, is the pane form of the study in
// docs/design/gradient-studie-2026-11-13/index.html; keep the two in step.

static float lf_hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float2 lf_grad(float2 i) {
    float a = lf_hash(i) * 6.28318;
    return float2(cos(a), sin(a));
}

static float lf_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(dot(lf_grad(i), f), dot(lf_grad(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
               mix(dot(lf_grad(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)), dot(lf_grad(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y);
}

static float3 lf_step(device const float *lut, int i) {
    return float3(lut[i * 3], lut[i * 3 + 1], lut[i * 3 + 2]);
}

// Sixteen OKLab steps read smoothly at s in 0...1: a Catmull-Rom curve through them.
static float3 lf_lut(device const float *lut, float s) {
    float f = clamp(s, 0.0, 1.0) * 15.0;
    int i = int(min(floor(f), 14.0));
    float u = f - float(i);
    float3 a = lf_step(lut, max(i - 1, 0)), b = lf_step(lut, i), c = lf_step(lut, i + 1), d = lf_step(lut, min(i + 2, 15));
    return 0.5 * ((2.0 * b) + (c - a) * u + (2.0 * a - 5.0 * b + 4.0 * c - d) * u * u + (3.0 * b - a - 3.0 * c + d) * u * u * u);
}

static float3 lf_srgb(float3 c) {
    float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
    float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
    float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
    l = l * l * l; m = m * m * m; s = s * s * s;
    float3 rgb = float3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
    rgb = clamp(rgb, float3(0.0), float3(1.0));
    return mix(rgb * 12.92, 1.055 * pow(rgb, float3(1.0 / 2.4)) - 0.055, step(float3(0.0031308), rgb));
}

static float lf_box(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, float2(0.0))) - r;
}

// position and size are in points; `scale` is device pixels per point.
// shape = (turn, wrap, reading room, dark ink). finish = (edge light, grain, seed, eased throughout).
[[ stitchable ]] half4 lightField(float2 position, float2 size, float time, float scale, float radius,
                                  device const float *lut, int lutCount, float4 shape, float4 finish) {
    if (lutCount < 48 || size.x < 1.0 || size.y < 1.0) { return half4(0.0, 0.0, 0.0, 1.0); }
    float turn = shape.x, wrap = shape.y, room = shape.z;
    bool darkInk = shape.w > 0.5;
    float edgeLight = finish.x, grain = finish.y, seed = finish.z, throughout = finish.w;
    float t = time;

    float2 uv = position / size;                               // 0,0 top left
    float aspect = size.x / size.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);               // centred, round units
    float side = min(size.x, size.y);

    // The bands run across the whole block in the order they have in the reference, with a slight arch.
    float2 down = float2(sin(turn), cos(turn));
    float2 c = p / float2(aspect, 1.0);
    float along = dot(c, down) / (abs(down.x) + abs(down.y)), across = dot(c, float2(down.y, -down.x));
    float v = clamp(0.5 + along + 0.1 * across * across, 0.0, 1.0);

    // Nothing travels. What changes, slowly, is the gradient's own range:
    v = pow(v, exp(0.32 * sin(t * 0.06 + seed)));                           // the bands crowd one end, then the other
    v += 0.045 * sin(6.28318 * v + t * 0.08) + 0.05 * sin(t * 0.045 + 1.0); // each widens and narrows in turn
    // and how far the bands wrap round the edge of the pane, measured from a rounder outline
    float pill = max(-lf_box(position - 0.5 * size, 0.5 * size, max(radius, 0.2 * side)), 0.0) / side;
    v += (0.07 + 0.05 * sin(t * 0.052 + 2.0)) * wrap * exp(-pow(pill / 0.13, 1.3));
    float3 lab = lf_lut(lut, v);

    // Where text sits, bands that would fight the text are eased towards the calm end's lightness.
    // The zone is the left side, a little more of it towards the top, and it wanders a little.
    float2 w = float2(lf_noise(p * 0.9 + float2(seed, t * 0.05)), lf_noise(p * 0.9 + float2(5.2 - t * 0.04, seed * 1.7)));
    float2 q = p + 0.7 * 0.42 * w;
    float2 cq = q / float2(aspect, 1.0) + 0.5;
    float cx = cq.x + 0.4 * (cq.y - 0.5) + 0.12 * lf_noise(q * 1.4 + float2(seed + 2.7, t * 0.04));
    float held = min(room * 1.25, 1.0) * max(max(throughout, smoothstep(1.06, 0.6, cx)), max(0.8 * smoothstep(0.7, 1.0, cq.y), 0.6 * smoothstep(0.26, 0.0, cq.y)));
    float ease = darkInk ? -held * max(0.74 - lab.x, 0.0) : held * max(lab.x - 0.66, 0.0);
    lab = float3(lab.x - ease, lab.y * (1.0 + 0.8 * abs(ease)), lab.z * (1.0 + 0.8 * abs(ease)));

    // A soft bevel, not a hard rim: the block lightens towards its edge over a long distance,
    // evenly all the way round, with only a faint hairline at the very edge.
    float d = max(-lf_box(position - 0.5 * size, 0.5 * size, radius), 0.0);
    float bevel = exp(-pow(d / 12.0, 1.4));
    float lift = edgeLight * (0.12 * bevel + 0.05 * exp(-d / 0.8));
    lab = float3(lab.x + lift * (1.0 - 0.45 * lab.x), lab.y * (1.0 - 0.9 * lift), lab.z * (1.0 - 0.9 * lift));

    // grain, in lightness only, one cell per device pixel
    float2 gp = floor(position * scale);
    float g = lf_hash(gp + seed * 7.0) + lf_hash(gp * 1.37 + 11.3) - 1.0;
    lab.x += g * grain * (0.55 + 0.45 * smoothstep(0.1, 0.5, lab.x));

    return half4(half3(lf_srgb(lab)), 1.0);
}
