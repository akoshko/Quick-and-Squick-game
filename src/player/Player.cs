using Godot;

namespace QuickAndSquick.player;

public partial class Player : CharacterBody2D
{
	[Export] [ExportCategory("Stats")] public int Speed { get; set; } = 400;
	
	public Vector2 MoveDirection = Vector2.Zero;

	public override void _PhysicsProcess(double delta)
	{
		MovementLoop();
	}

	private void MovementLoop()
	{
		MoveDirection.X = (Input.IsActionPressed("right") ? 1 : 0) - (Input.IsActionPressed("left") ? 1 : 0);
		MoveDirection.Y = (Input.IsActionPressed("down") ? 1 : 0) - (Input.IsActionPressed("up") ? 1 : 0);
		var motion = MoveDirection.Normalized() * Speed;
		SetVelocity(motion);
		MoveAndSlide();
	}
}