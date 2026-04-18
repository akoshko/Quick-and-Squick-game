using Godot;

namespace QuickAndSquick.splash;

public partial class SplashScreen : Control
{
    private float _timer = 0f;
    private const float Duration = 3f;
    private bool _gone = false;

    public override void _Process(double delta)
    {
        _timer += (float)delta;
        if (_timer >= Duration)
            GoToMenu();
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (@event.IsPressed())
            GoToMenu();
    }

    private void GoToMenu()
    {
        if (_gone) return;
        _gone = true;
        GetTree().ChangeSceneToFile("res://src/main_menu/MainMenu.tscn");
    }
}
