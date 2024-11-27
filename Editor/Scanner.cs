using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Serialization;

public class Scanner : ScriptableRendererFeature
{
    class ScannerPass : ScriptableRenderPass
    {
        #region 字段和属性
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
            m_SubsurfaceScatteringCS = Resources.Load<ComputeShader>("SubsurfaceScattering");
            //m_SubsurfaceScatteringCS = defaultResources.shaders.subsurfaceScatteringCS;
            //确定computID
            //确定ComputeShader   shader中函数调用
            m_SubsurfaceScatteringKernel = m_SubsurfaceScatteringCS.FindKernel(kernelName);
            //用于组合光照的着色器 Pixel Shader 调用 comuputeshader
            m_CombineLightingPass = CoreUtils.CreateEngineMaterial("_res/2 model/myshader/street_shader/SubsurfaceScattering/SubsurfaceScattering");
            m_CombineLightingPass.SetInt(SSSShaderID._StencilRef, (int)StencilUsage.SubsurfaceScattering);
            m_CombineLightingPass.SetInt(SSSShaderID._StencilMask, (int)StencilUsage.SubsurfaceScattering);

            m_SSSCopyStencilForSplitLighting = CoreUtils.CreateEngineMaterial(defaultResources.shaders.copyStencilBufferPS);
            m_SSSCopyStencilForSplitLighting.SetInt(SSSShaderID._StencilRef, (int)StencilUsage.SubsurfaceScattering);
            m_SSSCopyStencilForSplitLighting.SetInt(SSSShaderID._StencilMask, (int)StencilUsage.SubsurfaceScattering);

            m_SSSDefaultDiffusionProfile = defaultResources.assets.defaultDiffusionProfile;

            // fill the list with the max number of diffusion profile so we dont have
            // the error: exceeds previous array size (5 vs 3). Cap to previous size.
            m_SSSShapeParamsAndMaxScatterDists = new Vector4[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSTransmissionTintsAndFresnel0 = new Vector4[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSDisabledTransmissionTintsAndFresnel0 = new Vector4[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSWorldScalesAndFilterRadiiAndThicknessRemaps = new Vector4[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSDiffusionProfileHashes = new uint[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSDiffusionProfileUpdate = new int[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];
            m_SSSSetDiffusionProfiles = new DiffusionProfileSettings[DiffusionProfileConstants.DIFFUSION_PROFILE_COUNT];

            // If ray tracing is supported by the asset, do the initialization
            //删除rayTracing相关代码
           /* if (rayTracingSupported)
                InitializeSubsurfaceScatteringRT();*/
        }

        public ScannerPass()
        {
            _material = new Material(Shader.Find("Hidden/Scanner"));
        }

        public void Setup(Gradient circleColor, Color lineColor, Vector3 centerPos, float width, float bias, float speed, float maxRadius,
            bool isPoint, bool lineHor, bool lineVer, float gridWidth, float gridScale, bool changeSaturation, float circleMinAlpha, float blendIntensity)
        {
            if (_material == null)
                _material = new Material(Shader.Find("Hidden/Scanner"));

            CircleColor = circleColor;
            LineColor = lineColor;
            CenterPos = centerPos;
            Width = width;
            Bias = bias;
            IsPoint = isPoint;
            LineHor = lineHor;
            LineVer = lineVer;
            GridWidth = gridWidth;
            GridScale = gridScale;
            ChangeSaturation = changeSaturation;
            CircleMinAlpha = circleMinAlpha;
            BlendIntensity = blendIntensity;
            Speed = speed;
            MaxRadius = maxRadius;
        }
        //绘制到了不透明物体的前面
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
         {
             
             Vector4 scatteringDistance = (Vector4)m_diffusionProfile.profile.scatteringDistance;
             float worldScale = m_diffusionProfile.profile.worldScale;
             float filterRadius = m_diffusionProfile.profile.filterRadius;
             Vector4 shapeParam = new Vector4(m_diffusionProfile.profile.shapeParam.x, m_diffusionProfile.profile.shapeParam.y, m_diffusionProfile.profile.shapeParam.z, Mathf.Max(scatteringDistance.x, scatteringDistance.y, scatteringDistance.z));
             Color transmissionTint = m_diffusionProfile.profile.transmissionTint;
             Vector2 thicknessRemapValue = m_diffusionProfile.profile.thicknessRemap;
             float ior = m_diffusionProfile.profile.ior;
             float fresnel0 = ((ior - 1.0f) * (ior - 1.0f)) / ((ior + 1.0f) * (ior + 1.0f));
             m_diffusionProfile.transmissionTintAndFresnel0 = new Vector4(transmissionTint.r * 0.25f, transmissionTint.g * 0.25f, transmissionTint.b * 0.25f, fresnel0);
             m_diffusionProfile.worldScaleAndFilterRadiusAndThicknessRemap = new Vector4(worldScale, filterRadius, thicknessRemapValue.x, thicknessRemapValue.y - thicknessRemapValue.x);
             m_diffusionProfile.shapeParamAndMaxScatterDist = shapeParam;
             m_diffusionProfile.disabledTransmissionTintAndFresnel0 = new Vector4(0.0f, 0.0f, 0.0f, fresnel0);
         
             SortingCriteria sortingCriteria = renderingData.cameraData.defaultOpaqueSortFlags;
             DrawingSettings drawingSettings = CreateDrawingSettings(subsurfaceScatteringLightingTagId, ref renderingData, sortingCriteria);
         
             CommandBuffer cmd = CommandBufferPool.Get();
             cmd.SetGlobalVector("_TransmissionTintsAndFresnel0", m_diffusionProfile.transmissionTintAndFresnel0);
             cmd.SetGlobalVector("_WorldScalesAndFilterRadiiAndThicknessRemaps", m_diffusionProfile.worldScaleAndFilterRadiusAndThicknessRemap);
             cmd.SetGlobalVector("_ShapeParamsAndMaxScatterDists", m_diffusionProfile.shapeParamAndMaxScatterDist);
         
             using(new ProfilingScope(cmd, new ProfilingSampler("Subsurface Scattering")))
             {
                 cmd.SetRenderTarget(m_subsurfaceColorBuffer, m_renderer.cameraDepthTarget);
                 cmd.ClearRenderTarget(true, true, renderingData.cameraData.camera.backgroundColor);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings);
             }
             using(new ProfilingScope(cmd, new ProfilingSampler("Subsurface Scattering Pre Depth")))
             {
                 cmd.SetRenderTarget(depthBufferTarget);
                 cmd.ClearRenderTarget(true, true, Color.clear);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings);
             }
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
         
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, ShaderIDs._IrradianceSource, m_subsurfaceColorBuffer[1]);
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, ShaderIDs._SSSBufferTexture, m_subsurfaceColorBuffer[2]);
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, ShaderIDs._DepthTexture, depthBufferTarget);
                 cmd.SetComputeTextureParam(m_SubsurfaceScatteringCS, m_kernel, ShaderIDs._CameraFilteringBuffer, cameraFilterBufferID);
                 cmd.DispatchCompute(m_SubsurfaceScatteringCS, m_kernel, (Screen.width + 7) / 8, (Screen.height + 7) / 8, 1);
         
                 cmd.SetRenderTarget(m_renderer.cameraColorTarget, m_renderer.cameraDepthTarget);
                 context.ExecuteCommandBuffer(cmd);
                 cmd.Clear();
                 cmd.SetGlobalTexture(ShaderIDs._IrradianceSource, cameraFilterBufferID);
                 cmd.SetViewProjectionMatrices(Matrix4x4.identity, Matrix4x4.identity);
                 cmd.DrawProcedural(Matrix4x4.identity, m_material, 0, MeshTopology.Triangles, 3, 1);
                 cmd.SetViewProjectionMatrices(renderingData.cameraData.GetViewMatrix(), renderingData.cameraData.GetProjectionMatrix());
             }
             context.ExecuteCommandBuffer(cmd);
             CommandBufferPool.Release(cmd);
         }
       
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
        }
    }

    ScannerPass _scannerPass;
    private static readonly int GradientTexPara = Shader.PropertyToID("_GradientTex");
    private static readonly int LineColorPara = Shader.PropertyToID("_LineColor");
    private static readonly int RadiusPara = Shader.PropertyToID("_Radius");
    private static readonly int WidthPara = Shader.PropertyToID("_Width");
    private static readonly int BiasPara = Shader.PropertyToID("_Bias");
    private static readonly int SpeedPara = Shader.PropertyToID("_ExpansionSpeed");
    private static readonly int MaxRadiusPara = Shader.PropertyToID("_MaxRadius");
    private static readonly int GridScalePara = Shader.PropertyToID("_GridScale");
    private static readonly int GridWidthPara = Shader.PropertyToID("_GridWidth");
    private static readonly int CenterPosPara = Shader.PropertyToID("_CenterPos");
    private static readonly int CircleMinAlphaPara = Shader.PropertyToID("_CircleMinAlpha");
    private static readonly int BlendIntensityPara = Shader.PropertyToID("_BlendIntensity");

    public Vector3 centerPos;
    [GradientUsageAttribute(true)] public Gradient circleColor;
    [Range(0f, 10f)] public float width = 1;
    [Range(0f, 1000f)] public float bias = 0;
    [Range(0f, 100f)] public float speed;
    public float maxRadius;
    [Range(0.01f, 0.99f)] public float circleMinAlpha = 0.5f;
    [Range(0.01f, 1f)] public float blendIntensity = 0.9f;
    [ColorUsage(true, true)] public Color lineColor = Color.blue;
    public bool lineHor = true;
    public bool lineVer = true;
    public bool isPoint = true;
    [Range(0, 1)] public float gridWidth = 0.1f;
    public DiffusionProfileSettings DiffusionProfileSettings= new DiffusionProfileSettings();
    public float gridScale = 1;
    public bool changeSaturation = false;
    public RenderPassEvent passEvent = RenderPassEvent.AfterRenderingOpaques;

    /// <inheritdoc/>
    public override void Create()
    {
        _scannerPass = new ScannerPass
        {
            renderPassEvent = passEvent
        };
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        _scannerPass.Setup(circleColor, lineColor, centerPos, width, bias, speed, maxRadius,
            isPoint, lineHor, lineVer, gridWidth, gridScale, changeSaturation, circleMinAlpha, blendIntensity);
        renderer.EnqueuePass(_scannerPass);
    }
}