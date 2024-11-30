
Shader "Game/humanSSS"

{
    Properties
    {
        
        _BaseMap("Base Map", 2D) = "white" {}
        [Hdr] _BaseColor("Base Color", Color) = (1,1,1,1)
        _ShadowColor("暗部颜色修正", Color) = (1,1,1,1)
        _aoColor("ao颜色", Color) = (1,1,1,1)
         [Space(50)]
        [Hdr]_CharacterRimLightColor("侧面光颜色", Color) = (1,1,1,1)
        _CharacterRimLightDirection("XY侧面光方向",Vector)=(1,1,1,1)
        _SrmaTex("SrmaTex (RGBA)", 2D) = "white" {}
        _Normal("_Normal",2D) = "Bump"{}
        _SSSLUT("_SSSLUT",2D) = "Black"{}
        _LUTY("_LUTY",Range(0,4)) = 4
        _aoColor_value("_aoColor_value",Range(0,3)) = 1.5
        _Roughness_value("_Roughness_value",Range(0,5)) = 1.0
        [Space(50)]
        _refmap("_refmap",Cube) = ""{}
        _Mip("_Mip",Range(0,8)) = 4.0
        _F0("_F0",Vector) = (0.04,0.04,0.04,0.04)
        _tuneNormalBlur("_tuneNormalBlur",Color) = (0.04,0.04,0.04,0.04)
        _Mip_Value("_Mip_Value",Range(0,2)) = 0.5
        lobeWeight("lobeWeight",Range(0,2)) = 0.5
        [Space(50)]
        [Space(50)]
        anisotropic("anisotropic",Range(0,1)) = 0.5
        [Toggle(Test_On)]Test_0n("Test_0n",int)=0
        [Toggle(enable_globlemetalic)]enable_globlemetalic("使用单独反射贴图",int)=0
        [Toggle(RENDER_Unreal)]RENDER_Unreal("Unreal",int)=0
        [Toggle(ScreenRimLight_DitalNormal)]ScreenRimLight_DitalNormal("侧面光细节贴图",int)=0
        [Toggle(_SUBSURFACESCATTERING)]_SUBSURFACESCATTERING("SSS开关",int)=0
        [Toggle(_TRANSMISSION)]_TRANSMISSION("透射开关",int)=0
        [Toggle(HAIR_RENDER)]HAIR_RENDER("各向异性高光开关",int)=0
        [Toggle(F0_UN)]F0_UN("金属F0",int)=0
        [Toggle(Cloth_UN)]Cloth_UN("布料",int)=0
     
    } 
    
    SubShader
    {
        Tags
        {
             "RenderPipeline" = "UniversalPipeline" "RenderType"="Transparent"  "Queue"="Geometry" 
         
        }
         LOD 200

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            Cull front
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert             
            #pragma fragment frag

            //#pragma multi_compile_fragment _ _FIX_PROJECTION_ON

            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local BOOLEAN_STATECOLORENABLE_ON
            #pragma shader_feature_local BOOLEAN_VTENABLE_ON
            #pragma shader_feature_local _SUBSURFACESCATTERING
            #pragma shader_feature_local _TRANSMISSION

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "./Include/FixProjection1.hlsl"

            half3 _LightDirection;  // _WorldSpaceLightPos0
            half3 _LightPosition;
            CBUFFER_START(UnityPerMaterial)
                half3 _RColor;
                half3 _GColor;
                half3 _BColor;
                half4 _ShadowColor;
                half3 _StateColor;
                half _AOScale;
                half3 _VTColor;
                half _VTScale;
                bool _FresnelToggle;
                half4 _FresnelColor;
                half3 _SssColor;
                half _SssWeight;
                half _FresnelPower;
                half _Metalness;
                half4 _OffsetScale1;
                half4 _OffsetScale2;
                half4 _Param1;
                half4 _Param2;
            CBUFFER_END

            struct appdata_t
            {
                float4 vertexOS: POSITION;
                float3 normalOS: NORMAL;
#ifdef _ALPHATEST_ON
                float2 uv: TEXCOORD0;
#endif
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
#ifdef _ALPHATEST_ON
                float2 uv: TEXCOORD0;
#endif
                float4 positionCS: SV_POSITION;
            };

            // 获取裁剪空间下的阴影坐标             
            half4 GetShadowPositionHClips(appdata_t v)
            {
                float3 positionWS = TransformObjectToWorld(v.vertexOS.xyz);

#if _CASTING_PUNCTUAL_LIGHT_SHADOW//着色器根据是否需要处理点光源阴影而选择编译不同的代码路径。这可以提高性能，避免不必要的计算。
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
                float3 lightDirectionWS = _LightDirection;
#endif
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                positionWS = ApplyShadowBias(positionWS, normalWS, lightDirectionWS);

//#ifdef _FIX_PROJECTION_ON
              //  positionWS = fixProjection(positionWS);
//#endif

                float4 p = TransformWorldToHClip(positionWS);
                return p;
            }

            v2f vert(appdata_t v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
#ifdef _ALPHATEST_ON
                o.uv = v.uv;
#endif
                o.positionCS = GetShadowPositionHClips(v);
                return o;
            }

            half4 frag(v2f i) : SV_TARGET
            {
#ifdef _ALPHATEST_ON
                half4 baseColor = SampleAlbedoAlpha(i.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                baseColor *= _BaseColor;
                clip(baseColor.a - _Cutoff);
#endif
                return 0;
            }
            ENDHLSL
       
        } 
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            Cull front
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert             
            #pragma fragment frag

//            #pragma multi_compile_fragment _ _FIX_PROJECTION_ON

            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local BOOLEAN_STATECOLORENABLE_ON
            #pragma shader_feature_local BOOLEAN_VTENABLE_ON

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "./Include/FixProjection1.hlsl"

            half3 _LightDirection;  // _WorldSpaceLightPos0
            half3 _LightPosition;

            CBUFFER_START(UnityPerMaterial)
                half3 _RColor;
                half3 _GColor;
                half3 _BColor;
                half4 _ShadowColor;
                half3 _StateColor;
                half _AOScale;
                bool _FresnelToggle;
                half3 _VTColor;
                half _VTScale;
                half4 _FresnelColor;
                half3 _SssColor;
                half _SssWeight;
                half _FresnelPower;
                half _Metalness;
                half4 _OffsetScale1;
                half4 _OffsetScale2;
                half4 _Param1;
                half4 _Param2;
            CBUFFER_END

            struct appdata_t
            {
                float4 vertexOS: POSITION;
                float3 normalOS: NORMAL;
            #ifdef _ALPHATEST_ON
                float2 uv: TEXCOORD0;
            #endif
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
            #ifdef _ALPHATEST_ON
                float2 uv: TEXCOORD0;
            #endif
                float4 positionCS: SV_POSITION;
            };


            v2f vert(appdata_t v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
            #ifdef _ALPHATEST_ON
                o.uv = v.uv;
            #endif
                float3 positionWS = TransformObjectToWorld(v.vertexOS.xyz);
//#ifdef _FIX_PROJECTION_ON
                positionWS = fixProjection(positionWS);
//#endif
                o.positionCS = TransformWorldToHClip(positionWS);
                return o;
            }

            half4 frag(v2f i) : SV_TARGET
            {
            #ifdef _ALPHATEST_ON
                half4 baseColor = SampleAlbedoAlpha(i.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                baseColor *= _BaseColor;
                clip(baseColor.a - _Cutoff);
            #endif
                return 0;
            }
            ENDHLSL
        }
// This pass is used when drawing to a _CameraNormalsTexture texture
        Pass
        {
            Name "DepthNormals"
            Tags{"LightMode" = "DepthNormals"}

            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma only_renderers gles gles3 glcore d3d11
            #pragma target 2.0

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _PARALLAXMAP
            #pragma shader_feature_local _ _DETAIL_MULX2 _DETAIL_SCALED
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitDepthNormalsPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            // Lightmode matches the ShaderPassName set in UniversalRenderPipeline.cs. SRPDefaultUnlit and passes with
            // no LightMode tag are also rendered by Universal Render Pipeline
            Name "GBuffer"
            Tags{"LightMode" = "UniversalGBuffer"}

            ZWrite[_ZWrite]
            ZTest LEqual
            Cull[_Cull]

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            //#pragma shader_feature_local_fragment _ALPHAPREMULTIPLY_ON
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local_fragment _OCCLUSIONMAP
            #pragma shader_feature_local _PARALLAXMAP
            #pragma shader_feature_local _ _DETAIL_MULX2 _DETAIL_SCALED

            #pragma shader_feature_local_fragment _SPECULARHIGHLIGHTS_OFF
            #pragma shader_feature_local_fragment _ENVIRONMENTREFLECTIONS_OFF
            #pragma shader_feature_local_fragment _SPECULAR_SETUP
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF

            // -------------------------------------
            // Universal Pipeline keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            //#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            //#pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            #pragma multi_compile_fragment _ _RENDER_PASS_ENABLED

            // -------------------------------------
            // Unity defined keywords
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #pragma vertex LitGBufferPassVertex
            #pragma fragment LitGBufferPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitGBufferPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "UniversalForward"
            Tags{"LightMode"="UniversalForward" "SkinDiffuse"="true"}

            Cull Back
			ZWrite On

            HLSLPROGRAM
            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
           /* #pragma multi_compile_fragment _ _NORMALMAP
            #pragma multi_compile_fragment _ _EMISSION*/


            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature  _OVERLAY_NONE _OVERLAY_ADD _OVERLAY_MULTIPLY
            #pragma shader_feature  _ Test_On
            #pragma shader_feature  _ enable_globlemetalic
            #pragma shader_feature  _ RENDER_Unreal
            #pragma shader_feature  _ ScreenRimLight_DitalNormal
            #pragma shader_feature  _ SSS_RENDER
            #pragma shader_feature  _ HAIR_RENDER
            #pragma shader_feature  _ F0_UN
          
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "./Include/FixProjection1.hlsl"
            #include "./Include/PBR_Function.hlsl"
            

            CBUFFER_START(UnityPerMaterial)
           
            TEXTURE2D(_SrmaTex);SAMPLER(sampler_SrmaTex);float4 _SrmaTex_ST;
            TEXTURE2D(_SSSLUT);SAMPLER(sampler_SSSLUT);float4 _SSSLUT_ST;
            TEXTURE2D(_Normal);SAMPLER(sampler_Normal);float4 _Normal_ST;
            TEXTURECUBE(_refmap);SAMPLER(sampler_refmap);
            float4 _BaseColor;
            float4 _ShadowColor;
            float4 _ShadowColor1;
            float4 _CharacterRimLightColor,_CharacterRimLightDirection;
            float4 _aoColor;
            float _Roughness_value;
            float4 _F0;
            float4 _tuneNormalBlur;
            float _LUTY;
            float _Metalness;
            float _Smoothness;
            float _AOScale;
            float _Mip_Value;
            float _Mip;
            float anisotropic;
            float _SSSLut;
            float _aoColor_value;
            float lobeWeight;
          
            CBUFFER_END

            struct MeshData
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float4 tangent :TANGENT;
                float3 normal : NORMAL;
                float2 staticLightmapUV : TEXCOORD2;
                float2 dynamicLightmapUV : TEXCOORD3;
                float4 color : COLOR;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct V2FData
            {
                float4 pos : SV_POSITION; // 必须命名为pos ，因为 TRANSFER_VERTEX_TO_FRAGMENT 是这么命名的，为了正确地获取到Shadow
                float2 uv : TEXCOORD0;
                float3 tangent : TEXCOORD1;
                float3 bitangent : TEXCOORD2;
                float3 normal : TEXCOORD3;
                float3 posWS : TEXCOORD4;
                float3 posOS : TEXCOORD8;
                float4 shadowCoord : TEXCOORD5;
                half4  fogFactorAndVertexLight : TEXCOORD6; // x: fogFactor, yzw: vertex light
                UNITY_VERTEX_INPUT_INSTANCE_ID
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 7);
            };
            
            half4 UniversalFragmentPBR0(InputData inputData, SurfaceData surfaceData,SurfacePBR surfacepbr,TBNpbr tbnpbr)
            {
            #ifdef _SPECULARHIGHLIGHTS_OFF
                bool specularHighlightsOff = true;
            #else
                bool specularHighlightsOff = false;
            #endif
            
                BRDFData brdfData;
                BRDFData brdfData1;
            
                // NOTE: can modify alpha
                InitializeBRDFDataPBR(surfaceData.albedo, surfaceData.metallic, surfaceData.occlusion,surfaceData.smoothness,  brdfData);
                InitializeBRDFData(surfaceData, brdfData1);
                #if defined(DEBUG_DISPLAY)
                half4 debugColor;

                if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
                {
                    return debugColor;
                }
                #endif
                 BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
                 half4 shadowMask = CalculateShadowMask(inputData);
                 AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
                 uint meshRenderingLayers = GetMeshRenderingLightLayer();
                 Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
             
                LightingData lightingData = CreateLightingData(inputData, surfaceData);
                #if defined(_SCREEN_SPACE_OCCLUSION)
                    AmbientOcclusionFactor aoFactor = GetScreenSpaceAmbientOcclusion(inputData.normalizedScreenSpaceUV);
                    mainLight.color *= aoFactor.directAmbientOcclusion;
                    surfaceData.occlusion = min(surfaceData.occlusion, aoFactor.indirectAmbientOcclusion);
                #endif
                    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);
                  
                
               lightingData.mainLightColor = PBR_Light(brdfData,mainLight,inputData.normalWS,inputData.positionWS,
                                                       inputData.viewDirectionWS,surfacepbr,tbnpbr,surfaceData,inputData);
              
    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_CLUSTERED_LIGHTING
    for (uint lightIndex = 0; lightIndex < min(_AdditionalLightsDirectionalCount, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
        light.shadowAttenuation = saturate((light.shadowAttenuation - 0.375)/0.25);

        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
        {
            /*lightingData.additionalLightsColor += PBR_Light(brdfData,mainLight,inputData.normalWS,inputData.positionWS,
                                  inputData.viewDirectionWS,,surfacepbr);*/
              lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData1, brdfDataClearCoat, light,
                                                                                    inputData.normalWS, inputData.viewDirectionWS,
                                                                                    surfaceData.clearCoatMask, specularHighlightsOff);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);

        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
        {
            lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData1, brdfDataClearCoat, light,
                                                                                    inputData.normalWS, inputData.viewDirectionWS,
                                                                                    surfaceData.clearCoatMask, specularHighlightsOff);
        }
    LIGHT_LOOP_END
    #endif
            
            #ifdef _ADDITIONAL_LIGHTS_VERTEX
                color += inputData.vertexLighting * brdfData.diffuse;
            #endif
                //float3 hh=SubtractDirectMainLightFromLightmap(mainLight,inputData.normalWS,inputData.bakedGI);
                
                return CalculateFinalColor(lightingData,surfaceData.alpha);
                //return   lightingData.mainLightColor.xyzz ;
            }

            #define PI 3.141592654
          
            //直接光函数
            V2FData vert(MeshData v)
            {
                VertexPositionInputs positionInputs = GetVertexPositionInputs(v.vertex.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);
                float3 posWS = positionInputs.positionWS;
                half3 vertexLight = VertexLighting(posWS, normalInput.normalWS);
                half  fogFactor = ComputeFogFactor(positionInputs.positionCS.z);
                V2FData o;
                o.uv = v.uv;
                o.pos = positionInputs.positionCS;
                o.normal =TransformObjectToWorldNormal(v.normal);
                o.posWS = posWS;
                o.posOS = v.vertex.xyz;
                o.tangent = TransformObjectToWorldDir(v.tangent);
                //Unity引擎的问题，必须这么写 乘以 v.tangent.w
                o.bitangent = cross(o.normal, o.tangent) * v.tangent.w;
                o.shadowCoord = TransformWorldToShadowCoord(o.posWS);
                OUTPUT_LIGHTMAP_UV(i.lightmapUV, unity_LightmapST, o.lightmapUV);
                OUTPUT_SH(o.normal.xyz, o.vertexSH);
                o.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
                return o;
            }
            
            //    diffTerm=albedo * lightIntensity
            //    clamping（钳制）处理，以确保其在 [0, 1] 的范围内  clampNdotL
            //    权重 w 来计算包裹后的漫反射光照，确保计算过程中的能量守恒，并且根据材质的不同特性（如粗糙度、透明度等）来调整漫反射的强度。
            //    W应该是transmittance  
         
            //VFace 是背面的关键字
            //用法：bool backFace:VFace
            float4 frag(V2FData input,float backFace:VFace) : SV_Target
            {
                float2 uv = input.uv;
                float4 SRMA = SAMPLE_TEXTURE2D(_SrmaTex,sampler_SrmaTex,uv);
                half4 baseColor = SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                
                //float3 normalmap=SAMPLE_TEXTURE2D(_Normal,sampler_Normal,uv);
                float  metalic=SRMA.z;
                float  ao=SRMA.a;
                float  roughness=SRMA.y;
                float  specular=SRMA.x;
                float3 T = normalize(input.tangent);
                float3 N = normalize(input.normal);
                float3 B = normalize(input.bitangent);
                float3 L =  normalize(_MainLightPosition.xyz);
                float3 V = normalize(GetWorldSpaceViewDir(input.posWS));
                float3 H = normalize(V+L);
                float3 VH= dot(V,H);
                float3x3 TBN = float3x3(T,B,N);
               
                
                float3 normal=UnpackNormal(SAMPLE_TEXTURE2D(_Normal,sampler_Normal,uv));
                float  tangentFactor  = dot(T,normal);
                float  BtangentFactor = dot(B,normal);
                float  roughnessInTangent  = roughness * (1.0 - abs(tangentFactor));
                float  roughnessInBTangent = roughness * (1.0 - abs(BtangentFactor));
                       normal=normalize(mul(normal,TBN));
                float  TdotH=dot(T,H);
                float  BdotH=dot(B,H);
                float  NdotH=dot(N,H);
                float  TdotV=dot(T,V);
                float  BdotV=dot(B,V);
                float  NdotV=dot(N,V);
                float  TdotL=dot(T,L);
                float  BdotL=dot(B,L);
                float  NdotL=dot(N,L);
                      
               // 设置 SurfaceData
                SurfaceData surfaceData;
                surfaceData.albedo = baseColor.rgb;
                surfaceData.alpha =  baseColor.a;
                surfaceData.metallic   = _Metalness * SRMA.z;
                surfaceData.smoothness =SRMA.y;
                surfaceData.normalTS =  normal;
                surfaceData.specular = SRMA.y;

                surfaceData.occlusion =  SRMA.a;
                surfaceData.emission = 0.0;

                surfaceData.clearCoatMask = 0.0h;
                surfaceData.clearCoatSmoothness = 0.0h;

                //设置 InputData
                InputData inputData;
                inputData = (InputData)0;
                inputData.positionWS = input.posWS;
                inputData.normalWS = normal;
                inputData.viewDirectionWS = V;
                inputData.shadowCoord = input.shadowCoord;
                inputData.fogCoord = input.fogFactorAndVertexLight.x;
                inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
                //inputData.bakedGI = SAMPLE_GI(input.lightmapUV, input.vertexSH, normal) ;
                inputData.bakedGI = 0;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.pos);
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.lightmapUV);
                //


                SurfacePBR surfacepbr;
                surfacepbr.sampler_SSSLUT=sampler_SSSLUT;
                surfacepbr._SSSLUT=_SSSLUT;
                surfacepbr._refmap=_refmap;
                surfacepbr.sampler_refmap=sampler_refmap;
                surfacepbr.shadowcolor=_ShadowColor.rgb;
                surfacepbr.basecolor=_BaseColor.rgb;
                surfacepbr._LUTY=_LUTY;
                surfacepbr.aoColor=_aoColor.xyz;
                surfacepbr.aoColor_value=_aoColor_value;
                surfacepbr.Specular=specular;
                surfacepbr.F0=_F0.xyz;
                surfacepbr._Mip=_Mip;
                surfacepbr.albedo=baseColor.xyz;
                surfacepbr.metallic=metalic;
                surfacepbr.lobeWeight=lobeWeight;
                surfacepbr._Roughness_value=_Roughness_value;
                surfacepbr._Mip_Value=_Mip_Value;
                surfacepbr._NormalWorld=normal;
                surfacepbr._Normal_modle=N;
                surfacepbr._tuneNormalBlur=_tuneNormalBlur;
                surfacepbr._CharacterRimLightColor=_CharacterRimLightColor;
                surfacepbr._CharacterRimLightDirection=_CharacterRimLightDirection;
                surfacepbr.anisotropic=anisotropic;
                surfacepbr.posOS=input.posOS;

                TBNpbr tbnpbr;
                tbnpbr.TdotH=TdotH;
                tbnpbr.BdotH=BdotH;
                tbnpbr.NdotH=NdotH;
                tbnpbr.TdotV=TdotV;
                tbnpbr.BdotV=BdotV;
                tbnpbr.NdotV=NdotV;
                tbnpbr.TdotL=TdotL;
                tbnpbr.BdotL=BdotL;
                tbnpbr.NdotL=NdotL;
                tbnpbr.roughnessInTangent =roughnessInTangent;
                tbnpbr.roughnessInBTangent=roughnessInBTangent;
               
                FragmentBuffer output;
                half3 diffuseLighting;
                half3 specularLighting;
                //SubsurfaceScatterLit(inputData, surfaceData, diffuseLighting, specularLighting);
                output.specluarBuffer = half4(specularLighting, surfaceData.alpha);
                output.diffuseBuffer = half4(diffuseLighting, surfaceData.alpha);
                output.diffuseBuffer.rgb += surfaceData.emission;
                #if defined(_SUBSURFACESCATTERING)
                output.sssBuffer = half4(surface.albedo, subsurfaceData.subsurfaceMask);
                #else
                output.sssBuffer = half4(surfaceData.albedo, 0);
                #endif
               
                float4 Finalcolor=UniversalFragmentPBR0(inputData,surfaceData,surfacepbr,tbnpbr);
                
                
                float3 test = dot(N,V);
                #if Test_On
                return SRMA.r.xxxx;
                #else 
                return Finalcolor;
                #endif
               
            }
             ENDHLSL

        }
       
           
            //  UsePass "Universal Render Pipeline/Lit/ShadowCaster"
       
    }
        FallBack "Packages/com.unity.render-pipelines.universal/FallbackError"
}


// p2 -> p1 -> frame