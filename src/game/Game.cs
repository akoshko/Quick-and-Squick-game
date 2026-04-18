using System;
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
    private Label _p1HpLabel = default!;
    private Label _p2HpLabel = default!;

    public override void _Ready()
    {
        _player1 = GetNode<Player>("%Player1");
        _player2 = GetNode<Player>("%Player2");

        _spawn1 = GetNode<Marker2D>("%SpawnPoint1").GlobalPosition;
        _spawn2 = GetNode<Marker2D>("%SpawnPoint2").GlobalPosition;

        _partsLabel = GetNode<Label>("%PartsLabel");
        _p1HpLabel = GetNode<Label>("%P1HpLabel");
        _p2HpLabel = GetNode<Label>("%P2HpLabel");

        _player1.HpChanged += OnHpChanged;
        _player2.HpChanged += OnHpChanged;
        _player1.Died += OnPlayerDied;
        _player2.Died += OnPlayerDied;

        GetNode<Area2D>("Killzone").BodyEntered += OnKillzoneBodyEntered;

        GameManager.Instance.PartCollected += OnPartCollected;
        GameManager.Instance.AllPartsCollected += OnAllPartsCollected;
        GameManager.Instance.StateChanged += OnStateChanged;
        GameManager.Instance.Reset();

        RefreshHpLabel(_player1);
        RefreshHpLabel(_player2);
    }

    private void OnKillzoneBodyEntered(Node2D body)
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
        var player = playerIndex == 1 ? _player1 : _player2;
        RefreshHpLabel(player);
    }

    private void RefreshHpLabel(Player player)
    {
        string hearts = new string('♥', player.Hp) + new string('♡', player.MaxHp - player.Hp);
        var label = player.PlayerIndex == 1 ? _p1HpLabel : _p2HpLabel;
        label.Text = $"P{player.PlayerIndex}: {hearts}";
    }

    private void OnPlayerDied(int playerIndex)
    {
        GameManager.Instance.SetState(GameState.GameOver);
    }

    private void OnPartCollected(int total)
    {
        _partsLabel.Text = $"Детали: {total} / {GameManager.PartsNeeded}";
    }

    private void OnAllPartsCollected()
    {
        _partsLabel.Text = "Все детали собраны! Найди пирог!";
    }

    public override void _ExitTree()
    {
        GameManager.Instance.PartCollected -= OnPartCollected;
        GameManager.Instance.AllPartsCollected -= OnAllPartsCollected;
        GameManager.Instance.StateChanged -= OnStateChanged;
    }

    private void OnStateChanged(GameState newState)
    {
        switch (newState)
        {
            case GameState.Victory:
                Callable.From(() => GetTree().ChangeSceneToFile("res://src/victory_screen/VictoryScreen.tscn")).CallDeferred();
                break;
            case GameState.GameOver:
                Callable.From(() => GetTree().ChangeSceneToFile("res://src/defeat_menu/DefeatMenu.tscn")).CallDeferred();
                break;
            case GameState.Menu:
                break;
            case GameState.Playing:
                break;
            case GameState.Paused:
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(newState), newState, null);
        }
    }
}