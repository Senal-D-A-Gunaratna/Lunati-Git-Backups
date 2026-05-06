-- ============================================================
--  luanti_git_backups | init.lua
--  Automatically snapshots your Minetest world via Git.
--
--  SETUP (minetest.conf):
--    secure.trusted_mods = luanti_git_backups
--    auto_git_backup_interval = 900   (seconds, default 15 min)
-- ============================================================


-- ============================================================
-- SECTION 1: SECURITY
-- ============================================================

local ie = minetest.request_insecure_environment()
if not ie then
    minetest.log("error", "[luanti_git_backups] Mod not trusted! Add it to secure.trusted_mods in minetest.conf.")
    return
end


-- ============================================================
-- SECTION 2: NAMESPACE
-- ============================================================

luanti_git_backups = {}
local M = luanti_git_backups


-- ============================================================
-- SECTION 3: CONFIGURATION
-- ============================================================

M.MOD_TAG          = "[luanti_git_backups]"
M.world_path       = minetest.get_worldpath()
M.revert_countdown = 5

local backup_timer    = 0
local backup_interval = tonumber(minetest.settings:get("auto_git_backup_interval")) or 900


-- ============================================================
-- SECTION 4: UTILITIES
-- ============================================================

function M.shell_exec(cmd)
    local f = ie.io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s:gsub("^%s*(.-)%s*$", "%1")
end

local function log(level, msg)
    minetest.log(level, M.MOD_TAG .. " " .. msg)
end

local function broadcast(msg)
    minetest.chat_send_all(M.MOD_TAG .. " " .. msg)
end


-- ============================================================
-- SECTION 5: GIT CORE
-- ============================================================

local function git_init_if_needed()
    local cmd     = string.format("cd %q && git rev-parse --is-inside-work-tree >/dev/null 2>&1", M.world_path)
    local is_repo = ie.os.execute(cmd)
    if is_repo ~= true and is_repo ~= 0 then
        log("action", "No Git repo found — initialising...")
        ie.os.execute(string.format(
            "cd %q && git init && git add . && git commit -m \"Initial commit\"",
            M.world_path
        ))
    end
end

git_init_if_needed()
log("action", string.format("Loaded. Auto-backup every %d seconds.", backup_interval))

function M.do_commit()
    if M.world_path == "" then return "skipped" end

    ie.os.execute(string.format("rm -f %q/.git/index.lock", M.world_path))

    local timestamp = ie.os.date("%Y-%m-%d %H:%M:%S")
    local message   = string.format("Backup [%s]", timestamp)

    local success = ie.os.execute(string.format(
        "cd %q && git add . && nice -n 19 ionice -c 3 git commit -m %q",
        M.world_path, message
    ))

    if success then
        local short_hash = M.shell_exec(string.format(
            "cd %q && git rev-parse --short HEAD",
            M.world_path
        ))
        log("action", string.format("Snapshot created: %s [%s]", short_hash, timestamp))
        return short_hash, timestamp
    else
        log("action", "No changes detected — snapshot skipped.")
        return "skipped"
    end
end

local function git_find_hash(hash)
    return M.shell_exec(string.format(
        "cd %q && git rev-parse --verify %q 2>/dev/null",
        M.world_path, hash
    ))
end

local function git_reset_hard(hash)
    ie.os.execute(string.format("cd %q && git reset --hard %s", M.world_path, hash))
end

function M.do_revert(input_hash, commit_time, requester)
    local full_hash = git_find_hash(input_hash)
    if full_hash == "" then
        if requester then
            minetest.chat_send_player(requester, M.MOD_TAG .. " Hash '" .. input_hash .. "' not found.")
        end
        return false
    end

    local short_hash = full_hash:sub(1, 7)

    if not commit_time or commit_time == "" then
        commit_time = M.shell_exec(string.format(
            "cd %q && git show -s --format='%%ai' %s",
            M.world_path, full_hash
        ))
    end

    broadcast(string.format(
        "WARNING: Server reverting to %s [%s] in %d seconds!",
        short_hash, commit_time, M.revert_countdown
    ))

    for i = M.revert_countdown - 1, 1, -1 do
        minetest.after(M.revert_countdown - i, function()
            broadcast("Reverting in " .. i .. "...")
        end)
    end

    minetest.after(M.revert_countdown, function()
        for _, player in ipairs(minetest.get_connected_players()) do
            minetest.kick_player(
                player:get_player_name(),
                string.format("Server reverted to %s [%s]. Please reconnect.", short_hash, commit_time)
            )
        end

        git_reset_hard(full_hash)

        minetest.after(0.5, function()
            minetest.request_shutdown(
                string.format("Revert to %s [%s] complete.", short_hash, commit_time),
                false
            )
        end)
    end)

    return true
end


-- ============================================================
-- SECTION 6: AUTOMATED BACKUP TIMER
-- ============================================================

minetest.register_globalstep(function(dtime)
    backup_timer = backup_timer + dtime
    if backup_timer >= backup_interval then
        backup_timer = 0
        M.do_commit()
    end
end)


-- ============================================================
-- SECTION 7: CHAT COMMANDS  (/git)
-- ============================================================

local function cmd_commit()
    local short_hash, timestamp = M.do_commit()
    if short_hash == "skipped" then
        return true, "No new changes detected."
    end
    return true, string.format("Snapshot created — hash: %s  [%s]", short_hash, timestamp)
end

local function cmd_log()
    local out = M.shell_exec(string.format(
        "cd %q && git log --format='%%h | %%ai | %%ar' -n 15",
        M.world_path
    ))
    return true, "Last 15 snapshots:\n" .. (out ~= "" and out or "No history found.")
end

local function cmd_revert(args)
    local input_hash = args[2]
    if not input_hash then
        return false, "Usage: /git revert <hash>"
    end

    local ok = M.do_revert(input_hash, nil, nil)
    if not ok then
        return false, "Hash '" .. input_hash .. "' not found."
    end

    return true, string.format(
        "Revert scheduled — restoring %s in %d seconds.",
        input_hash, M.revert_countdown
    )
end

local function cmd_gui(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then return false, "Player not found." end
    M.show_gui(player)
    return true, ""
end

minetest.register_chatcommand("git", {
    params      = "<commit|log|revert|gui> [hash]",
    description = "Manage world Git snapshots",
    privs       = { server = true },
    func = function(name, param)
        local args = {}
        for word in param:gmatch("%S+") do
            table.insert(args, word)
        end

        local sub = args[1]

        if     sub == "commit" or sub == "-c"                  then return cmd_commit()
        elseif sub == "log"    or sub == "-l"                  then return cmd_log()
        elseif sub == "revert" or sub == "-r"                  then return cmd_revert(args)
        elseif sub == "gui"    or sub == "-g" or sub == "-gui" then return cmd_gui(name)
        else
            return true, "Subcommands: commit (-c) | log (-l) | revert (-r) <hash> | gui (-g)"
        end
    end,
})


-- ============================================================
-- SECTION 8: LOAD GUI
-- ============================================================

dofile(minetest.get_modpath("luanti_git_backups") .. "/gui.lua")
