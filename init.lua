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
-- Returns the short hash and timestamp on success, or "skipped" if nothing changed.
local function git_commit()
    if world_path == "" then return end

    -- Remove stale lock files that would block git add/commit.
    ie.os.execute(string.format("rm -f %q/.git/index.lock", world_path))

    local timestamp = ie.os.date("%Y-%m-%d %H:%M:%S")
    local message   = string.format("Backup [%s]", timestamp)

    -- nice/ionice keep the commit from causing lag spikes for players.
    local success = ie.os.execute(string.format(
        "cd %q && git add . && nice -n 19 ionice -c 3 git commit -m %q",
        world_path, message
    ))

    if success then
        local short_hash = shell_exec(string.format(
            "cd %q && git rev-parse --short HEAD",
            world_path
        ))
        log("action", string.format("Snapshot created: %s [%s]", short_hash, timestamp))
        return short_hash, timestamp
    else
        log("action", "No changes detected — snapshot skipped.")
        return "skipped"
    end
end

-- Resolves a short/full Git hash to a verified full commit hash.
local function git_find_hash(hash)
    return shell_exec(string.format(
        "cd %q && git rev-parse --verify %q 2>/dev/null",
        world_path, hash
    ))
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
    local short_hash, timestamp = git_commit()
    if short_hash == "skipped" then
        return true, "No new changes detected."
    end
    return true, string.format("Snapshot created — hash: %s  [%s]", short_hash, timestamp)
end

local function cmd_log()
    -- %h = short hash, %ai = timestamp, %ar = relative date
    local out = shell_exec(string.format(
        "cd %q && git log --format='%%h | %%ai | %%ar' -n 15",
        world_path
    ))
    return true, "Last 15 snapshots:\n" .. (out ~= "" and out or "No history found.")
end

local function cmd_revert(args)
    local input_hash = args[2]
    if not input_hash then
        return false, "Usage: /git revert <hash>"
    end

    local full_hash = git_find_hash(input_hash)
    if full_hash == "" then
        return false, "Hash '" .. input_hash .. "' not found."
    end

    local short_hash = full_hash:sub(1, 7)

    -- Get the timestamp of the target commit to show players.
    local commit_time = shell_exec(string.format(
        "cd %q && git show -s --format='%%ai' %s",
        world_path, full_hash
    ))

    -- Warn all players and count down before kicking.
    broadcast(string.format(
        "WARNING: Server reverting to %s [%s] in %d seconds!",
        short_hash, commit_time, REVERT_COUNTDOWN
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
                string.format("Server reverted to %s [%s]. Please reconnect.", short_hash, commit_time)
            )
        end

        git_reset_hard(full_hash)

        -- Short delay so kick packets flush before shutdown.
        minetest.after(0.5, function()
            minetest.request_shutdown(
                string.format("Revert to %s [%s] complete.", short_hash, commit_time),
                false
            )
        end)
    end)

    return true, string.format(
        "Revert scheduled — restoring %s [%s] in %d seconds.",
        short_hash, commit_time, REVERT_COUNTDOWN
    )
end

-- Register the /git command and route subcommands.
minetest.register_chatcommand("git", {
    params      = "<commit|log|revert> [hash]",
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
            return true, "Subcommands: commit (-c) | log (-l) | revert (-r) <hash>"
        end
    end,
})
