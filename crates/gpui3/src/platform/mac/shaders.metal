#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

float4 hsla_to_rgba(Hsla hsla);
float4 to_device_position(float2 pixel_position, uint order, uint max_order, float2 viewport_size);

struct QuadVertexOutput {
    float4 position [[position]];
    float4 background_color;
    float4 border_color;
    uint quad_id;
};

vertex QuadVertexOutput quad_vertex(
    uint unit_vertex_id [[vertex_id]],
    uint quad_id [[instance_id]],
    constant float2 *unit_vertices [[buffer(QuadInputIndex_Vertices)]],
    constant Quad *quads [[buffer(QuadInputIndex_Quads)]],
    constant QuadUniforms *uniforms [[buffer(QuadInputIndex_Uniforms)]]
) {
    float2 unit_vertex = unit_vertices[unit_vertex_id];
    Quad quad = quads[quad_id];
    float2 position_2d = unit_vertex * float2(quad.bounds.size.width, quad.bounds.size.height) + float2(quad.bounds.origin.x, quad.bounds.origin.y);
    float2 viewport_size = float2(uniforms->viewport_size.width, uniforms->viewport_size.height);
    float4 device_position = to_device_position(position_2d, quad.order, uniforms->max_order, viewport_size);
    float4 background_color = hsla_to_rgba(quad.background);
    float4 border_color = hsla_to_rgba(quad.border_color);
    return QuadVertexOutput {
        device_position,
        background_color,
        border_color,
        quad_id
    };
}

fragment float4 quad_fragment(
    QuadVertexOutput input [[stage_in]],
    constant Quad *quads [[buffer(QuadInputIndex_Quads)]],
    constant QuadUniforms *uniforms [[buffer(QuadInputIndex_Uniforms)]]
) {
    Quad quad = quads[input.quad_id];
    float2 half_size = float2(quad.bounds.size.width, quad.bounds.size.height) / 2.;
    float2 center = float2( quad.bounds.origin.x, quad.bounds.origin.y ) + half_size;
    float2 center_to_point = input.position.xy - center;
    float corner_radius;
    if (center_to_point.x < 0.) {
        if (center_to_point.y < 0.) {
            corner_radius = quad.corner_radii.top_left;
        } else {
            corner_radius = quad.corner_radii.bottom_left;
        }
    } else {
        if (center_to_point.y < 0.) {
            corner_radius = quad.corner_radii.top_right;
        } else {
            corner_radius = quad.corner_radii.bottom_right;
        }
    }

    float2 rounded_edge_to_point = fabs(center_to_point) - half_size + corner_radius;
    float distance = length(max(0., rounded_edge_to_point)) + min(0., max(rounded_edge_to_point.x, rounded_edge_to_point.y)) - corner_radius;

    float vertical_border = center_to_point.x <= 0. ? quad.border_widths.left : quad.border_widths.right;
    float horizontal_border = center_to_point.y <= 0. ? quad.border_widths.top : quad.border_widths.bottom;
    float2 inset_size = half_size - corner_radius - float2(vertical_border, horizontal_border);
    float2 point_to_inset_corner = fabs(center_to_point) - inset_size;
    float border_width;
    if (point_to_inset_corner.x < 0. && point_to_inset_corner.y < 0.) {
        border_width = 0.;
    } else if (point_to_inset_corner.y > point_to_inset_corner.x) {
        border_width = horizontal_border;
    } else {
        border_width = vertical_border;
    }

    float4 color;
    if (border_width == 0.) {
        color = input.background_color;
    } else {
        float inset_distance = distance + border_width;

        // Decrease border's opacity as we move inside the background.
        input.border_color.a *= 1. - saturate(0.5 - inset_distance);

        // Alpha-blend the border and the background.
        float output_alpha = quad.border_color.a + quad.background.a * (1. - quad.border_color.a);
        float3 premultiplied_border_rgb = input.border_color.rgb * quad.border_color.a;
        float3 premultiplied_background_rgb = input.background_color.rgb * input.background_color.a;
        float3 premultiplied_output_rgb = premultiplied_border_rgb + premultiplied_background_rgb * (1. - input.border_color.a);
        color = float4(premultiplied_output_rgb, output_alpha);
    }

    return color;
}

float4 hsla_to_rgba(Hsla hsla) {
    float h = hsla.h * 6.0; // Now, it's an angle but scaled in [0, 6) range
    float s = hsla.s;
    float l = hsla.l;
    float a = hsla.a;

    float c = (1.0 - fabs(2.0*l - 1.0)) * s;
    float x = c * (1.0 - fabs(fmod(h, 2.0) - 1.0));
    float m = l - c/2.0;

    float r = 0.0;
    float g = 0.0;
    float b = 0.0;

    if (h >= 0.0 && h < 1.0) {
        r = c;
        g = x;
        b = 0.0;
    } else if (h >= 1.0 && h < 2.0) {
        r = x;
        g = c;
        b = 0.0;
    } else if (h >= 2.0 && h < 3.0) {
        r = 0.0;
        g = c;
        b = x;
    } else if (h >= 3.0 && h < 4.0) {
        r = 0.0;
        g = x;
        b = c;
    } else if (h >= 4.0 && h < 5.0) {
        r = x;
        g = 0.0;
        b = c;
    } else {
        r = c;
        g = 0.0;
        b = x;
    }

    float4 rgba;
    rgba.x = (r + m);
    rgba.y = (g + m);
    rgba.z = (b + m);
    rgba.w = a;
    return rgba;
}

float4 to_device_position(float2 pixel_position, uint order, uint max_order, float2 viewport_size) {
    return float4(pixel_position / viewport_size * float2(2., -2.) + float2(-1., 1.), (1. - order / max_order), 1.);
}
