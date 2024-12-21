#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
#include "Assets/_res/2 model/myshader/street_shader/Editor/DiffusionProfileSettings.cs.hlsl"
#include "Assets/_res/2 model/myshader/street_shader/Editor/DiffusionProfile.hlsl"
// ----------------------------------------------------------------------------
// helper functions
// ----------------------------------------------------------------------------

// 0: [ albedo = albedo ]
// 1: [ albedo = 1 ]
// 2: [ albedo = sqrt(albedo) ]
//Post-scatter模式下，前向渲染以Albedo为白色计算diffuse，在SSS Pass进行Albdeo的混合；Pre- and post- scatter模式，前向和SSS Pass将以Albedo为sqrt(Albedo)计算diffuse，最后叠加。
uint GetSubsurfaceScatteringTexturingMode(int diffusionProfile)
{
    uint  _TexturingModeFlags = (1 << 0) | (1 << 2); // 初始化 _TexturingModeFlags
    uint  texturingMode = 0;
    uint _EnableSubsurfaceScattering = 1;
    bool enableSss = true;
#if defined(SHADERPASS) && (SHADERPASS == SHADERPASS_SUBSURFACE_SCATTERING)
    enableSss = true;
#else
    enableSss =false;
#endif
    enableSss = _EnableSubsurfaceScattering != 0;


    if (enableSss)
    {
        bool performPostScatterTexturing = IsBitSet(_TexturingModeFlags, diffusionProfile);

        if (performPostScatterTexturing)
        {
            // Post-scatter texturing mode: the albedo is only applied during the SSS pass.
        #if defined(SHADERPASS) && (SHADERPASS != SHADERPASS_SUBSURFACE_SCATTERING)
            texturingMode = 1;
        #endif
        }
        else
        {
            // Pre- and post- scatter texturing mode.
            texturingMode = 2;
        }
    }

    return texturingMode;
}

// Returns the modified albedo (diffuse color) for materials with subsurface scattering.
// See GetSubsurfaceScatteringTexturingMode() above for more details.
// Ref: Advanced Techniques for Realistic Real-Time Skin Rendering.
float3 ApplySubsurfaceScatteringTexturingMode(uint texturingMode, float3 color)
{
    switch (texturingMode)
    {
        case 2:  color = sqrt(color); break;
        case 1:  color = 1;           break;
        default: color = color;       break;
    }

    return color;
}

// ----------------------------------------------------------------------------
// Encoding/decoding SSS buffer functions
// ----------------------------------------------------------------------------

struct SSSData
{
    float3 diffuseColor; //albedo
    float  subsurfaceMask;//次表面散射遮罩
    uint   diffusionProfileIndex;//
};

#define SSSBufferType0 float4 // Must match GBufferType0 in deferred

// SSSBuffer texture declaration
TEXTURE2D_X(_SSSBufferTexture);

// Note: The SSS buffer used here is sRGB
void EncodeIntoSSSBuffer(SSSData sssData, uint2 positionSS, out SSSBufferType0 outSSSBuffer0)
{
    outSSSBuffer0 = float4(sssData.diffuseColor, PackFloatInt8bit(sssData.subsurfaceMask, sssData.diffusionProfileIndex, 16));
}

// Note: The SSS buffer used here is sRGB
void DecodeFromSSSBuffer(float4 sssBuffer, uint2 positionSS, out SSSData sssData)
{
    sssData.diffuseColor = sssBuffer.rgb;
    UnpackFloatInt8bit(sssBuffer.a, 16, sssData.subsurfaceMask, sssData.diffusionProfileIndex);
}

void DecodeFromSSSBuffer(uint2 positionSS, out SSSData sssData)
{
    float4 sssBuffer = LOAD_TEXTURE2D_X(_SSSBufferTexture, positionSS);
    DecodeFromSSSBuffer(sssBuffer, positionSS, sssData);
}

// OUTPUT_SSSBUFFER start from SV_Target2 as SV_Target0 and SV_Target1 are used for lighting buffer, shifts to SV_Target3 if VT is enabled
#ifdef UNITY_VIRTUAL_TEXTURING
    #define OUTPUT_SSSBUFFER(NAME) out SSSBufferType0 MERGE_NAME(NAME, 0) : SV_Target3
#else
    #define OUTPUT_SSSBUFFER(NAME) out SSSBufferType0 MERGE_NAME(NAME, 0) : SV_Target2
#endif

#define ENCODE_INTO_SSSBUFFER(SURFACE_DATA, UNPOSITIONSS, NAME) EncodeIntoSSSBuffer(ConvertSurfaceDataToSSSData(SURFACE_DATA), UNPOSITIONSS, MERGE_NAME(NAME, 0))

#define DECODE_FROM_SSSBUFFER(UNPOSITIONSS, SSS_DATA) DecodeFromSSSBuffer(UNPOSITIONSS, SSS_DATA)

// 为了支持次表面散射，我们需要知道哪些像素使用了次表面散射材质。
// 它当然可以通过读取模版缓冲来实现。 
// 一个更快的解决方案（避免额外的纹理获取）是通过SSS像素的颜色不是黑色来确定（通常情况下是可以的）。
// 我们选择B通道，因为它是最不明显的。
#define HALF_MIN 6.103515625e-5 
float3 TagLightingForSSS(float3 subsurfaceLighting)
{
    subsurfaceLighting.b = max(subsurfaceLighting.b, HALF_MIN);
    return subsurfaceLighting;
}

// See TagLightingForSSS() for details.
bool TestLightingForSSS(float3 subsurfaceLighting)
{
    return subsurfaceLighting.b > 0;
}

// ----------------------------------------------------------------------------
// Helper functions to use SSS/Transmission with a material
// ----------------------------------------------------------------------------

// Following function allow to easily setup SSS and transmission inside a material.
// User can request either SSS functions, or Transmission functions, or both, by defining MATERIAL_INCLUDE_SUBSURFACESCATTERING and/or MATERIAL_INCLUDE_TRANSMISSION
// before including this file.
// + It require that the material follow naming convention for properties inside BSDFData

// struct BSDFData
// {
//     (...)
//     // Share for SSS and Transmission
//     uint materialFeatures;
//     uint diffusionProfile;
//     // For SSS
//     float3 diffuseColor;
//     float3 fresnel0;
//     float subsurfaceMask;
//     // For transmission
//     float thickness;
//     bool useThickObjectMode;
//     float3 transmittance;
//     perceptualRoughness; // Only if user chose to support DisneyDiffuse
//     (...)
// }

// Note: Transmission functions for light evaluation are also included in LightEvaluation.hlsl file based on the MATERIAL_INCLUDE_TRANSMISSION
#define MATERIALFEATUREFLAGS_SSS_TRANSMISSION_START (1 << 16) // It should be safe to start these flags

#define MATERIALFEATUREFLAGS_SSS_OUTPUT_SPLIT_LIGHTING         ((MATERIALFEATUREFLAGS_SSS_TRANSMISSION_START) << 0)
#define MATERIALFEATUREFLAGS_SSS_TEXTURING_MODE_OFFSET FastLog2((MATERIALFEATUREFLAGS_SSS_TRANSMISSION_START) << 1) // Note: The texture mode is 2bit, thus go from '<< 1' to '<< 3'
// Flags used as a shortcut to know if we have thick mode transmission
// It is important to keep this flag pointing at the inverse of the current diffusion profile thickness mode, i.e. the
// current diffusion profile thickness mode is thin because we don't want to sample shadows for the default profile
// so this define is set to thick mode. It is important to keep it as is because when we initialize the BSDF datas
// we assume that all neutral values including the thickness mode are 0 (so by default when we shade a material that
// doesn't have transmission on a tile with the material feature transmission enabled, we don't evaluate the diffusion
// profile because the thick flag is not set (for pixels that have transmission, we force the flags in a per-pixel
// material feature)).
#define MATERIALFEATUREFLAGS_TRANSMISSION_MODE_THICK_OBJECT     ((MATERIALFEATUREFLAGS_SSS_TRANSMISSION_START) << 3)

// 15 degrees
#define TRANSMISSION_WRAP_ANGLE (PI/12)
#define TRANSMISSION_WRAP_LIGHT cos(PI/2 - TRANSMISSION_WRAP_ANGLE)

#ifdef MATERIAL_INCLUDE_SUBSURFACESCATTERING

void FillMaterialSSS(uint diffusionProfileIndex, float subsurfaceMask, inout BSDFData bsdfData)
{
    bsdfData.diffusionProfileIndex = diffusionProfileIndex;
    bsdfData.fresnel0 = _TransmissionTintsAndFresnel0[diffusionProfileIndex].a;
    bsdfData.subsurfaceMask = subsurfaceMask;
    bsdfData.materialFeatures |= MATERIALFEATUREFLAGS_SSS_OUTPUT_SPLIT_LIGHTING;
    bsdfData.materialFeatures |= GetSubsurfaceScatteringTexturingMode(diffusionProfileIndex) << MATERIALFEATUREFLAGS_SSS_TEXTURING_MODE_OFFSET;
}

bool ShouldOutputSplitLighting(BSDFData bsdfData)
{
    return HasFlag(bsdfData.materialFeatures, MATERIALFEATUREFLAGS_SSS_OUTPUT_SPLIT_LIGHTING);
}

float3 GetModifiedDiffuseColorForSSS(BSDFData bsdfData)
{
    // Subsurface scattering mode
    uint   texturingMode = (bsdfData.materialFeatures >> MATERIALFEATUREFLAGS_SSS_TEXTURING_MODE_OFFSET) & 3;
    return ApplySubsurfaceScatteringTexturingMode(texturingMode, bsdfData.diffuseColor);
}

#endif

#ifdef MATERIAL_INCLUDE_TRANSMISSION

// Assume that bsdfData.diffusionProfileIndex is init
void FillMaterialTransmission(uint diffusionProfileIndex, float thickness, inout BSDFData bsdfData)
{
    float2 remap = _WorldScalesAndFilterRadiiAndThicknessRemaps[diffusionProfileIndex].zw;

    bsdfData.diffusionProfileIndex = diffusionProfileIndex;
    bsdfData.fresnel0              = _TransmissionTintsAndFresnel0[diffusionProfileIndex].a;
    bsdfData.thickness             = remap.x + remap.y * thickness;

    // The difference between the thin and the regular (a.k.a. auto-thickness) modes is the following:
    // * in the thin object mode, we assume that the geometry is thin enough for us to safely share
    // the shadowing information between the front and the back faces;
    // * the thin mode uses baked (textured) thickness for all transmission calculations;
    // * the thin mode uses wrapped diffuse lighting for the NdotL;
    // * the auto-thickness mode uses the baked (textured) thickness to compute transmission from
    // indirect lighting and non-shadow-casting lights; for shadowed lights, it calculates
    // the thickness using the distance to the closest occluder sampled from the shadow map.
    // If the distance is large, it may indicate that the closest occluder is not the back face of
    // the current object. That's not a problem, since large thickness will result in low intensity.
    bool useThickObjectMode = !IsBitSet(asuint(_TransmissionFlags), diffusionProfileIndex);

    bsdfData.materialFeatures |= useThickObjectMode ? MATERIALFEATUREFLAGS_TRANSMISSION_MODE_THICK_OBJECT : 0;

    // Compute transmittance using baked thickness here. It may be overridden for direct lighting
    // in the auto-thickness mode (but is always used for indirect lighting).
    bsdfData.transmittance = ComputeTransmittanceDisney(_ShapeParamsAndMaxScatterDists[diffusionProfileIndex].rgb,
                                                        _TransmissionTintsAndFresnel0[diffusionProfileIndex].rgb,
                                                        bsdfData.thickness);
}

#endif

#if defined(MATERIAL_INCLUDE_SUBSURFACESCATTERING) || defined(MATERIAL_INCLUDE_TRANSMISSION)

uint FindDiffusionProfileIndex(uint diffusionProfileHash)
{
    if (diffusionProfileHash == 0)
        return 0;

    uint diffusionProfileIndex = 0;
    uint i = 0;

    // Fetch the 4 bit index number by looking for the diffusion profile unique ID:
    for (i = 0; i < _DiffusionProfileCount; i++)
    {
        if (_DiffusionProfileHashTable[i].x == diffusionProfileHash)
        {
            diffusionProfileIndex = i;
            break;
        }
    }

    return diffusionProfileIndex;
}

#endif
