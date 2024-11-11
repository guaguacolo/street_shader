
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Debug/Debugging3D.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DBuffer.hlsl"

//间接光函数
//间接光 F
struct SurfacePBR
{
    Texture2D _SSSLUT;
    SAMPLER (sampler_SSSLUT);
    Texture2D _BRDFLut;
    SAMPLER (sampler_BRDFLut);
    TextureCube _refmap;
    SAMPLER (sampler_refmap);
    half3 shadowcolor;
    half3 shadowcolor1;
    half3 basecolor;
    half _LUTY;
    half aoColor_value;
    float3 aoColor;
    float Specular;
    float4 F0;
    float _Mip;
    float3 _DitelNormal;
    float3 albedo;
    float metallic;
    float lobeWeight;
    float _Roughness_value;
    float _Mip_Value;
    float3 _NormalWorld;
    float3 _Normal_modle;
    float4 _tuneNormalBlur;
    float4 _CharacterRimLightColor;
    float4 _CharacterRimLightBorderOffset;
    float4 _CharacterRimLightDirection;
};
float3 FresnalSchlickRoughness(float NV, float3 F0,float roughness)
{
    float s=1.0-roughness;
    return F0+(max(s.xxx,F0)-F0)*pow(1.0-NV,5.0);
     
}


float3 F_Schlick_Unreal( float3  SpecularColor, float VoH )
{
    float Fc = pow(( 1 - VoH ),5.0);                 // 1 sub, 3 mul
    return /*saturate( 50.0 *  SpecularColor.g ) */ Fc + (1 - Fc) * SpecularColor;    // 1 add, 3 mad
     
    // Anything less than 2% is physically impossible and is instead considered to be shadowing
    //return saturate( 50.0 * SpecularColor.g ) * Fc + (1 - Fc) * SpecularColor;
}
float DielectricSpecularcularToF0(float specular,float F0)
{
    return F0*specular;
}
float3 ComputeF0(float specular, float3 BaseColor, float Metallic,float F0)
{
    return lerp(DielectricSpecularcularToF0(F0,specular).xxx, BaseColor, Metallic.xxx);
}
//屏幕侧面光
float3 ScreenRimLight(SurfacePBR surfacepbr,float shadow)
{
    float3 N=0;
    #if ScreenRimLight_DitalNormal
    N=surfacepbr._NormalWorld;
    #else
    N=surfacepbr._Normal_modle;
    #endif
    float3 normal1InView = normalize(mul(UNITY_MATRIX_V,N));
 
    float3 characterRimLightDir = normalize(float3(surfacepbr._CharacterRimLightDirection.xy, 1));
 
    //float viewNormaloRimLightDir = pow((1-(dot(normal1InView, characterRimLightDir)*0.5+0.5)),1)*1;
    float viewNormaloRimLightDir = pow((1-(dot(normal1InView, characterRimLightDir)*0.5+0.5)),5)*5;
    float minBorder = surfacepbr._CharacterRimLightDirection.z + 0.5 - surfacepbr._CharacterRimLightDirection.w;
    float maxBorder = surfacepbr._CharacterRimLightDirection.z + 0.5 + surfacepbr._CharacterRimLightDirection.w;
 
    float rimTempValue = (viewNormaloRimLightDir - minBorder) / (maxBorder - minBorder);
    float3 rimColor2nd = smoothstep(0, 1, rimTempValue) * surfacepbr._CharacterRimLightColor.xyz ;
    return viewNormaloRimLightDir.xxx;
}


float3 F_FresnelSchlick(float HV,float3 F0)
{
    float FC=pow(1.0-(clamp(HV,0.0,1.0)),5.0);
    return F0+(1.0-F0)*pow(1.0-(clamp(HV,0.0,1.0)),5.0);
}
          
float D_DistributionGGX(float3 N,float3 H,float Roughness)
{
    float a= Roughness*Roughness;
    float a2=a*a;
    float NH=max(saturate(dot(N,H)),0);
    float NH2=NH*NH;
    float numerator= a2;
    float denominator= (NH2*(a2-1.0)+1.0);
    denominator=PI*denominator*denominator;
    return numerator/max(denominator,0.01);
}
//// Vis = G / (4*NoL*NoV)
float Vis_SmithJointApprox( float a2, float NoV, float NoL )
{
    float a = sqrt(a2);
    float Vis_SmithV = NoL * ( NoV * ( 1 - a ) + a );
    float Vis_SmithL = NoV * ( NoL * ( 1 - a ) + a );
    return 0.5 * rcp( Vis_SmithV + Vis_SmithL );
}

float GeometryShlickGGX(float NV,float Roughness)
{
    float r= Roughness+1.0;
    float k=r*r/8.0;
    float numerator=NV;
    float denominator=k+(1.0-k)*NV;
    return numerator/max(denominator,0.001);
}
float G_GeometrySmith(float3 N, float3 L, float3 V,float Roughness)
{
    float NV=max(saturate(dot(N,V)),0);
    float NL=max(saturate(dot(N,L)),0);

    float GGX1=GeometryShlickGGX(NV,Roughness);
    float GGX2=GeometryShlickGGX(NL,Roughness);
    return GGX1*GGX2;
}
//预积分SSS
float3 BentNormlsDiffuseLighting(float3 norm,float3 L,float Curvature,SurfacePBR surfacepbr)
{
//法线分层模糊
    float3 N_high=norm;     
    float3 N_low=surfacepbr._NormalWorld;     
    float3 rN=lerp(N_high,N_low,surfacepbr._tuneNormalBlur.x);
    float3 gN=lerp(N_high,N_low,surfacepbr._tuneNormalBlur.y);
    float3 bN=lerp(N_high,N_low,surfacepbr._tuneNormalBlur.z);
    float3 NdotL=float3(dot(rN,L),dot(gN,L),dot(bN,L));
    float3 lookup=NdotL*0.5+0.5;
    float3 diffuseSSS;
    diffuseSSS.r=SAMPLE_TEXTURE2D(surfacepbr._SSSLUT,surfacepbr.sampler_SSSLUT,float2(lerp(0.002,0.998,(lookup.r)),Curvature*surfacepbr._LUTY)).r;
    diffuseSSS.g=SAMPLE_TEXTURE2D(surfacepbr._SSSLUT,surfacepbr.sampler_SSSLUT,float2(lerp(0.002,0.998,(lookup.g)),Curvature*surfacepbr._LUTY)).g;
    diffuseSSS.b=SAMPLE_TEXTURE2D(surfacepbr._SSSLUT,surfacepbr.sampler_SSSLUT,float2(lerp(0.002,0.998,(lookup.b)),Curvature*surfacepbr._LUTY)).b;
    return diffuseSSS;
}
float2  EnvBRDFApprox(float Roughness,float NoV)
{
    const float4 c0 = {-1,-0.0275,-0.572,0.022};
    const float4 c1 = {1,0.0425,1.04,-0.04};
    float4 r= Roughness*c0+c1;
    float a004=min(r.x*r.x,exp2(-9.28*NoV))*r.x+r.y;
    float2 AB = float2(-1.04,1.04)*a004+r.zw;
    return AB;
}
inline void InitializeBRDFDataPBR(half3 albedo, half3 metalic, float ao,half3 roughness,  out BRDFData outBRDFData)
{
    outBRDFData = (BRDFData)0;
    outBRDFData.albedo = albedo;
    outBRDFData.diffuse = metalic;
    outBRDFData.specular = ao;
    outBRDFData.roughness = roughness;
    
}
half3 DirectBDRF_DualLobeSpecular(half roughness,half specular, half3 normalWS, half3 lightDirectionWS, half3 viewDirectionWS,SurfacePBR surfacepbr,float mask)
{
    float3 halfDir = SafeNormalize(float3(lightDirectionWS) + float3(viewDirectionWS));
    float  roughness2=roughness*roughness;
    float NoH = saturate(dot(normalWS, halfDir));
    float LoH = saturate(dot(lightDirectionWS, halfDir));
 
    float d = NoH * NoH * saturate(roughness2-1) + 1.00001f;
    float nv = saturate(dot(normalWS,lightDirectionWS));
    float LoH2 = LoH * LoH;
    float sAO = saturate(-0.3f + nv * nv);
    sAO =  lerp(pow(0.75, 8.00f), 1.0f, sAO);
    float SpecularOcclusion = sAO;
    float specularTermGGX_roghness = roughness2 / ((d * d) * max(0.1h, LoH2) * 1);
    float specularTermBeckMann =
        (2.0 * (roughness2) /
        ((d * d) * max(0.1h, LoH2) * 0.3)) * surfacepbr.lobeWeight * 1*mask;
    float specularTerm = (specularTermGGX_roghness / 2 + specularTermBeckMann) * SpecularOcclusion ;
 
    float3 specular_double = specularTerm * specular;
    return specular_double;
}
 float3 PBR_Light(BRDFData brdfData,Light light,half3 normal, half3 posWS,half3 V,SurfacePBR surface_pbr)

            {
 //参数部分
                float3 L=normalize(light.direction);
                float3 H = normalize(V+L);
                float3 VH=dot(V,H);
                float3 NV=dot(normal,V);
                float3 NL=saturate(dot(normal,L));
                float3 R = normalize(reflect(-V,normal)); 
                half3  radiance=light.color;
                float  roughness_G=brdfData.roughness;
                float  roughness=pow(brdfData.roughness,surface_pbr._Roughness_value);
                float  metalic=surface_pbr.metallic;
                float3 baseColor=surface_pbr.albedo;
                float  specular1=surface_pbr.Specular;
                float  ao=pow(brdfData.specular,5);
                float3 F0=surface_pbr.F0.xyz;
                float  F0_Unreal=surface_pbr.F0.xyz;
                float  _Mip=surface_pbr._Mip;
                float  _Mip_Value=surface_pbr._Mip_Value;
                
                //F0=lerp(F0,baseColor,metalic);
 
                        
 //SSS 预积分
                //Curvature
                float  deltaWorldNormal=length(fwidth(normal));
                float  deltaWorldPos = length(fwidth(posWS));
                float  curvature = (deltaWorldNormal/deltaWorldPos)*0.06;
                float3 SSSNL=BentNormlsDiffuseLighting(normal,L,curvature,surface_pbr);
 
 //虚幻引擎的F  G               
                float3 SpecularColor =ComputeF0(specular1,baseColor,metalic,F0_Unreal);
                float3 F_Unreal=F_Schlick_Unreal(SpecularColor,VH);
                float  vis=Vis_SmithJointApprox(roughness*roughness,NV,NL);
 //DFG
   
                float3 F = F0 + (1 - F0) * exp2((-5.55473 * VH - 6.98316) * VH);
                //       F=F_FresnelSchlick(VH,F0); 
                float  D=D_DistributionGGX(normal,H,roughness);
                float  G=G_GeometrySmith(normal,L,V,roughness_G);
                
               
               
 //间接光 菲尼尔
                float3 F_IndirectLight=FresnalSchlickRoughness(NV,F0,roughness);
 //间接光漫反射
 //间接光漫反射所占据的比例
                float3 KD_Indirectlight=float3(1,1,1)-F_IndirectLight;
                       KD_Indirectlight*=(1-metalic);
 //传入球谐函数
                float3 irradianSH=SampleSH(normal);
                float3 Diffuse_Indirect=irradianSH*baseColor*KD_Indirectlight;
                       
 //间接光镜面反射
                float  mip      = roughness*(1.7-0.7*roughness)*UNITY_SPECCUBE_LOD_STEPS;
                float4 rgb_mip = SAMPLE_TEXTURECUBE_LOD(unity_SpecCube0,samplerunity_SpecCube0,R,mip);
        #if enable_globlemetalic
                       rgb_mip =  SAMPLE_TEXTURECUBE_LOD(surface_pbr._refmap,surface_pbr.sampler_refmap,normal,_Mip)*0.5;
        #endif
                float3 EnvSpeculaiPrefilted=DecodeHDREnvironment(rgb_mip,unity_SpecCube0_HDR)*_Mip_Value;
 //数值拟合
                float2 env_brdf= EnvBRDFApprox(roughness,NV);
                float3 Specular_Indirect =EnvSpeculaiPrefilted*(F_IndirectLight*env_brdf.r+env_brdf.g);
 //阴影
 //计算阴影
                float3 shadow=light.distanceAttenuation * light.shadowAttenuation;
                //Diffuse_Indirect=lerp(Diffuse_Indirect*surface_pbr.shadowcolor,Diffuse_Indirect,shadow);
 //直接光 高光
                float  numerator= D*G*F;
                float  denominator=max(4*NV*NL,0.001);
   
                float  specular= numerator/denominator;
                float  specular_double=DirectBDRF_DualLobeSpecular(roughness,roughness,normal,L,V,surface_pbr,D);
 //虚幻 高光
       #if RENDER_Unreal
                       specular= D*vis*F_Unreal;
                       specular= specular_double*0.15+D*vis*F_Unreal*0.85;
       #endif
                
 //直接光 漫反射
                float3 ks=F;
        #if RENDER_Unreal
                       ks=saturate(F_Unreal);
        #endif
                float3 kd=(1-ks)*(1-metalic);
 //皮肤直接光
                float3 Diffuse=kd*baseColor;//没有除以PI
                float3 DirectLight = (Diffuse+ specular)* radiance * SSSNL*surface_pbr.basecolor ;
                DirectLight = lerp(DirectLight*surface_pbr.shadowcolor,DirectLight,shadow);
 //ao
                       ao=smoothstep(0,1,ao);
                float3 aoColor=lerp(surface_pbr.aoColor,1,ao);
                       aoColor=saturate(lerp(1,aoColor,surface_pbr.aoColor_value));
                float3 IndirectLight=(Diffuse_Indirect+Specular_Indirect)*aoColor;
 //屏幕侧面光
                float3 ScreenRimcol=ScreenRimLight(surface_pbr,shadow);
 //最终光照
                float3 Finalcolor=0;
                Finalcolor.xyz=((DirectLight+IndirectLight)+ScreenRimcol);
                return ScreenRimcol;

            }