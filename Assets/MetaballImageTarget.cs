using UnityEngine;
using UnityEngine.UI;

/// <summary>
///     MetaBallの対象オブジェクトとして登録するコンポーネント
/// </summary>
public class MetaballImageTarget : MonoBehaviour, IDrawable
{
    [SerializeField] private Material material;

    [SerializeField] private Image image;

    private void Start()
    {
        MetaballRendererFeature.AddTarget(this);
    }

    private void Update()
    {
    }

    private void OnDestroy()
    {
        MetaballRendererFeature.RemoveTarget(this);
    }

    public Material Material => material;

    public Transform Transform => transform;

    public Mesh Mesh => image.canvasRenderer.GetMesh();
}