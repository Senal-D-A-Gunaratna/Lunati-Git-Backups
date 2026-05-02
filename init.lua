local ie = minetest.request_insecure_environment()
if not ie then
    minetest.log("error", "[auto_git_backup] Mod not trusted! Check minetest.conf")
    return
end

local world_path = minetest.get_worldpath()
local timer = 0

-- Check if git repo exists, if not, initialize it
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
    ie.os.execute(string.format("rm -f %q/.git/index.lock", world_path))

    -- 2. Get current commit count
    local count_raw = shell_exec(string.format("cd %q && git rev-list --count HEAD 2>/dev/null || echo 0", world_path))
    local count = tonumber(count_raw) or 0

    -- 3. Attempt the commit
    -- We use 'git commit' without --allow-empty.
    -- If there are no changes, the exit code will be non-zero (false).
    local cmd = string.format("cd %q && git add . && nice -n 19 ionice -c 3 git commit -m %q", world_path, tostring(count))
    local success = ie.os.execute(cmd)

    if success then
        minetest.log("action", "[auto_git_backup] Snapshot created: " .. count)
        return count
    else
        minetest.log("action", "[auto_git_backup] No changes to backup.")
        return "skipped"
    end
end

local function show_force_push_dialog(name)
    local formspec = "size[6,3]" ..
        "label[1,0.5;Push failed. Would you like to force push?]" ..
        "button_exit[1,1.5;2,1;yes;Yes (Force)]" ..
        "button_exit[3,1.5;2,1;no;No (Cancel)]"
    minetest.show_formspec(name, "auto_git_backup:force_push", formspec)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
    if formname ~= "auto_git_backup:force_push" then return end

    local name = player:get_player_name()
    if fields.yes then
        minetest.chat_send_player(name, "Attempting force push...")
        local success = ie.os.execute(string.format("cd %q && git push --force", world_path))
        if success == true or success == 0 then
            minetest.chat_send_player(name, "Force push successful.")
        else
            minetest.chat_send_player(name, "Force push failed. Check server logs.")
        end
    elseif fields.no then
        minetest.chat_send_player(name, "Force push cancelled.")
    end
end)

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

        if subcommand == "push" or subcommand == "-p" then
            local success = ie.os.execute(string.format("cd %q && git push", world_path))
            if success == true or success == 0 then
                return true, "Push successful."
            end
            show_force_push_dialog(name)
            return true, "Push failed. Opening confirmation dialog..."
        elseif subcommand == "commit" or subcommand == "-c" then
            local result = do_git_commit()
            if result == "skipped" then
                return true, "No new changes detected."
            else
                return true, "Snapshot created with ID: " .. result
            end
        elseif subcommand == "log" or subcommand == "-l" then
            local out = shell_exec(string.format("cd %q && git log --format='%%s | %%ad' --date=relative -n 15", world_path))
            return true, "Last 15:\n" .. (out ~= "" and out or "No history.")
        elseif subcommand == "revert" or subcommand == "-r" then
            local id = args[2]
            if not id then return false, "Usage: /git revert <id>" end
            local hash = shell_exec(string.format("cd %q && git log --all --grep='^%s$' --format='%%H' -n 1", world_path, id))
            if hash == "" then return false, "ID not found." end
            ie.os.execute(string.format("cd %q && git reset --hard %s", world_path, hash))
            for _, player in ipairs(minetest.get_connected_players()) do
                minetest.kick_player(player:get_player_name(), "World reverted to snapshot " .. id .. ". Returning to menu.")
            end
            minetest.after(0.5, function()
                minetest.request_shutdown("Rollback complete", false)
            end)
            return true, "Reverting to " .. id .. "..."
        else
            return true, "Available: /git [-c|commit], /git [-p|push], /git [-l|log], /git [-r|revert] id"
        end
    end,
})
