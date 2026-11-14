# Repository Guidelines

## Project Structure

This branch develops a new Godot 4.7 game. The entry scene is `src/Main.tscn`; gameplay scenes and GDScript are organized by feature under `src/` (such as `player/`, `quests/`, `npc/`, and `game/`), with related visuals kept nearby. Shared fonts and theme resources are in `assets/`. Godot-generated `.import` and `.uid` files belong beside their source assets and scripts.

## Build, Run, and Test

- `godot --path .` opens/runs the game with the installed Godot executable.
- `dotnet build` is relevant only when changing the existing .NET project or test harness; prefer GDScript for game behavior and features.
- `./coverage.sh` runs the existing GoDotTest suite and produces a coverage report; use it for .NET/test-harness changes when its prerequisites are installed.

Open `project.godot` in Godot to edit scenes, inspect imports, and test gameplay changes.

## Style and Naming

Follow the surrounding file’s formatting. GDScript functions and variables use `snake_case`; script and scene filenames follow the existing `PascalCase` pattern (for example, `VictoryScreen.gd` and `VictoryScreen.tscn`). Keep related scenes and scripts together, and use `res://` paths for project resources.

GohuFont is configured through `assets/GohuTheme.tres`. Keep MSDF enabled for small world-space text enlarged by the camera, and pass GohuFont explicitly to `draw_string` calls. Quest checkmark sizes are configured separately for the active quest panel and the “All Quests” window; after changing either size, check both panels in portrait orientation.

## Testing

Run the game in Godot after gameplay changes. For UI or asset changes, inspect the affected scene at its target aspect ratio, especially both quest panels in portrait mode. Add tests to the existing GoDotTest harness only when the change concerns its .NET code.

## Commits and Pull Requests

Recent commits use short, imperative summaries (for example, “Improve quest icon sizes in portrait mode”). Include only changes for the current task. If a file contains unrelated edits, stage only the relevant lines or hunks—for example, in `project.godot`. Pull requests should summarize the change, note how it was checked, link related issues when available, and include screenshots for visual changes.

## Configuration

Update `project.godot` and `export_presets.cfg` deliberately; they affect startup, input, rendering, and exported builds. Do not commit secrets or machine-specific settings.
