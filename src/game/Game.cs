using System;
using Godot;

namespace QuickAndSquick.game;

public partial class Game : Control
{
  public Button TestButton { get; private set; } = default!;
  public int ButtonPresses { get; private set; }

  public override void _Ready() => TestButton = GetNode<Button>("%TestButton");

  public void OnTestButtonPressed()
  {
    ButtonPresses++;
    Console.WriteLine($"Button was presses {ButtonPresses} times");
  }
}
