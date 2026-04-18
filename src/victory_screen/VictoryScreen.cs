using Godot;

namespace QuickAndSquick.victory_screen;

public partial class VictoryScreen : Control
{
    private float _timer = 0f;
    private bool _canExit = false;
    private bool _gone = false;

    public override void _Ready()
    {
        var scoreLabel = GetNode<Label>("Center/VBox/ScoreMessage");
        int collected = GameManager.Instance.PartsCollected;
        int needed = GameManager.PartsNeeded;

        scoreLabel.Text = collected >= needed
            ? "Congrats! You collected all the parts!"
            : $"You didn't collect all the details, pay attention next time!\n({collected} / {needed})";
    }

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
