# Luanti git backups

> **Linux Only**: This mod is specifically designed for Linux/Unix environments. It utilizes `nice` and `ionice` for process prioritization. Windows is not supported.

## Introduction

A high-performance, automated snapshot system using *git* version control for Luanti worlds. This mod leverages git to provide lightweight, incremental backups of your world state with minimal impact on server performance.

## Features

- **Automated Snapshots**: Periodically saves the world state (default: every 15 minutes).
- **Low Impact**: Uses `nice` and `ionice` to ensure backup processes don't cause lag spikes for players.
- **git Hash Identification**: Every snapshot is identified by its unique git hash, making rollbacks precise and tamper-proof.
- **Easy Rollbacks**: Revert the entire world to any previous snapshot via chat command or the in-game GUI.
- **In-Game GUI**: A graphical interface for browsing, committing, and reverting snapshots without typing commands.
- **In-Game Log**: View snapshot history with hashes, timestamps, and relative ages without leaving the game.
- **Safety First**: Automatic git lock cleanup, countdown broadcast, player kick, and graceful shutdown during reverts.

## Requirements

1. **git**: Must be installed on the host system.
2. **Operating System**: Linux/Unix only (required for `nice` and `ionice`).
3. **Permissions**: Requires an **insecure environment** to execute system commands.

## Installation

1. Clone the repository into your mods folder:

```bash
git clone https://github.com/Senal-D-A-Gunaratna/luanti_git_backups.git ~/.minetest/mods/luanti_git_backups
```

2. Enable the mod in your world configuration.

3. **Required**: Add this mod under `Trusted mods` using the Luanti Settings GUi
- enable `Show advanced settings`
- go to `Developer Options` $→$ `Trusted Mods`
- add `luanti_git_backups` under `Trusted Mods`

## Updating

```bash
cd ~/.minetest/mods/luanti_git_backups
git fetch --all
git reset --hard origin/main
```

## Configuration

Use the Luanti Settings GUi
- go to the `mods` section `Luanti git backups`
*Value is in seconds. Default is 900 seconds (15 minutes)*

---

## Usage

All commands require `server` privileges.

### Chat Commands

| Command              | Alias          | Description                                                             |
| :------------------- | :------------- | :---------------------------------------------------------------------- |
| `/git commit`        | `-c`           | Manually create a world snapshot.                                       |
| `/git log`           | `-l`           | Show the last 15 snapshots with hash, timestamp, and age.               |
| `/git revert <hash>` | `-r <hash>`    | Revert the world to the specified snapshot hash and restart the server. |
| `/git gui`           | `-g`           | Open the in-game snapshot GUI.                                          |

### In-Game GUI

Open with `/git -g` or `/git gui`. Requires `server` privileges.

The GUI provides:

- **Scrollable snapshot list** showing hash, timestamp, and age for up to 50 recent snapshots.
- **Commit Snapshot** button to manually trigger a backup.
- **Revert to Selected** button — select a row then click to revert. A confirmation dialog will appear showing the hash and timestamp before anything is changed.
- **Refresh** button to reload the snapshot list.

### How Reverting Works

Whether triggered by command or GUI:

1. All players receive a warning broadcast with a 5-second countdown.
2. All connected players are kicked with a notification.
3. The world is hard-reset to the selected git commit.
4. The server shuts down automatically so the database reloads cleanly on next start.

---

## Technical Notes

- **Snapshot Identity**: Snapshots are identified by their git short hash (e.g. `a3f9c1d`). Both the chat command and GUI accept short hashes. This is more reliable than sequential numbers, which can shift after a revert.
- **Storage Efficiency**: git stores only deltas between snapshots, making it far more disk-efficient than `.zip` or `.tar` backups.
- **Auto Initialisation**: On first run the mod automatically runs `git init` in your world folder if no repository exists.
- **Lock Cleanup**: Stale `.git/index.lock` files are automatically removed before each commit to prevent backup failures.

---

## Credits & Licensing
- **Code**: Licensed under the [MIT License](LICENSE).
- **Git Logo**: Original logo by Jason Long, licensed under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/).
