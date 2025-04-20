using UnityEngine;

public interface IDrawable
{
    Material Material { get; set; }
    Transform Transform { get; set; }
    Mesh Mesh { get; set; }
}