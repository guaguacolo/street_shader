Shader "Hidden/HighShadow"
{
    Properties
    {
    }

   SubShader
    {
        Tags
        {
             "RenderPipeline" = "UniversalPipeline" /*"RenderType"="TranspaHirent"*/"RenderType"="HightShadowCaster"  "Queue"="Geometry" 
         
        }
         LOD 200

        Pass
        {
            Name "HightShadowCaster"
            Tags { "LightMode" = "HightShadowCaster" }
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
            
                half3 _LightDirection;  // _WorldSpaceLightPos0
                half3 _LightPosition;
            CBUFFER_START(UnityPerMaterial)
              
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
    }
    Fallback Off
}
