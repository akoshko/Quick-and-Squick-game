using Godot;
using QuickAndSquick.player;

namespace QuickAndSquick.collectible;

public partial class ComputerPart : Area2D
{
    public override void _Ready()
    {
        CollisionMask = 1; // Player is on physics layer 1
        BodyEntered += OnBodyEntered;

        var anim = GetNodeOrNull<AnimationPlayer>("AnimationPlayer");
        if (anim?.HasAnimation("float") == true)
        {
            anim.Play("float");
        }
    }

    private void OnBodyEntered(Node2D body)
    {
        if (body is not Player) return;
        GameManager.Instance.CollectPart();
        QueueFree();
    }
}
