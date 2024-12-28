using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering.Universal;


    [ExecuteInEditMode]
    public class CalculateBounds : MonoBehaviour
    {
        Bounds bounds = new Bounds();
        public Transform shadowCaster;
        public Light mainLight;
        public float shadowClipDistance = 10;
        private Matrix4x4 viewMatrix, projMatrix;

        private List<Vector3> vertexPositions = new List<Vector3>();
        private List<MeshRenderer> vertexRenderer = new List<MeshRenderer>();
        private SkinnedMeshRenderer[] skinmeshes;
        private int boundsCount;

        public HightShadowRenderFeature shadowRenderFeature;

        void Start()
        {
            Debug.Log("Start method called");
            // 获取 HightShadowRenderFeature 实例
            //shadowRenderFeature = FindObjectOfType<HightShadowRenderFeature>();
            if (shadowRenderFeature == null)
            {
                Debug.Log("HightShadowRenderFeature cant found.");
            }
            else
            {
                Debug.Log("HightShadowRenderFeature  found.");
            }
            // 获取所有 SkinnedMeshRenderer 组件并检查是否为空
            skinmeshes = shadowCaster.GetComponentsInChildren<SkinnedMeshRenderer>();

            // 如果 skinmeshes 数组为空，则进行错误处理
            if (skinmeshes == null || skinmeshes.Length == 0)
            {
                Debug.LogError("No SkinnedMeshRenderers found in shadowCaster.");
               
            }

            Debug.Log(skinmeshes.Length + " SkinnedMeshRenderers found");

            for (int i = 0; i < skinmeshes.Length; i++)
            {
                if (skinmeshes[i] != null)
                {
                    CalculateAABB(boundsCount, skinmeshes[i]);
                    boundsCount += 1;
                }
                else
                {
                    Debug.LogWarning("SkinnedMeshRenderer at index " + i + " is null.");
                }
            }

            float x = bounds.extents.x;
            float y = bounds.extents.y;
            float z = bounds.extents.z;

            vertexPositions.Add(new Vector3(x, y, z));
            vertexPositions.Add(new Vector3(x, -y, z));
            vertexPositions.Add(new Vector3(x, y, -z));
            vertexPositions.Add(new Vector3(x, -y, -z));
            vertexPositions.Add(new Vector3(-x, y, z));
            vertexPositions.Add(new Vector3(-x, -y, z));
            vertexPositions.Add(new Vector3(-x, y, -z));
            vertexPositions.Add(new Vector3(-x, -y, -z));

            for (int i = 0; i < vertexPositions.Count; i++)
            {
                vertexRenderer.Add(GameObject.CreatePrimitive(PrimitiveType.Sphere).GetComponent<MeshRenderer>());
                vertexRenderer[i].transform.position = vertexPositions[i] + bounds.center;
                vertexRenderer[i].material.SetColor("_BaseColor", Color.red);
                vertexRenderer[i].transform.localScale = new Vector3(0.1f, 0.1f, 0.1f);
            }

            UpdateMatrices();
        }

        void Update()
        {
            if (mainLight != null)
            {
                Debug.Log("mainLight is assigned");
            }
            else
            {
                Debug.Log("mainLight is not assigned");
            }

            Debug.Log("Update called");
            UpdateAABB();
            fitToScene();
            Debug.Log("viewMatrix" + viewMatrix);
            Debug.Log("projMatrix"+projMatrix);
        }

        void CalculateAABB(int boundsCount, SkinnedMeshRenderer skinmeshRender)
        {
            if (boundsCount == 0)
            {
                bounds = skinmeshRender.bounds;
            }
            else
            {
                bounds.Encapsulate(skinmeshRender.bounds);
            }

            Debug.Log(skinmeshRender.name + " is being encapsulated");
            Debug.Log(boundsCount);
        }

        public void UpdateAABB()
        {
            if (skinmeshes == null || skinmeshes.Length == 0)
            {
                Debug.LogError("No SkinnedMeshRenderers to process.");
                return;
            }

            int boundsCount = 0;
            Bounds newBounds = new Bounds();

            foreach (var skinmesh in skinmeshes)
            {
                if (skinmesh != null)
                {
                    CalculateAABB(boundsCount, skinmesh);
                    boundsCount++;
                }
                else
                {
                    Debug.LogWarning("SkinnedMeshRenderer is null in UpdateAABB.");
                }
            }

            float x = bounds.extents.x;
            float y = bounds.extents.y;
            float z = bounds.extents.z;

            // 仅在包围盒发生变化时更新顶点位置
            if (vertexPositions.Count < 8)
            {
                vertexPositions.Clear();
                AddBoundingBoxCorners(x, y, z);
            }
            else
            {
                UpdateBoundingBoxCorners(x, y, z);
            }

            for (int i = 0; i < vertexPositions.Count; i++)
            {
                vertexRenderer[i].transform.position = vertexPositions[i] + bounds.center;
                vertexRenderer[i].material.SetColor("_BaseColor", Color.cyan);
            }
        }
        // 添加包围盒角点
        private void AddBoundingBoxCorners(float x, float y, float z)
        {
            vertexPositions.Add(new Vector3(x, y, z));
            vertexPositions.Add(new Vector3(x, -y, z));
            vertexPositions.Add(new Vector3(x, y, -z));
            vertexPositions.Add(new Vector3(x, -y, -z));
            vertexPositions.Add(new Vector3(-x, y, z));
            vertexPositions.Add(new Vector3(-x, -y, z));
            vertexPositions.Add(new Vector3(-x, y, -z));
            vertexPositions.Add(new Vector3(-x, -y, -z));
        }

        // 更新包围盒角点位置
        private void UpdateBoundingBoxCorners(float x, float y, float z)
        {
            vertexPositions[0] = new Vector3(x, y, z);
            vertexPositions[1] = new Vector3(x, -y, z);
            vertexPositions[2] = new Vector3(x, y, -z);
            vertexPositions[3] = new Vector3(x, -y, -z);
            vertexPositions[4] = new Vector3(-x, y, z);
            vertexPositions[5] = new Vector3(-x, -y, z);
            vertexPositions[6] = new Vector3(-x, y, -z);
            vertexPositions[7] = new Vector3(-x, -y, -z);
        }

        public void fitToScene()
        {
           
            float xmin = float.MaxValue, xmax = float.MinValue;
            float ymin = float.MaxValue, ymax = float.MinValue;
            float zmin = float.MaxValue, zmax = float.MinValue;

            foreach (var vertex in vertexPositions)
            {
                Vector3 vertexLS = mainLight.transform.worldToLocalMatrix.MultiplyPoint(vertex);
                xmin = Mathf.Min(xmin, vertexLS.x);
                xmax = Mathf.Max(xmax, vertexLS.x);
                ymin = Mathf.Min(ymin, vertexLS.y);
                ymax = Mathf.Max(ymax, vertexLS.y);
                zmin = Mathf.Min(zmin, vertexLS.z);
                zmax = Mathf.Max(zmax, vertexLS.z);
            }

            viewMatrix = mainLight.transform.worldToLocalMatrix;

            if (SystemInfo.usesReversedZBuffer)
            {
                viewMatrix.m20 = -viewMatrix.m20;
                viewMatrix.m21 = -viewMatrix.m21;
                viewMatrix.m22 = -viewMatrix.m22;
                viewMatrix.m23 = -viewMatrix.m23;
            }

            zmax += shadowClipDistance * shadowCaster.localScale.x;

            Vector4 row0 = new Vector4(2 / (xmax - xmin), 0, 0, -(xmax + xmin) / (xmax - xmin));
            Vector4 row1 = new Vector4(0, 2 / (ymax - ymin), 0, -(ymax + ymin) / (ymax - ymin));
            Vector4 row2 = new Vector4(0, 0, -2 / (zmax - zmin), -(zmax + zmin) / (zmax - zmin));
            Vector4 row3 = new Vector4(0, 0, 0, 1);

            projMatrix.SetRow(0, row0);
            projMatrix.SetRow(1, row1);
            projMatrix.SetRow(2, row2);
            projMatrix.SetRow(3, row3);

            UpdateMatrices();
        }

        private void UpdateMatrices()
        {
            if (shadowRenderFeature != null)
            {
                Debug.Log("shadowRenderFeature is assigned");
                shadowRenderFeature.SetMatrices(viewMatrix, projMatrix);
                Debug.Log("viewMatrix10086" + viewMatrix);
                Debug.Log("projMatrix10086" +projMatrix);
                Shader.SetGlobalMatrix("_ShadowViewMatrix", viewMatrix);
                Shader.SetGlobalMatrix("_ShadowProjMatrix", projMatrix);
            }
        }

        public void OnDestroy()
        {
            // Clean up code if necessary
        }
    }

