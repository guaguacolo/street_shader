// ----------------------------------------------------------------------------
// SSS/透射率助手
// ----------------------------------------------------------------------------
//#define LOG2_E 1.4427 // log2(e)
//#define PI 3.14159265359
// 计算通过物体的光的分数。
// 评估积分{0, inf}{2 * Pi * r * R(sqrt(r^2 + d^2))}，其中 R 是扩散曲线。
// 注意：'volumeAlbedo' 应该预先乘以 0.25。
// 参考：Approximate Reflectance Profiles for Efficient Subsurface Scattering by Pixar（仅限 BSSRDF）。
float3 ComputeTransmittanceDisney(float3 S, float3 volumeAlbedo, float thickness)
{
    // Thickness and SSS mask are decoupled for artists.
    // In theory, we should modify the thickness by the inverse of the mask scale of the profile.
    // thickness /= subsurfaceMask;

    float3 exp_13 = exp2(((LOG2_E * (-1.0/3.0)) * thickness) * S); // Exp[-S * t / 3]

    // Premultiply & optimize: T = (1/4 * A) * (e^(-S * t) + 3 * e^(-S * t / 3))
    return volumeAlbedo * (exp_13 * (exp_13 * exp_13 + 3));
}

// Performs sampling of the Normalized Burley diffusion profile in polar coordinates.
// The result must be multiplied by the albedo.
// 采样周围的像素然后加权平均，照亮并模糊
float3 EvalBurleyDiffusionProfile(float r, float3 S)
{
    float3 exp_13 = exp2(((LOG2_E * (-1.0/3.0)) * r) * S); // Exp[-S * r / 3]
    float3 expSum = exp_13 * (1 + exp_13 * exp_13);        // Exp[-S * r / 3] + Exp[-S * r]

    return (S * rcp(8 * PI)) * expSum; // S / (8 * Pi) * (Exp[-S * r / 3] + Exp[-S * r])
}

/// https://zero-radiance.github.io/post/sampling-diffusion/
// 在极坐标中执行归一化的Burley扩散曲线的采样。 
// 'U'是随机数（CDF的值）: [0, 1)
// rcp(s) = 1 / ShapeParam = 散射距离.
// 'r' 是采样的径向距离, s.t. (u = 0 -> r = 0) and (u = 1 -> r = Inf).
// rcp(Pdf) 是相应的PDF值的倒数。
void SampleBurleyDiffusionProfile(float u, float rcpS, out float r, out float rcpPdf)
{
    u = 1 - u; // Convert CDF to CCDF

    float g = 1 + (4 * u) * (2 * u + sqrt(1 + (4 * u) * u));
    float n = exp2(log2(g) * (-1.0/3.0));                    // g^(-1/3)
    float p = (g * n) * n;                                   // g^(+1/3)
    float c = 1 + p + n;                                     // 1 + g^(+1/3) + g^(-1/3)
    float d = (3 / LOG2_E * 2) + (3 / LOG2_E) * log2(u);     // 3 * Log[4 * u]
    float x = (3 / LOG2_E) * log2(c) - d;                    // 3 * Log[c / (4 * u)]

    // x      = s * r
    // exp_13 = Exp[-x/3] = Exp[-1/3 * 3 * Log[c / (4 * u)]]
    // exp_13 = Exp[-Log[c / (4 * u)]] = (4 * u) / c
    // exp_1  = Exp[-x] = exp_13 * exp_13 * exp_13
    // expSum = exp_1 + exp_13 = exp_13 * (1 + exp_13 * exp_13)
    // rcpExp = rcp(expSum) = c^3 / ((4 * u) * (c^2 + 16 * u^2))
    float rcpExp = ((c * c) * c) * rcp((4 * u) * ((c * c) + (4 * u) * (4 * u)));

    r      = x * rcpS;
    rcpPdf = (8 * PI * rcpS) * rcpExp; // (8 * Pi) / s / (Exp[-s * r / 3] + Exp[-s * r])
}
