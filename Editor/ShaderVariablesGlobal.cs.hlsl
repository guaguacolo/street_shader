//
// This file was automatically generated. Please don't edit by hand. Execute Editor command [ Edit / Render Pipeline / Generate Shader Includes ] instead
//

#include <HLSLSupport.cginc>
#ifndef SHADERVARIABLESGLOBAL_CS_HLSL
#define SHADERVARIABLESGLOBAL_CS_HLSL
//
// UnityEngine.Rendering.HighDefinition.ShaderVariablesGlobal:  static fields
//
#define RENDERING_LIGHT_LAYERS_MASK (255)
#define RENDERING_LIGHT_LAYERS_MASK_SHIFT (0)
#define RENDERING_DECAL_LAYERS_MASK (65280)
#define RENDERING_DECAL_LAYERS_MASK_SHIFT (8)
#define DEFAULT_RENDERING_LAYER_MASK (257)
#define MAX_ENV2DLIGHT (32)

// Generated from UnityEngine.Rendering.HighDefinition.ShaderVariablesGlobal
// PackingRules = Exact
GLOBAL_CBUFFER_START(ShaderVariablesGlobal, b0)
    float4 _ShapeParamsAndMaxScatterDists;
    float4 _TransmissionTintsAndFresnel0;
    float4 _WorldScalesAndFilterRadiiAndThicknessRemaps;
    uint4  _DiffusionProfileHashTable;
    uint  _EnableSubsurfaceScattering;
CBUFFER_END


#endif
