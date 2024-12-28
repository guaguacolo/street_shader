Shader "Custom/URP_ShadowReceiverShader"
{
    Properties
    {
         _MAP("MAP",2D)="white"{}
        _Color ("Base Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {
            Name "FORWARD"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // 声明阴影贴图纹理
            TEXTURE2D(HightShadowTex);
            TEXTURE2D(_MAP);
            SAMPLER(sampler_HightShadowTex);
            SAMPLER(sampler__MAP);

            // 属性
            float4 _Color;

            // 顶点着色器输入输出结构体
            struct Attributes
            {
                float4 position : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            // 顶点着色器
            Varyings vert(Attributes v)
            {
                Varyings o;
                o.pos = TransformObjectToHClip(v.position);
                o.uv = v.uv; // 传递UV坐标
                return o;
            }

            // 片段着色器
            half4 frag(Varyings i) : SV_Target
            {
                // 使用阴影贴图获取阴影值
                half shadow = SAMPLE_TEXTURE2D(HightShadowTex,sampler_HightShadowTex, i.uv).r;
                half _MAP1 = SAMPLE_TEXTURE2D(_MAP,sampler__MAP, i.uv);

                // 基于阴影值计算颜色
                half3 color = _Color.rgb * shadow; // 使用阴影值调整颜色
                return half4(color, 1.0f);
            }

            ENDHLSL
        }
    }

    FallBack "Universal Forward"
}
