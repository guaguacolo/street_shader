Shader "Game/skin"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        [Hdr] _BaseColor("Base Color", Color) = (1,1,1,1)
        _ShadowColor("Shadow Color", Color) = (1,1,1,1)
        _BumpMap("Bump Map", 2D) = "bump" {}
        _BumpScale("Bump Scale", Float) = 1.0
        _MaskTex("MaskTex (RGB)", 2D) = "white" {}
        _RColor("RColor", Color) = (0,0,0,0)
        _GColor("GColor", Color) = (0,0,0,0)
        _BColor("BColor", Color) = (0,0,0,0)
        _SrmaTex("SrmaTex (RGBA)", 2D) = "white" {}
        _Metalness("Metalness", Range(0,10)) = 0.0
        _Smoothness("Smoothness", Range(0,10)) = 0.0
        [Toggle(_FresnelToggle)]_FresnelToggle("_FresnelToggle",Float)=0.0
        _AOScale("AO Scale", Range(0,1)) = 1.0
        [Hdr] _FresnelColor("Fresnel Color", Color) = (1,0.78,0,1)
        _FresnelPower("Fresnel Power", Float) = 12.0
        _SssTex("SssTex", 2D) = "white" {}
        _SssColor("Sss Color", Color) = (0,0,0,0)
        _SssWeight("Sss Weight", Float) = 0.0
        _VTColor("VT Color", Color) = (1,0.9,0,1)
        _VTScale("VT Scale", Float) = 0.0

        //�۾��߹����
        _OffsetScale1("Offset&Scale1", Vector) = (0.48, 0.5, 1, 1)
        _OffsetScale2("Offset&Scale2", Vector) = (0.51, 0.5, 1, 1)
        _Param1("Param1", Vector) = (0.026, 0.003, 1.6, 1)
        _Param2("Param2", Vector) = (0.02, 0.001, 0.5, 1)

        [HideInInspector] _StateColor("State Color", Color) = (1,0,0,1)
        [HideInInspector] _Cutoff("Cutoff", Range(0,1)) = 0.5
        [HideInInspector] _Surface("__surface", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "RenderType"="Opaque"
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

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "./Include/FixProjection.hlsl"

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

            // ��ȡ�ü��ռ��µ���Ӱ����             
            half4 GetShadowPositionHClips(appdata_t v)
            {
                float3 positionWS = TransformObjectToWorld(v.vertexOS.xyz);

#if _CASTING_PUNCTUAL_LIGHT_SHADOW
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
#else
                float3 lightDirectionWS = _LightDirection;
#endif
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                positionWS = ApplyShadowBias(positionWS, normalWS, lightDirectionWS);

//#ifdef _FIX_PROJECTION_ON
                positionWS = fixProjection(positionWS);
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
            #include "./Include/FixProjection.hlsl"

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
        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }
            //Blend SrcAlpha OneMinusSrcAlpha
            Blend[_SrcBlend][_DstBlend]
            ZWrite[_ZWrite]
            //AlphaTest Greater[_Cutoff]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fog
            //#define FOG_LINEAR

            //#define _MAIN_LIGHT_SHADOWS
            //#define _SHADOWS_SOFT
            //#define _EMISSION

            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _NORMALMAP
            #pragma multi_compile_fragment _ _EMISSION
            
//            #pragma multi_compile_fragment _ _FIX_PROJECTION_ON

            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _FresnelToggle
            #pragma shader_feature_local BOOLEAN_STATECOLORENABLE_ON
            #pragma shader_feature_local BOOLEAN_VTENABLE_ON
            #pragma shader_feature _BODYPART_BASE _BODYPART_EYESHADOW _BODYPART_EYEHILIGHT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "./Include/FixProjection.hlsl"
            #include "./Include/PBR_Function.hlsl"

            sampler2D _MaskTex;
            sampler2D _SrmaTex;
            sampler2D _SssTex;
            CBUFFER_START(UnityPerMaterial)
                half _Cutoff;
                half3 _RColor;
                half3 _GColor;
                half3 _BColor;
                half4 _BaseColor;
                half4 _ShadowColor;
                half3 _StateColor;
                half _AOScale;
                half3 _VTColor;
                half _VTScale;
                //bool _FresnelToggle;
                half4 _FresnelColor;
                half3 _SssColor;
                half _BumpScale;
                half _SssWeight;
                half _FresnelPower;
                half _Smoothness;
                half _Metalness;
                half4 _OffsetScale1;
                half4 _OffsetScale2;
                half4 _Param1;
                half4 _Param2;
            CBUFFER_END

            struct appdata_t
            {
                float4 vertexOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
                float2 lightmapUV : TEXCOORD1;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;    // xyz: tangent, w: sign
                float3 viewDirWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
                half4 fogFactorAndVertexLight : TEXCOORD6; // x: fogFactor, yzw: vertex light
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 7);
            };

            inline float3 UnityObjectToWorldNormal(in float3 norm)
            {
#ifdef UNITY_ASSUME_UNIFORM_SCALING
                return UnityObjectToWorldDir(norm);
#else
                // mul(IT_M, norm) => mul(norm, I_M) => {dot(norm, I_M.col0), dot(norm, I_M.col1), dot(norm, I_M.col2)}
                return normalize(mul(norm, (float3x3)unity_WorldToObject));
#endif
            }

            inline half Remap(half value, half2 inEdge, half2 outEdge)
            {
                return outEdge.x + (value - inEdge.x) * (outEdge.y - outEdge.x) / (inEdge.y - inEdge.x);
            }

            inline half FresnelEffect(half3 Normal, half3 ViewDir, half Power)
            {
                return pow((1.0h - saturate(dot(Normal, ViewDir))), Power);
            }

            inline half SmoothStep(half a, half b, half x)
            {
                float t = saturate((x - a) / (b - a));
                return t * t * (3.0 - (2.0 * t));
            }

            v2f vert(appdata_t v)
            {
                float3 positionWS = TransformObjectToWorld(v.vertexOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);
//#ifdef _FIX_PROJECTION_ON
                VertexNormal vn = fixProjection(positionWS, normalInput.normalWS);
                positionWS = vn.vertex;
                normalInput.normalWS = vn.normal;
//#endif
                float4 positionCS = TransformWorldToHClip(positionWS);

                half3 vertexLight = VertexLighting(positionWS, normalInput.normalWS);
                half fogFactor = ComputeFogFactor(positionCS.z);

                v2f o;
                o.positionCS = positionCS;
                o.uv = v.uv;
                o.positionWS = positionWS; // TransformObjectToWorld(v.vertexOS.xyz);
                o.normalWS = normalInput.normalWS; // UnityObjectToWorldNormal(v.normalOS);    // LitForwardPass.hlsl
                real sign = v.tangentOS.w * GetOddNegativeScale();
                o.tangentWS = float4(normalInput.tangentWS.xyz, sign);
                o.viewDirWS = GetWorldSpaceViewDir(positionWS);
                o.shadowCoord = TransformWorldToShadowCoord(o.positionWS);
                OUTPUT_LIGHTMAP_UV(i.lightmapUV, unity_LightmapST, o.lightmapUV);
                OUTPUT_SH(o.normalWS.xyz, o.vertexSH);
                o.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
                return o;
            }

            half3 GetBaseRGB(half3 texRGB, half4 srma, float2 uv, float3 normalWS, float3 viewDirWS, out half3 emission)
            {
                half3 mask = tex2D(_MaskTex, uv).rgb;
                //mask = saturate((mask - 0.375)/0.25);
                half3 rgb = lerp(0,_RColor, mask.r);
                rgb = lerp(rgb, _GColor, mask.g);
                rgb = lerp(rgb, _BColor, mask.b);
                rgb = any(mask) ? rgb*texRGB : texRGB;

#ifdef BOOLEAN_VTENABLE_ON
                half3 vtColor = (1 - saturate(dot(normalWS, viewDirWS))) * _VTColor;
                half timeScale = _VTScale * Remap(sin(_Time.y * 30), half2(-1.0h, 1.0h), half2(0.3h, 1.0h));
                rgb += vtColor * timeScale;
#endif

                // sss
                Light l = GetMainLight();
                half sssIntencity = FresnelEffect(normalWS, -l.direction, 5) * _SssWeight;
                half3 sssColor = tex2D(_SssTex, uv).rgb * _SssColor;
                emission = sssIntencity * sssColor;
                return rgb;
            }

            half4 UniversalFragmentPBR0(InputData inputData, SurfaceData surfaceData)
            {
                #if defined(_SPECULARHIGHLIGHTS_OFF)
                bool specularHighlightsOff = true;
                #else
                bool specularHighlightsOff = false;
                #endif
                BRDFData brdfData;

                // NOTE: can modify "surfaceData"...
                InitializeBRDFData(surfaceData, brdfData);

                #if defined(DEBUG_DISPLAY)
                half4 debugColor;

                if (CanDebugOverrideOutputColor(inputData, surfaceData, brdfData, debugColor))
                {
                    return debugColor;
                }
                #endif

                // Clear-coat calculation...
                BRDFData brdfDataClearCoat = CreateClearCoatBRDFData(surfaceData, brdfData);
                half4 shadowMask = CalculateShadowMask(inputData);
                AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
                uint meshRenderingLayers = GetMeshRenderingLightLayer();
                Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
                mainLight.shadowAttenuation = saturate((mainLight.shadowAttenuation - 0.375)/0.25);

                // NOTE: We don't apply AO to the GI here because it's done in the lighting calculation below...
                MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

                LightingData lightingData = CreateLightingData(inputData, surfaceData);

                lightingData.giColor = GlobalIllumination(brdfData, brdfDataClearCoat, surfaceData.clearCoatMask,
                                                        inputData.bakedGI, aoFactor.indirectAmbientOcclusion, inputData.positionWS,
                                                        inputData.normalWS, inputData.viewDirectionWS);

                if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
                {
                    lightingData.mainLightColor = LightingPhysicallyBased(brdfData, brdfDataClearCoat,
                                                                        mainLight,
                                                                        inputData.normalWS, inputData.viewDirectionWS,
                                                                        surfaceData.clearCoatMask, specularHighlightsOff);
                }

                #if defined(_ADDITIONAL_LIGHTS)
                uint pixelLightCount = GetAdditionalLightsCount();

                #if USE_CLUSTERED_LIGHTING
                for (uint lightIndex = 0; lightIndex < min(_AdditionalLightsDirectionalCount, MAX_VISIBLE_LIGHTS); lightIndex++)
                {
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
                    light.shadowAttenuation = saturate((light.shadowAttenuation - 0.375)/0.25);

                    if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
                    {
                        lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                                    inputData.normalWS, inputData.viewDirectionWS,
                                                                                    surfaceData.clearCoatMask, specularHighlightsOff);
                    }
                }
                #endif

                LIGHT_LOOP_BEGIN(pixelLightCount)
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
                    light.shadowAttenuation = saturate((light.shadowAttenuation - 0.375)/0.25);

                    if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
                    {
                        lightingData.additionalLightsColor += LightingPhysicallyBased(brdfData, brdfDataClearCoat, light,
                                                                                    inputData.normalWS, inputData.viewDirectionWS,
                                                                                    surfaceData.clearCoatMask, specularHighlightsOff);
                    }
                LIGHT_LOOP_END
                #endif

                #if defined(_ADDITIONAL_LIGHTS_VERTEX)
                lightingData.vertexLightingColor += inputData.vertexLighting * brdfData.diffuse;
                #endif

                return CalculateFinalColor(lightingData, surfaceData.alpha);
            }

            half4 frag(v2f i) : SV_Target
            {
#ifdef _BODYPART_EYEHILIGHT
                half4 baseColor = _BaseColor;
#elif defined(_BODYPART_EYESHADOW)
                half4 baseColor = _BaseColor;
#else
                half4 baseColor = SampleAlbedoAlpha(i.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                baseColor *= _BaseColor;
#endif

#ifdef _ALPHATEST_ON
                clip(baseColor.a - _Cutoff);
#endif
                float3 viewDirWS = SafeNormalize(i.viewDirWS);
                float3 normalWS = SafeNormalize(i.normalWS);

#ifdef _NORMALMAP
                half3 normalTS = SampleNormal(i.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);;
                half sgn = i.tangentWS.w;      // should be either +1 or -1
                float3 bitangent = sgn * cross(normalWS, i.tangentWS.xyz);
                normalWS = TransformTangentToWorld(normalTS, half3x3(i.tangentWS.xyz, bitangent, normalWS));
                normalWS = NormalizeNormalPerPixel(normalWS);
#else
                half3 normalTS = 0;
#endif

                half3 emission = 0;
#ifdef BOOLEAN_STATECOLORENABLE_ON
                half4 srma = tex2D(_SrmaTex, i.uv);
                baseColor.rgb = _StateColor;
#else
    #ifdef _BODYPART_BASE
                half4 srma = tex2D(_SrmaTex, i.uv);
                baseColor.rgb = GetBaseRGB(baseColor.rgb, srma, i.uv, normalWS, viewDirWS, emission);
    #elif _BODYPART_EYESHADOW
                half4 srma = half4(0, 0, 0, 1);
                half shadowA = baseColor.a;
                baseColor.a = smoothstep(0, 1, i.uv.y) * shadowA;
                //baseColor.a *= baseColor.a;
#elif _BODYPART_EYEHILIGHT
                half len1 = length((i.uv - _OffsetScale1.xy) * _OffsetScale1.zw);
                half a1 = SmoothStep(_Param1.x + _Param1.y, _Param1.x - _Param1.y, len1) * _Param1.z;
                half len2 = length((i.uv - _OffsetScale2.xy) * _OffsetScale2.zw);
                half a2 = SmoothStep(_Param2.x + _Param2.y, _Param2.x - _Param2.y, len2) * _Param2.z;
                baseColor.a *= a1 + a2;
                half4 srma = half4(0, 1, 0, 1);
#endif
#endif
                // ���� SurfaceData
                SurfaceData surfaceData;
                surfaceData.albedo = baseColor.rgb;
                surfaceData.alpha = baseColor.a;
                surfaceData.metallic = _Metalness * srma.b;
                surfaceData.smoothness = _Smoothness * srma.r;
                surfaceData.normalTS = normalTS;
                surfaceData.specular = half3(0.0, 0.0, 0.0);

                surfaceData.occlusion = _AOScale * srma.a;
                surfaceData.emission = emission;

                surfaceData.clearCoatMask = 0.0h;
                surfaceData.clearCoatSmoothness = 0.0h;

                // ���� InputData
                InputData inputData;
                inputData = (InputData)0;
                inputData.positionWS = i.positionWS;

                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = viewDirWS;

                inputData.shadowCoord = i.shadowCoord;

                inputData.fogCoord = i.fogFactorAndVertexLight.x;
                inputData.vertexLighting = i.fogFactorAndVertexLight.yzw;
                inputData.bakedGI = SAMPLE_GI(i.lightmapUV, i.vertexSH, normalWS) * _ShadowColor.rgb;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(i.lightmapUV);

                // Lighting Model, e.g.
                half4 color = UniversalFragmentPBR0(inputData, surfaceData);

                //color.rgb += lerp(0, _ShadowColor, (baseColor.rgb - color.rgb) * _ShadowColor.a);
                //��ӷ������⿪��
                // ��������
               
                #ifdef  _FresnelToggle
                
                half fresnel = FresnelEffect(normalWS, viewDirWS, _FresnelPower) * srma.g;
                color.rgb = lerp(color.rgb,_FresnelColor.rgb, fresnel * _FresnelColor.a);
                #endif
               
                // Handle Fog
                color.rgb = MixFog(color.rgb, inputData.fogCoord);
                return color;
            }

            ENDHLSL
        }
    }
    FallBack "Diffuse"
    CustomEditor "RoleShaderUI"
}
