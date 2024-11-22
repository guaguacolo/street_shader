using UnityEditor.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;  // 使用 URP 命名空间
using UnityEngine;

namespace UnityEditor.Rendering.Universal
{
    using UnityObject = UnityEngine.Object;

    //
    // Sample use:
    //
    // [CustomEditor(typeof(TestComponent)]
    // class TestEditor : HDBaseEditor<TestComponent>
    // {
    //     SerializedProperty m_MyFloat;
    //
    //     protected override void OnEnable()
    //     {
    //         base.OnEnable();
    //         m_MyFloat = properties.Find(x => x.myFloat);
    //     }
    //
    //     public override void OnInspectorGUI()
    //     {
    //         EditorGUILayout.PropertyField(m_MyFloat);
    //     }
    // }
    //
       class BaseEditor<T> : Editor
       where T : UnityObject
    {
        internal PropertyFetcher<T> properties { get; private set; }

        protected T m_Target
        {
            get { return target as T; }
        }

        protected T[] m_Targets
        {
            get { return targets as T[]; }
        }

        protected UniversalRenderPipeline m_URPPipeline
        {
            get { return RenderPipelineManager.currentPipeline as UniversalRenderPipeline; }
        }

        protected virtual void OnEnable()
        {
            properties = new PropertyFetcher<T>(serializedObject);
        }
    }
}
