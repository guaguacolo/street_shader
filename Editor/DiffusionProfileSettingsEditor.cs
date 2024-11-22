using UnityEngine;
using UnityEditor;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace UnityEditor.Rendering.Universal
{
    
    [CustomEditor(typeof(Material))]
    partial class DiffusionProfileSettingsEditor : BaseEditor<DiffusionProfileSettings>
    {
        sealed class Profile
        {
            internal SerializedProperty self;
            internal Material           objReference;
            internal SerializedProperty scatteringDistance;
            internal SerializedProperty transmissionTint;
            internal SerializedProperty texturingMode;
            internal SerializedProperty transmissionMode;
            internal SerializedProperty thicknessRemap;
            internal SerializedProperty worldScale;
            internal SerializedProperty ior;

            // Render preview
            internal RenderTexture profileRT;
            internal RenderTexture transmittanceRT;

            internal Profile()
            {
                profileRT       = new RenderTexture(256, 256, 0, RenderTextureFormat.DefaultHDR);
                transmittanceRT = new RenderTexture(16, 256, 0, RenderTextureFormat.DefaultHDR);
            }

            internal void Release()
            {
                CoreUtils.Destroy(profileRT);
                CoreUtils.Destroy(transmittanceRT);
            }
        }

        Profile m_Profile;
        Material m_ProfileMaterial;
        Material m_TransmittanceMaterial;

        protected  void OnEnable()
        {
            if (m_Profile == null)
            {
                m_Profile = new Profile();
            }

            // These shaders don't need to be reference by RenderPipelineResource as they are not use at runtime
            m_ProfileMaterial       = CoreUtils.CreateEngineMaterial("Hidden/SSS/DrawDiffusionProfile");
            m_TransmittanceMaterial = CoreUtils.CreateEngineMaterial("Hidden/SSS/DrawTransmittanceGraph");

            var serializedProfile = serializedObject.FindProperty("profile");
            var scatteringDistance = serializedProfile.FindPropertyRelative("scatteringDistance");
            var transmissionTint = serializedProfile.FindPropertyRelative("transmissionTint");
            var texturingMode = serializedProfile.FindPropertyRelative("texturingMode");
            var transmissionMode = serializedProfile.FindPropertyRelative("transmissionMode");
            var thicknessRemap = serializedProfile.FindPropertyRelative("thicknessRemap");
            var worldScale = serializedProfile.FindPropertyRelative("worldScale");
            var ior = serializedProfile.FindPropertyRelative("ior");

            Undo.undoRedoPerformed += UpdateProfile;
        }

        void OnDisable()
        {
            CoreUtils.Destroy(m_ProfileMaterial);
            CoreUtils.Destroy(m_TransmittanceMaterial);

            m_Profile.Release();

            m_Profile = null;

            Undo.undoRedoPerformed -= UpdateProfile;
        }

        public override void OnInspectorGUI()
        {
            CheckStyles();

            serializedObject.Update();

            EditorGUILayout.Space();

            var profile = m_Profile;

            EditorGUI.indentLevel++;

            using (var scope = new EditorGUI.ChangeCheckScope())
            {
                EditorGUILayout.PropertyField(profile.scatteringDistance, new GUIContent("Scattering Distance"));
                EditorGUILayout.PropertyField(profile.transmissionTint, new GUIContent("Transmission Tint"));
                EditorGUILayout.Slider(profile.ior, 1.0f, 2.0f, new GUIContent("IOR (Index of Refraction)"));
                EditorGUILayout.PropertyField(profile.worldScale, new GUIContent("World Scale"));
                EditorGUILayout.Space();
                EditorGUILayout.LabelField(s_Styles.SubsurfaceScatteringLabel, EditorStyles.boldLabel);

                profile.texturingMode.intValue = EditorGUILayout.Popup(s_Styles.texturingMode, profile.texturingMode.intValue, s_Styles.texturingModeOptions);

                EditorGUILayout.Space();
                EditorGUILayout.LabelField(s_Styles.TransmissionLabel, EditorStyles.boldLabel);

                profile.transmissionMode.intValue = EditorGUILayout.Popup(s_Styles.profileTransmissionMode, profile.transmissionMode.intValue, s_Styles.transmissionModeOptions);

                EditorGUILayout.PropertyField(profile.transmissionTint, s_Styles.profileTransmissionTint);
                EditorGUILayout.PropertyField(profile.thicknessRemap, s_Styles.profileMinMaxThickness);
                var thicknessRemap = profile.thicknessRemap.vector2Value;
                EditorGUILayout.MinMaxSlider(s_Styles.profileThicknessRemap, ref thicknessRemap.x, ref thicknessRemap.y, 0f, 50f);
                profile.thicknessRemap.vector2Value = thicknessRemap;

                EditorGUILayout.Space();
                EditorGUILayout.LabelField(s_Styles.profilePreview0, s_Styles.centeredMiniBoldLabel);
                EditorGUILayout.LabelField(s_Styles.profilePreview1, EditorStyles.centeredGreyMiniLabel);
                EditorGUILayout.LabelField(s_Styles.profilePreview2, EditorStyles.centeredGreyMiniLabel);
                EditorGUILayout.LabelField(s_Styles.profilePreview3, EditorStyles.centeredGreyMiniLabel);
                EditorGUILayout.Space();

                serializedObject.ApplyModifiedProperties();
                m_Target.UpdateCache(); 
                if (profile.objReference != null)
                {
                    EditorUtility.SetDirty(profile.objReference);
                }
                // NOTE: We cannot change only upon scope changed since there is no callback when Reset is triggered for Editor and the scope is not changed when Reset is called.
                // The following operations are not super cheap, but are not overly expensive, so we instead trigger the change every time inspector is drawn.
               /* if (scope.changed)
                {
                    // 手动标记对象为脏，这样 Unity 会重新计算或更新该对象
                   

                    // 如果有需要的更新逻辑，可以在这里手动调用
                    // 例如，更新缓存或重新计算渲染设置
                    // 假设你有自定义的更新缓存逻辑
                }*/
            }

            RenderPreview(profile);

            EditorGUILayout.Space();
            EditorGUI.indentLevel--;

            serializedObject.ApplyModifiedProperties();
        }

        void RenderPreview(Profile profile)
        {
            var obj = profile.objReference;

            m_ProfileMaterial.SetFloat("_MaxRadius", obj.GetFloat("_MaxRadius"));
            m_ProfileMaterial.SetVector("_ShapeParam", obj.GetVector("_ShapeParam"));


            // Draw the profile.
            //EditorGUI.DrawPreviewTexture(GUILayoutUtility.GetRect(256f, 256f), profile.profileRT, m_ProfileMaterial, ScaleMode.ScaleToFit, 1f);
            Rect profileRect = GUILayoutUtility.GetRect(256f, 256f);
            EditorGUI.DrawPreviewTexture(profileRect, profile.profileRT, m_ProfileMaterial, ScaleMode.ScaleToFit, 1f);
            EditorGUILayout.Space();
            EditorGUILayout.LabelField(s_Styles.transmittancePreview0, s_Styles.centeredMiniBoldLabel);
            EditorGUILayout.LabelField(s_Styles.transmittancePreview1, EditorStyles.centeredGreyMiniLabel);
            EditorGUILayout.LabelField(s_Styles.transmittancePreview2, EditorStyles.centeredGreyMiniLabel);
            EditorGUILayout.Space();

            m_TransmittanceMaterial.SetVector("_ShapeParam", obj.GetVector("_ShapeParam"));
            m_TransmittanceMaterial.SetColor("_TransmissionTint", obj.GetColor("_TransmissionTint"));


            // Draw the transmittance graph.
            //EditorGUI.DrawPreviewTexture(GUILayoutUtility.GetRect(16f, 16f), profile.transmittanceRT, m_TransmittanceMaterial, ScaleMode.ScaleToFit, 16f);
            Rect transmittanceRect = GUILayoutUtility.GetRect(16f, 16f);
            EditorGUI.DrawPreviewTexture(transmittanceRect, profile.transmittanceRT, m_TransmittanceMaterial, ScaleMode.ScaleToFit, 16f);
        }

        void UpdateProfile()
        {
            if (m_Profile.objReference != null)
            {
                EditorUtility.SetDirty(m_Profile.objReference);
            }
            m_Target.UpdateCache();
        }
    }
}
