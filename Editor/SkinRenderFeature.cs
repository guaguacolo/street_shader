using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Serialization;
using System.Collections.Generic;
using UnityEditor.VersionControl;

//[System.Serializable] //使得类或结构体可以进行序列化

public class SkinRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public  class Settings  
    {  
        public RenderPassEvent   RenderPassEvent;  
        [SerializeField] public  RenderPassEvent passEvent= RenderPassEvent.BeforeRenderingSkybox;
        [SerializeField] public  DiffusionProfileSettings  m_diffusionProfile ;
        public float Intensity = 1f;
        
    }  
    [SerializeField]
    
    public Settings settings = new Settings();
    SkinRenderPass m_ScriptablePass;
     
    public override void Create()
    {
        m_ScriptablePass = new SkinRenderPass(settings);
        m_ScriptablePass.renderPassEvent = settings.RenderPassEvent;
        if (m_ScriptablePass.renderPassEvent == RenderPassEvent.BeforeRenderingOpaques)
        {
            Debug.Log($"SkinRenderPass RenderPassEvent set to: {m_ScriptablePass.renderPassEvent}");
        }
        else
        {
            Debug.Log($"SkinRenderPass RenderPassEvent wrong");
        }
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        m_ScriptablePass.SetRenderer(renderer);
        Debug.Log("SkinRenderPass added to renderer");
        renderer.EnqueuePass(m_ScriptablePass);
       
    }
    class SkinRenderPass       : ScriptableRenderPass
    {
        #region 属性
        RTHandle      m_SSSColor;
        RTHandle      m_SSSColorMSAA;
        bool          m_SSSReuseGBufferMemory;
        ComputeShader m_SubsurfaceScatteringCS;
        Material      m_CombineLightingPass;
        RTHandle      m_SSSCameraFilteringBuffer;
        Material      m_SSSCopyStencilForSplitLighting;
        public  Settings settings; 
        Vector4[]                           m_SSSShapeParamsAndMaxScatterDists;
        Vector4[]                           m_SSSTransmissionTintsAndFresnel0;
        Vector4[]                           m_SSSDisabledTransmissionTintsAndFresnel0;
        Vector4[]                           m_SSSWorldScalesAndFilterRadiiAndThicknessRemaps;
        uint[]                              m_SSSDiffusionProfileHashes;
        int[]                               m_SSSDiffusionProfileUpdate;
        DiffusionProfileSettings[]          m_SSSSetDiffusionProfiles;
        DiffusionProfileSettings            m_SSSDefaultDiffusionProfile;
        int                                 m_SSSActiveDiffusionProfileCount;
        uint                                m_SSSTexturingModeFlags;        // 1 bit/profile: 0 = PreAndPostScatter, 1 = PostScatter
        uint                                m_SSSTransmissionFlags;         // 1 bit/profile: 0 = regular, 1 = thin
        public DiffusionProfileSettings m_diffusionProfile;
        private RenderTargetIdentifier[]    m_subsurfaceColorBuffer = new RenderTargetIdentifier[3];
        private RenderTargetIdentifier      depthBufferTarget;
        FilteringSettings                   m_FilteringSettings ;
        private  ShaderTagId        subsurfaceScatteringLightingTagId ;
        private ScriptableRenderer          m_Renderer;
        public SkinRenderPass(Settings settings)
        {
            this.settings= settings;
            m_FilteringSettings = new FilteringSettings(RenderQueueRange.opaque);
            m_diffusionProfile  =new DiffusionProfileSettings();
            m_diffusionProfile  =settings.m_diffusionProfile;
            this.renderPassEvent = settings.RenderPassEvent;
           
        }
        public void SetRenderer(ScriptableRenderer renderer)
        {
            this.m_Renderer = renderer;
        }
        //DiffusionProfileSettings defaultResources = Resources.Load<DiffusionProfileSettings>("Path/To/DefaultResources");
        //ScriptableRenderer 是渲染管线中负责具体渲染的部分
       
        #endregion
        //次表面散射缓冲区初始化
        /*void InitSSSBuffers()
        {
            UniversalRenderPipelineAsset  settings =  GraphicsSettings.currentRenderPipeline as UniversalRenderPipelineAsset;
            bool supportsMSAA = settings.msaaSampleCount > 1;
            if (settings.supportsCameraOpaqueTexture) // forward only
            {
                // 在全前向渲染的情况下，我们必须为前向 SSS 分配渲染目标（或重用已经存在的一个）
                m_SSSColor = RTHandles.Alloc(Vector2.one, TextureXR.slices, colorFormat: GraphicsFormat.R8G8B8A8_SRGB, dimension: TextureXR.dimension, useDynamicScale: true, name: "SSSBuffer");
                m_SSSReuseGBufferMemory = false;
            }
            if (NeedTemporarySubsurfaceBuffer() || supportsMSAA)
            {
                // 注意：必须与 m_CameraSssDiffuseLightingBuffer 的格式相同
                m_SSSCameraFilteringBuffer = RTHandles.Alloc(Vector2.one, TextureXR.slices, colorFormat: GraphicsFormat.B10G11R11_UFloatPack32, dimension: TextureXR.dimension, enableRandomWrite: true, useDynamicScale: true, name: "SSSCameraFiltering"); // 启用 UAV
            }
        }*/
       /* static bool NeedTemporarySubsurfaceBuffer()
        {
            // Caution: need to be in sync with SubsurfaceScattering.cs USE_INTERMEDIATE_BUFFER (Can't make a keyword as it is a compute shader)
            // Typed UAV loads from FORMAT_R16G16B16A16_FLOAT is an optional feature of Direct3D 11.
            // Most modern GPUs support it. We can avoid performing a costly copy in this case.
            // TODO: test/implement for other platforms.
            return (SystemInfo.graphicsDeviceType != GraphicsDeviceType.PlayStation4 &&
                    SystemInfo.graphicsDeviceType != GraphicsDeviceType.PlayStation5 &&
                    SystemInfo.graphicsDeviceType != GraphicsDeviceType.XboxOne &&
                    SystemInfo.graphicsDeviceType != GraphicsDeviceType.XboxOneD3D12 &&
                    SystemInfo.graphicsDeviceType != GraphicsDeviceType.GameCoreXboxOne &&
                    SystemInfo.graphicsDeviceType != GraphicsDeviceType.GameCoreXboxSeries);
        }*/

        void DestroySSSBuffers()
        {
            //释放不再使用的资源
            RTHandles.Release(m_SSSColorMSAA);
            RTHandles.Release(m_SSSCameraFilteringBuffer);
            if (!m_SSSReuseGBufferMemory)
            {
                RTHandles.Release(m_SSSColor);
            }
        }
       
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
           /* m_CombineLightingPass.SetInt(SSSShaderID._StencilRef,  (int)StencilUsage.SubsurfaceScattering);
            m_CombineLightingPass.SetInt(SSSShaderID._StencilMask, (int)StencilUsage.SubsurfaceScattering);*/
            //m_CombineLightingPass = CoreUtils.CreateEngineMaterial(Shader.Find("Hidden/HDRP/CombineLighting"));
            m_CombineLightingPass = CoreUtils.CreateEngineMaterial(Shader.Find("Game/Combinetest"));
            if (m_CombineLightingPass == null) {
                Debug.LogError(" m_CombineLightingPass 未能加载！");
            } else {
                Debug.Log(" m_CombineLightingPass 成功加载！");
            }
           
            //InitializeSubsurfaceScattering();
            int width = cameraTextureDescriptor.width;
            int height = cameraTextureDescriptor.height;
            cmd.GetTemporaryRT(SSSShaderID._DepthTexture,     width, height, 16, FilterMode.Bilinear, RenderTextureFormat.Depth);
            cmd.GetTemporaryRT(SSSShaderID._IrradianceSource, width, height, 0,  FilterMode.Bilinear, GraphicsFormat.B10G11R11_UFloatPack32);
            cmd.GetTemporaryRT(SSSShaderID._SSSBufferTexture, width, height, 0,  FilterMode.Bilinear, GraphicsFormat.R8G8B8A8_UNorm);
            m_subsurfaceColorBuffer[0] = m_Renderer.cameraColorTarget;
            m_subsurfaceColorBuffer[1] = new RenderTargetIdentifier(SSSShaderID._IrradianceSource);//DiffuseBuffer
            m_subsurfaceColorBuffer[2] = new RenderTargetIdentifier(SSSShaderID._SSSBufferTexture);//sssBuffer
            depthBufferTarget          = new RenderTargetIdentifier(SSSShaderID._DepthTexture);    //计算总光照强度，viewZ
        }
        // 用来做每帧的操作
        // 每帧在管线指定位置执行一次（在上面 SetupRenderPasses 里配置位置）
        // 进行自定义的 次表面散射（Subsurface Scattering, SSS） 渲染操作的实现
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            
             //调用ComputeShader 或者开放窗口
             m_SubsurfaceScatteringCS = Resources.Load<ComputeShader>("SubsurfaceScattering");
             
             int  m_kernel               = m_SubsurfaceScatteringCS.FindKernel("SubsurfaceScattering");
           
             #region Diffuse属性
             // 1. 设置子表面散射参数
             Vector4 scatteringDistance = (Vector4)m_diffusionProfile.profile.scatteringDistance;
             float worldScale           = m_diffusionProfile.profile.worldScale;
             float filterRadius         = m_diffusionProfile.profile.filterRadius;
             Vector4 shapeParam         = new Vector4(m_diffusionProfile.profile.shapeParam.x,
                                                      m_diffusionProfile.profile.shapeParam.y,
                                                      m_diffusionProfile.profile.shapeParam.z,
                                                      Mathf.Max(scatteringDistance.x,scatteringDistance.y, scatteringDistance.z));
             Color transmissionTint      = m_diffusionProfile.profile.transmissionTint;
             Vector2 thicknessRemapValue = m_diffusionProfile.profile.thicknessRemap;
             float ior                   = m_diffusionProfile.profile.ior;
             float fresnel0              = ((ior - 1.0f) * (ior - 1.0f)) / ((ior + 1.0f) * (ior + 1.0f));
             m_diffusionProfile._TransmissionTintsAndFresnel0 = new Vector4(transmissionTint.r * 0.25f, transmissionTint.g * 0.25f, transmissionTint.b * 0.25f, fresnel0);
             m_diffusionProfile._WorldScalesAndFilterRadiiAndThicknessRemaps = new Vector4(worldScale, filterRadius, thicknessRemapValue.x, thicknessRemapValue.y - thicknessRemapValue.x);
             m_diffusionProfile._ShapeParamsAndMaxScatterDists = shapeParam;
             m_diffusionProfile.disabled_TransmissionTintsAndFresnel0 = new Vector4(0.0f, 0.0f, 0.0f, fresnel0);
             // 2. 创建绘制设置
             SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags; 
             subsurfaceScatteringLightingTagId = new ShaderTagId("SkinDiffuse");
             DrawingSettings drawingSettings = CreateDrawingSettings(subsurfaceScatteringLightingTagId, ref renderingData, sortingCriteria);
             
             // 3. 命令缓冲区的创建和设置全局变量
             //使用 CommandBuffer 来执行多个渲染操作。CommandBuffer 用于将一系列命令排队，然后一起执行，以提高性能和控制。
             CommandBuffer cmd = CommandBufferPool.Get();
             cmd.SetGlobalVector("_TransmissionTintsAndFresnel0", m_diffusionProfile._TransmissionTintsAndFresnel0);
             cmd.SetGlobalVector("_WorldScalesAndFilterRadiiAndThicknessRemaps", m_diffusionProfile._WorldScalesAndFilterRadiiAndThicknessRemaps);
             cmd.SetGlobalVector("_ShapeParamsAndMaxScatterDists", m_diffusionProfile._ShapeParamsAndMaxScatterDists);
             // 4. 执行子表面散射渲染
             #endregion
             var projectMatrix = renderingData.cameraData.camera.projectionMatrix;
             var invProject = projectMatrix.inverse; //vp矩阵
             //绘制MRT到屏幕上:
             using(new ProfilingScope(cmd, new ProfilingSampler("Subsurface Scattering")))
             {
                 cmd.SetRenderTarget(m_subsurfaceColorBuffer,m_Renderer.cameraDepthTargetHandle);
                 cmd.ClearRenderTarget(true, true, renderingData.cameraData.camera.backgroundColor);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 //CPU向GPU每帧提交绘制指定物体的指令，绘制用的Shader就使用描边的Shader
                 context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings);
             }
             //绘制ComputeShader需要用到的深度图:
             // 5. 预深度渲染
             using(new ProfilingScope(cmd, new ProfilingSampler("Subsurface Scattering Pre Depth")))
             { 
                 // 示例：将深度纹理设置为渲染目标 只处理深度 不处理颜色
                 cmd.SetRenderTarget(depthBufferTarget);
                 // 清除渲染目标，清除颜色和深度
                 cmd.ClearRenderTarget(true, true, Color.clear);
                 // 执行命令缓冲区中的命令
                 context.ExecuteCommandBuffer(cmd);
                 // 清除命令缓冲区中的命令，准备下一次使用
                 cmd.Clear();
                 context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings);
             }
             // 6. 计算子表面散射
             //调用ComputeShader计算模糊:
             using(new ProfilingScope(cmd, new ProfilingSampler("Compute SubsurfaceScattering")))
             {
                 
                
                 int cameraFilterBuffer = Shader.PropertyToID("cameraFilterBuffer");
                 RenderTargetIdentifier cameraFilterBufferID = new RenderTargetIdentifier(cameraFilterBuffer);
                 RenderTextureDescriptor decs = renderingData.cameraData.cameraTargetDescriptor;
                 decs.enableRandomWrite = true;
                 cmd.GetTemporaryRT(cameraFilterBuffer, decs);
         
                 cmd.SetRenderTarget(cameraFilterBufferID, m_Renderer.cameraDepthTargetHandle);
                 cmd.ClearRenderTarget(false, true, Color.clear);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, SSSShaderID._IrradianceSource, m_subsurfaceColorBuffer[1]);//DiffuseBuffer
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, SSSShaderID._SSSBufferTexture, m_subsurfaceColorBuffer[2]);//sssBuffer
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, SSSShaderID._DepthTexture,              depthBufferTarget);
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, SSSShaderID._CameraFilteringBuffer, cameraFilterBufferID);
                 cmd.DispatchCompute(m_SubsurfaceScatteringCS, m_kernel, (Screen.width + 7) / 8, (Screen.height + 7) / 8, 1);
                 
                 cmd.SetRenderTarget(m_Renderer.cameraColorTarget/*, m_Renderer.cameraDepthTarget*/);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 cmd.SetGlobalTexture(SSSShaderID._IrradianceSource, cameraFilterBufferID);
                 cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
                 cmd.DrawProcedural(Matrix4x4.identity, m_CombineLightingPass, 0, MeshTopology.Triangles, 3, 1);
                 cmd.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(), renderingData.cameraData.GetProjectionMatrix());
             }
             // 7. 执行命令缓冲区并释放资源
             context.ExecuteCommandBuffer(cmd);
             CommandBufferPool.Release(cmd);
             DestroySSSBuffers();
         }
       
       
    }
    //AddRenderPasses 方法的主要作用是将自定义渲染通道添加到 URP 渲染过程中。
    //通过 Setup 方法，传入各种参数，配置渲染通道的具体行为。
    //最终，调用 renderer.EnqueuePass 将该渲染通道加入渲染队列，确保它在渲染过程中被执行。
}