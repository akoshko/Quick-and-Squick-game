using Godot;

namespace QuickAndSquick.victory_screen;

public partial class VictoryScreen : Control
{
    private float _timer = 0f;
    private bool _canExit = false;
    private bool _gone = false;

    public override void _Process(double delta)
    {
        _timer += (float)delta;
        if (_timer >= 2f)
            _canExit = true;
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (!_canExit || _gone) return;
        if (!@event.IsPressed()) return;
        if (@event is InputEventKey or InputEventJoypadButton)
        {
            _gone = true;
            GameManager.Instance.Reset();
            GetTree().ChangeSceneToFile("res://src/main_menu/MainMenu.tscn");
        }
    }
}
