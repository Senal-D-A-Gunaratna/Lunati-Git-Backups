-- ==========================================
-- 1. SECURITY: Request Insecure Environment
-- ==========================================
-- This allows the mod to access system-level commands (os.execute).
-- The mod folder must be added to 'secure.trusted_mods' in minetest.conf.
local ie = minetest.request_insecure_environment()
if not ie then
    minetest.log("error", "[auto_git_backup] Mod not trusted! Check minetest.conf")
    return
end

-- ==========================================
-- 2. INITIALIZATION & CONFIGURATION
-- ==========================================
local world_path = minetest.get_worldpath()
local timer = 0
-- Loads interval from minetest.conf (default is 900 seconds / 15 minutes)
local backup_interval = tonumber(minetest.settings:get("auto_git_backup_interval")) or 900

-- Checks if a .git directory exists in the world folder.
-- If not found, it runs 'git init' and creates the first commit.
local function check_and_init_repo()
    local test_cmd = string.format("cd %q && git rev-parse --is-inside-work-tree >/dev/null 2>&1", world_path)
    local is_repo = ie.os.execute(test_cmd)
    if is_repo ~= true and is_repo ~= 0 then
        minetest.log("action", "[auto_git_backup] Git repository not found. Initializing...")
        local init_cmd = string.format("cd %q && git init && git add . && git commit -m \"Initial commit\"", world_path)
        ie.os.execute(init_cmd)
    end
end
check_and_init_repo()

-- Helper function to capture the output of shell commands (like reading commit hashes)
local function shell_exec(cmd)
    local f = ie.io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s:gsub("^%s*(.-)%s*$", "%1")
end

-- ==========================================
-- 3. THE BACKUP CORE: do_git_commit()
-- ==========================================
local function do_git_commit()
    if world_path == "" then return end

    -- Cleanup: Remove any stale git lock files that might block the backup
    ie.os.execute(string.format("rm -f %q/.git/index.lock", world_path))

    -- ID Generation: Uses the total commit count as a user-friendly Snapshot ID
    local count_raw = shell_exec(string.format("cd %q && git rev-list --count HEAD 2>/dev/null || echo 0", world_path))
    local count = tonumber(count_raw) or 0

    local timestamp = ie.os.date("%Y-%m-%d %H:%M:%S")
    local msg = string.format("Snapshot #%d [%s]", count, timestamp)

    -- PERFORMANCE: 'nice -n 19' sets lowest CPU priority.
    -- 'ionice -c 3' sets lowest disk I/O priority (Idle).
    -- This prevents the backup from causing lag spikes for players.
    local cmd = string.format("cd %q && git add . && nice -n 19 ionice -c 3 git commit -m %q", world_path, msg)
    local success = ie.os.execute(cmd)

    if success then
        minetest.log("action", "[auto_git_backup] Snapshot created: " .. count)
        return count
    else
        -- If no files were changed, Git returns a non-zero exit code.
        minetest.log("action", "[auto_git_backup] No changes to backup.")
        return "skipped"
    end
end

-- ==========================================
-- 4. AUTOMATED TIMER
-- ==========================================
-- Triggers the backup function periodically based on the config interval.
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer >= backup_interval then
        timer = 0
        do_git_commit()
    end
end)

-- ==========================================
-- 5. CHAT COMMANDS (/git)
-- ==========================================
minetest.register_chatcommand("git", {
    params = "<subcommand>",
    description = "Git management",
    privs = {server = true},
    func = function(name, param)
        local args = {}
        for word in param:gmatch("%S+") do table.insert(args, word) end
        local subcommand = args[1]

        -- SUBCOMMAND: Manual Commit
        if subcommand == "commit" or subcommand == "-c" then
            local result = do_git_commit()
            if result == "skipped" then
                return true, "No new changes detected."
            else
                return true, "Snapshot created with ID: " .. result
            end

        -- SUBCOMMAND: View History
        elseif subcommand == "log" or subcommand == "-l" then
            -- Shows the last 15 snapshots with relative dates (e.g., "5 minutes ago")
            local out = shell_exec(string.format("cd %q && git log --format='%%s | %%ad' --date=relative -n 15", world_path))
            return true, "Last 15:\n" .. (out ~= "" and out or "No history.")

        -- SUBCOMMAND: Revert / Rollback
        elseif subcommand == "revert" or subcommand == "-r" then
            local id = args[2]
            if not id then return false, "Usage: /git revert <id>" end

            -- 1. Search the Git history for a commit starting with "Snapshot #<id>"
            local hash = shell_exec(string.format("cd %q && git log --all --grep='^Snapshot #%s ' --format='%%H' -n 1", world_path, id))

            if hash == "" then return false, "ID not found." end

            -- 2. Broadcast warning with 5-second countdown
            minetest.chat_send_all("WARNING: World reverting to snapshot #" .. id .. " in 5 seconds!")

            for i = 4, 1, -1 do
                minetest.after(5 - i, function()
                    minetest.chat_send_all("Reverting in " .. i .. "...")
                end)
            end

            -- 3. After countdown: kick players, reset, then shutdown
            minetest.after(5, function()
                for _, player in ipairs(minetest.get_connected_players()) do
                    minetest.kick_player(player:get_player_name(), "World reverted to snapshot #" .. id .. ". Returning to menu.")
                end

                -- 4. Execute a Hard Reset to that commit hash (this overwrites world data)
                ie.os.execute(string.format("cd %q && git reset --hard %s", world_path, hash))

                -- 5. Safety Shutdown: The server must restart to reload the database/map
                minetest.after(0.5, function()
                    minetest.request_shutdown("Rollback complete", false)
                end)
            end)

            return true, "Reverting to snapshot #" .. id .. " in 5 seconds..."

        else
            return true, "Available: /git [-c|commit], /git [-l|log], /git [-r|revert] id"
        end
    end,
})
