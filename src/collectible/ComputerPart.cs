using Godot;
using QuickAndSquick.player;

namespace QuickAndSquick.collectible;

public partial class ComputerPart : Area2D
{
    public override void _Ready()
    {
        var anim = GetNodeOrNull<AnimationPlayer>("AnimationPlayer");
        if (anim?.HasAnimation("float") == true)
        {
            anim.Play("float");
        }
    }

    // Connected from body_entered in scene
    public void OnBodyEntered(Node2D body)
    {
        if (body is not Player) return;
        GameManager.Instance.CollectPart();
        QueueFree();
    }
}
