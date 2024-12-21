Shader "Hidden/HDRP/CombineLighting"
{
    Properties
    {
        [HideInInspector] _StencilMask("_StencilMask", Int) = 7
        [HideInInspector] _StencilRef("_StencilRef", Int) = 1
    }

    SubShader
    {
        HLSLINCLUDE
        #pragma target 4.5
        //#pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch
        // #pragma enable_d3d11_debug_symbols

        /*#pragma vertex Vert
        #pragma fragment Frag*/

        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Library/PackageCache/com.unity.shadergraph@13.1.8/ShaderGraphLibrary/ShaderVariables.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        
        
        float _ProbeExposureScale;
                TEXTURE2D(_IrradianceSource);
        float GetCurrentExposureMultiplier()
        {
        #if SHADEROPTIONS_PRE_EXPOSITION
            // _ProbeExposureScale is a scale used to perform range compression to avoid saturation of the content of the probes. It is 1.0 if we are not rendering probes.
            return LOAD_TEXTURE2D(_ExposureTexture, int2(0, 0)).x * _ProbeExposureScale;
        #else
            return _ProbeExposureScale;
        #endif
}
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
        ENDHLSL

        Tags{ "RenderPipeline" = "UniversalForward" }
         Pass
        {
            Stencil
            {
                ReadMask [_StencilMask]
                Ref  [_StencilRef]
                Comp Equal
                Pass Keep
            }

            Cull   Off
            ZTest  Less	   // Required for XR occlusion mesh optimization
            ZWrite Off
            Blend  One One // Additive

            HLSLPROGRAM
            
            float4 Frag(Varyings input) : SV_Target0
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                return float4(1,1,1,1);
                //return LOAD_TEXTURE2D_X(_IrradianceSource, input.positionCS.xy);
            }
            ENDHLSL
        }

    }
    Fallback Off
}