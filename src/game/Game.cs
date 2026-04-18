using Godot;
using QuickAndSquick.player;

namespace QuickAndSquick.game;

public partial class Game : Node2D
{
    private Player _player1 = default!;
    private Player _player2 = default!;
    private Vector2 _spawn1;
    private Vector2 _spawn2;
    private Label _partsLabel = default!;

    public override void _Ready()
    {
        _player1 = GetNode<Player>("%Player1");
        _player2 = GetNode<Player>("%Player2");

        _spawn1 = GetNode<Marker2D>("%SpawnPoint1").GlobalPosition;
        _spawn2 = GetNode<Marker2D>("%SpawnPoint2").GlobalPosition;

        _partsLabel = GetNode<Label>("%PartsLabel");

        _player1.HpChanged += OnHpChanged;
        _player2.HpChanged += OnHpChanged;
        _player1.Died += OnPlayerDied;
        _player2.Died += OnPlayerDied;

        GameManager.Instance.PartCollected += OnPartCollected;
        GameManager.Instance.AllPartsCollected += OnAllPartsCollected;
        GameManager.Instance.StateChanged += OnStateChanged;
        GameManager.Instance.Reset();
    }

    // Connected from Killzone.body_entered signal in the scene
    public void OnKillzoneBodyEntered(Node2D body)
    {
        if (body == _player1)
        {
            _player1.Respawn(_spawn1);
        }
        else if (body == _player2)
        {
            _player2.Respawn(_spawn2);
        }
    }

    private void OnHpChanged(int playerIndex, int newHp)
    {
        // TODO: update HP display when Dasha has HP bar sprites
    }

    private void OnPlayerDied(int playerIndex)
    {
        if (_player1.Hp <= 0 && _player2.Hp <= 0)
        {
            GameManager.Instance.SetState(GameState.GameOver);
        }
    }

    private void OnPartCollected(int total)
    {
        _partsLabel.Text = $"Детали: {total} / {GameManager.PartsNeeded}";
    }

    private void OnAllPartsCollected()
    {
        _partsLabel.Text = "Все детали собраны! Найди пирог!";
    }

    private void OnStateChanged(GameState newState)
    {
        if (newState == GameState.Victory)
        {
            GetTree().ChangeSceneToFile("res://src/victory_screen/VictoryScreen.tscn");
        }
        else if (newState == GameState.GameOver)
        {
            GetTree().ChangeSceneToFile("res://src/defeat_menu/DefeatMenu.tscn");
        }
    }
}