#version 440
// Generated pieces are kept in sync by hand with Model.js (see shaders/README.md).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 b0;
    vec4 b1;
    vec4 b2;
    vec4 b3;
    vec4 b4;
    vec4 b5;
    vec4 b6;
    vec4 b7;
    vec4 b8;
    vec4 b9;
    vec4 b10;
    vec4 b11;
    vec4 b12;
    vec4 b13;
    vec4 b14;
    vec4 b15;
    vec4 accent;      // theme accent, straight (non-premultiplied) RGBA
    vec2 area;        // item size in px
    vec3 accHsl;      // accent hue, saturation, lightness (0..1)
    float cols;
    float rows;
    float pitch;
    float cellSize;
    int tick;
};

// The spectrum, 0..1 per band, packed four to a vec4 (up to 64 bands).
vec4 pick(int k) {
    switch (k) {
    case 0: return b0;
    case 1: return b1;
    case 2: return b2;
    case 3: return b3;
    case 4: return b4;
    case 5: return b5;
    case 6: return b6;
    case 7: return b7;
    case 8: return b8;
    case 9: return b9;
    case 10: return b10;
    case 11: return b11;
    case 12: return b12;
    case 13: return b13;
    case 14: return b14;
    case 15: return b15;
    }
    return vec4(0.0);
}
float band(int i) {
    if (i < 0 || i >= 64) return 0.0;
    return pick(i >> 2)[i & 3] * 0.01;
}

// Same hash as Model.noise: stable within a frame, changes with c.
float noise(int a, int b, int c) {
    uint h = (uint(a) * 374761393u) ^ (uint(b) * 668265263u) ^ (uint(c) * 1274126177u);
    h = (h ^ (h >> 13)) * 1103515245u;
    h ^= h >> 16;
    return float(h) * (1.0 / 4294967296.0);
}

// Model.fireState: 0..1 up a lit flame, 1.5 a spark, -1 dark.
float fireState(float height, int row, float nz) {
    if (height < 0.5) return -1.0;
    float u = float(row) / max(1.0, height);
    if (u < 1.0) {
        float solid = 0.4;
        if (u <= solid) return u;
        float keep = 1.0 - (u - solid) / (1.0 - solid) * 0.92;
        return nz < keep ? u : -1.0;
    }
    if (float(row) < height + 3.0 && nz > 0.985) return 1.5;
    return -1.0;
}

// Model.fireHsl: colour up the flame, built from the accent's hue and its neighbours. Returns h, s, l, a.
vec4 fireHsl(float t) {
    bool spark = t > 1.0;
    float u = clamp(t, 0.0, 1.0);
    // stops: position, hue shift, lightness shift, alpha
    const vec4 S0 = vec4(0.0, -0.04, 0.16, 1.0);
    const vec4 S1 = vec4(0.3, 0.0, 0.04, 1.0);
    const vec4 S2 = vec4(0.65, 0.07, 0.0, 1.0);
    const vec4 S3 = vec4(1.0, 0.13, 0.05, 0.3);
    vec4 a = S2, b = S3;
    if (u <= S1.x) { a = S0; b = S1; }
    else if (u <= S2.x) { a = S1; b = S2; }
    vec4 m = mix(a, b, (b.x == a.x) ? 0.0 : (u - a.x) / (b.x - a.x));
    float hue = fract(accHsl.x + m.y);
    float light = clamp(accHsl.z + m.z, 0.12, 0.85);
    return vec4(hue, min(1.0, accHsl.y * 1.05), light, m.w * (spark ? 0.6 : 1.0));
}

vec3 hsl2rgb(float h, float s, float l) {
    vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    float c = (1.0 - abs(2.0 * l - 1.0)) * s;
    return l + c * (k - 0.5);
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x * area.x, (1.0 - qt_TexCoord0.y) * area.y);   // y counts up from the bottom
    int col = int(floor(p.x / pitch));
    int row = int(floor(p.y / pitch));
    if (col < 0 || col >= int(cols) || row < 0 || row >= int(rows)) { fragColor = vec4(0.0); return; }

    // Flame height per column: the band blended with its neighbours, licked up and down by noise.
    float m = 0.6 * band(col) + 0.2 * (col > 0 ? band(col - 1) : 0.0) + 0.2 * band(col + 1);
    float fh = min(rows, clamp(m, 0.0, 1.0) * rows * (0.8 + 0.4 * noise(col, 99, tick >> 1)));
    float st = fireState(fh, row, noise(col, row, tick));

    vec2 ctr = vec2((float(col) + 0.5) * pitch, (float(row) + 0.5) * pitch);
    float rad = min(1.0, cellSize / 4.0);
    vec2 q = abs(p - ctr) - vec2(cellSize * 0.5 - rad);
    float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
    float cov = clamp(0.5 - sd, 0.0, 1.0);

    vec4 rgba;
    if (st >= 0.0) {
        vec4 hsl = fireHsl(st);
        rgba = vec4(hsl2rgb(hsl.x, hsl.y, hsl.z), hsl.w);
    } else {
        rgba = vec4(accent.rgb, 0.06 * accent.a);
    }
    float a = rgba.a * cov * ((row & 1) == 1 ? 0.86 : 1.0);   // every other row a little dimmer: scanlines
    fragColor = vec4(rgba.rgb * a, a) * qt_Opacity;
}
