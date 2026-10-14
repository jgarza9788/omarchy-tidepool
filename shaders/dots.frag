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
    float cols;
    float rows;
    float pitchX;
    float pitchY;
    float dotSize;
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

void main() {
    vec2 p = vec2(qt_TexCoord0.x * area.x, (1.0 - qt_TexCoord0.y) * area.y);   // y counts up from the bottom
    int nRows = int(rows), nCols = int(cols);
    int rc = int(floor(p.y / pitchY));
    float a = 0.0;
    for (int dr = -2; dr <= 2; ++dr) {
        int r = rc + dr;
        if (r < 0 || r >= nRows) continue;
        bool shifted = (r & 1) == 1;                  // odd rows sit half a column over
        float off = shifted ? 1.0 : 0.5;
        int cc = int(floor(p.x / pitchX - off + 0.5));
        float cy = (float(r) + 0.5) * pitchY;
        for (int dc = -2; dc <= 2; ++dc) {
            int c = cc + dc;
            if (c < 0 || c >= nCols || (shifted && c >= nCols - 1)) continue;
            // A shifted dot sits between two columns, so it follows both.
            float v = shifted ? 0.5 * (band(c) + band(c + 1)) : band(c);
            float level = clamp(v * rows - float(r), 0.0, 1.0);
            float d = max(1.0, dotSize * (0.18 + (2.5 - 0.18) * level));
            vec2 ctr = vec2((float(c) + off) * pitchX, cy);
            float cov = clamp(d * 0.5 - distance(p, ctr) + 0.5, 0.0, 1.0);
            a = 1.0 - (1.0 - a) * (1.0 - 0.66 * cov);    // translucent dots blend where they overlap
        }
    }
    a *= accent.a;
    fragColor = vec4(accent.rgb * a, a) * qt_Opacity;
}
