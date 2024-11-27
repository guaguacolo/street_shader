#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Debug/Debugging3D.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DBuffer.hlsl"
#include "Assets/_res/2 model/myshader/street_shader/Editor/DiffusionProfile.hlsl"
struct SubsurfaceScatteringData
{
    float3 fresnel0;
    float3 transmittance;
    float subsurfaceMask;
    float thickness;
};
struct FragmentBuffer
{
    half4 specluarBuffer : SV_TARGET1;
    half4 diffuseBuffer : SV_TARGET2;
    half4 sssBuffer : SV_TARGET3;
};

void InitializationSubsurfaceScatteringData(InputData input, inout SubsurfaceScatteringData subsurfaceData)
{
    //#ifdef _SUBSURFACESCATTERING
    subsurfaceData.fresnel0 = _TransmissionTintsAndFresnel0.a;
    subsurfaceData.subsurfaceMask = _SubsurfaceMask;
    //#ifdef _SUBSURFACEMASKMAP
    subsurfaceData.subsurfaceMask *= SAMPLE_TEXTURE2D(_SubsurfaceMaskMap, sampler_SubsurfaceMaskMap, input.uv).r;
    //#endif
    //#endif

    //#ifdef _TRANSMISSION
    float2 remap = _WorldScalesAndFilterRadiiAndThicknessRemaps.zw;
    subsurfaceData.fresnel0 = _TransmissionTintsAndFresnel0.a;
    half thickness = _Thickness;
    //#ifdef _THICKNESSMAP
    thickness *= SAMPLE_TEXTURE2D(_ThicknessMap, sampler_ThicknessMap, input.uv).r;
    //#endif
    subsurfaceData.thickness = remap.x + remap.y * thickness;
    subsurfaceData.transmittance = ComputeTransmittanceDisney(_ShapeParamsAndMaxScatterDists,
                                                              _TransmissionTintsAndFresnel0,
                                                              subsurfaceData.thickness);
    //#endif
}