using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace UnityEngine.Rendering.Universal
{
    [GenerateHLSL]
    class DiffusionProfileConstants
    {
        public const int DIFFUSION_PROFILE_COUNT      = 16; // Max. number of profiles, including the slot taken by the neutral profile
        public const int DIFFUSION_PROFILE_NEUTRAL_ID = 0;  // Does not result in blurring
        public const int SSS_PIXELS_PER_SAMPLE        = 4;
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
       /* public enum TexturingMode : uint
        {
            PreAndPostScatter = 0,
            PostScatter = 1
        }

        public enum TransmissionMode : uint
        {
            Regular = 0,
            ThinObject = 1
        }
*/
        [ColorUsage(false, true)]
        public Color            scatteringDistance;         // Per color channel (no meaningful units)
        [ColorUsage(false, true)]
        public Color            transmissionTint;           // HDR color
        //public TexturingMode    texturingMode;
        //public TransmissionMode transmissionMode;
        public Vector2          thicknessRemap;             // X = min, Y = max (in millimeters)
        public float            worldScale;                 // Size of the world unit in meters
        public float            ior;                        // 1.4 for skin (mean ~0.028)

        public Vector3          shapeParam   { get; private set; }          // RGB = shape parameter: S = 1 / D
        public float            filterRadius { get; private set; }          // In millimeters
        public float            maxScatteringDistance { get; private set; } // No meaningful units

        // Unique hash used in shaders to identify the index in the diffusion profile array
        public uint             hash = 0;

        // Here we need to have one parameter in the diffusion profile parameter because the deserialization call the default constructor
        public DiffusionProfile(bool dontUseDefaultConstructor)
        {
            ResetToDefault();
        }

        public void ResetToDefault()
        {
            scatteringDistance = Color.grey;
            transmissionTint = Color.white;
            //texturingMode = TexturingMode.PreAndPostScatter;
            //transmissionMode = TransmissionMode.ThinObject;
            thicknessRemap = new Vector2(0f, 5f);
            worldScale = 1f;
            ior = 1.4f;   // 1.4 for skin (mean ~0.028)
        }

        internal void Validate()
        {
            thicknessRemap.y = Mathf.Max(thicknessRemap.y, 0f);
            thicknessRemap.x = Mathf.Clamp(thicknessRemap.x, 0f, thicknessRemap.y);
            worldScale       = Mathf.Max(worldScale, 0.001f);
            ior              = Mathf.Clamp(ior, 1.0f, 2.0f);

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
        // Performs sampling of a Normalized Burley diffusion profile in polar coordinates.
        // 'u' is the random number (the value of the CDF): [0, 1).
        // rcp(s) = 1 / ShapeParam = ScatteringDistance.
        // Returns the sampled radial distance, s.t. (u = 0 -> r = 0) and (u = 1 -> r = Inf).
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
                    //texturingMode == other.texturingMode &&
                   // transmissionMode == other.transmissionMode &&
                    thicknessRemap == other.thicknessRemap &&
                    worldScale == other.worldScale &&
                    ior == other.ior;
        }
    }

    [CreateAssetMenu(menuName = "TA/Create Diffusion Profile Settings", fileName = "NewDiffusionProfileSettings")]
    public class DiffusionProfileSettings : ScriptableObject
    {
        [SerializeField]
        public DiffusionProfile profile;
         //X = meters per world unit：世界单位的米数，表示一个世界单位对应多少米，用于在不同尺度下统一物体的比例。Y = filter radius (in mm)：过滤半径，单位为毫米，通常用于控制光照或其他效果的扩展范围。
         //Z = remap start：用于重映射的起始值，可能与材质的厚度或其他物理属性相关。W = end - start：重映射的结束值，表示某个物理值的变化范围。
        [NonSerialized] public Vector4 _WorldScalesAndFilterRadiiAndThicknessRemaps; // X = meters per world unit, Y = filter radius (in mm), Z = remap start, W = end - start
        //RGB = S = 1 / D：这里的 S 表示散射强度（通常是一个控制次表面散射效果的参数），D 表示散射距离的倒数，通常用于表示散射的强度与距离的关系。
        //A = d = RgbMax(D)：A 表示最大散射距离 d，通常用于控制散射距离的最大值。
        //该 Vector4 用于控制散射效果的形状参数及最大散射距离。
        [NonSerialized] internal Vector4 _ShapeParamsAndMaxScatterDists;                // RGB = S = 1 / D, A = d = RgbMax(D)
        //RGB = color：传输的颜色，通常用于设置物体的传输颜色（例如皮肤的色调或水的颜色等）。
        //A = fresnel0：Fresnel 方程中的 F0，表示反射率的初始值，用于控制表面光泽感，特别是在表面透明的情况下。
        //该 Vector4 用于定义物体的传输色调和 Fresnel 方程的 F0 值，影响物体的透明度和反射效果。
        [NonSerialized] internal Vector4 _TransmissionTintsAndFresnel0;                // RGB = color, A = fresnel0
        //这个字段的作用类似于 transmissionTintAndFresnel0，但是它是用于调试目的，通过将传输颜色设置为黑色（RGB = black），可以禁用传输效果。
        //这通常是用来在调试过程中去除传输效果，以便更好地观察其他渲染效果的影响。
        [NonSerialized] internal Vector4 disabled_TransmissionTintsAndFresnel0;        // RGB = black, A = fresnel0 - For debug to remove the transmission
        [NonSerialized] internal int updateCount;

        void OnEnable()
        {
            if (profile == null)
                profile = new DiffusionProfile(true);

            profile.Validate();
            UpdateCache();
        }


        internal void UpdateCache()
        {
            _WorldScalesAndFilterRadiiAndThicknessRemaps = new Vector4(profile.worldScale,
                                                                     profile.filterRadius,
                                                                     profile.thicknessRemap.x,
                                                                     profile.thicknessRemap.y - profile.thicknessRemap.x);
            _ShapeParamsAndMaxScatterDists   = profile.shapeParam;
            _ShapeParamsAndMaxScatterDists.w = profile.maxScatteringDistance;
            // Convert ior to fresnel0
            float fresnel0 = (profile.ior - 1.0f) / (profile.ior + 1.0f);
            fresnel0 *= fresnel0; // square
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
        public void SetDefaultParams()
        {
            _WorldScalesAndFilterRadiiAndThicknessRemaps = new Vector4(1, 0, 0, 1);
            _ShapeParamsAndMaxScatterDists                = new Vector4(16777216, 16777216, 16777216, 0);
            _TransmissionTintsAndFresnel0.w              = 0.04f; // Match DEFAULT_SPECULAR_VALUE defined in Lit.hlsl
        }
    }
}
