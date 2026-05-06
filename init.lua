-- ============================================================
--  auto_git_backup | init.lua
--  Automatically snapshots your Minetest world via Git.
--
--  SETUP (minetest.conf):
--    secure.trusted_mods = lunati_git_backups
--    auto_git_backup_interval = 900   (seconds, default 15 min)
-- ============================================================


-- ============================================================
-- SECTION 1: SECURITY
-- ============================================================

local ie = minetest.request_insecure_environment()
if not ie then
    minetest.log("error", "[auto_git_backup] Mod not trusted! Add it to secure.trusted_mods in minetest.conf.")
    return
end


-- ============================================================
-- SECTION 2: CONFIGURATION
-- ============================================================

local MOD_TAG          = "[auto_git_backup]"
local world_path       = minetest.get_worldpath()
local backup_timer     = 0
local backup_interval  = tonumber(minetest.settings:get("auto_git_backup_interval")) or 900
local REVERT_COUNTDOWN = 5


-- ============================================================
-- SECTION 3: UTILITIES
-- ============================================================

-- Runs a shell command and returns its trimmed stdout.
local function shell_exec(cmd)
    local f = ie.io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s:gsub("^%s*(.-)%s*$", "%1")
end

-- Shorthand logger.
local function log(level, msg)
    minetest.log(level, MOD_TAG .. " " .. msg)
end

-- Broadcasts a message to all connected players.
local function broadcast(msg)
    minetest.chat_send_all(MOD_TAG .. " " .. msg)
end


-- ============================================================
-- SECTION 4: GIT CORE
-- ============================================================

-- Initialises a Git repo in the world folder if one does not exist.
local function git_init_if_needed()
    local cmd = string.format("cd %q && git rev-parse --is-inside-work-tree >/dev/null 2>&1", world_path)
    local is_repo = ie.os.execute(cmd)
    if is_repo ~= true and is_repo ~= 0 then
        log("action", "No Git repo found — initialising...")
        ie.os.execute(string.format(
            "cd %q && git init && git add . && git commit -m \"Initial commit\"",
            world_path
        ))
    end
end

git_init_if_needed()
log("action", string.format("Loaded. Auto-backup every %d seconds.", backup_interval))

-- Creates a new Git snapshot of the world.
-- Returns the snapshot number and short hash on success, or "skipped" if nothing changed.
local function git_commit()
    if world_path == "" then return end

    -- Remove stale lock files that would block git add/commit.
    ie.os.execute(string.format("rm -f %q/.git/index.lock", world_path))

    -- Use commit count as a human-readable Snapshot ID.
    local count_raw = shell_exec(string.format(
        "cd %q && git rev-list --count HEAD 2>/dev/null || echo 0",
        world_path
    ))
    local count = tonumber(count_raw:match("%d+")) or 0

    local timestamp = ie.os.date("%Y-%m-%d %H:%M:%S")
    local message   = string.format("Snapshot #%d [%s]", count, timestamp)

    -- nice/ionice keep the commit from causing lag spikes for players.
    local success = ie.os.execute(string.format(
        "cd %q && git add . && nice -n 19 ionice -c 3 git commit -m %q",
        world_path, message
    ))

    if success then
        -- Grab the short hash of the commit we just made.
        local short_hash = shell_exec(string.format(
            "cd %q && git rev-parse --short HEAD",
            world_path
        ))
        log("action", string.format("Snapshot created: #%d (%s)", count, short_hash))
        return count, short_hash
    else
        log("action", "No changes detected — snapshot skipped.")
        return "skipped"
    end
end

-- Resolves a user-supplied identifier to a full commit hash.
-- Accepts either a Snapshot ID (e.g. "42") or a short/full Git hash.
local function git_find_hash(id)
    -- Try matching "Snapshot #<id>" in commit messages first.
    local hash = shell_exec(string.format(
        "cd %q && git log --all --grep='^Snapshot #%s ' --format='%%H' -n 1",
        world_path, id
    ))
    -- Fall back to treating the input as a raw short/full hash.
    if hash == "" then
        hash = shell_exec(string.format(
            "cd %q && git rev-parse --verify %q 2>/dev/null",
            world_path, id
        ))
    end
    return hash
end

-- Hard-resets the repo to a specific commit hash.
local function git_reset_hard(hash)
    ie.os.execute(string.format("cd %q && git reset --hard %s", world_path, hash))
end


-- ============================================================
-- SECTION 5: AUTOMATED BACKUP TIMER
-- ============================================================

minetest.register_globalstep(function(dtime)
    backup_timer = backup_timer + dtime
    if backup_timer >= backup_interval then
        backup_timer = 0
        git_commit()
    end
end)


-- ============================================================
-- SECTION 6: CHAT COMMANDS  (/git)
-- ============================================================

local function cmd_commit()
    local count, short_hash = git_commit()
    if count == "skipped" then
        return true, "No new changes detected."
    end
    return true, string.format("Snapshot created — ID: #%d  hash: %s", count, short_hash)
end

local function cmd_log()
    -- %h = short hash, %s = subject, %ad = author date
    local out = shell_exec(string.format(
        "cd %q && git log --format='%%s | %%h | %%ad' --date=relative -n 15",
        world_path
    ))
    return true, "Last 15 snapshots:\n" .. (out ~= "" and out or "No history found.")
end

local function cmd_revert(args)
    local id = args[2]
    if not id then
        return false, "Usage: /git revert <snapshot_id or hash>"
    end

    local hash = git_find_hash(id)
    if hash == "" then
        return false, "Snapshot '" .. id .. "' not found."
    end

    local short_hash = hash:sub(1, 7)

    -- Warn all players and count down before kicking.
    broadcast(string.format(
        "WARNING: Server reverting to snapshot #%s (%s) in %d seconds!",
        id, short_hash, REVERT_COUNTDOWN
    ))

    for i = REVERT_COUNTDOWN - 1, 1, -1 do
        minetest.after(REVERT_COUNTDOWN - i, function()
            broadcast("Reverting in " .. i .. "...")
        end)
    end

    -- After the countdown: kick → reset → shutdown.
    minetest.after(REVERT_COUNTDOWN, function()
        for _, player in ipairs(minetest.get_connected_players()) do
            minetest.kick_player(
                player:get_player_name(),
                string.format("Server reverted to snapshot #%s (%s). Please reconnect.", id, short_hash)
            )
        end

        git_reset_hard(hash)

        -- Short delay so kick packets flush before shutdown.
        minetest.after(0.5, function()
            minetest.request_shutdown(
                string.format("Revert to snapshot #%s (%s) complete.", id, short_hash),
                false
            )
        end)
    end)

    return true, string.format(
        "Revert scheduled — snapshot #%s (%s) restoring in %d seconds.",
        id, short_hash, REVERT_COUNTDOWN
    )
end

-- Register the /git command and route subcommands.
minetest.register_chatcommand("git", {
    params      = "<commit|log|revert> [id or hash]",
    description = "Manage world Git snapshots",
    privs       = { server = true },
    func = function(name, param)
        local args = {}
        for word in param:gmatch("%S+") do
            table.insert(args, word)
        end

        local sub = args[1]

        if     sub == "commit" or sub == "-c" then return cmd_commit()
        elseif sub == "log"    or sub == "-l" then return cmd_log()
        elseif sub == "revert" or sub == "-r" then return cmd_revert(args)
        else
            return true, "Subcommands: commit (-c) | log (-l) | revert (-r) <id or hash>"
        end
    end,
})
