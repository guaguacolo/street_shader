Shader "Hidden/DianDian/SSSSBlit"
{
    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Debug/Debugging3D.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/GlobalIllumination.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/AmbientOcclusion.hlsl"
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DBuffer.hlsl"
    /*#include "Packages/com.centurygame.render-pipelines.common/ShaderLibrary/Common.hlsl"
	#include "Packages/com.centurygame.render-pipelines.common/ShaderLibrary/UnityInstancing.hlsl"
    #include "Packages/com.centurygame.render-pipelines.common/ShaderLibrary/Color.hlsl"
	#include "Packages/com.centurygame.render-pipelines.common/ShaderLibrary/Packing.hlsl"
	#include "Packages/com.centurygame.renderpipeline/Shaders/Library/DDInput.hlsl"
	#include "Packages/com.centurygame.render-pipelines.common/ShaderLibrary/EntityLighting.hlsl"*/

	#define MaxSamplerSteps 25

	struct Attributes
	{
		uint vertexID     : SV_VertexID;
		UNITY_VERTEX_INPUT_INSTANCE_ID
	};

	struct Varyings
	{
		float4 positionCS : SV_POSITION;
		float2 uv         : TEXCOORD0;
	};

	TEXTURE2D(_SourceTex);
	SAMPLER(sampler_SourceTex);	
	TEXTURE2D(_DiffuseOnlyDepthTexture);
	SAMPLER(sampler_DiffuseOnlyDepthTexture);
	TEXTURE2D(_SSSProfileIndexTexture);
	SAMPLER(sampler_SSSProfileIndexTexture);
	

	float4 _SSSSGlobalKernelsBuffer[500];
	float _SSSSScaleBuffer[20];

	float4 _SourceTex_TexelSize;
	float4 _DiffuseOnlyDepthTexture_TexelSize;
	float4 _BackgroundColor;
	float _SSSScaleMulti;
	float _DistanceToProjectionWindow;
	int _SamplerSteps;

	float4 SSS(float4 SceneColor, float2 UV, float2 SSSVec, float SSSIntencity, int startIndex) 
	{
		float SceneDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_DiffuseOnlyDepthTexture, sampler_DiffuseOnlyDepthTexture, UV), _ZBufferParams);
		float2 UVOffset = SSSVec * _DistanceToProjectionWindow / SceneDepth;
		float4 BlurSceneColor = SceneColor;
		BlurSceneColor.rgb *= _SSSSGlobalKernelsBuffer[startIndex].rgb;

		[loop]
		for (int i = 1; i < _SamplerSteps; i++) {
			float2 SSSUV = UV + _SSSSGlobalKernelsBuffer[i + startIndex].a * UVOffset;
			float4 SSSSceneColor = SAMPLE_TEXTURE2D(_SourceTex, sampler_SourceTex, SSSUV);
			if(SSSSceneColor.g == 0)
				SSSSceneColor = SceneColor;
#ifdef _SSS_FOLLOW_SURFACE
			float SSSDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_DiffuseOnlyDepthTexture, sampler_DiffuseOnlyDepthTexture, SSSUV), _ZBufferParams).r;
			float SSSScale = saturate(_DistanceToProjectionWindow * 300 * SSSIntencity * abs(SceneDepth - SSSDepth));
			SSSSceneColor.rgb = lerp(SSSSceneColor.rgb, SceneColor.rgb, SSSScale);
#endif
			BlurSceneColor.rgb += _SSSSGlobalKernelsBuffer[i + startIndex].rgb * SSSSceneColor.rgb;
		}
		return BlurSceneColor;
	}

	Varyings vert(Attributes input)
	{
		Varyings output;
		UNITY_SETUP_INSTANCE_ID(input);
		output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
		output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
		return output;
	}

	
	float4 fragXAxis(Varyings i) : SV_Target 
	{
		float2 surfaceData = SAMPLE_TEXTURE2D(_SSSProfileIndexTexture, sampler_SSSProfileIndexTexture, i.uv).xy;
		int index = round(surfaceData.r * 255);
		float4 SceneColor = SAMPLE_TEXTURE2D(_SourceTex, sampler_SourceTex, i.uv);
		float SSSIntencity = (_SSSSScaleBuffer[index] * _DiffuseOnlyDepthTexture_TexelSize.x * _SSSScaleMulti * surfaceData.g);
		float3 XAxisSSS = SSS(SceneColor, i.uv, float2(SSSIntencity, 0), SSSIntencity, index * MaxSamplerSteps).rgb;
		return float4(XAxisSSS, SceneColor.a);
	}

	
	float4 fragYAxis(Varyings i) : SV_Target
	{
		float2 surfaceData = SAMPLE_TEXTURE2D(_SSSProfileIndexTexture, sampler_SSSProfileIndexTexture, i.uv).xy;
		int index = round(surfaceData.r * 255);
		float4 SceneColor = SAMPLE_TEXTURE2D(_SourceTex, sampler_SourceTex, i.uv);
		float SSSIntencity = (_SSSSScaleBuffer[index] * _DiffuseOnlyDepthTexture_TexelSize.y * _SSSScaleMulti * surfaceData.g);
		float3 YAxisSSS = SSS(SceneColor, i.uv, float2(0, SSSIntencity), SSSIntencity, index * MaxSamplerSteps).rgb;
		return float4(YAxisSSS, SceneColor.a);
	}

	float4 diffuseRepair(Varyings i) : SV_Target
	{
		float4 SceneColor0 = SAMPLE_TEXTURE2D(_SourceTex, sampler_SourceTex, i.uv + _SourceTex_TexelSize.xy * float2(1, 1));
		float4 SceneColor1 = SAMPLE_TEXTURE2D(_SourceTex, sampler_SourceTex, i.uv + _SourceTex_TexelSize.xy * float2(-1, 1));
		float4 SceneColor2 = SAMPLE_TEXTURE2D(_SourceTex, sampler_SourceTex, i.uv + _SourceTex_TexelSize.xy * float2(-1, -1));
		float4 SceneColor3 = SAMPLE_TEXTURE2D(_SourceTex, sampler_SourceTex, i.uv + _SourceTex_TexelSize.xy * float2(1, -1));

		if(SceneColor0.g != 0)
			return SceneColor0;
		if(SceneColor1.g != 0)
			return SceneColor1;
		if(SceneColor2.g != 0)
			return SceneColor2;
		if(SceneColor3.g != 0)
			return SceneColor3;
		return 0;
	}
	ENDHLSL

	SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline" = "DDRenderPipeline" }

		Pass
		{
			Name "XAxisSSS"
			ZTest Always 
			ZWrite Off 
			Cull Off
			Blend Off 

			Stencil
            {
                Ref 1                       
                Comp equal                       
            }

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment fragXAxis

			#pragma multi_compile _ _SSS_FOLLOW_SURFACE
			#pragma multi_compile _ _USE_HALF_RESOLUTION
			ENDHLSL
		}

		Pass
		{
			Name "YAxisSSS"
			ZTest Always 
			ZWrite Off 
			Cull Off
			Blend Off 

			Stencil
            {
                Ref 1                       
                Comp equal                       
            }

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment fragYAxis

			#pragma multi_compile _ _SSS_FOLLOW_SURFACE
			#pragma multi_compile _ _USE_HALF_RESOLUTION
			ENDHLSL
		}

		Pass
		{
			Name "SSSDiffuseRepair"
			ZTest Always 
			ZWrite Off 
			Cull Off
			Blend Off 

			Stencil
            {
                Ref 1                      
                Comp notequal                       
            }

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment diffuseRepair
			ENDHLSL
		}
	}
}