Shader "Hidden/HDRP/CombineLight"
{
    Properties
    {
        [HideInInspector] _StencilMask("_StencilMask", Int) = 7
        [HideInInspector] _StencilRef("_StencilRef", Int) = 1
        _IrradianceSource ("Irradiance Source", 2D) = "white" { }
    }

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" }

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
            ZTest  Less   // Required for XR occlusion mesh optimization
            ZWrite Off
            Blend  One One // Additive

            HLSLPROGRAM
            #pragma target 4.5
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // 纹理和采样器声明
            TEXTURE2D(_IrradianceSource);
            SAMPLER(sampler_IrradianceSource);

            struct Attributes
            {
                uint vertexID : SV_VertexID;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_Position;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // 顶点着色器，计算纹理坐标
            Varyings Vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                
                // 生成全屏三角形的UV坐标
                if (input.vertexID == 0)
                    output.uv = float2(0.0, 0.0); // 左下角
                else if (input.vertexID == 1)
                    output.uv = float2(1.0, 0.0); // 右下角
                else
                    output.uv = float2(0.5, 1.0); // 顶部中间

                output.positionCS = float4(input.vertexID == 0 ? -1.0 : (input.vertexID == 1 ? 1.0 : 0.0), 
                                           input.vertexID == 0 ? -1.0 : (input.vertexID == 2 ? 1.0 : 0.0), 
                                           0.0, 1.0);
                return output;
            }

            // 片段着色器
            float4 Frag(Varyings input) : SV_Target
            {
                // 使用采样器采样纹理
                return tex2D(sampler_IrradianceSource, input.uv);
            }
            ENDHLSL
        }
    }
    Fallback Off
}
