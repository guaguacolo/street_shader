using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering.Universal;

[CustomEditor(typeof(SkinRenderFeature))]
public class SkinRenderFeatureEditor : Editor
{
    public override void OnInspectorGUI()
    {
        SkinRenderFeature skinRenderFeature = (SkinRenderFeature)target;

        // 展示 SkinRenderFeature 中的 Settings 面板
        EditorGUILayout.LabelField("Skin Render Feature Settings", EditorStyles.boldLabel);
        skinRenderFeature.settings.RenderPassEvent = (RenderPassEvent)EditorGUILayout.EnumPopup("Render Pass Event", skinRenderFeature.settings.RenderPassEvent);
        skinRenderFeature.settings.Intensity = EditorGUILayout.FloatField("Intensity", skinRenderFeature.settings.Intensity);

        // 展示 DiffusionProfileSettings
        EditorGUILayout.PropertyField(serializedObject.FindProperty("settings.m_diffusionProfile"), new GUIContent("Diffusion Profile"));

        // 应用修改
        serializedObject.ApplyModifiedProperties();
    }
}