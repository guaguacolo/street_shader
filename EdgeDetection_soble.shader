Shader "Unlit/SobelFilter"
{
	Properties 
	{
	    [HideInInspector]_MainTex ("Base (RGB)", 2D) = "white" {}
		[Toggle(POSTERIZE)]_Poseterize ("Posterize", Float) = 0
		_PosterizationCount ("Count", int) = 8
		_EdgeColor ("EdgeColor", Color) = (0, 0, 0, 1)
	}
	SubShader 
	{
		Tags { "RenderType"="Opaque" }
		LOD 200
		
		Pass
		{
            Name "Sobel Filter"
            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            
            #pragma shader_feature POSTERIZE
            TEXTURE2D(_CameraDepthTexture);
            SAMPLER(sampler_CameraDepthTexture);
            
#ifndef RAW_OUTLINE
            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
#endif
            float _Delta;
            float4 _EdgeColor;
            float4 _BackgroudColor;
            int _PosterizationCount;
            half4 _MainTex_TexelSize;
            
            struct Attributes
            {
                float4 positionOS       : POSITION;
                float2 texcoord         : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv[9]        : TEXCOORD0;
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };
            float luminance(float4 color)
            {
	             return 0.2125 * color.r + 0.7154 * color.g + 0.0721 * color.b;
            }
            
            float SampleDepth(float2 uv)
            {
#if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED)
                return SAMPLE_TEXTURE2D_ARRAY(_CameraDepthTexture, sampler_CameraDepthTexture, uv, unity_StereoEyeIndex).r;
#else
                return SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_CameraDepthTexture, uv);
#endif
            }
            
            float sobel (Varyings i) 
            { //定义卷积核：
                const half Gx[9] = 
                {
                    -1, 0, 1,
                     0, 0, 0,
                    -1, 0, 1
                };
                const half Gy[9] =
                {
                    -1, 0, -1,
                    0, 0, 0, 
                    1, 0, 1
                };
                half texColor;
                half edgeX = 0;
                half edgeY = 0;
                UNITY_LOOP
                for(int j=0;j<9;j++)
                {
                    texColor = luminance(SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex, i.uv[j]));  //依次对9个像素采样，计算明度值
                    edgeX += texColor * Gx[j];
                    edgeY += texColor * Gy[j];
                }
 
                half edge = 1 - (abs(edgeX) + abs(edgeY))/2; //绝对值代替开根号求模，节省开销
                return edge;

            }
            
            Varyings vert(Attributes  input)
            {
                Varyings output = (Varyings)0;
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.vertex = vertexInput.positionCS;
            	half2 uv = input.texcoord;
 
               output.uv[0] = uv + _MainTex_TexelSize.xy * half2(-1, -1);
               output.uv[1] = uv + _MainTex_TexelSize.xy * half2(0, -1);
               output.uv[2] = uv + _MainTex_TexelSize.xy * half2(1, -1);
               output.uv[3] = uv + _MainTex_TexelSize.xy * half2(-1, 0);
               output.uv[4] = uv + _MainTex_TexelSize.xy * half2(0, 0);
               output.uv[5] = uv + _MainTex_TexelSize.xy * half2(1, 0);
               output.uv[6] = uv + _MainTex_TexelSize.xy * half2(-1, 1);
               output.uv[7] = uv + _MainTex_TexelSize.xy * half2(0, 1);
               output.uv[8] = uv + _MainTex_TexelSize.xy * half2(1, 1);
 
                return output;
            }
            
            half4 frag (Varyings input) : SV_Target 
            {
              half edge = sobel(input);
 
                float4 withEdgeColor = lerp(_EdgeColor, SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex, input.uv[4]), edge);  //4是原始像素位置
                return withEdgeColor;
            }
            
			#pragma vertex vert
			#pragma fragment frag
			
			ENDHLSL
		}
	} 
	FallBack "Diffuse"
}
