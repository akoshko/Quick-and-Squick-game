using Godot;
using QuickAndSquick.player;

namespace QuickAndSquick.enemy;

public partial class WalkingBug : CharacterBody2D
{
    [Export] public float Speed { get; set; } = 60f;
    [Export] public int Damage { get; set; } = 1;

    private float _direction = 1f;
    private float _gravity;
    private Sprite2D _sprite = default!;
    private RayCast2D _edgeCheck = default!;

    public override void _Ready()
    {
        _gravity = ProjectSettings.GetSetting("physics/2d/default_gravity").AsSingle();
        _sprite = GetNode<Sprite2D>("Sprite2D");
        _edgeCheck = GetNode<RayCast2D>("EdgeCheck");
    }

    public override void _PhysicsProcess(double delta)
    {
        var velocity = Velocity;

        if (!IsOnFloor())
        {
            velocity.Y += _gravity * (float)delta;
        }

        velocity.X = _direction * Speed;
        Velocity = velocity;
        MoveAndSlide();

        // Turn around at walls or when no floor ahead
        if (IsOnWall() || (IsOnFloor() && !_edgeCheck.IsColliding()))
        {
            TurnAround();
        }
    }

    private void TurnAround()
    {
        _direction *= -1f;
        _sprite.FlipH = _direction < 0;
        // Move EdgeCheck to always face forward
        _edgeCheck.Position = new Vector2(Mathf.Abs(_edgeCheck.Position.X) * _direction, _edgeCheck.Position.Y);
    }

    // Connected from HitBox.body_entered in scene
    public void OnHitBoxBodyEntered(Node2D body)
    {
        if (body is Player player)
        {
            player.TakeDamage(Damage);
        }
    }
}
