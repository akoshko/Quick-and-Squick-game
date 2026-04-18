using Godot;
using QuickAndSquick.player;

namespace QuickAndSquick.player_camera;

public partial class PlayerCamera : Camera2D
{
    [Export] public float SmoothSpeed { get; set; } = 6f;
    [Export] public float ZoomLevel { get; set; } = 6f;

    public static Rect2 VisibleRect { get; private set; }

    private Player _player1 = default!;
    private Player _player2 = default!;

    public override void _Ready()
    {
        Zoom = Vector2.One * ZoomLevel;
        _player1 = GetNode<Player>("%Player1");
        _player2 = GetNode<Player>("%Player2");

        // Snap to midpoint immediately so VisibleRect is correct on frame 1
        GlobalPosition = (_player1.GlobalPosition + _player2.GlobalPosition) / 2f;
        var halfSize = GetViewportRect().Size / (2f * Zoom);
        VisibleRect = new Rect2(GlobalPosition - halfSize, halfSize * 2f);
    }

    public override void _ExitTree()
    {
        VisibleRect = default;
    }

    public override void _Process(double delta)
    {
        var midpoint = (_player1.GlobalPosition + _player2.GlobalPosition) / 2f;
        GlobalPosition = GlobalPosition.Lerp(midpoint, SmoothSpeed * (float)delta);

        var halfSize = GetViewportRect().Size / (2f * Zoom);
        VisibleRect = new Rect2(GlobalPosition - halfSize, halfSize * 2f);
    }
}
