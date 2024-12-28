using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

//[System.Serializable] //使得类或结构体可以进行序列化

public class HightShadowRenderFeature : ScriptableRendererFeature
{
    public static HightShadowRenderFeature Instance { get; private set; }
    [System.Serializable]
    public  class Settings  
    {  
        public RenderPassEvent   RenderPassEvent;  
        //[SerializeField] public  RenderPassEvent passEvent= RenderPassEvent.BeforeRenderingSkybox;
        public float Intensity = 1f;
        
    }  
    [SerializeField]
    
    public Settings settings = new Settings();
    SkinRenderPass m_ScriptablePass;
     
    public override void Create()
    {
        m_ScriptablePass = new SkinRenderPass(settings);
        m_ScriptablePass.renderPassEvent = settings.RenderPassEvent;
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        m_ScriptablePass.SetRenderer(renderer);
       
        renderer.EnqueuePass(m_ScriptablePass);
       
    }
    public void SetMatrices(Matrix4x4 viewMatrix, Matrix4x4 projMatrix)
    {
        m_ScriptablePass.SetMatrices(viewMatrix, projMatrix);
    }
    class SkinRenderPass       : ScriptableRenderPass
    {
        #region 属性
        Material                            m_CombineLightingPass;
        public  Shader                      shadowDepthShader;
        private GameObject                  shadowCameraGO=new GameObject();
        public  Settings                    settings; 
        FilteringSettings                   m_FilteringSettings ;
        private  ShaderTagId                subsurfaceScatteringLightingTagId ;
        private  ScriptableRenderer         m_Renderer;
        /*GameObject shadowCameraGO           = new GameObject("shadowCameraName");*/
        private Camera                      shadowMapCamera;
        private Matrix4x4                   shadowViewMatrix;
        private Matrix4x4                   shadowProjectionMatrix;
        public  List<Renderer>              shadowRenderers; // 包含所有目标渲染器的列表
        public List<Renderer>               roleShadowRenderers = new List<Renderer>();
        private Dictionary<Renderer, Material[]> cacheMaterial = new Dictionary<Renderer, Material[]>();
        
       
        private int textureSize = 2048; // 阴影贴图的大小
        private int ShadowMapDepth = 24; // 深度缓冲区的位数
        private RenderTexture shadowTexture;
        
        public SkinRenderPass(Settings settings)
        {
            this.settings= settings;
            m_FilteringSettings  = new FilteringSettings(RenderQueueRange.opaque);
            this.renderPassEvent = settings.RenderPassEvent;
           
        }
        private void CacheMaterials()
        {
            cacheMaterial.Clear();
            foreach (var renderer in roleShadowRenderers)
            {
                cacheMaterial[renderer] = renderer.sharedMaterials;
            }
        }
        void NeedShadowRenderers()
        {
            
            roleShadowRenderers = new List<Renderer>();

            // 查找场景中所有带有 "ShadowCaster" 标签的对象的 Renderer
            GameObject[] shadowCasterObjects = GameObject.FindGameObjectsWithTag("HighShadow");
            //Debug.Log("Found " + shadowCasterObjects.Length + " objects with 'HighShadow' tag.");
            foreach (GameObject obj in shadowCasterObjects)
            {
                
                Renderer renderer = obj.GetComponent<Renderer>();
                if (renderer != null)
                {
                    roleShadowRenderers.Add(renderer);
                }
            }
        }
        public void SetRenderer(ScriptableRenderer renderer)
        {
            this.m_Renderer = renderer;
        }
        #endregion
        public void SetMatrices(Matrix4x4 viewMatrix, Matrix4x4 projMatrix)
        {
            this.shadowViewMatrix = viewMatrix;
            this.shadowProjectionMatrix = projMatrix;
        }
        private bool isShadowCameraCreated = false;
        void CreateShadowCamera()
        {
            if (isShadowCameraCreated) return; 
            shadowDepthShader = Shader.Find("Hidden/HighShadow");
            if (shadowDepthShader == null)
            {
                Debug.Log("Shader 'HightShadow' not found.");
            }
            else
            {
                Debug.Log("Shader 'HightShadow'  found.");
            }
            // 如果 shadowCameraGO 为空，则创建一个新的 GameObject
           
                shadowCameraGO = new GameObject("ShadowCameraHightShadow");
                Debug.Log("shadowCameraGO created.");
                shadowCameraGO.name = "ShadowCameraHightShadow"; 
                shadowCameraGO.hideFlags = HideFlags.DontSave | HideFlags.NotEditable;
                isShadowCameraCreated = true;
                if (shadowMapCamera == null)
                {
                    Debug.Log("shadowMapCamera null.");
                    shadowMapCamera = shadowCameraGO.AddComponent<Camera>();
                }

                shadowMapCamera.renderingPath = RenderingPath.Forward;
                shadowMapCamera.clearFlags = CameraClearFlags.Depth;
                shadowMapCamera.depthTextureMode = DepthTextureMode.None;
                shadowMapCamera.useOcclusionCulling = false;
                shadowMapCamera.cullingMask = LayerMask.GetMask("NPC");
                shadowMapCamera.orthographic = true;
                shadowMapCamera.depth = -100;
                shadowMapCamera.aspect = 1f;
                shadowMapCamera.SetReplacementShader(shadowDepthShader, "HightShadowCaster");
                
        }
        void DestroySSSBuffers()
        {
            if (shadowTexture != null)
            {
                shadowTexture.Release();
                DestroyImmediate(shadowTexture);
            }
        }
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            //CreateShadowCamera();
            shadowTexture = new RenderTexture(textureSize, textureSize, ShadowMapDepth, RenderTextureFormat.Shadowmap, RenderTextureReadWrite.Linear);
            shadowTexture.filterMode = FilterMode.Bilinear;
            shadowTexture.useMipMap = false;
            shadowTexture.autoGenerateMips = false;
            Debug.Log("Shadow Texture Created: " + shadowTexture);
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            //CreateShadowCamera();
            NeedShadowRenderers();
            CacheMaterials();
            Shader shadowShader = Shader.Find("Hidden/HighShadow"); 
            if(shadowShader == null)
            {
                Debug.Log("shadowShader:未被加载 ");
            }
            else
            {
                Debug.Log("shadowShader:成功加载 ");
            }
            CommandBuffer cmd = CommandBufferPool.Get();
            Shader.SetGlobalTexture("HightShadowTex", shadowTexture); 
             
             //绘制MRT到屏幕上:
             using(new ProfilingScope(cmd, new ProfilingSampler("HightShadowRenderFeature")))
             {
                 cmd.SetRenderTarget(shadowTexture, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
                 cmd.ClearRenderTarget(true, false, Color.clear);
                 cmd.SetViewMatrix(shadowViewMatrix );
                 cmd.SetProjectionMatrix(shadowProjectionMatrix );
                 Debug.Log("shadowViewMatrix11" + shadowViewMatrix);
                 Debug.Log("shadowProjectionMatrix11"+shadowProjectionMatrix);
                 Debug.Log($"roleShadowRenderers count: {roleShadowRenderers.Count}");
                 
                 /*foreach(var r in roleShadowRenderers)
                 {
                     if (!cacheMaterial.TryGetValue(r, out Material[] sharedMaterials))
                         continue;
                     for(int i = 0; i < sharedMaterials.Length; i++)
                     {
                         var material = sharedMaterials[i];
                         var passId = material.FindPass("ShadowCaster");
                         if (-1 != passId)
                             cmd.DrawRenderer(r, material, i, passId);
                     }
                 }*/
                 foreach (var r in roleShadowRenderers)
                 {
                     // 尝试从缓存中获取该 Renderer 对应的 sharedMaterials
                     if (!cacheMaterial.TryGetValue(r, out Material[] sharedMaterials))
                         continue;  // 如果缓存中没有找到该 Renderer 对应的 sharedMaterials，则跳过
                     Material shadowMaterial = new Material(shadowShader);
                     Debug.Log("shadermingzi111111111111"+shadowShader.name);
                     // 只渲染第一个找到的材质的 ShadowCaster pass
                     var passId = shadowMaterial.FindPass("HightShadowCaster");  // 找到阴影 pass
                     if (passId != -1)
                     {
                         cmd.DrawRenderer(r, shadowMaterial, 0, passId); // 使用新的材质进行渲染
                        
                     }
                    
                 }
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
             }
             context.ExecuteCommandBuffer(cmd);
             CommandBufferPool.Release(cmd);
             DestroySSSBuffers();
         }
    }
}