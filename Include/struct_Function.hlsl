#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"


struct SubsurfaceScatteringData
{
    float3 fresnel0;
    float3 transmittance;
    float  subsurfaceMask;
    float  thickness;
    float3 diffT;
    float3 specularLighting;
    float3 diffuseLighting;
    Light addtionLight;
};

struct FragmentBuffer
{
    half4 specluarBuffer : SV_TARGET1;
    half4 diffuseBuffer  : SV_TARGET2;
    half4 sssBuffer      : SV_TARGET3;
};
struct TBNpbr
{
    float  TdotH;
    float  BdotH;
    float  NdotH;
    float  TdotV;
    float  BdotV;
    float  NdotV;
    float  TdotL;
    float  BdotL;
    float  NdotL;
    float  roughnessInTangent ;
    float  roughnessInBTangent;
};
struct SurfacePBR
{
    Texture2D _SSSLUT;
    SAMPLER (sampler_SSSLUT);
    Texture2D _BRDFLut;
    SAMPLER (sampler_BRDFLut);
    TextureCube _refmap;
    SAMPLER (sampler_refmap);
    half3 shadowcolor;
    half3 basecolor;
    half _LUTY;
    half aoColor_value;
    float3 aoColor;
    float  Specular;
    float3 F0;
    float _Mip;
    float3 _DitelNormal;
    float3 albedo;
    float3 posOS;
    float metallic;
    float dital_normal_value;
    float lobeWeight;
    float _Roughness_value;
    float _Mip_Value;
    float anisotropic;
    float3 _NormalWorld;
    float3 _Normal_modle;
    float3 dital_normal;
    float4 _tuneNormalBlur;
    float4 _CharacterRimLightColor;
    float4 _CharacterRimLightBorderOffset;
    float4 _CharacterRimLightDirection;
};