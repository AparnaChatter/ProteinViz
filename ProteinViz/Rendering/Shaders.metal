// ProteinViz — Metal Rendering Engine
// Architectural reference: BioViewer by Raúl Montón Pinillos
// https://github.com/Androp0v/BioViewer
// Licensed under GPL-3.0. ProteinViz is also released under GPL-3.0.
// Sphere impostor technique adapted from BioViewer's Metal implementation.
//
//  Shaders.metal
//  ProteinViz
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Types

struct InstanceData {
    float3 position;
    float4 color;
    float radius;
};

struct FrameUniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
};

struct VertexOut {
    float4 position [[position]];
    float3 centerView;
    float2 offsetView;
    float4 color;
    float radius;
};

// MARK: - Helpers

constant float2 kQuadCorners[6] = {
    float2(-1.0, -1.0),
    float2( 1.0, -1.0),
    float2(-1.0,  1.0),
    float2(-1.0,  1.0),
    float2( 1.0, -1.0),
    float2( 1.0,  1.0)
};

constant float3 kLightDirection = float3(0.577f, 0.577f, 0.577f);
constant float kAmbientStrength = 0.3f;
constant float kDiffuseStrength = 0.7f;
constant float kSpecularStrength = 0.18f;
constant float kShininess = 24.0f;

// MARK: - Vertex Shader

vertex VertexOut vertexSphereImpostor(uint vertexID [[vertex_id]],
                                      uint instanceID [[instance_id]],
                                      const device InstanceData *instances [[buffer(0)]],
                                      constant FrameUniforms &uniforms [[buffer(1)]]) {
    VertexOut out;

    InstanceData instance = instances[instanceID];
    float2 corner = kQuadCorners[vertexID];
    float3 centerWorld = instance.position;
    float4 centerModel = float4(centerWorld, 1.0);
    float4 centerView4 = uniforms.viewMatrix * uniforms.modelMatrix * centerModel;

    float3 offsetView = float3(corner.x * instance.radius, corner.y * instance.radius, 0.0);
    float4 viewPosition = float4(centerView4.xyz + offsetView, 1.0);

    out.position = uniforms.projectionMatrix * viewPosition;
    out.centerView = centerView4.xyz;
    out.offsetView = offsetView.xy;
    out.color = instance.color;
    out.radius = instance.radius;
    return out;
}

// MARK: - Fragment Shader

fragment float4 fragmentSphereImpostor(VertexOut in [[stage_in]],
                                       constant FrameUniforms &uniforms [[buffer(1)]]) {
    float radius = max(in.radius, 0.0001f);
    float2 normalizedXY = in.offsetView / radius;
    float dist2 = dot(normalizedXY, normalizedXY);

    if (dist2 > 1.0f) {
        discard_fragment();
    }

    float z = sqrt(max(0.0f, 1.0f - dist2));
    float3 normal = normalize(float3(normalizedXY, z));
    float3 viewPosition = in.centerView + float3(in.offsetView.x, in.offsetView.y, z * radius);

    float3 viewDirection = normalize(-viewPosition);
    float3 halfVector = normalize(kLightDirection + viewDirection);

    float diffuse = max(dot(normal, kLightDirection), 0.0f) * kDiffuseStrength;
    float specular = pow(max(dot(normal, halfVector), 0.0f), kShininess) * kSpecularStrength;
    float lighting = kAmbientStrength + diffuse;

    float3 litColor = in.color.rgb * lighting + float3(specular);
    return float4(saturate(litColor), in.color.a);
}
