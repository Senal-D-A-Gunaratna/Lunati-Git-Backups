local ie = minetest.request_insecure_environment()
if not ie then
    minetest.log("error", "[auto_git_backup] Mod not trusted! Add 'secure.trusted_mods = auto_git_backup' to minetest.conf")
    return
end

local world_path = minetest.get_worldpath()
local timer = 0

-- Helper to run shell commands
local function shell_exec(cmd)
    local f = ie.io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s:gsub("^%s*(.-)%s*$", "%1") 
end

-- Main Logic
local function do_git_commit()
    if world_path == "" then return "Error: No world path" end
    
    -- 1. Remove stale locks
    ie.os.execute("rm -f " .. world_path .. "/.git/index.lock")

    -- 2. SMART CHECK: Check for changes
    -- Returns 0 (true in Lua) if NO changes found
    local no_changes = ie.os.execute("cd " .. world_path .. " && git add . && git diff --cached --quiet")

    if no_changes then
        minetest.log("action", "[auto_git_backup] No new changes detected.")
        return "skipped"
    end

    -- 3. Get commit count
    local count_raw = shell_exec("cd " .. world_path .. " && git rev-list --count HEAD 2>/dev/null || echo 0")
    local count = tonumber(count_raw) or 0
    
    -- 4. Execute Commit
    local cmd = string.format(
        "cd %q && ( [ ! -d .git ] && git init && git add . && git commit -m '0' || true ); " ..
        "nice -n 19 ionice -c 3 git commit -m '%d' &",
        world_path, count
    )
    
    ie.os.execute(cmd)
    return count
end

-- Timer Loop
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer >= 900 then
        timer = 0
        do_git_commit()
    end
end)

-- Chat Commands
minetest.register_chatcommand("git", {
    params = "<subcommand> [args]",
    description = "Git management. /git help",
    privs = {server = true},
    func = function(name, param)
        local args = {}
        for word in param:gmatch("%S+") do table.insert(args, word) end
        local subcommand = args[1]

        if subcommand == "help" or not subcommand then
            return true, "Commands: commit, log, revert <id>\nTarget: " .. world_path
        elseif subcommand == "commit" then
            local result = do_git_commit()
            if result == "skipped" then
                return true, "No new changes detected. Skipping backup."
            else
                return true, "Snapshot created with ID: " .. result
            end
        elseif subcommand == "log" then
            local log_cmd = string.format("cd %q && git log --format='%%s | %%ad' --date=relative -n 15", world_path)
            local output = shell_exec(log_cmd)
            return true, "Last 15 Backups:\n" .. (output ~= "" and output or "No history.")
        elseif subcommand == "revert" then
            local id = args[2]
            if not id then return false, "Usage: /git revert <id>" end
            local hash = shell_exec(string.format("cd %q && git log --all --grep='^%s$' --format='%%H' -n 1", world_path, id))
            if hash == "" then return false, "ID not found." end
            ie.os.execute(string.format("cd %q && git reset --hard %s", world_path, hash))
            return true, "Reverted to " .. id .. ". RESTART NOW!"
        end
    end,
})