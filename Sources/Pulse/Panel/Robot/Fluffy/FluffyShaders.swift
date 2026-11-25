// Copyright (c) 2026 qunqin24. Licensed under the Apache License, Version 2.0.
//
// Ported from Open Bot Avatar's fluffy shaders (`dist/dom/fluffy/shaders.js`,
// https://github.com/DominikScholz/open-bot-avatar, v0.4.0), Copyright (c)
// 2026 Dominik Scholz, MIT License — see THIRD_PARTY_NOTICES.md.
import CryptoKit
import Foundation

/// Open Bot Avatar's fluffy shaders, GLSL ES 3.0 rewritten in Metal Shading
/// Language line for line: one program draws the body with its eyes seated
/// in it, shells of pile lifted off it, and single strands, chosen by `pass`.
///
/// Compiled from source when the renderer starts (`makeLibrary(source:)`),
/// because SwiftPM does not compile `.metal` files.
///
/// What differs from the GLSL is only what the two languages make differ:
/// uniforms are one struct of `float4`s, so Swift's layout matches it without
/// padding rules; vertices are read from buffers by index instead of through
/// attribute arrays; and clip-space depth runs 0…1 rather than −1…1.
enum FluffyShaders {
    /// SHA-256 of the package's `vertexShader + fragmentShader`, as bundled.
    /// `BotAvatarTests` compares it with the bundled script, so a new version
    /// whose shaders changed fails until this port is brought up to date.
    static let upstreamDigest = "ed0feecb396e641d89bdce5d33df816e426d114ee048b15fb788c2ff4cfb0365"

    static func digest(of source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    constant int BODY = 0, SHELL = 1, STRAND = 2;
    // SOCKET_PAD and DYE_RAMP_RANGE, as the GLSL has them inlined.
    constant float FAR = 3.8;
    constant float DYE_RAMP_RANGE = 2.4;

    struct Uniforms {
      float4 view0, view1, view2;   // the view's columns
      float4 pivot, extent;
      float4 eyeRegion[2];          // face-plane center, square span, maximum host depth
      float4 eyeSize;               // eye 0 in xy, eye 1 in zw
      float4 color, ink;
      float4 params;                // radius, shell, strandWidth, pass
    };

    struct Varyings {
      float4 position [[position]];
      float3 P, N, V, pilePosition, lean;
      float tip, variation, across, pocketDepth;
    };

    static float3x3 viewOf(constant Uniforms &u) {
      return float3x3(u.view0.xyz, u.view1.xyz, u.view2.xyz);
    }

    // Distance to the nearer eye's contour, viewBox units, from the eyes' distance tiles.
    static float socketDistance(float3 p, float3 normal, thread float2 &uv, thread float3 &local,
                                constant Uniforms &u, texture2d<float> eyeField, sampler eyeSampler) {
      uv = float2(0.);
      local = float3(0.);
      if (normal.z < .03 || p.z < -.05) return FAR;
      for (int i = 0; i < 2; i++) {
        float4 e = u.eyeRegion[i];
        float2 delta = p.xy - e.xy;
        if (e.z > 0. && p.z <= e.w && max(abs(delta.x), abs(delta.y)) < e.z * .49) {
          float2 coords = delta / e.z;
          float2 sampleUV = (coords + .5 + float2(float(i), 0.)) * float2(.5, 1.);
          float d = (eyeField.sample(eyeSampler, sampleUV, level(0.)).r - .5) * (2. * FAR);
          if (d >= 3.77) continue;
          uv = sampleUV;
          float2 size = i == 0 ? u.eyeSize.xy : u.eyeSize.zw;
          local.xy = 2. * delta / max(size, float2(.01));
          // As lids close, the pressed lip narrows with the expression.
          local.z = smoothstep(.35, 1.5, size.y / max(.01, size.x));
          return d * mix(1.5, 1., local.z);
        }
      }
      return FAR;
    }

    vertex Varyings fluffyVertex(uint vertexID [[vertex_id]], uint instanceID [[instance_id]],
                                 device const float *surface [[buffer(0)]],
                                 device const float *roots [[buffer(1)]],
                                 constant Uniforms &u [[buffer(2)]],
                                 texture2d<float> eyeField [[texture(0)]],
                                 sampler eyeSampler [[sampler(0)]]) {
      int pass = int(u.params.w);
      float radius = u.params.x, shell = u.params.y, strandWidth = u.params.z;
      float3x3 view = viewOf(u);
      float3 position, normal;
      float2 seed = float2(0.);
      if (pass == STRAND) {
        device const float *r = roots + 8 * instanceID;
        position = float3(r[0], r[1], r[2]);
        normal = float3(r[3], r[4], r[5]);
        seed = float2(r[6], r[7]);
      } else {
        device const float *v = surface + 6 * vertexID;
        position = float3(v[0], v[1], v[2]);
        normal = float3(v[3], v[4], v[5]);
      }
      Varyings out;
      float3 n = normalize(normal), p = position;
      float3 rounded = (position - u.pivot.xyz) / u.extent.xyz;
      // Broadly bend the lighting normals across flat front faces of inflated paths.
      float3 shadingNormal = normalize(n + .78 * rounded);
      out.pilePosition = position;
      // Sweep across the visible surface. A downwards bias keeps the front from parting at a point.
      float wave = .21 * sin(dot(position, float3(.11, .045, .08))) + .14 * sin(.13 * position.y - .07 * position.z);
      float angle = .22 + .94 * (view * shadingNormal).x + wave;
      float3 sweep = transpose(view) * float3(sin(angle), cos(angle), .18);
      out.lean = sweep - n * dot(n, sweep);

      float2 uv;
      float3 local;
      float d = socketDistance(position, n, uv, local, u, eyeField, eyeSampler);
      float seat = min(1.55, max(0., position.z) * .40);
      // The rounded cap sits below the packed pile at the mouth of the socket.
      float dome = sqrt(max(0., 1. - dot(local.xy, local.xy)));
      float cap = mix(smoothstep(0., 1.3, -d), dome, local.z) * smoothstep(-.15, .38, -d);
      float floorDepth = 1. - smoothstep(-.15, 1.65, d);
      p.z += seat * (.56 * cap - .98 * floorDepth);
      // Compressed fibers lie along the lip.
      float loft = mix(.07, 1., smoothstep(.75, 3.7, d));
      float lip = smoothstep(-.10, 1., d) * (1. - smoothstep(1., 2.85, d));
      if (pass == BODY) p.z += seat * .15 * lip;
      out.pilePosition.z = p.z;

      out.tip = 0.;
      out.variation = .5;
      out.across = 0.;
      if (pass == SHELL) {
        p += n * shell * 1.10 * loft;
        p += out.lean * (1.05 * shell * loft);
      }
      if (pass == STRAND) {
        // Four cross-sections make a bent, tapered strand. Roots are fixed in model space.
        out.tip = float(vertexID / 2) / 3.;
        out.across = float(vertexID % 2) * 2. - 1.;
        float3 tangent = normalize(cross(n, abs(n.y) < .93 ? float3(0, 1, 0) : float3(1, 0, 0)));
        float3 bitangent = cross(n, tangent);
        float flow = 2.3 * sin(.24 * p.x + .13 * p.z + sin(.22 * p.y)) + 1.3 * sin(.32 * p.y - .15 * p.x);
        float turn = flow + (seed.x - .5) * 2.6;
        float3 comb = out.lean + .24 * (tangent * cos(turn) + bitangent * sin(turn));
        if (d < 3.5) {
          // Around a socket the strands lie along its edge.
          float2 radial = normalize(local.xy * float2(1.7, 1.) + float2(.001));
          float2 alongEdge = float2(-radial.y, radial.x);
          comb.xy = mix(comb.xy, alongEdge * (dot(comb.xy, alongEdge) < 0. ? -1. : 1.), .88 * (1. - smoothstep(.4, 3.5, d)));
        }
        float3 bend = cross(n, comb);
        float len = mix(1.6, 3.8, seed.y) * loft;
        float tip = out.tip;
        float3 direction = n * (.30 + .18 * tip) + comb * (.93 - .12 * tip) + bend * (seed.x - .5) * .45 * tip;
        out.pilePosition += comb * (.7 * len * tip);
        p += n * .52 * loft;
        float width = (.073 + .11 * seed.y) * strandWidth;
        p += .065 * n + len * tip * direction;
        float3 screenDir = view * (direction + .06 * comb);
        float2 widthDir = normalize(float2(-screenDir.y, screenDir.x) + float2(.0001, 0));
        p += transpose(view) * float3(widthDir * out.across * width * (1. - .94 * tip), 0);
        shadingNormal = normalize(shadingNormal + .19 * comb);
        out.variation = seed.x;
      }

      float3 projected = view * (p - u.pivot.xyz);
      out.pocketDepth = dot(position - p, n) / max(.01, seat);
      out.P = float3(p.xy, position.z);
      out.N = view * shadingNormal;
      out.V = normal;
      // GL's (x, -y, -z) / radius, with depth moved from -1…1 to Metal's 0…1.
      out.position = float4(projected.x / radius, -projected.y / radius, .5 - .5 * projected.z / radius, 1.);
      return out;
    }

    static float fiberMap(float3 p, float3 n, texture2d<float> pile, sampler pileSampler) {
      float3 w = pow(abs(n), float3(5.));
      w /= max(.001, w.x + w.y + w.z);
      return dot(w, float3(pile.sample(pileSampler, p.zy / 16.).r, pile.sample(pileSampler, p.xz / 16.).r,
                           pile.sample(pileSampler, p.xy / 16.).r));
    }

    // Sample the same model-space roots at every view: only the direction of the short filter changes.
    static float brushedHeight(float3 pilePosition, float3 lean, texture3d<float> brushedPile, sampler brushedSampler) {
      float3 uvw = pilePosition / 15.;
      float3 stepUV = lean * .019;
      float locks = 4. * brushedPile.sample(brushedSampler, uvw).r;
      for (int i = 1; i <= 3; i++) {
        float3 delta = float(i) * stepUV;
        locks += (4. - float(i)) * (brushedPile.sample(brushedSampler, uvw + delta).r + brushedPile.sample(brushedSampler, uvw - delta).r);
      }
      float tuft = brushedPile.sample(brushedSampler, uvw * .42).r;
      return clamp(.5 + 1.65 * (locks / 16. - .5) + .16 * (tuft - .5), 0., 1.);
    }

    fragment float4 fluffyFragment(Varyings in [[stage_in]],
                                   constant Uniforms &u [[buffer(0)]],
                                   texture2d<float> eyeField [[texture(0)]],
                                   texture2d<float> pile [[texture(1)]],
                                   texture3d<float> brushedPile [[texture(2)]],
                                   texture2d<float> dyeRamp [[texture(3)]],
                                   sampler clampLinear [[sampler(0)]],
                                   sampler pileSampler [[sampler(1)]],
                                   sampler brushedSampler [[sampler(2)]]) {
      int pass = int(u.params.w);
      float shell = u.params.y;
      float3x3 view = viewOf(u);
      float3 color = u.color.rgb, ink = u.ink.rgb;
      float3 n = normalize(in.N);
      float3 light = normalize(float3(-.52, -.83, .62));
      float diffuse = dot(n, light);
      float wrap = clamp((diffuse + .65) / 1.65, 0., 1.);
      float facingLight = clamp(.66 + .34 * diffuse, 0., 1.);
      float diffuseLevel = .87 + .13 * wrap;
      float sheen = .014 * wrap * wrap;
      float rimExposure = 1.;

      // Pile gives way to the eye.
      float2 uv;
      float3 local;
      float d = socketDistance(in.P, normalize(in.V), uv, local, u, eyeField, clampLinear);
      if (pass == SHELL && d < .1) discard_fragment();
      if (pass == STRAND && d < .10 - .08 * in.variation) discard_fragment();

      float height = brushedHeight(in.pilePosition, in.lean, brushedPile, brushedSampler);
      float pileFill = .925 + .075 * smoothstep(.22, .81, height);
      if (pass == STRAND) {
        float edge = min(1., abs(in.across));
        float glint = smoothstep(.08, .82, in.tip) * (1. - .32 * edge * edge);
        diffuseLevel *= .935 + .11 * in.variation + .035 * clamp(in.tip, 0., 1.);
        sheen += (.012 + .20 * glint) * (.44 + .56 * in.variation) * facingLight;
      } else {
        float layer = pass == SHELL ? shell : 0.;
        // A shell keeps only the locks that reach its height.
        if (pass == SHELL && height < .21 + .59 * layer) discard_fragment();
        diffuseLevel *= .895 + .16 * height + .035 * layer;
        sheen += (.012 + .13 * smoothstep(.41, .86, height) + .022 * layer) * facingLight;
        rimExposure = .80 + .34 * layer;
      }

      // A soft light behind the right shoulder grazes the pile.
      float grazing = 1. - smoothstep(.09, .83, abs(n.z));
      float backlit = smoothstep(-.20, .79, dot(n.xy, float2(.66, -.75)));

      // Around a socket: a crease where the pile is pressed down, and light on its rolled lip.
      float upper = 0., crease = 0., pileRelief = 0., contact = 0., lipLight = 0.;
      if (d < 3.7) {
        float2 texel = 1. / float2(eyeField.get_width(), eyeField.get_height());
        float2 g = float2(eyeField.sample(clampLinear, uv + float2(texel.x, 0)).r - eyeField.sample(clampLinear, uv - float2(texel.x, 0)).r,
                          eyeField.sample(clampLinear, uv + float2(0, texel.y)).r - eyeField.sample(clampLinear, uv - float2(0, texel.y)).r);
        float2 outward = g / max(length(g), .001);
        upper = dot(outward, normalize(float2(.96, -.28)));
        float fibers = fiberMap(in.P, normalize(in.V), pile, pileSampler);
        float buried = smoothstep(-.12, .82, in.pocketDepth);
        crease = (1. - smoothstep(-.12, 1.65 + 1.30 * upper + .6 * (fibers - .5), d)) * mix(.24, 1., buried);
        if (pass == STRAND) {
          pileRelief = ((in.tip - .46) * .16 + (fibers - .48) * .11) * (1. - smoothstep(1.5, 3.65, d));
        }
        contact = (1. - smoothstep(-.04, .38, d)) * mix(.35, 1., buried);
        float lip = smoothstep(.03, .49, d) * (1. - smoothstep(1.10, 3.65, d));
        float gathered = clamp(.22 - .52 * outward.x + 1.14 * outward.y, 0., 1.22);
        float tipLight = .14 + .22 * fibers;
        lipLight = tipLight * gathered * lip * mix(.40, 1., local.z);
      }
      float occlusion = crease * (.76 + .18 * upper);
      float fiberLight = (sheen + .46 * grazing * backlit * rimExposure) * (1. - crease) + lipLight;
      diffuseLevel = (diffuseLevel * (1. - .48 * occlusion) + pileRelief) * (1. - (.36 + .04 * upper) * contact);

      float backing = diffuseLevel * pileFill;
      float exposure = backing * backing * (.72 + .39 * wrap) + 1.45 * fiberLight * pileFill;
      float4 ramp = dyeRamp.sample(clampLinear, float2(exposure / DYE_RAMP_RANGE, .5));
      float3 base = ramp.rgb;
      if (ramp.a > 0.) {
        float value = max(color.r, max(color.g, color.b));
        float3 dye = color / max(value, .001);
        float weakest = min(dye.r, min(dye.g, dye.b));
        float3 scatter = (1. - dye) * (.09 + .91 * (dye - weakest)) * clamp(1.85 * fiberLight, 0., 1.);
        float brightness = clamp(value * diffuseLevel + (.35 + .65 * value) * fiberLight, 0., 1.);
        base = mix(base, (dye + scatter) * brightness * pileFill, ramp.a);
      }

      if (pass == BODY && d < 3.7) {
        // The eye: a glossy bead in the socket.
        float2 curve = local.xy * .94;
        float3 dome = normalize(float3(curve, sqrt(max(.02, 1. - dot(curve, curve)))));
        float3 beadNormal = normalize(view * dome);
        float2 key = beadNormal.xy - float2(.59, -.865);
        key = float2(key.x - .76 * key.y, key.y) / float2(.55, .70);
        float2 fill = beadNormal.xy - float2(.61, -.195);
        fill = float2(fill.x - .37 * fill.y, fill.y) / float2(.47, 1.01);
        float stripLight = .38 * exp(-dot(key, key));
        float sideLight = .13 * exp(-dot(fill, fill));
        float coatBounce = .003 + .018 * pow(1. - clamp(beadNormal.z, 0., 1.), 1.6);
        float inkValue = max(ink.r, max(ink.g, ink.b));
        float3 bead = ink * sqrt(inkValue) * (.40 + .24 * beadNormal.z + .24 * inkValue) + color * coatBounce;
        float3 reflection = mix(float3(1.), color, .28) * stripLight + mix(float3(1.), color, .72) * sideLight;
        bead += reflection * smoothstep(-.12, .55, -d);
        float aa = max(.15, fwidth(d));
        base = mix(bead, base, smoothstep(-aa * .5, aa * .5, d));
      }
      return float4(base, 1.);
    }
    """
}
