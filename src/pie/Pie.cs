using Godot;
using QuickAndSquick.player;

namespace QuickAndSquick.pie;

public partial class Pie : Area2D
{
    private Label? _hintLabel;

    public override void _Ready()
    {
        CollisionMask = 1; // Player is on physics layer 1
        BodyEntered += OnBodyEntered;

        _hintLabel = GetNodeOrNull<Label>("Hint");
        GameManager.Instance.PartCollected += OnPartCollected;
        UpdateHint();
    }

    private void OnPartCollected(int total) => UpdateHint();

    private void UpdateHint()
    {
        if (_hintLabel == null) return;
        bool ready = GameManager.Instance.PartsCollected >= GameManager.PartsNeeded;
        _hintLabel.Visible = ready;
    }

    private void OnBodyEntered(Node2D body)
    {
        if (body is not Player) return;
        if (GameManager.Instance.PartsCollected < GameManager.PartsNeeded) return;
        GameManager.Instance.SetState(GameState.Victory);
    }
}
