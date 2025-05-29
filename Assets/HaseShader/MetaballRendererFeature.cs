using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public sealed class MetaballRendererFeature : ScriptableRendererFeature
{
    private static readonly HashSet<IDrawable> Targets = new();

    [SerializeField] private MetaballSettings settings = new();

    private MetaballPass metaballPass;

    public static void AddTarget(IDrawable item)
    {
        Targets.Add(item);
    }

    public static void RemoveTarget(IDrawable item)
    {
        Targets.Remove(item);
    }

    public override void Create()
    {
        Debug.Log("MetaballPass 生成");
        var metaballMaterial = CoreUtils.CreateEngineMaterial(settings.MetaballShader);
        metaballMaterial.SetTexture("_ColorRamp", settings.RampTexture);
        metaballMaterial.SetFloat("_Threshold", settings.Threshold);
        metaballMaterial.SetFloat("_LineLength", settings.LineLength);
        metaballMaterial.SetInt("_SrcBlend", (int)settings.SrcBlend);
        metaballMaterial.SetInt("_DstBlend", (int)settings.DstBlend);

        metaballPass = new MetaballPass(
            settings.ProfilerTag,
            settings.Event,
            Targets,
            metaballMaterial,
            settings.BlurryIterations);
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        Debug.Log("MetaballPass レンダラーのキューにパスを追加");
        metaballPass.SourceIdentifier = renderer.cameraColorTarget;
        renderer.EnqueuePass(metaballPass);
    }

    // ここで、レンダラーに 1 つまたは複数のレンダリング パスを挿入できます。
    // このメソッドは、カメラごとに 1 回レンダラーを設定するときに呼び出されます。
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
    }


    [Serializable]
    public sealed class MetaballSettings
    {
        public string ProfilerTag = "MetaballRenderFeature";
        public RenderPassEvent Event = RenderPassEvent.BeforeRenderingTransparents;
        public Shader MetaballShader;

        public BlendMode SrcBlend = BlendMode.SrcAlpha;
        public BlendMode DstBlend = BlendMode.OneMinusSrcAlpha;

        public Texture2D RampTexture;

        [Range(1, 16)] public int BlurryIterations = 1;

        [Range(0.001f, 1f)] public float Threshold = 0.04f;

        [Range(0f, 1f)] public float LineLength = 0.5f;
    }
}