/// Metal-Shader als Quelltext. Wird zur Laufzeit kompiliert, damit kein Xcode nötig ist.
enum Shaders {
    static let source = """
        #include <metal_stdlib>
        using namespace metal;

        // Muss zu SpriteInstance in SpriteRenderer.swift passen.
        struct Instance {
            float4 dst;   // x, y, w, h in virtuellen Pixeln (y nach unten)
            float4 src;   // x, y, w, h in Atlaspixeln
            uint4 extra;  // x = Atlasseite, y = Einfärbung RGBA8
        };

        // Muss zu SpriteRenderer.maxPages passen.
        constant uint MAX_PAGES = 16;

        // Muss zu ViewUniforms in SpriteRenderer.swift passen.
        struct Uniforms {
            float2 drawableSize;
            float2 offset;
            float scale;
        };

        struct VOut {
            float4 position [[position]];
            float2 atlas;
            float4 srcRect [[flat]];
            uint page [[flat]];
            uint tint [[flat]];
        };

        vertex VOut sprite_vertex(uint vid [[vertex_id]],
                                  uint iid [[instance_id]],
                                  const device Instance *instances [[buffer(0)]],
                                  constant Uniforms &u [[buffer(1)]]) {
            float2 corner = float2(vid & 1, vid >> 1);
            Instance inst = instances[iid];
            float2 p = (inst.dst.xy + corner * inst.dst.zw) * u.scale + u.offset;
            VOut out;
            out.position = float4(p.x / u.drawableSize.x * 2.0 - 1.0,
                                  1.0 - p.y / u.drawableSize.y * 2.0, 0.0, 1.0);
            out.atlas = inst.src.xy + corner * inst.src.zw;
            out.srcRect = inst.src;
            out.page = inst.extra.x;
            out.tint = inst.extra.y;
            return out;
        }

        // Atlasseiten: R = Palettenindex, G = deckend (0/1). Palette: 256×1 RGBA.
        // Alle Seiten sind gleichzeitig gebunden, damit ein Draw-Call die Zeichenreihenfolge behält.
        fragment float4 sprite_fragment(VOut in [[stage_in]],
                                        array<texture2d<uint>, MAX_PAGES> atlas [[texture(0)]],
                                        texture2d<float> palette [[texture(16)]]) {
            float2 lo = in.srcRect.xy;
            float2 hi = in.srcRect.xy + in.srcRect.zw - 1.0;
            uint2 coord = uint2(clamp(floor(in.atlas), lo, hi));
            uint2 texel = atlas[in.page].read(coord).rg;
            if (texel.g == 0) {
                discard_fragment();
            }
            float4 color = palette.read(uint2(texel.r, 0));
            if (in.tint != 0) {
                float4 tint = unpack_unorm4x8_to_float(in.tint);
                color.rgb = mix(color.rgb, tint.rgb, tint.a);
            }
            return color;
        }
        """
}
