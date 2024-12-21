using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace UnityEngine.Rendering.Universal
{
    [GenerateHLSL]
    class DiffusionProfileConstants
    {
        public const int DIFFUSION_PROFILE_COUNT      = 16; // 定义了最大配置文件数量，包括中性配置文件所占用的槽位，最大值为16。
        public const int DIFFUSION_PROFILE_NEUTRAL_ID = 0;  // 定义了中性配置文件的ID，不会导致模糊处理，其值为0
        public const int SSS_PIXELS_PER_SAMPLE        = 4;  // 定义了每个样本的像素数量，用于次表面散射处理，其值为4
    }

    enum DefaultSssSampleBudgetForQualityLevel
    {
        Low    = 20,
        Medium = 40,
        High   = 80,
        Max    = 1000
    }

    [Serializable]
    public class DiffusionProfile : IEquatable<DiffusionProfile>
    {
        public enum TexturingMode : uint
        {
            PreAndPostScatter = 0,
            PostScatter = 1
        }

        public enum TransmissionMode : uint
        {
            Regular = 0,
            ThinObject = 1
        }

        [ColorUsage(false, true)]
        public Color            scatteringDistance;         // Per color channel (no meaningful units)
        [ColorUsage(false, true)]
        public Color            transmissionTint;           // HDR color
        public TexturingMode    texturingMode;
        public TransmissionMode transmissionMode;
        public Vector2          thicknessRemap;             // X = min, Y = max (in millimeters)
        public float            worldScale;                 // Size of the world unit in meters
        public float            ior;                        // 1.4 for skin (mean ~0.028)
   
        public Vector3          shapeParam   { get; private set; }          // RGB = shape parameter: S = 1 / D
        public float            filterRadius { get; private set; }          // "以毫米为单位"
        public float            maxScatteringDistance { get; private set; } // No meaningful units

        // Unique hash used in shaders to identify the index in the diffusion profile array
        public uint             hash = 0;

        // Here we need to have one parameter in the diffusion profile parameter because the deserialization call the default constructor
        public DiffusionProfile(bool dontUseDefaultConstructor)
        {
            //初始化数据
            ResetToDefault();
        }

        public void ResetToDefault()
        {
            scatteringDistance = Color.grey;
            transmissionTint = Color.white;
            texturingMode = TexturingMode.PreAndPostScatter;
            transmissionMode = TransmissionMode.ThinObject;
            thicknessRemap = new Vector2(1f, 5f);
            worldScale = 1f;
            ior = 1.4f;   //  ior（折射率）被初始化为 1.4f（皮肤的折射率，平均值约为 0.028）
        }
        //约束参数范围 获取最大的散射距离 
        internal void Validate()
        {
            thicknessRemap.y = Mathf.Max(thicknessRemap.y, 0f);
            thicknessRemap.x = Mathf.Clamp(thicknessRemap.x, 0f, thicknessRemap.y);
            worldScale       = Mathf.Max(worldScale, 0.001f);
            ior              = Mathf.Clamp(ior, 1.0f, 2.0f);
            //获取最大的散射距离  //获得采样距离r和概率分布函数的倒数rcpPdf
            UpdateKernel();
        }

        // Ref: Approximate Reflectance Profiles for Efficient Subsurface Scattering by Pixar.
        void UpdateKernel()
        {    
            //RGB散射距离,作为参数调节
            Vector3 sd = (Vector3)(Vector4)scatteringDistance;
            // Rather inconvenient to support (S = Inf).
            shapeParam = new Vector3(Mathf.Min(16777216, 1.0f / sd.x),
                                     Mathf.Min(16777216, 1.0f / sd.y),
                                     Mathf.Min(16777216, 1.0f / sd.z));
            //通过0.997f的cdf计算出最大的散射范围
            float cdf = 0.997f;
            maxScatteringDistance = Mathf.Max(sd.x, sd.y, sd.z);
            //获得采样距离r和概率分布函数的倒数rcpPdf
            filterRadius = SampleBurleyDiffusionProfile(cdf, maxScatteringDistance);
        }

        static float DisneyProfile(float r, float s)
        {
            return s * (Mathf.Exp(-r * s) + Mathf.Exp(-r * s * (1.0f / 3.0f))) / (8.0f * Mathf.PI * r);
        }

        static float DisneyProfilePdf(float r, float s)
        {
            return r * DisneyProfile(r, s);
        }

        static float DisneyProfileCdf(float r, float s)
        {
            return 1.0f - 0.25f * Mathf.Exp(-r * s) - 0.75f * Mathf.Exp(-r * s * (1.0f / 3.0f));
        }

        static float DisneyProfileCdfDerivative1(float r, float s)
        {
            return 0.25f * s * Mathf.Exp(-r * s) * (1.0f + Mathf.Exp(r * s * (2.0f / 3.0f)));
        }

        static float DisneyProfileCdfDerivative2(float r, float s)
        {
            return (-1.0f / 12.0f) * s * s * Mathf.Exp(-r * s) * (3.0f + Mathf.Exp(r * s * (2.0f / 3.0f)));
        }

        // The CDF is not analytically invertible, so we use Halley's Method of root finding.
        // { f(r, s, p) = CDF(r, s) - p = 0 } with the initial guess { r = (10^p - 1) / s }.
        static float DisneyProfileCdfInverse(float p, float s)
        {
            // Supply the initial guess.
            float r = (Mathf.Pow(10f, p) - 1f) / s;
            float t = float.MaxValue;

            while (true)
            {
                float f0 = DisneyProfileCdf(r, s) - p;
                float f1 = DisneyProfileCdfDerivative1(r, s);
                float f2 = DisneyProfileCdfDerivative2(r, s);
                float dr = f0 / (f1 * (1f - f0 * f2 / (2f * f1 * f1)));

                if (Mathf.Abs(dr) < t)
                {
                    r = r - dr;
                    t = Mathf.Abs(dr);
                }
                else
                {
                    // Converged to the best result.
                    break;
                }
            }

            return r;
        }

        // https://zero-radiance.github.io/post/sampling-diffusion/
        // 在极坐标系下对归一化的 Burley 扩散轮廓进行采样。
        // 'u' 是随机数（CDF 的值）：[0, 1)。
        // rcp(s) = 1 / ShapeParam = ScatteringDistance。
        // 返回采样的径向距离，使得 (u = 0 -> r = 0) 和 (u = 1 -> r = Inf)。
        //获得采样距离r和概率分布函数的倒数rcpPdf
        static float SampleBurleyDiffusionProfile(float u, float rcpS)
        {
            u = 1 - u; // Convert CDF to CCDF

            float g = 1 + (4 * u) * (2 * u + Mathf.Sqrt(1 + (4 * u) * u));
            float n = Mathf.Pow(g, -1.0f/3.0f);                      // g^(-1/3)
            float p = (g * n) * n;                                   // g^(+1/3)
            float c = 1 + p + n;                                     // 1 + g^(+1/3) + g^(-1/3)
            float x = 3 * Mathf.Log(c / (4 * u));

            return x * rcpS;
        }

        public bool Equals(DiffusionProfile other)
        {
            if (other == null)
                return false;

            return  scatteringDistance == other.scatteringDistance &&
                    transmissionTint == other.transmissionTint &&
                    texturingMode == other.texturingMode &&
                    transmissionMode == other.transmissionMode &&
                    thicknessRemap == other.thicknessRemap &&
                    worldScale == other.worldScale &&
                    ior == other.ior;
        }
    }

    [CreateAssetMenu(menuName = "TA/Create Diffusion Profile Settings", fileName = "NewDiffusionProfileSettings")]
    public class DiffusionProfileSettings : ScriptableObject
    {
        //其他文件调用的  参数部分  
        [SerializeField]
        public DiffusionProfile profile;
        [NonSerialized] public   Vector4 _WorldScalesAndFilterRadiiAndThicknessRemaps;
        [NonSerialized] internal Vector4 _ShapeParamsAndMaxScatterDists;           
        [NonSerialized] internal Vector4 _TransmissionTintsAndFresnel0;         
        [NonSerialized] internal Vector4 disabled_TransmissionTintsAndFresnel0;     
        [NonSerialized] internal int updateCount;

        void OnEnable()
        {
            if (profile == null)
                profile = new DiffusionProfile(true);
            //约束参数范围 获取最大的散射距离 获得采样距离r和概率分布函数的倒数rcpPdf
            profile.Validate();
            UpdateCache();
        }


        internal void UpdateCache()
        {
            // 更新世界尺度、滤波半径和厚度重映射
            _WorldScalesAndFilterRadiiAndThicknessRemaps = new Vector4(profile.worldScale,
                                                                       profile.filterRadius,
                                                                       profile.thicknessRemap.x,
                                                                     profile.thicknessRemap.y - profile.thicknessRemap.x);
            // 更新形状参数和最大散射距离
            _ShapeParamsAndMaxScatterDists   = profile.shapeParam;
            _ShapeParamsAndMaxScatterDists.w = profile.maxScatteringDistance;
            // 将折射率（ior）转换为 Fresnel0
            float fresnel0 = (profile.ior - 1.0f) / (profile.ior + 1.0f);
                  fresnel0 *= fresnel0; // 0.028
            _TransmissionTintsAndFresnel0 = new Vector4(profile.transmissionTint.r * 0.25f, profile.transmissionTint.g * 0.25f, profile.transmissionTint.b * 0.25f, fresnel0); // Premultiplied
            disabled_TransmissionTintsAndFresnel0 = new Vector4(0.0f, 0.0f, 0.0f, fresnel0);
            updateCount++;
        }

        internal bool HasChanged(int update)
        {
            return update == updateCount;
        }

        /// <summary>
        /// Initialize the settings for the default diffusion profile.
        /// </summary>
        /// 初始化默认的扩散轮廓设置
        public void SetDefaultParams()
        {
            _WorldScalesAndFilterRadiiAndThicknessRemaps  = new Vector4(1, 0, 0, 1);
            _ShapeParamsAndMaxScatterDists                = new Vector4(16777216, 16777216, 16777216, 0);
            _TransmissionTintsAndFresnel0.w               = 0.04f; // Match DEFAULT_SPECULAR_VALUE defined in Lit.hlsl
        }
    }
}
