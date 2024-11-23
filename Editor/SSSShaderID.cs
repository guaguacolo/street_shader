using UnityEngine;

public static class SSSShaderID
{
    //Some Examples
    public static int _MaxRadius = Shader.PropertyToID("_MaxRadius");
    //Use id value instead of string could have less cost.
    //Set your custom variables here
    public static int _ShapeParam = Shader.PropertyToID("_ShapeParam");
    public static int _TransmissionTint = Shader.PropertyToID("_TransmissionTint");
    public static int _ThicknessRemap = Shader.PropertyToID("_ThicknessRemap");
    public static int _MirrorPos = Shader.PropertyToID("_MirrorPos");
    public static int _BlurOffset = Shader.PropertyToID("_BlurOffset");
}