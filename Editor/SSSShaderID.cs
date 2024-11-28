using UnityEngine;

public static class SSSShaderID
{
    //Some Examples
    public static readonly int _MaxRadius = Shader.PropertyToID("_MaxRadius");
    //Use id value instead of string could have less cost.
    //Set your custom variables here
    public static readonly int _ShapeParam = Shader.PropertyToID("_ShapeParam");
    public static readonly int _TransmissionTint = Shader.PropertyToID("_TransmissionTint");
    public static readonly int _ThicknessRemap = Shader.PropertyToID("_ThicknessRemap");
    public static readonly int _MirrorPos = Shader.PropertyToID("_MirrorPos");
    public static readonly int _BlurOffset = Shader.PropertyToID("_BlurOffset");
    public static readonly int _StencilRef = Shader.PropertyToID("_StencilRef");
    public static readonly int _StencilCmp = Shader.PropertyToID("_StencilCmp");
    public static readonly int _StencilMask = Shader.PropertyToID("_StencilMask");
    public static readonly int _DepthTexture = Shader.PropertyToID("_DepthTexture");
    public static readonly int _IrradianceSource = Shader.PropertyToID("_IrradianceSource");
    public static readonly int _SSSBufferTexture = Shader.PropertyToID("_SSSBufferTexture");
    public static readonly int _CameraFilteringBuffer = Shader.PropertyToID("_CameraFilteringBuffer");
   
}