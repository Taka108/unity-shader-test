using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public sealed class MetaballPass : ScriptableRenderPass
{
    private readonly int applyBloomPass;
    private readonly int applyMetaballPass;

    private readonly int downSamplingPass;
    private readonly Material metaballMaterial;
    private readonly RenderTargetHandle metaballSourceHandle;

    private readonly MaterialPropertyBlock metaballSourceProps = new();

    private readonly string profilerTag;
    private readonly IEnumerable<IDrawable> targets;
    private readonly RenderTargetHandle[] temporatyTargetHandles;
    private readonly int upSamplingPass;
    public RenderTargetIdentifier SourceIdentifier;

    public MetaballPass(
        string profilerTag,
        RenderPassEvent renderPassEvent,
        IEnumerable<IDrawable> targets,
        Material metaballMaterial,
        int blurryIterations)
    {
        this.profilerTag = profilerTag;
        this.renderPassEvent = renderPassEvent;
        this.targets = targets;
        this.metaballMaterial = metaballMaterial;

        metaballSourceHandle.Init("_MetaballSource");

        temporatyTargetHandles = new RenderTargetHandle[blurryIterations];
        for (var i = 0; i < blurryIterations; i++) temporatyTargetHandles[i].Init($"_MetaballTemp{i}");

        downSamplingPass = metaballMaterial.FindPass("DownSampling");
        upSamplingPass = metaballMaterial.FindPass("UpSampling");
        applyBloomPass = metaballMaterial.FindPass("ApplyBloom");
        applyMetaballPass = metaballMaterial.FindPass("ApplyMetaball");

        metaballSourceProps.SetInt("_StencilComp", (int)CompareFunction.Always);
    }

    private int BlurryIterations => temporatyTargetHandles.Length;

    // このメソッドは、レンダーパスを実行する前に呼び出されます。
    // レンダーターゲットとそのクリア状態を設定するために使用できます。また、一時的なレンダーターゲットテクスチャを作成するためにも使用できます。
    // 空の場合、このレンダーパスはアクティブなカメラのレンダーターゲットにレンダリングされます。
    // CommandBuffer.SetRenderTarget を呼び出さないでください。代わりに <c>ConfigureTarget</c> と <c>ConfigureClear</c> を呼び出してください。
    // レンダーパイプラインは、ターゲットのセットアップとクリアがパフォーマンスの高い方法で行われるようにします。
    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        Debug.Log("MetaballPass Configure");
    }

    // ここでレンダリングロジックを実装できます。
    // 描画コマンドを発行したり、コマンドバッファを実行したりするには、<c>ScriptableRenderContext</c> を使用します。
    // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
    // ScriptableRenderContext.submit を呼び出す必要はありません。レンダリングパイプラインがパイプラインの特定のポイントでこれを呼び出します。
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        // ターゲットがいなかったら早期リターン
        if (!targets.Any())
        {
            Debug.Log("ターゲットがいない！！");
            return;
        }

        // 新しくバッファを取得して名前をつける
        var cmd = CreateCommandBuffer(ref renderingData);

        // テンプレ。GPUにこのコマンドの実行を命じて、リリース
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public CommandBuffer CreateCommandBuffer(ref RenderingData renderingData)
    {
        // カメラの取得
        var cam = renderingData.cameraData.camera;
        Debug.Log("カメラは" + cam.gameObject.name + "を使用しております");

        // コマンドバッファを準備
        var cmd = CommandBufferPool.Get(profilerTag);
        using (new ProfilingScope(cmd, new ProfilingSampler(profilerTag)))
        {
            var targetDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            targetDescriptor.depthBufferBits = 0;

            // レンダーテクスチャ準備
            SetupRenderTexture(ref cmd, renderingData, targetDescriptor);
            // メッシュ描画
            foreach (var x in targets) DrawMesh(ref cmd, x, cam);

            // Blurring

            // Down sampling
            var currentSource = metaballSourceHandle;
            var currentDestination = temporatyTargetHandles[0];

            targetDescriptor.width /= 2;
            targetDescriptor.height /= 2;
            cmd.GetTemporaryRT(currentDestination.id, targetDescriptor, FilterMode.Bilinear);
            cmd.Blit(currentSource.id, currentDestination.id, metaballMaterial, downSamplingPass);
            cmd.ReleaseTemporaryRT(currentSource.id);

            for (var i = 1; i < BlurryIterations; i++)
            {
                currentSource = currentDestination;
                currentDestination = temporatyTargetHandles[i];

                targetDescriptor.width /= 2;
                targetDescriptor.height /= 2;
                cmd.GetTemporaryRT(currentDestination.id, targetDescriptor, FilterMode.Bilinear);
                cmd.Blit(currentSource.id, currentDestination.id, metaballMaterial, downSamplingPass);
            }

            // Up sampling
            for (var i = BlurryIterations - 2; i >= 0; i--)
            {
                currentSource = currentDestination;
                currentDestination = temporatyTargetHandles[i];

                cmd.Blit(currentSource.id, currentDestination.id, metaballMaterial, upSamplingPass);
                cmd.ReleaseTemporaryRT(currentSource.id);
            }

            // cmd.SetGlobalTexture("_MetaballSource", currentDestination.Identifier());
            cmd.Blit(currentDestination.id, SourceIdentifier, metaballMaterial, applyMetaballPass);
        }

        return cmd;
    }

    private void DrawMesh(ref CommandBuffer cmd, IDrawable drawable, Camera camera)
    {
        var pass = drawable.Material.FindPass("MetaballSource");

        if (drawable.Transform is RectTransform rectTransform)
        {
            // uguiのImageなどを想定
            var screenPos = RectTransformUtility.WorldToScreenPoint(camera, rectTransform.position);
            RectTransformUtility.ScreenPointToWorldPointInRectangle(rectTransform, screenPos, camera,
                out var worldPoint);
            var matrix = Matrix4x4.TRS(worldPoint, Quaternion.identity, rectTransform.lossyScale);
            cmd.DrawMesh(drawable.Mesh, matrix, drawable.Material, 0, pass, metaballSourceProps);
        }
        else
        {
            // それ以外を想定
            cmd.DrawMesh(drawable.Mesh, drawable.Transform.localToWorldMatrix, drawable.Material, 0, pass,
                metaballSourceProps);
        }
    }

    private void SetupRenderTexture(ref CommandBuffer cmd, RenderingData renderingData,
        RenderTextureDescriptor targetDescriptor)
    {
        // RenderTextureを取得
        // 名前IDはソースハンドルIDにしちゃう
        cmd.GetTemporaryRT(metaballSourceHandle.id, targetDescriptor, FilterMode.Bilinear);
        // 作成したレンダーテクスチャをコマンドにセット
        cmd.SetRenderTarget(metaballSourceHandle.id);
        // レンダーテクスチャのクリア
        cmd.ClearRenderTarget(true, true, Color.black, 1f);
    }

    /// このレンダリング パスの実行中に作成された割り当てられたリソースをすべてクリーンアップします。
    public override void FrameCleanup(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(metaballSourceHandle.id);
        foreach (var handle in temporatyTargetHandles) cmd.ReleaseTemporaryRT(handle.id);
    }
}