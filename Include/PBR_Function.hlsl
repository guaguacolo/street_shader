
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Debug/Debugging3D.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DBuffer.hlsl"
#include "Assets/_res/2 model/myshader/street_shader/Editor/DiffusionProfile.hlsl"
#include "Assets/_res/2 model/myshader/street_shader/Include/struct_Function.hlsl"
//间接光函数
//间接光 F

float3 FresnalSchlickRoughness(float NV, float3 F0,float roughness)
{
    float s=1.0-roughness;
    return F0+(max(s.xxx,F0))*pow(1.0-NV,5.0);
}
float3 F_Schlick_Unreal( float3  SpecularColor, float VoH )
{
    float Fc = pow(( 1.0f - saturate(VoH) ),5.0f);                 // 1 sub, 3 mul
     
    // Anything less than 2% is physically impossible and is instead considered to be shadowing
    return saturate( 50.0 * SpecularColor.g ) * Fc + (1 - Fc) * SpecularColor;
}
float DielectricSpecularcularToF0(float specular,float3 F0)
{
    return F0*specular;
}
float3 ComputeF0(float specular, float3 BaseColor, float Metallic,float3 F0)
{
    return lerp(DielectricSpecularcularToF0(specular,F0).xxx, BaseColor, Metallic.xxx);
}
//屏幕侧面光
float3 ScreenRimLight(SurfacePBR surfacepbr,float shadow,float posWS)
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
    float viewNormaloRimLightDir = (1-(dot(normal1InView, characterRimLightDir)));
    //float minBorder = surfacepbr._CharacterRimLightDirection.z + 0.5 - surfacepbr._CharacterRimLightDirection.w;
    //float maxBorder = surfacepbr._CharacterRimLightDirection.z + 0.5 + surfacepbr._CharacterRimLightDirection.w;
    //float minBorder = pow((posWS+10)/20+0.8,2) + 0.5 - max(0.3,(posWS+10)/20*0.01);
    //float maxBorder = pow((posWS+10)/20+0.8,2) + 0.5 + max(0.3,(posWS+10)/20*0.01);
    float minBorder = pow((posWS+10)/20+0.8,2) + 0.2 - surfacepbr._CharacterRimLightDirection.w;
    float maxBorder = pow((posWS+10)/20+0.8,2) + 0.2 + surfacepbr._CharacterRimLightDirection.w;
    float rimTempValue = (viewNormaloRimLightDir - minBorder) / (maxBorder - minBorder);
    float3 rimColor2nd = smoothstep(0, 0.5, rimTempValue) * surfacepbr._CharacterRimLightColor.xyz*(-surfacepbr.posOS.z+0.1);
    return rimColor2nd;
}
float3 F_FresnelSchlick(float HV,float3 F0)
{
    float FC=pow(1.0-(clamp(HV,0.0,1.0)),5.0);
    return F0+(1.0-F0)*pow(1.0-(clamp(HV,0.0,1.0)),5.0);
}
//各向异性高光D
float D_DistributionGGX_Distribution(float anisotropic, float roughness, float NdotH, float HdotX, float HdotY)
{
    float aspect = (1.0 - 0.9 * anisotropic);
          aspect= aspect*aspect;
    float roughnessSqr = roughness * roughness;
    float NdotHSqr = NdotH * NdotH;
    float ax = roughnessSqr / aspect;
    float ay = roughnessSqr * aspect;
    float d = HdotX * HdotX / (ax * ax) + HdotY * HdotY / (ay * ay) + NdotHSqr;
    return 1 / (3.14159 * ax * ay * d * d);
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
// Vis = G / (4*NoL*NoV)  HDRP
// Note: V = G / (4 * NdotL * NdotV)
// Ref: http://jcgt.org/published/0003/02/03/paper.pdf
float GeometryShlickGGX(float NV,float Roughness)
{
    float r= Roughness+1.0;
    float k=r*r/8.0;
    float numerator=NV;
    float denominator=k+(1.0-k)*NV;
    return numerator/max(denominator,0.001);
}

 float Remap(float value, float fromMin, float fromMax, float toMin, float toMax)
{
    return toMin + (value - fromMin) * (toMax - toMin) / (fromMax - fromMin);
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
float3 BentNormlsDiffuseLighting(float3 norm,float3 L,float Curvature,SurfacePBR surfacepbr,float shadow)
{
//法线分层模糊
    float3 N_high=norm;     
    float3 N_low=surfacepbr._Normal_modle;     
    float3 rN=lerp(N_high,N_low,surfacepbr._tuneNormalBlur.x);
    float3 gN=lerp(N_high,N_low,surfacepbr._tuneNormalBlur.y);
    float3 bN=lerp(N_high,N_low,surfacepbr._tuneNormalBlur.z);
    float3 NdotL=float3(dot(rN,L),dot(gN,L),dot(bN,L));
    half t = (1.0-0.9) * saturate(float3(dot(-rN,L),dot(-gN,L),dot(-bN,L)));
    float3 lookup=NdotL*0.5+0.5;
    float3 diffuseSSS;
    Curvature*=surfacepbr._LUTY;
    diffuseSSS.r=SAMPLE_TEXTURE2D(surfacepbr._SSSLUT,surfacepbr.sampler_SSSLUT,float2(lerp(0.002,0.998,(lookup.r)* shadow),Curvature)).r;
    diffuseSSS.g=SAMPLE_TEXTURE2D(surfacepbr._SSSLUT,surfacepbr.sampler_SSSLUT,float2(lerp(0.002,0.998,(lookup.g)* shadow),Curvature)).g;
    diffuseSSS.b=SAMPLE_TEXTURE2D(surfacepbr._SSSLUT,surfacepbr.sampler_SSSLUT,float2(lerp(0.002,0.998,(lookup.b)* shadow),Curvature)).b;
    return diffuseSSS*(1+t);
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

half3 DirectBDRF_DualLobeSpecular(half roughness, half3 normalWS, half3 lightDirectionWS, half3 viewDirectionWS,SurfacePBR surfacepbr,float mask)
{
    float3 halfDir = SafeNormalize(float3(lightDirectionWS) + float3(viewDirectionWS));
    float roughness2=roughness*roughness;
    float NoH = saturate(dot(normalWS, halfDir));
    float LoH = saturate(dot(lightDirectionWS, halfDir));
 
    float d = NoH * NoH * saturate(roughness2-1) + 1.00001f;
    float nv = saturate(dot(normalWS,lightDirectionWS));
    float LoH2 = LoH * LoH;
    float sAO = saturate(-0.3f + nv * nv);
          sAO =  lerp(pow(0.75, 8.00f), 1.0f, sAO);
    float SpecularOcclusion = sAO;
    float specularTermGGX_roghness = roughness2 / ((d * d) * max(0.1h, LoH2) * (roughness * half(4.0) + half(2.0)));
    float specularTermBeckMann =(2.0 * (roughness2) /((d * d) * max(0.1h, LoH2) * (roughness * half(4.0) + half(2.0)))) * surfacepbr.lobeWeight *mask;
    float specularTerm = (specularTermGGX_roghness / 2 + specularTermBeckMann) * SpecularOcclusion;
    #if defined (SHADER_API_MOBILE) || defined (SHADER_API_SWITCH)
          specularTerm = specularTerm - HALF_MIN;
          specularTerm = clamp(specularTerm, 0.0, 100.0);
    #endif
    float3 specular_double = specularTerm * surfacepbr.Specular/*+(surfacepbr.basecolor*(float3)(surfacepbr.Specular))*/;
    return specular_double.xxx;
}
 float3 PBR_Light(BRDFData brdfData,Light light,half3 normal, half3 posWS,half3 V,SurfacePBR surface_pbr,TBNpbr tbnpbr, SurfaceData surfaceData
                 ,InputData inputData,inout SubsurfaceScatteringData subsurfacescatteringdata)

            {
 //参数部分
                float3 L=normalize(light.direction);
                float3 H = normalize(V+L);
                float  HX=dot(H,float3(1,0,0));
                float  HY=dot(H,float3(0,1,0));
                float3 VH=dot(V,H);
                float3 NV=saturate(dot(normal,V));
                float3 NL=saturate(dot(normal,L));
                float3 NH=saturate(dot(normal,H));
                float3 R = normalize(reflect(-V,normal)); 
                half3  radiance=light.color;
                float  roughness_G=brdfData.roughness;
                float  roughness=pow(brdfData.roughness,surface_pbr._Roughness_value);
                float  metalic=surface_pbr.metallic;
                float3 baseColor=surface_pbr.albedo;
                float  specular1=surface_pbr.Specular;
                float  ao=pow(brdfData.specular,5);
                float3 F0=surface_pbr.F0.xyz;
                float  _Mip=surface_pbr._Mip;
                float  _Mip_Value=surface_pbr._Mip_Value;
                       FragmentBuffer output;
  #if F0_UN             
                F0=lerp((float3)0.04,baseColor,metalic);
  #endif
    
    
    
  //阴影
  //计算阴影
                float3 shadow=light.distanceAttenuation * light.shadowAttenuation;                      
 //SSS 预积分
              /*  //Curvature
                float  deltaWorldNormal=length(fwidth(normal));
                float  deltaWorldPos = length(fwidth(posWS));
                float  curvature = (deltaWorldNormal/deltaWorldPos);
                float3 SSSNL=BentNormlsDiffuseLighting(normal,L,curvature,surface_pbr,shadow);*/
    
 //HDRP G
                
                float3 SpecularColor =ComputeF0(specular1,baseColor,metalic,F0);
                float3 F_Unreal      =F_Schlick_Unreal(SpecularColor,VH);
                float  vis           =V_SmithJointGGX(NL,NV,roughness);
 //DFG
   
                float3 F = F0 + (1 - F0) * exp2((-5.55473 * VH - 6.98316) * VH);
                //float3 F=F_FresnelSchlick(VH,F0);
    
                float  D=D_DistributionGGX(normal,H,roughness);
 /* #if DITAL_NORMAL
    normal=lerp(normal,surface_pbr.dital_normal,surface_pbr.dital_normal_value);
    D=D_DistributionGGX(normal,H,roughness);
 #endif*/
     
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
 
               
 //直接光 高光
                float  numerator= D*G*F_Unreal;
                float  denominator=max(4*NV*NL,0.001);
                float  v=DV_SmithJointGGXAniso(tbnpbr.TdotH,tbnpbr.BdotH,tbnpbr.NdotH,tbnpbr.TdotV,tbnpbr.BdotV,tbnpbr.NdotV,tbnpbr.TdotL,tbnpbr.BdotL,tbnpbr.NdotL,
                                 tbnpbr.roughnessInTangent,tbnpbr.roughnessInBTangent);
                       v=saturate(v);
                float  specular= numerator/denominator;
                float  specular_double=DirectBDRF_DualLobeSpecular(roughness,normal,L,V,surface_pbr,1);
 /* #if DITAL_NORMAL
                     
                       specular_double=DirectBDRF_DualLobeSpecular(roughness,normal,L,V,surface_pbr,1);
    #endif*/
 //双层 高光
       #if RENDER_Unreal
                       specular= D*vis*F;
                       specular=saturate(specular_double*0.75+specular);
       #endif
       #if HAIR_RENDER
                       specular= v*F;
       #endif
                 
 //直接光 漫反射
                float3 ks=F;
        #if RENDER_Unreal
                       ks=saturate(F);
        #endif
                float3 kd=(1-ks)*(1-metalic);
      /*  #if SSS_RENDER
         NL=SSSNL;
        #endif*/
 //皮肤直接光
    //透射参数
  
                float  flippedNdotL = ComputeWrappedDiffuseLighting(-NL,cos(PI/2 - (PI/12)));

    
                float3 diffT=flippedNdotL*baseColor*radiance;
                float3 Diffuse=kd*baseColor* radiance *NL*surface_pbr.basecolor*shadow;//没有除以PI

    
                float3 DirectLight = (Diffuse+ specular)* radiance *NL*surface_pbr.basecolor*shadow ;
                       //DirectLight = lerp(DirectLight*surface_pbr.shadowcolor,DirectLight,shadow);
 //ao
                       specular=specular* radiance *NL*surface_pbr.basecolor*shadow ;
                       ao=smoothstep(0,1,ao);
                float3 aoColor=lerp(surface_pbr.aoColor,1,ao);
                       aoColor=saturate(lerp(1,aoColor,surface_pbr.aoColor_value));

 //屏幕侧面光
              
                float3 ScreenRimcol=ScreenRimLight(surface_pbr,shadow,posWS);
    
    
                float3 IndirectLight=(Diffuse_Indirect+Specular_Indirect)*aoColor*surface_pbr.shadowcolor;
                       //IndirectLight = lerp(IndirectLight*surface_pbr.shadowcolor,IndirectLight,shadow);

//#endif
                       subsurfacescatteringdata.specularLighting+=specular+Specular_Indirect*aoColor/**surface_pbr.shadowcolor*/;
                       subsurfacescatteringdata.diffuseLighting +=(Diffuse +Diffuse_Indirect*aoColor*surface_pbr.shadowcolor);
                       subsurfacescatteringdata.diffT +=diffT;
  
 
 //最终光照
               
                float3 Finalcolor=0;
                Finalcolor.xyz=((DirectLight+IndirectLight)+ScreenRimcol)/*shadow*/;
                return Finalcolor;

            }