using Godot;

namespace QuickAndSquick.main_menu;

public partial class MainMenu : Control
{
    private bool _starting = false;

    public override void _UnhandledInput(InputEvent @event)
    {
        if (_starting) return;
        if (!@event.IsPressed()) return;
        if (@event is InputEventKey or InputEventJoypadButton)
        {
            _starting = true;
            GetTree().ChangeSceneToFile("res://src/game/Game.tscn");
        }
    }
}
