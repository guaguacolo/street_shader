/*
    ��shader�ĺ���˼�룺��ѡ�����ĵ㣬����ÿ�����ص㵽������ĵ�ľ���distance���������뾶maxRadius���Ƚϣ�
    ʵ��Բ�����Ⱦ���distance��maxRadius+width���Ƚϣ�����֮ǰ�����
    ���������ͼ���ڵ���������ϵͳһ
*/
Shader "Hidden/Scanner"
{
    Properties
    {
        _MainTex("MainTex",2D)= "white"{}
        _GradientTex("GradientTex",2D)= "white"{}
        [HDR]_LineColor("LineColor",color)=(0,0,0,0)
        _CenterPos("CenterPos",vector)=(0,0,0,0)
        _Width("Width",float)=1
        _Bias("Bias",float)=0
        _GridWidth("GridWidth",float) = 0.01
        _GridScale("GridScale",float)=1
        _CircleMinAlpha("CircleMinAlpha",range(0,1)) = 0.5
        _BlendIntensity("BlendIntensity",range(0,1)) = 0.9
        _ExpansionSpeed("ExpansionSpeed",float) = 1
        _MaxRadius("MaxRadius",float) = 10
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
        }

        Blend One Zero

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
        float4 _MainTex_ST;
        float4 _MainTex_TexelSize;
        float4 _LineColor;
        float4 _CenterPos;
        float _ExpansionSpeed;
        float _MaxRadius;
        float _Width;
        float _Bias;
        float _GridWidth;
        float _GridScale;
        half _CircleMinAlpha;
        half _BlendIntensity;
        CBUFFER_END

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_GradientTex);
        //SAMPLER(sampler_linear_repeat);
        SAMPLER(sampler_linear_clamp);
        TEXTURE2D(_CameraDepthTexture);
        SAMPLER(sampler_CameraDepthTexture);

        struct appdata
        {
            float4 positionOS:POSITION;
            float2 texcoord:TEXCOORD;
        };

        struct v2f
        {
            float4 positionCS:SV_POSITION;
            float2 texcoord:TEXCOORD;
        };
        ENDHLSL

        pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ LINEONCIRCLE_ON
            #pragma multi_compile _ LINEINSIDE_ON2
            #pragma multi_compile _ LINEHOR_ON
            #pragma multi_compile _ LINEVER_ON
            #pragma multi_compile _ ISPOINT_ON
            #pragma multi_compile _ CHANGE_SATURATION_ON

            v2f vert(appdata i)
            {
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);
                o.texcoord = i.texcoord;
                return o;
            }

            float Gray(real3 color)
            {
                return 0.2125 * color.r + 0.7154 * color.g + 0.0821 * color.b;
            }

            float Remap(float x, float s1, float s2, float t1 = 0, float t2 = 1)
            {
                return (x - t1) / (t2 - t1) * (s2 - s1) + s1;
            }

            real4 frag(v2f i):SV_TARGET
            {
                float radius = (_Time.y * _ExpansionSpeed) % _MaxRadius;
                real depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, i.texcoord);
                float3 worldPos = ComputeWorldSpacePosition(i.texcoord, depth, UNITY_MATRIX_I_VP);
                float4 sceneColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.texcoord);
                float lengthToCenter = distance(worldPos.xz, _CenterPos.xz);
                float nearDistance = radius - _Width / 2 - _Bias;
                float farDistance = radius + _Width / 2 - _Bias;
                float scannerNearLine = smoothstep(nearDistance, farDistance, lengthToCenter);
                float scannerFarLine = step(farDistance, lengthToCenter);
                real4 color = 0;
                float circleMask = scannerNearLine - scannerFarLine;

                float4 circleColor = SAMPLE_TEXTURE2D(_GradientTex, sampler_linear_clamp, float2(circleMask,0));
                circleMask = 1 - abs(1 - circleMask * 2);
                circleMask = saturate(circleMask + _CircleMinAlpha);
                circleMask = smoothstep(_CircleMinAlpha, 1, circleMask);
                sceneColor *= saturate(1 - circleMask * _BlendIntensity);
                float sceneMask = step(lengthToCenter, radius - _Bias);

                #if CHANGE_SATURATION_ON
                    sceneColor = sceneColor * sceneMask+ Gray(sceneColor.xyz)*(1-sceneMask);
                #endif

                color = sceneColor + circleColor * circleMask;

                float2 xzGrid = frac(worldPos.xz * _GridScale);

                float gridLine = 0;

                #if LINEHOR_ON
                gridLine = step(xzGrid.x,_GridWidth);
                #endif
                #if LINEVER_ON
                gridLine += step(xzGrid.y,_GridWidth);;
                #if ISPOINT_ON
                gridLine = step(1.5,gridLine);
                #else
                gridLine = saturate(gridLine);
                #endif
                #endif

                return lerp(color, color*(1-_LineColor.a) + gridLine * sceneMask * _LineColor * (sceneMask - circleMask)* _LineColor.a, gridLine * sceneMask * (sceneMask - circleMask));
            }
            ENDHLSL

        }

    }
}