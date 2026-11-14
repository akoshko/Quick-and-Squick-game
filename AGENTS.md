# Repository Guidelines

## Project Structure

This branch develops a new Godot 4.7 game. The entry scene is `src/Main.tscn`; gameplay scenes and GDScript are organized by feature under `src/` (such as `player/`, `quests/`, `npc/`, and `game/`), with related visuals kept nearby. Shared fonts and theme resources are in `assets/`. Godot-generated `.import` and `.uid` files belong beside their source assets and scripts.

## Build, Run, and Test

- `godot --path .` opens/runs the game with the installed Godot executable.
- `godot --path . -- --portrait` opens the game in a portrait window with touch controls for mobile layout checks.
- `./test/gameplay/run.sh` runs the GDScript regression suite in Godot 4.7 without opening a window. Run it from the repository root. Set `GODOT` to the executable path if Godot is outside `PATH`.
- `dotnet build` is relevant only when changing the existing .NET project or test harness; prefer GDScript for game behavior and features.
- `./coverage.sh` runs the existing GoDotTest suite and produces a coverage report; use it for .NET/test-harness changes when its prerequisites are installed.

Open `project.godot` in Godot to edit scenes, inspect imports, and test gameplay changes.

## Style and Naming

Follow the surrounding file’s formatting. GDScript functions and variables use `snake_case`; script and scene filenames follow the existing `PascalCase` pattern (for example, `VictoryScreen.gd` and `VictoryScreen.tscn`). Keep related scenes and scripts together, and use `res://` paths for project resources.

GohuFont is configured through `assets/GohuTheme.tres`. Keep MSDF enabled for small world-space text enlarged by the camera, and pass GohuFont explicitly to `draw_string` calls. Quest checkmark sizes are configured separately for the active quest panel and the “All Quests” window; after changing either size, check both panels in portrait orientation.

## Testing

Gameplay regression tests live in `test/gameplay/GameplayTests.gd`. The suite starts the current game scenes in a 390 × 844 portrait viewport and writes the test character profile to a temporary directory.

For every gameplay feature or fix, add or update tests for the changed behavior and any regression it addresses. Exercise features through the same scenes, input, or signals that the current game uses. Before marking the change ready, run the full gameplay suite with `./test/gameplay/run.sh` and resolve any failures.

Run the game in Godot after gameplay changes. For UI or asset changes, inspect the affected scene at its target aspect ratio, especially both quest panels in portrait mode. Add tests to the existing GoDotTest harness only when the change concerns its .NET code.

When restoring solid objects during gameplay, test with the player both inside the restored area and mid-step at its edge. Verify that the player can exit and resume normal movement.

When changing default NPC dialogue, check scene overrides and verify dialogue that depends on quest state.

When changing where an NPC appears or its draw order, run the scene in a Godot window with the player nearby. Visually verify that the NPC appears in the intended spot and that the sprites overlap in the intended order.

When changing the HUD or achievement notifications, use portrait mode to check that notifications do not cover the current quest, the boss health bar, or journal controls. Trigger two notifications in quick succession and verify that both appear in order, including when the journal is opened and closed between them.

Add new achievements to the shared list in `src/quests/QuestPanel.gd` and unlock them through `GameManager.unlock_achievement(id)`. For hidden achievements, verify that the title and description are revealed only after unlocking.

## Commits and Pull Requests

Recent commits use short, imperative summaries (for example, “Improve quest icon sizes in portrait mode”). Include only changes for the current task. If a file contains unrelated edits, stage only the relevant lines or hunks—for example, in `project.godot`. Pull requests should summarize the change, note how it was checked, link related issues when available, and include screenshots for visual changes.

## Configuration

Update `project.godot` and `export_presets.cfg` deliberately; they affect startup, input, rendering, and exported builds. Do not commit secrets or machine-specific settings.
