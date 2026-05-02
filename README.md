# Lunati Git Backups

A high-performance, automated version control and snapshot system for Luanti worlds. This mod leverages Git to provide lightweight, incremental backups of your world state with minimal impact on server performance.

## Features

*   **Automated Snapshots**: Periodically saves the world state (default: every 15 minutes).
*   **Low Impact**: Uses `nice` and `ionice` (on Linux) to ensure backup processes don't cause lag spikes for players.
*   **Easy Rollbacks**: Revert the entire world to a previous snapshot directly from the chat console.
*   **In-Game Logs**: View the history of your world snapshots without leaving the game.
*   **Safety First**: Automatically attempts to clear Git locks and handles world shutdowns gracefully during reverts to prevent data corruption.

## Requirements

1.  **Git**: Must be installed on the host system.
2.  **Operating System**: Designed for Linux/Unix (required for `nice` and `ionice` process prioritization).
3.  **Permissions**: This mod requires an **insecure environment** to execute system commands.

## Installation

1.  Copy the `auto_git_backup` folder into your Minetest `mods` directory.
2.  Enable the mod in your world configuration.
3.  **Crucial**: Add the mod to your `secure.trusted_mods` list in `minetest.conf`:

```conf
secure.trusted_mods = auto_git_backup
```

## Configuration

You can adjust the backup frequency by adding the following setting to your `minetest.conf`:

```conf
auto_git_backup_interval = 900
```
*(Value is in seconds. Default is 900 seconds / 15 minutes.)*

## Usage

The mod provides a central `/git` command (requires `server` privileges):

| Command            | Description                                                             |
| :----------------- | :---------------------------------------------------------------------- |
| `/git commit`      | Manually trigger a world snapshot.                                      |
| `/git log`         | Display the last 15 snapshots with timestamps.                          |
| `/git revert <id>` | Reverts the world to the specified snapshot ID and restarts the server. |

### How Reverting Works
When you issue a `/git revert` command:
1.  The mod identifies the correct Git hash based on your ID.
2.  All connected players are kicked with a notification.
3.  The world files are reset to that state.
4.  The server shuts down automatically to reload the database state.

## Technical Notes

*   **Snapshot IDs**: This mod uses simple incrementing numbers (Git commit counts) as IDs to make them easier to type in-game than long hexadecimal hashes.
*   **Storage**: Because it uses Git, only changes (deltas) are stored, making it far more disk-efficient than traditional `.zip` or `.tar` backups.
*   **Repository Initialization**: On the first run, the mod will automatically run `git init` in your world folder if a repository isn't already present.

---
*Maintained as part of the Lunati-style tool suite for Minetest.*
