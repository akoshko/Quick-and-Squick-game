using Godot;

namespace QuickAndSquick.defeat_menu;

public partial class DefeatMenu : Control
{
    private float _timer = 0f;
    private bool _canRestart = false;
    private bool _gone = false;

    public override void _Process(double delta)
    {
        _timer += (float)delta;
        if (_timer >= 1.5f)
        {
            _canRestart = true;
        }
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (!_canRestart || _gone)
        {
            return;
        }

        if (!@event.IsPressed())
        {
            return;
        }

        if (@event is InputEventKey or InputEventJoypadButton)
        {
            _gone = true;
            GameManager.Instance.Reset();
            GetTree().ChangeSceneToFile("res://src/game/Game.tscn");
        }
    }
}
