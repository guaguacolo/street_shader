using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Serialization;
using System.Collections.Generic;
using UnityEditor.VersionControl;

[System.Serializable] //使得类或结构体可以进行序列化
public class SkinRenderFeature  : ScriptableRendererFeature
{
    class SkinRenderPass : ScriptableRenderPass
    {
        
        #region 属性
        RTHandle m_SSSColor;
        RTHandle m_SSSColorMSAA;
        bool m_SSSReuseGBufferMemory;
        // Disney SSS Model
        //确定ComputeShader
        ComputeShader m_SubsurfaceScatteringCS;
        int m_SubsurfaceScatteringKernel;
        int m_SubsurfaceScatteringKernelMSAA;
        Material m_CombineLightingPass;
        // End Disney SSS Model
        // Need an extra buffer on some platforms
        RTHandle m_SSSCameraFilteringBuffer;
        // This is use to be able to read stencil value in compute shader
        Material m_SSSCopyStencilForSplitLighting;
        // List of every diffusion profile data we need
        Vector4[]                   m_SSSShapeParamsAndMaxScatterDists;
        Vector4[]                   m_SSSTransmissionTintsAndFresnel0;
        Vector4[]                   m_SSSDisabledTransmissionTintsAndFresnel0;
        Vector4[]                   m_SSSWorldScalesAndFilterRadiiAndThicknessRemaps;
        uint[]                      m_SSSDiffusionProfileHashes;
        int[]                       m_SSSDiffusionProfileUpdate;
        DiffusionProfileSettings[]  m_SSSSetDiffusionProfiles;
        DiffusionProfileSettings    m_SSSDefaultDiffusionProfile;
        int                         m_SSSActiveDiffusionProfileCount;
        uint                        m_SSSTexturingModeFlags;        // 1 bit/profile: 0 = PreAndPostScatter, 1 = PostScatter
        uint                        m_SSSTransmissionFlags;         // 1 bit/profile: 0 = regular, 1 = thin
        public DiffusionProfileSettings     m_diffusionProfile;
        private RenderTargetIdentifier[]    m_subsurfaceColorBuffer = new RenderTargetIdentifier[3];
        private RenderTargetIdentifier      depthBufferTarget;
        private List<ShaderTagId>  shaderTagIdList;
        FilteringSettings m_FilteringSettings = new FilteringSettings(RenderQueueRange.all);
        static readonly ShaderTagId subsurfaceScatteringLightingTagId = new ShaderTagId("SubsurfaceScattering");
        
        //DiffusionProfileSettings defaultResources = Resources.Load<DiffusionProfileSettings>("Path/To/DefaultResources");
        //ScriptableRenderer 是渲染管线中负责具体渲染的部分
        private ScriptableRenderer m_renderer;
        #endregion
        void DestroySSSBuffers()
        {
            RTHandles.Release(m_SSSColorMSAA);
            RTHandles.Release(m_SSSCameraFilteringBuffer);
            if (!m_SSSReuseGBufferMemory)
            {
                RTHandles.Release(m_SSSColor);
            }
        }
        struct SubsurfaceScatteringParameters
        {
            public ComputeShader    subsurfaceScatteringCS;
            public int              subsurfaceScatteringCSKernel;
            public int              sampleBudget;
            public bool             needTemporaryBuffer;
            public Material         copyStencilForSplitLighting;
            public Material         combineLighting;
            public int              numTilesX;
            public int              numTilesY;
            public int              numTilesZ;
        }

        struct SubsurfaceScatteringResources
        {
            public RTHandle colorBuffer;
            public RTHandle diffuseBuffer;
            public RTHandle depthStencilBuffer;
            public RTHandle depthTexture;

            public RTHandle cameraFilteringBuffer;
            public ComputeBuffer coarseStencilBuffer;
            public RTHandle sssBuffer;
        }
        RTHandle GetSSSBuffer()
        {
            return m_SSSColor;
        }

        RTHandle GetSSSBufferMSAA()
        {
            return m_SSSColorMSAA;
        }
        
        void InitializeSubsurfaceScattering()
        {
            // Disney SSS (compute + combine)
            //确定computeID
            string kernelName = "SubsurfaceScattering";
            //调用ComputeShader 或者开放窗口
            m_SubsurfaceScatteringCS = Resources.Load<ComputeShader>("_res/2 model/myshader/street_shader/SubsurfaceScattering/SubsurfaceScattering");
            //m_SubsurfaceScatteringCS = defaultResources.shaders.subsurfaceScatteringCS;
            //确定computID
            //确定ComputeShader   shader中函数调用
            m_SubsurfaceScatteringKernel = m_SubsurfaceScatteringCS.FindKernel(kernelName);
            //用于组合光照的着色器 Pixel Shader 调用 comuputeshader
            m_CombineLightingPass = CoreUtils.CreateEngineMaterial("_res/2 model/myshader/street_shader/SubsurfaceScattering/SubsurfaceScattering");
            //StencilUsage 是一个枚举类型，它定义了一些常量，用来指定模板测试的不同使用场景
            m_CombineLightingPass.SetInt(SSSShaderID._StencilRef,  (int)StencilUsage.SubsurfaceScattering);
            m_CombineLightingPass.SetInt(SSSShaderID._StencilMask, (int)StencilUsage.SubsurfaceScattering);

            //m_SSSCopyStencilForSplitLighting = CoreUtils.CreateEngineMaterial(defaultResources.shaders.copyStencilBufferPS);
            m_SSSCopyStencilForSplitLighting = CoreUtils.CreateEngineMaterial(Resources.Load<Shader>("_res/2 model/myshader/street_shader/SubsurfaceScattering/copyStencilBufferPS"));
            m_SSSCopyStencilForSplitLighting.SetInt(SSSShaderID._StencilRef, (int)StencilUsage.SubsurfaceScattering);
            m_SSSCopyStencilForSplitLighting.SetInt(SSSShaderID._StencilMask, (int)StencilUsage.SubsurfaceScattering);

            m_SSSDefaultDiffusionProfile = UnityEditor.AssetDatabase.LoadAssetAtPath<DiffusionProfileSettings>("Assets/_res/2 model/myshader/street_shader/Editor/NewDiffusionProfileSettings");
            // fill the list with the max number of diffusion profile so we dont have
            // the error: exceeds previous array size (5 vs 3). Cap to previous size.
            m_SSSShapeParamsAndMaxScatterDists = new Vector4[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSTransmissionTintsAndFresnel0 = new Vector4[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSDisabledTransmissionTintsAndFresnel0 = new Vector4[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSWorldScalesAndFilterRadiiAndThicknessRemaps = new Vector4[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSDiffusionProfileHashes = new uint[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSDiffusionProfileUpdate = new int[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSSetDiffusionProfiles = new DiffusionProfileSettings[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            //删除rayTracing相关代码
           /* if (rayTracingSupported)
                InitializeSubsurfaceScatteringRT();*/
        }

       

       
        //绘制到了不透明物体的前面
        //配置一些临时的渲染目标和渲染缓冲区
        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            //从 cameraTextureDescriptor 中提取当前渲染目标的宽度和高度。这个描述符通常由相机提供，包含当前渲染目标的详细信息（如分辨率、格式等）。
            int width = cameraTextureDescriptor.width;
            int height = cameraTextureDescriptor.height;
            //创建临时渲染目标
            /*_DepthTexture: 这是一个深度纹理，使用 RenderTextureFormat.Depth 格式来存储深度信息。它的深度缓冲区使用 16 位存储，并设置了 Bilinear 滤镜模式。
              _IrradianceSource: 这是一个浮点格式的渲染目标，使用 GraphicsFormat.B10G11R11_UFloatPack32 格式。该渲染目标可能用于存储计算后的辐射源数据（如次表面散射中使用的光照数据）。
              _SSSBufferTexture: 这是一个普通的 RGBA 渲染目标，使用 GraphicsFormat.R8G8B8A8_UNorm 格式，可能用于存储次表面散射的结果或中间数据。*/
            cmd.GetTemporaryRT(SSSShaderID._DepthTexture, width, height, 16, FilterMode.Bilinear, RenderTextureFormat.Depth);
            cmd.GetTemporaryRT(SSSShaderID._IrradianceSource, width, height, 0, FilterMode.Bilinear, GraphicsFormat.B10G11R11_UFloatPack32);
            cmd.GetTemporaryRT(SSSShaderID._SSSBufferTexture, width, height, 0, FilterMode.Bilinear, GraphicsFormat.R8G8B8A8_UNorm);
            /*m_subsurfaceColorBuffer[0]: 这指向当前相机的颜色目标（通常是屏幕或渲染纹理），它存储最终的颜色输出。
            m_subsurfaceColorBuffer[1] 和 m_subsurfaceColorBuffer[2]: 这两个渲染目标分别指向之前创建的 _IrradianceSource 和 _SSSBufferTexture，它们在渲染过程中将被用来存储中间数据。
            depthBufferTarget: 这个标识符指向 _DepthTexture，即深度缓冲区，它将在后续的渲染过程中用于深度测试或其他操作。*/
            m_subsurfaceColorBuffer[0] = m_renderer.cameraColorTarget;
            m_subsurfaceColorBuffer[1] = new RenderTargetIdentifier(SSSShaderID._IrradianceSource);
            m_subsurfaceColorBuffer[2] = new RenderTargetIdentifier(SSSShaderID._SSSBufferTexture);
            //用于标识渲染目标（Render Target）。渲染目标是渲染管线中的一个重要概念，表示 GPU 渲染操作的输出位置。可以是帧缓冲区（屏幕）、纹理、RenderTexture 或者其他类似的资源。
            depthBufferTarget = new RenderTargetIdentifier(SSSShaderID._DepthTexture);
        }
        // 用来做每帧的操作
        // 每帧在管线指定位置执行一次（在上面 SetupRenderPasses 里配置位置）
        //进行自定义的 次表面散射（Subsurface Scattering, SSS） 渲染操作的实现
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
         {
             //scatteringDistance: 次表面散射的距离。
             //worldScale: 渲染时物体的尺度。
             //filterRadius: 滤波半径。
             //shapeParam: 物体形状的参数。
             //transmissionTint: 物体的传输色调（影响颜色的散射）。
             //thicknessRemapValue: 厚度的重新映射。
             //ior: 物体的折射率（Index of Refraction, IOR）。
             //fresnel0: 根据折射率计算的 Fresnel 值。
             Vector4 scatteringDistance = (Vector4)m_diffusionProfile.profile.scatteringDistance;
             float worldScale = m_diffusionProfile.profile.worldScale;
             float filterRadius = m_diffusionProfile.profile.filterRadius;
             Vector4 shapeParam = new Vector4(m_diffusionProfile.profile.shapeParam.x, m_diffusionProfile.profile.shapeParam.y, m_diffusionProfile.profile.shapeParam.z, Mathf.Max(scatteringDistance.x, scatteringDistance.y, scatteringDistance.z));
             Color transmissionTint = m_diffusionProfile.profile.transmissionTint;
             Vector2 thicknessRemapValue = m_diffusionProfile.profile.thicknessRemap;
             float ior = m_diffusionProfile.profile.ior;
             float fresnel0 = ((ior - 1.0f) * (ior - 1.0f)) / ((ior + 1.0f) * (ior + 1.0f));
             //这些值被用于构建一个 Vector4 并设置为全局变量：
             //m_diffusionProfile._TransmissionTintsAndFresnel0 = new Vector4(transmissionTint.r * 0.25f, transmissionTint.g * 0.25f, transmissionTint.b * 0.25f, fresnel0);
             //m_diffusionProfile._WorldScalesAndFilterRadiiAndThicknessRemaps = new Vector4(worldScale, filterRadius, thicknessRemapValue.x, thicknessRemapValue.y - thicknessRemapValue.x);
             // m_diffusionProfile._ShapeParamsAndMaxScatterDists = shapeParam;
             //m_diffusionProfile.disabled_TransmissionTintsAndFresnel0 = new Vector4(0.0f, 0.0f, 0.0f, fresnel0);
             //配置了渲染物体时的绘制顺序和设置 sortingCriteria: 选择渲染顺序的标准，这里使用的是默认的排序标准。
             //drawingSettings: 通过 CreateDrawingSettings 函数创建的渲染设置，它用于指定渲染时的设置，包括材质、着色器、排序标准等
             SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags; 
             //drawingSettings 是一个 DrawingSettings 类型的结构体，它定义了如何绘制渲染器的设置。它包含了渲染的排序、着色器、材质等信息。
             //着色器和着色器标签：指定使用的着色器以及需要渲染的图形部分（例如 Forward、Deferred）。
             //排序标志：指定如何排序渲染对象（例如按距离排序、按材质排序）。
             //渲染队列范围：指示需要渲染的物体属于哪个渲染队列。
             DrawingSettings drawingSettings = CreateDrawingSettings(subsurfaceScatteringLightingTagId, ref renderingData, sortingCriteria);
             //使用 CommandBuffer 来执行多个渲染操作。CommandBuffer 用于将一系列命令排队，然后一起执行，以提高性能和控制。
             CommandBuffer cmd = CommandBufferPool.Get();
             cmd.SetGlobalVector("_TransmissionTintsAndFresnel0", m_diffusionProfile._TransmissionTintsAndFresnel0);
             cmd.SetGlobalVector("_WorldScalesAndFilterRadiiAndThicknessRemaps", m_diffusionProfile._WorldScalesAndFilterRadiiAndThicknessRemaps);
             cmd.SetGlobalVector("_ShapeParamsAndMaxScatterDists", m_diffusionProfile._ShapeParamsAndMaxScatterDists);
             //接下来进行几轮渲染操作，使用不同的 ProfilingScope 来分析不同的渲染阶段。
             //设置渲染目标为 m_subsurfaceColorBuffer 和深度缓冲区。
             //清除渲染目标并绘制场景中的物体。
             using(new ProfilingScope(cmd, new ProfilingSampler("Subsurface Scattering")))
             {
                 cmd.SetRenderTarget(m_subsurfaceColorBuffer, m_renderer.cameraDepthTarget);
                 cmd.ClearRenderTarget(true, true, renderingData.cameraData.camera.backgroundColor);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 //CPU向GPU每帧提交绘制指定物体的指令，绘制用的Shader就使用描边的Shader
                 context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings);
             }
             using(new ProfilingScope(cmd, new ProfilingSampler("Subsurface Scattering Pre Depth")))
             { 
                 // 示例：将深度纹理设置为渲染目标
                 cmd.SetRenderTarget(depthBufferTarget);
                 // 清除渲染目标，清除颜色和深度
                 cmd.ClearRenderTarget(true, true, Color.clear);
                 // 执行命令缓冲区中的命令
                 context.ExecuteCommandBuffer(cmd);
                 // 清除命令缓冲区中的命令，准备下一次使用
                 cmd.Clear();
                 // 绘制渲染器
                 //renderingData.cullResults：它是一个 CullingResults 类型的对象，包含了场景中所有可见的渲染器（即那些位于相机视野中的渲染物体）
                 //drawingSettings 是一个 DrawingSettings 类型的结构体，它定义了如何绘制渲染器的设置。它包含了渲染的排序、着色器、材质等信息。
                 //m_FilteringSettings 是一个 FilteringSettings 类型的结构体，它定义了如何筛选哪些渲染器应被绘制。
                 //m_FilteringSettings 允许你只绘制某个特定图层的物体，或者只渲染某些类型的对象（如动态物体）。
                 context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings);
             }
             //使用计算着色器进行次表面散射的计算。
            // 设置临时渲染目标并进行计算。
             using(new ProfilingScope(cmd, new ProfilingSampler("SubsurfaceScattering")))
             {
                 int m_kernel = m_SubsurfaceScatteringCS.FindKernel("SubsurfaceScattering");
                 int cameraFilterBuffer = Shader.PropertyToID("cameraFilterBuffer");
                 RenderTargetIdentifier cameraFilterBufferID = new RenderTargetIdentifier(cameraFilterBuffer);
                 RenderTextureDescriptor decs = renderingData.cameraData.cameraTargetDescriptor;
                 decs.enableRandomWrite = true;
                 cmd.GetTemporaryRT(cameraFilterBuffer, decs);
         
                 cmd.SetRenderTarget(cameraFilterBufferID, m_renderer.cameraDepthTarget);
                 cmd.ClearRenderTarget(false, true, Color.clear);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, SSSShaderID._IrradianceSource, m_subsurfaceColorBuffer[1]);
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, SSSShaderID._SSSBufferTexture, m_subsurfaceColorBuffer[2]);
                 //SetComputeTextureParam 用来将纹理传递给计算着色器 m_SubsurfaceScatteringCS 这里是computeshader
                 // 将深度纹理设置为计算着色器的参数
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, SSSShaderID._DepthTexture, depthBufferTarget);
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, SSSShaderID._CameraFilteringBuffer, cameraFilterBufferID);
                 // 执行计算着色器
                 cmd.DispatchCompute(m_SubsurfaceScatteringCS, m_kernel, (Screen.width + 7) / 8, (Screen.height + 7) / 8, 1);
         
                 cmd.SetRenderTarget(m_renderer.cameraColorTarget, m_renderer.cameraDepthTarget);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 cmd.SetGlobalTexture(SSSShaderID._IrradianceSource, cameraFilterBufferID);
                 cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
                 //某些渲染效果中，你可能只需要绘制一个特定的形状（如一个全屏的矩形或三角形），而不需要复杂的网格数据。DrawProcedural 可以非常高效地完成这种任务。
                 cmd.DrawProcedural(Matrix4x4.identity, m_CombineLightingPass, 0, MeshTopology.Triangles, 3, 1);
                 cmd.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(), renderingData.cameraData.GetProjectionMatrix());
             }
             //命令缓冲区执行与释放
             context.ExecuteCommandBuffer(cmd);
             CommandBufferPool.Release(cmd);
         }
       
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    
    //AddRenderPasses 方法的主要作用是将自定义渲染通道添加到 URP 渲染过程中。
    //通过 Setup 方法，传入各种参数，配置渲染通道的具体行为。
    //最终，调用 renderer.EnqueuePass 将该渲染通道加入渲染队列，确保它在渲染过程中被执行。
    public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingOpaques;
     SkinRenderPass m_ScriptablePass;
    public override void Create()
    {
        m_ScriptablePass = new SkinRenderPass
        {
            renderPassEvent = passEvent
        };
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
       
        renderer.EnqueuePass(m_ScriptablePass);
    }
}