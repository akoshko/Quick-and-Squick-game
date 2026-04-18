using Godot;
using QuickAndSquick.player_camera;

namespace QuickAndSquick.player;

public partial class Player : CharacterBody2D
{
    [Export] public int PlayerIndex { get; set; } = 1;
    [Export] public float Speed { get; set; } = 180f;
    [Export] public float JumpVelocity { get; set; } = -400f;
    [Export] public float PowerJumpVelocity { get; set; } = -600f;
    [Export] public int MaxHp { get; set; } = 3;

    public int Hp { get; private set; }
    public bool IsDead => Hp <= 0;

    [Signal] public delegate void DiedEventHandler(int playerIndex);
    [Signal] public delegate void HpChangedEventHandler(int playerIndex, int newHp);

    private float _gravity;
    private AnimationPlayer _animPlayer = default!;
    private Sprite2D _sprite = default!;
    private CollisionShape2D _collisionShape = default!;
    private string _currentAnim = "";
    private bool _isCrouching;

    public override void _Ready()
    {
        Hp = MaxHp;
        _gravity = ProjectSettings.GetSetting("physics/2d/default_gravity").AsSingle();
        _animPlayer = GetNode<AnimationPlayer>("AnimationPlayer");
        _sprite = GetNode<Sprite2D>("Sprite2D");
        _collisionShape = GetNode<CollisionShape2D>("CollisionShape2D");
    }

    public override void _PhysicsProcess(double delta)
    {
        if (IsDead) return;
        if (GameManager.Instance?.State == GameState.Paused) return;

        var velocity = Velocity;

        if (!IsOnFloor())
        {
            velocity.Y += _gravity * (float)delta;
        }

        _isCrouching = Input.IsActionPressed(P("crouch")) && IsOnFloor();

        if (IsOnFloor() && !_isCrouching)
        {
            if (Input.IsActionJustPressed(P("jump")))
            {
                velocity.Y = JumpVelocity;
            }
            else if (Input.IsActionJustPressed(P("power_jump")))
            {
                velocity.Y = PowerJumpVelocity;
            }
        }

        float direction = 0f;
        if (!_isCrouching)
        {
            if (Input.IsActionPressed(P("left")))
            {
                direction -= 1f;
            }

            if (Input.IsActionPressed(P("right")))
            {
                direction += 1f;
            }
        }

        velocity.X = direction != 0
            ? direction * Speed
            : Mathf.MoveToward(velocity.X, 0, Speed);

        if (direction != 0)
        {
            _sprite.FlipH = direction < 0;
        }

        Velocity = velocity;
        MoveAndSlide();
        ClampToViewport();
        PlayAnimation(direction);
    }

    private void PlayAnimation(float direction)
    {
        string anim;
        if (!IsOnFloor())
        {
            anim = "jump";
        }
        else if (_isCrouching)
        {
            anim = "crouch";
        }
        else if (direction != 0)
        {
            anim = "run";
        }
        else
        {
            anim = "idle";
        }

        if (anim == _currentAnim)
        {
            return;
        }

        _currentAnim = anim;

        if (_animPlayer.HasAnimation(anim))
        {
            _animPlayer.Play(anim);
        }
        else
        {
            _animPlayer.Play("idle");
        }
    }

    public void TakeDamage(int amount = 1)
    {
        if (IsDead) return;
        Hp = Mathf.Max(0, Hp - amount);
        EmitSignal(SignalName.HpChanged, PlayerIndex, Hp);
        if (Hp <= 0)
        {
            Visible = false;
            _collisionShape.SetDeferred(CollisionShape2D.PropertyName.Disabled, true);
            SetPhysicsProcess(false);
            EmitSignal(SignalName.Died, PlayerIndex);
        }
    }

    private void ClampToViewport()
    {
        var rect = PlayerCamera.VisibleRect;
        if (rect == default) return;

        var pos = GlobalPosition;
        float margin = 8f;
        float clampedX = Mathf.Clamp(pos.X, rect.Position.X + margin, rect.End.X - margin);
        if (!Mathf.IsEqualApprox(pos.X, clampedX))
        {
            GlobalPosition = new Vector2(clampedX, pos.Y);
            Velocity = new Vector2(0, Velocity.Y);
        }
    }
    
    public void Respawn(Vector2 spawnPosition)
    {
        GlobalPosition = spawnPosition;
        Velocity = Vector2.Zero;
        TakeDamage(1);
    }

    // Returns "p1_jump", "p2_left", etc.
    private string P(string action) => $"p{PlayerIndex}_{action}";
}