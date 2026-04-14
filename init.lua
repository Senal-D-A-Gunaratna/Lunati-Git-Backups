local ie = minetest.request_insecure_environment()
if not ie then
    minetest.log("error", "[auto_git_backup] Mod not trusted! Check minetest.conf")
    return
end

local world_path = minetest.get_worldpath()
local timer = 0

local function shell_exec(cmd)
    local f = ie.io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s:gsub("^%s*(.-)%s*$", "%1") 
end

local function do_git_commit()
    if world_path == "" then return end
    
    -- 1. Prep the environment
    ie.os.execute("rm -f " .. world_path .. "/.git/index.lock")
    
    -- 2. Get current commit count
    local count_raw = shell_exec("cd " .. world_path .. " && git rev-list --count HEAD 2>/dev/null || echo 0")
    local count = tonumber(count_raw) or 0
    
    -- 3. Attempt the commit
    -- We use 'git commit' without --allow-empty. 
    -- If there are no changes, the exit code will be non-zero (false).
    local cmd = "cd " .. world_path .. " && git add . && nice -n 19 ionice -c 3 git commit -m '" .. count .. "'"
    local success = ie.os.execute(cmd)

    if success then
        minetest.log("action", "[auto_git_backup] Snapshot created: " .. count)
        return count
    else
        minetest.log("action", "[auto_git_backup] No changes to backup.")
        return "skipped"
    end
end

minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer >= 900 then
        timer = 0
        do_git_commit()
    end
end)

minetest.register_chatcommand("git", {
    params = "<subcommand>",
    description = "Git management",
    privs = {server = true},
    func = function(name, param)
        local args = {}
        for word in param:gmatch("%S+") do table.insert(args, word) end
        local subcommand = args[1]

        if subcommand == "commit" then
            local result = do_git_commit()
            if result == "skipped" then
                return true, "No new changes detected."
            else
                return true, "Snapshot created with ID: " .. result
            end
        elseif subcommand == "log" then
            local out = shell_exec("cd " .. world_path .. " && git log --format='%s | %ad' --date=relative -n 15")
            return true, "Last 15:\n" .. (out ~= "" and out or "No history.")
        elseif subcommand == "revert" then
            local id = args[2]
            if not id then return false, "Usage: /git revert <id>" end
            local hash = shell_exec(string.format("cd %q && git log --all --grep='^%s$' --format='%%H' -n 1", world_path, id))
            if hash == "" then return false, "ID not found." end
            ie.os.execute(string.format("cd %q && git reset --hard %s", world_path, hash))
            return true, "World reverted to " .. id .. ". RESTART NOW!"
        else
            return true, "Available: /git commit, /git log, /git revert <id>"
        end
    end,
})