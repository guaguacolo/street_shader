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

        private Material _material;

        private Gradient _circleColor;

        private Gradient CircleColor
        {
            get => _circleColor;
            set
            {
                if (_circleColor != value)
                {
                    _circleColor = value;
                    Texture2D gradientMap = new Texture2D(128, 1);
                    // gradientMap.name = "GradientMap";
                    for (int i = 0; i < 128; i++)
                    {
                        gradientMap.SetPixel(i, 0, _circleColor.Evaluate((float)i / 128.0f));
                    }

                    gradientMap.Apply();
                    _material.SetTexture(GradientTexPara, gradientMap);
                }
            }
        }

        private Color _lineColor;

        private Color LineColor
        {
            get => _lineColor;
            set
            {
                if (_lineColor != value)
                {
                    _lineColor = value;
                    _material.SetColor(LineColorPara, _lineColor);
                }
            }
        }

        private Vector3 _centerPos;

        private Vector3 CenterPos
        {
            get => _centerPos;
            set
            {
                if (_centerPos != value)
                {
                    _centerPos = value;
                    _material.SetVector(CenterPosPara, _centerPos);
                }
            }
        }

        private float _width;

        private float Width
        {
            get => _width;
            set
            {
                if (_width != value)
                {
                    _width = value;
                    _material.SetFloat(WidthPara, _width);
                }
            }
        }

        private float _bias;

        private float Bias
        {
            get => _bias;
            set
            {
                if (_bias != value)
                {
                    _bias = value;
                    _material.SetFloat(BiasPara, _bias);
                }
            }
        }

        private bool _isPoint;

        private bool IsPoint
        {
            get => _isPoint;
            set
            {
                if (_isPoint != value)
                {
                    _isPoint = value;
                    if (_isPoint)
                    {
                        _material.EnableKeyword("ISPOINT_ON");
                    }
                    else
                    {
                        _material.DisableKeyword("ISPOINT_ON");
                    }
                }
            }
        }

        private bool _lineHor;

        private bool LineHor
        {
            get => _lineHor;
            set
            {
                if (_lineHor != value)
                {
                    _lineHor = value;
                    if (_lineHor)
                    {
                        _material.EnableKeyword("LINEHOR_ON");
                    }
                    else
                    {
                        _material.DisableKeyword("LINEHOR_ON");
                    }
                }
            }
        }

        private bool _lineVer;

        private bool LineVer
        {
            get => _lineVer;
            set
            {
                if (_lineVer != value)
                {
                    _lineVer = value;
                    if (_lineVer)
                    {
                        _material.EnableKeyword("LINEVER_ON");
                    }
                    else
                    {
                        _material.DisableKeyword("LINEVER_ON");
                    }
                }
            }
        }

        private float _gridWidth;

        private float GridWidth
        {
            get => _gridWidth;
            set
            {
                if (_gridWidth != value)
                {
                    _gridWidth = value;
                    _material.SetFloat(GridWidthPara, _gridWidth);
                }
            }
        }

        private float _gridScale;

        private float GridScale
        {
            get => _gridScale;
            set
            {
                if (_gridScale != value)
                {
                    _gridScale = value;
                    _material.SetFloat(GridScalePara, _gridScale);
                }
            }
        }

        private bool _changeSaturation;

        private bool ChangeSaturation
        {
            get => _changeSaturation;
            set
            {
                if (_changeSaturation != value)
                {
                    _changeSaturation = value;
                    if (_changeSaturation)
                    {
                        _material.EnableKeyword("CHANGE_SATURATION_ON");
                    }
                    else
                    {
                        _material.DisableKeyword("CHANGE_SATURATION_ON");
                    }
                }
            }
        }

        private float _circleMinAlpha;

        private float CircleMinAlpha
        {
            get => _circleMinAlpha;
            set
            {
                if (_circleMinAlpha != value)
                {
                    _circleMinAlpha = value;
                    _material.SetFloat(CircleMinAlphaPara, _circleMinAlpha);
                }
            }
        }

        private float _blendIntensity;

        private float BlendIntensity
        {
            get => _blendIntensity;
            set
            {
                if (_blendIntensity != value)
                {
                    _blendIntensity = value;
                    _material.SetFloat(BlendIntensityPara, _blendIntensity);
                }
            }
        }

        private float _speed;

        private float Speed
        {
            get => _speed;
            set
            {
                if (_speed != value)
                {
                    _speed = value;
                    _material.SetFloat(SpeedPara, _speed);
                }
            }
        }

        private float _maxRadius;

        private float MaxRadius
        {
            get => _maxRadius;
            set
            {
                if (_maxRadius != value)
                {
                    _maxRadius = value;
                    _material.SetFloat(MaxRadiusPara, _maxRadius);
                }
            }
        }

        #endregion

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

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            ConfigureTarget(renderingData.cameraData.renderer.cameraColorTarget);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("Scan");
            int tempRT = Shader.PropertyToID("Depth2WorldPosTempRT");
            RenderTextureDescriptor desc = renderingData.cameraData.cameraTargetDescriptor;
            cmd.GetTemporaryRT(tempRT, desc);

            cmd.Blit(colorAttachment, tempRT, _material, 0);
            cmd.Blit(tempRT, colorAttachment);
            context.ExecuteCommandBuffer(cmd);

            cmd.ReleaseTemporaryRT(tempRT);
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