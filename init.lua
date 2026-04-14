local ie = minetest.request_insecure_environment()
if not ie then
    minetest.log("error", "[auto_git_backup] Mod not trusted! Add 'secure.trusted_mods = auto_git_backup' to minetest.conf")
    return
end

local world_path = minetest.get_worldpath()
local timer = 0

-- Helper to run shell commands and return output
local function shell_exec(cmd)
    local f = ie.io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s:gsub("^%s*(.-)%s*$", "%1") 
end

-- Logic to handle smart commits
local function do_git_commit(is_manual)
    if world_path == "" then return end
    
    -- 1. Remove stale locks to prevent hanging
    ie.os.execute("rm -f " .. world_path .. "/.git/index.lock")

    -- 2. Check for real changes
    -- 'git diff --cached --quiet' returns 0 (true in Lua) only if there are NO changes
    local check_cmd = "cd " .. world_path .. " && git add . && git diff --cached --quiet"
    local no_changes = ie.os.execute(check_cmd)

    if no_changes then
        local msg = "[auto_git_backup] No changes detected. Skipping commit."
        minetest.log("action", msg)
        if is_manual then minetest.chat_send_all(msg) end
        return "skipped"
    end

    -- 3. Get commit count for the ID
    local count_raw = shell_exec("cd " .. world_path .. " && git rev-list --count HEAD 2>/dev/null || echo 0")
    local count = tonumber(count_raw) or 0
    
    -- 4. Execute the commit with low system priority
    local cmd = string.format(
        "cd %q && nice -n 19 ionice -c 3 git commit -m '%d' > /dev/null 2>&1 &",
        world_path, count
    )
    
    ie.os.execute(cmd)
    return count
end

-- 15-Minute Auto-Backup Loop
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer >= 900 then
        timer = 0
        do_git_commit(false)
    end
end)

-- The /git CLI Command
minetest.register_chatcommand("git", {
    params = "<subcommand> [args]",
    description = "Git world management. Usage: /git help",
    privs = {server = true},
    func = function(name, param)
        local args = {}
        for word in param:gmatch("%S+") do table.insert(args, word) end
        local subcommand = args[1]

        if subcommand == "help" or not subcommand then
            return true, 
                "\nGIT-BACKUP(1)             Manual             GIT-BACKUP(1)\n" ..
                "\nCOMMANDS\n" ..
                "       commit    Save only if changes exist.\n" ..
                "       log       Show last 15 backups.\n" ..
                "       revert    Roll back to <id>.\n" ..
                "\nCURRENT WORLD\n" ..
                "       " .. world_path

        elseif subcommand == "commit" then
            local result = do_git_commit(true)
            if result == "skipped" then
                return true, "No changes detected since last snapshot."
            else
                return true, "Snapshot created with ID: " .. result
            end

        elseif subcommand == "log" then
            local log_cmd = string.format("cd %q && git log --format='%%s | %%ad' --date=relative -n 15", world_path)
            local output = shell_exec(log_cmd)
            return true, "Backup History (ID | Time):\n" .. (output ~= "" and output or "No history found.")

        elseif subcommand == "revert" then
            local id = args[2]
            if not id or not tonumber(id) then return false, "Usage: /git revert <id>" end

            local find_cmd = string.format("cd %q && git log --all --grep='^%s$' --format='%%H' -n 1", world_path, id)
            local hash = shell_exec(find_cmd)

            if hash == "" then return false, "Backup ID " .. id .. " not found." end

            local revert_cmd = string.format("cd %q && git reset --hard %s", world_path, hash)
            ie.os.execute(revert_cmd)
            return true, "World reverted to ID " .. id .. ". RESTART MINETEST NOW!"
        else
            return false, "Unknown subcommand. Type /git help."
        end
    end,
})