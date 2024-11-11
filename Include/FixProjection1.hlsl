
inline float4x4 OrthoMatrix(float3 cameraPos, float3 objPosWS)
{
    // 正交投影矩阵 mo
    // 1/Size/Aspect, 0, 0, 0
    // 0, 1/Size, 0, 0
    // 0, 0, -2/(F-N), -(F+N)/(F-N)
    // 0, 0, 0, 1

    // unity_CameraProjection 主摄像机透视投影矩阵 mp
    // 2N/W, 0, 0, 0
    // 0, 2N/H, 0, 0
    // 0, 0, -(F+N)/(F-N), -2NF/(F-N)
    // 0, 0, -1, 0
    // 
    // UNITY_MATRIX_P 当前渲染透视投影矩阵
    // 2N/W, 0, 0, 0
    // 0, -2N/H, 0, 0
    // 0, 0, N/(F-N), NF/(F-N)
    // 0, 0, -1, 0

    float4x4 mp = unity_CameraProjection;
    float dist = -cameraPos.z;// distance(cameraPos, objPosWS);
    float mp00 = mp[0][0]; // 2N/H/Aspect = cotHA/Aspect
    float mp11 = mp[1][1]; // -2N/H=-cotHA
    float mp22 = mp[2][2];
    float mp23 = mp[2][3];

    // size = tanHA*dist
    // mo00 = 1/Size/Aspect = cotHA/dist/Aspect =m00/dist
    // mo11 = 1/size = cotHA/dist = -m11/dist
    float mo00 = mp00 / dist;
    float mo11 = mp11 / dist;
    //((f+n)^2/(f-n)^2-1)/(-2nf/(f-n)) = ((f-n)^2+4fn)/(f-n)^2-1)/(-2nf/(f-n))=(4fn/(f-n)^2)/(-2nf/(f-n)) = -2/(f-n) = mo22
    float mo22 = (mp22 * mp22 - 1) / mp23;
    float mo23 = mp22;

    return float4x4(
        float4(mo00, 0.0h, 0.0h, 0.0h),
        float4(0.0h, mo11, 0.0h, 0.0h),
        float4(0.0h, 0.0h, mo22, mo23),
        float4(0.0h, 0.0h, 0.0h, 0.0h));
}

//inline float4 fixProjection(float3 cameraPos, VertexPositionInputs vpi, float scale)
//{
//    float3 objPosWS = unity_ObjectToWorld._14_24_34;
//    float4 pWS0 = float4(objPosWS.x, 0, objPosWS.z, 1);       // 计算出物体落脚点的世界坐标
//    float4 pVS0 = mul(unity_WorldToCamera, pWS0);            // 落脚点的相机空间
//    //float4 pCS0 = mul(UNITY_MATRIX_P, pVS0);               // 修正后转回裁剪空间
//
//    float4x4 om = OrthoMatrix(cameraPos, objPosWS);          // 取得相机的正交矩阵
//    float4 fCS0 = mul(om, pVS0);                             // 用修正矩阵转换
//    float4 fpVS0 = mul(unity_CameraInvProjection, fCS0);     // 修正后转回相机空间
//    //float4 fpCS0 = mul(UNITY_MATRIX_P, fpVS0);               // 修正后转回裁剪空间
//    float4 fpWS0 = mul(unity_CameraToWorld, fpVS0);
//
//    float4 pVS = mul(unity_WorldToCamera, float4(vpi.positionWS, 1));
//    float4 fCS = mul(om, pVS);                               // 用修正矩阵转换
//    float4 fpVS = mul(unity_CameraInvProjection, fCS);       // 修正后转回相机空间
//    //float4 fpCS = mul(UNITY_MATRIX_P, fpVS);                 // 修正后转回裁剪空间
//    float4 fpWS = mul(unity_CameraToWorld, fpVS);
//
//    float4 dp = pWS0 - fpWS0;
//    float4 p = fpWS + dp;
//    //p.xyz += dp.xyz * p.w;
//
//    return lerp(vpi.positionCS, mul(UNITY_MATRIX_VP, p), 1);
//}
//
//inline float4 fixProjection(float3 cameraPos, VertexPositionInputs vpi, float scale)
//{
//    float3 objPosWS = unity_ObjectToWorld._14_24_34;
//    float4 pWS0 = float4(objPosWS.x, 0, objPosWS.z, 1);       // 计算出物体落脚点的世界坐标
//    float4 pVS0 = mul(unity_WorldToCamera, pWS0);            // 落脚点的相机空间
//    pVS0.z = -pVS0.z;
//    float4 pCS0 = mul(UNITY_MATRIX_P, pVS0);               // 修正后转回裁剪空间
//
//    float4x4 om = OrthoMatrix(cameraPos, objPosWS);          // 取得相机的正交矩阵
//    float4 fCS0 = mul(om, pVS0);                             // 用修正矩阵转换
//    float4 fpVS0 = mul(unity_CameraInvProjection, float4(fCS0.xyz, 1));     // 修正后转回相机空间
//    float4 fpCS0 = mul(UNITY_MATRIX_P, fpVS0);               // 修正后转回裁剪空间
//
//    float4 pVS = mul(unity_WorldToCamera, float4(vpi.positionWS, 1));
//    pVS.z = -pVS.z;
//    float4 fCS = mul(om, pVS);                               // 用修正矩阵转换
//    float4 fpVS = mul(unity_CameraInvProjection, float4(fCS.xyz, 1));       // 修正后转回相机空间
//    float4 fpCS = mul(UNITY_MATRIX_P, fpVS);                 // 修正后转回裁剪空间
//
//    float3 dp = (pCS0.xyz / pCS0.w - fpCS0.xyz / fpCS0.w);
//    float4 p = fpCS;
//    p.xyz += dp.xyz * p.w;
//    return lerp(vpi.positionCS, p, scale);
//}
//
//
//inline float4x4 fixProjection0(float3 cameraPos, float scale)
//{
//    // 正交投影矩阵 mo
//    // 1/Size/Aspect, 0, 0, 0
//    // 0, 1/Size, 0, 0
//    // 0, 0, -2/(F-N), -(F+N)/(F-N)
//    // 0, 0, 0, 1
//
//    // unity_CameraProjection 主摄像机透视投影矩阵 mp
//    // 2N/W, 0, 0, 0
//    // 0, 2N/H, 0, 0
//    // 0, 0, -(F+N)/(F-N), -2NF/(F-N)
//    // 0, 0, -1, 0
//    // 
//    // UNITY_MATRIX_P 当前渲染透视投影矩阵
//    // 2N/W, 0, 0, 0
//    // 0, -2N/H, 0, 0
//    // 0, 0, N/(F-N), NF/(F-N)
//    // 0, 0, -1, 0
//    float3 objPosWS = unity_ObjectToWorld._14_24_34;
//
//    float4x4 mp = UNITY_MATRIX_P;
//    float dist = distance(cameraPos, objPosWS);
//    float mp00 = mp[0][0]; // 2N/H/Aspect = cotHA/Aspect
//    float mp11 = mp[1][1]; // -2N/H=-cotHA
//    float mp22 = mp[2][2];
//    float mp23 = mp[2][3];
//
//    //size = tanHA*dist
//    // mo00 = 1/Size/Aspect = cotHA/dist/Aspect =m00/dist
//    // mo11 = 1/size = cotHA/dist = -m11/dist
//    float mo00 = mp00 / dist;
//    float mo11 = mp11 / dist;
//
//    float far = mp23 / mp22;
//    float near = mp22 * far / (1 + mp22);
//    //float near = abs(_ProjectionParams.y);
//    //float far = _ProjectionParams.z;
//    float deep = far - near;
//    float mo22 = 2 / deep;
//    float mo23 = (near + far) / deep;
//
//    return float4x4(
//        lerp(mp[0], float4(mo00, 0.0h, 0.0h, 0.0h), scale),
//        lerp(mp[1], float4(0.0h, mo11, 0.0h, 0.0h), scale),
//        lerp(mp[2], float4(0.0h, 0.0h, mo22, mo23), scale),
//        lerp(mp[3], float4(0.0h, 0.0h, 0.0h, 1.0h), scale));
//}

uniform float FixProjectionScale;
uniform float4x4 WorldToCameraMatrix;
uniform float4x4 CameraToWorldMatrix;

inline float3 fixProjection(float3 p)
{
    float3 o = unity_ObjectToWorld._14_24_34;
    float4x4 m = WorldToCameraMatrix;
    float4 o_v = mul(m, float4(o, 1));
    float4 p_v = mul(m, float4(p, 1));
    o_v /= o_v.w;
    p_v /= p_v.w;

    float3 offset = p_v.xyz - o_v.xyz;
    float offz = offset.z;
    p_v.x += p_v.x * offz * -FixProjectionScale;

    float4x4 im = CameraToWorldMatrix;
    float4 r = mul(im, p_v);
    r /= r.w;
    return r.xyz;
}

struct VertexNormal
{
    float3 vertex;
    float3 normal;
};

inline VertexNormal fixProjection(float3 p, float3 n)
{
    float3 o = unity_ObjectToWorld._14_24_34;
    float4x4 m = WorldToCameraMatrix;
    float4 o_v = mul(m, float4(o, 1));
    float4 p_v = mul(m, float4(p, 1));
    float3 n_v = mul((float3x3)m, n);
    o_v /= o_v.w;
    p_v /= p_v.w;

    float3 offset = p_v.xyz - o_v.xyz;
    float offz = offset.z;
    p_v.x -= p_v.x * offz * FixProjectionScale;
    n_v.x = lerp(n_v.x, offz * FixProjectionScale * n_v.x, FixProjectionScale*2);

    float4x4 im = CameraToWorldMatrix;
    float4 r = mul(im, p_v);
    r /= r.w;

    VertexNormal vn;
    vn.vertex = r.xyz;
    vn.normal = mul((float3x3)im, n_v);
    return vn;
}