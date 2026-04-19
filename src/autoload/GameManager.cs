using System;
using Godot;

namespace QuickAndSquick;

public enum GameState { Menu, Playing, Paused, GameOver, Victory }

public partial class GameManager : Node
{
    public static GameManager Instance { get; private set; } = default!;

    public GameState State { get; private set; } = GameState.Playing;
    public int PartsCollected { get; private set; }
    public const int PartsNeeded = 15;

    [Signal] public delegate void StateChangedEventHandler(GameState newState);
    [Signal] public delegate void PartCollectedEventHandler(int total);
    [Signal] public delegate void AllPartsCollectedEventHandler();

    public override void _Ready() => Instance = this;

    public void SetState(GameState newState)
    {
        State = newState;
        EmitSignal(SignalName.StateChanged, (int)newState);
    }

    public void CollectPart()
    {
        PartsCollected++;
        EmitSignal(SignalName.PartCollected, PartsCollected);
        if (PartsCollected >= PartsNeeded)
            EmitSignal(SignalName.AllPartsCollected);
    }

    public void Reset()
    {
        PartsCollected = 0;
        SetState(GameState.Playing);
    }

    public override void _Process(double delta)
    {
        for (int device = 0; device <= 1; device++)
        {
            if (Input.IsJoyButtonPressed(device, JoyButton.Back) &&
                Input.IsJoyButtonPressed(device, JoyButton.Start))
            {
                GetTree().Quit();
                return;
            }
        }
    }

    public override void _UnhandledInput(InputEvent @event)
    {
        if (!@event.IsActionPressed("pause")) return;
        switch (State)
        {
            case GameState.Playing:
                SetState(GameState.Paused);
                break;
            case GameState.Paused:
                SetState(GameState.Playing);
                break;
            case GameState.Menu:
                break;
            case GameState.GameOver:
                break;
            case GameState.Victory:
                break;
            default:
                throw new ArgumentOutOfRangeException();
        }
    }
}
