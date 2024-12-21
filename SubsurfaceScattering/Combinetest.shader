Shader "Game/Combinetest"
{
    Properties
    {
        [HideInInspector] _StencilMask("_StencilMask", Int) = 7
        [HideInInspector] _StencilRef("_StencilRef", Int) = 1
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Stencil
            {
                ReadMask [_StencilMask]
                Ref      [_StencilRef]
                Comp     Equal
                Pass     Keep
            }

            Cull   Off
            ZTest  Less   // Required for XR occlusion mesh optimization
            ZWrite Off
            Blend  One One // Additive

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                TEXTURE2D(_IrradianceSource);
            CBUFFER_END

            struct Attributes
            {
                uint vertexID : SV_VertexID;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_Position;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
                return output;
            }

            // 定义 Frag 函数，确保它被正确调用
            float4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                return LOAD_TEXTURE2D_X(_IrradianceSource, input.positionCS.xy);
            }

            ENDHLSL
        }
    }
    Fallback Off
}
