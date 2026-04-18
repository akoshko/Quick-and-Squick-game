using Godot;
using QuickAndSquick.player;

namespace QuickAndSquick.player_camera;

public partial class PlayerCamera : Camera2D
{
    [Export] public float SmoothSpeed { get; set; } = 6f;
    // Zoom > 1 = zoom in (things appear bigger). 3 = tiles at 16px look like 48px.
    [Export] public float ZoomLevel { get; set; } = 3f;

    private Player _player1 = default!;
    private Player _player2 = default!;

    public override void _Ready()
    {
        Zoom = Vector2.One * ZoomLevel;
        _player1 = GetNode<Player>("%Player1");
        _player2 = GetNode<Player>("%Player2");
    }

    public override void _Process(double delta)
    {
        var midpoint = (_player1.GlobalPosition + _player2.GlobalPosition) / 2f;
        GlobalPosition = GlobalPosition.Lerp(midpoint, SmoothSpeed * (float)delta);
    }
}
