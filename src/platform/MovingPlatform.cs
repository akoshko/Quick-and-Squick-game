using Godot;

namespace QuickAndSquick.platform;

public partial class MovingPlatform : AnimatableBody2D
{
    [Export] public Vector2 MoveDistance { get; set; } = new Vector2(100f, 0f);
    [Export] public float Duration { get; set; } = 2f;

    private Vector2 _start;
    private float _timer = 0f;

    public override void _Ready()
    {
        _start = GlobalPosition;
    }

    public override void _PhysicsProcess(double delta)
    {
        _timer += (float)delta;
        float t = (Mathf.Sin(_timer * Mathf.Pi / Duration) + 1f) / 2f;
        GlobalPosition = _start.Lerp(_start + MoveDistance, t);
    }
}
