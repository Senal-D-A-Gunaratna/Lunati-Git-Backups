# Lunati Git Backups

**IMPORTANT**
**Linux Only**: This mod is specifically designed for Linux/Unix environments. It utilizes **nice** and **ionice** for process prioritization. Performance and compatibility on other operating systems (like Windows) are not supported.

## Introduction


### A high-performance, automated snapshot system using *git* version control for Luanti worlds. This mod leverages git to provide lightweight, incremental backups of your world state with minimal impact on server performance.

## Features

- **Automated Snapshots**: Periodically saves the world state (default: every 15 minutes).
- **Low Impact**: Uses `nice` and `ionice` (on Linux) to ensure backup processes don't cause lag spikes for players.
- **Easy Rollbacks**: Revert the entire world to a previous snapshot directly from the chat console.
- **In-Game Logs**: View the history of your world snapshots without leaving the game.
- **Safety First**: Automatically attempts to clear Git locks and handles world shutdowns gracefully during reverts to prevent data corruption.

## Requirements

1. **Git**: Must be installed on the host system.
2. **Operating System**: Designed for Linux/Unix (required for `nice` and `ionice` process prioritization).
3. **Permissions**: This mod requires an **insecure environment** to execute system commands.

## Installation

1. Clone the repository to get the mod:
```bash
git clone https://github.com/Senal-D-A-Gunaratna/lunati-git-backups.git ~/.minetest/mods/lunati-git-backups
```
this will add the `lunati-git-backups` mod into your `.minetest/mods` directory.

2. Enable the mod in your world configuration.
3. **Crucial**: Add the mod to your `secure.trusted_mods` list in `minetest.conf`:

```conf
secure.trusted_mods = lunati-git-backups
```
## Updating
To get the latest features and bug fixes:
```bash
cd ~/.minetest/mods/lunati-git-backups
git fetch --all
git reset --hard origin/main
```

## Configuration

You can adjust the backup frequency by adding the following setting to your `minetest.conf`:

```conf
auto_git_backup_interval = 900
```

_(Value is in seconds. Default is 900 seconds / 15 minutes.)_

## Usage

The mod provides a central `/git` command (requires `server` privileges):

| Command                              | Description                                                             |
| :----------------------------------- | :---------------------------------------------------------------------- |
| `/git -c` or `/git commit` or        | Manually trigger a world snapshot.                                      |
| `/git -l` or `/git log` or           | Display the last 15 snapshots with timestamps.                          |
| `/git -r <id>` or `/git revert <id>` | Reverts the world to the specified snapshot ID and restarts the server. |

### How Reverting Works

When you issue a `git -r` or `/git revert` command:

1. The mod identifies the correct Git hash based on your ID.
2. All connected players are kicked with a notification.
3. The world files are reset to that state.
4. The server shuts down automatically to reload the database state.

## Technical Notes

- **Snapshot IDs**: This mod uses simple incrementing numbers (Git commit counts) as IDs to make them easier to type in-game than long hexadecimal hashes.
- **Storage**: Because it uses Git, only changes (deltas) are stored, making it far more disk-efficient than traditional `.zip` or `.tar` backups.
- **Repository Initialization**: On the first run, the mod will automatically run `git init` in your world folder if a repository isn't already present.
- **License: MIT**
