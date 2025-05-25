using UnityEngine;

public interface IDrawable
{
    Material Material { get; }
    Transform Transform { get; }
    Mesh Mesh { get; }
}