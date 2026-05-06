-- ============================================================
--  auto_git_backup | gui.lua
--  Formspec GUI for managing Git snapshots.
-- ============================================================

local MOD_TAG          = "[auto_git_backup]"
local FORMNAME_MAIN    = "auto_git_backup:main"
local FORMNAME_CONFIRM = "auto_git_backup:confirm"

-- ============================================================
-- UTILITIES
-- ============================================================

local function log(level, msg)
    minetest.log(level, MOD_TAG .. " " .. msg)
end

-- Stores the selected hash per-player for the confirmation dialog.
local pending_revert = {}

-- ============================================================
-- FORMSPEC BUILDERS
-- ============================================================

-- Builds the main GUI formspec dynamically based on screen size.
local function build_main_form(player, snapshots)
    local info     = player:get_properties()
    local name     = player:get_player_name()

    -- Minetest formspecs use a fixed unit grid.
    -- We use a generous fixed size that scales well on most screens.
    local W, H     = 14, 9

    local list_h   = H - 3.5  -- height reserved for the snapshot list
    local rows     = math.floor(list_h / 0.6)

    -- Build the snapshot table rows (truncate to fit).
    local cells = {}
    for i = 1, math.min(#snapshots, rows) do
        local s = snapshots[i]
        table.insert(cells, minetest.formspec_escape(s.hash))
        table.insert(cells, minetest.formspec_escape(s.timestamp))
        table.insert(cells, minetest.formspec_escape(s.relative))
    end

    local form = table.concat({
        "formspec_version[4]",
        string.format("size[%f,%f]", W, H),
        "bgcolor[#1a1a2e;true]",

        -- Title bar
        string.format("box[0,0;%f,0.7;#16213e]", W),
        string.format("label[0.3,0.4;%s]", minetest.formspec_escape(MOD_TAG .. " World Snapshots")),

        -- Snapshot table
        string.format("label[0.3,1.0;Hash]"),
        string.format("label[3.5,1.0;Timestamp]"),
        string.format("label[9.5,1.0;Age]"),
        string.format("box[0,1.2;%f,0.05;#444466]", W),  -- divider

        string.format(
            "tablecolumns[text,width=3;text,width=6;text,width=4]" ..
            "table[0.3,1.3;%f,%f;snapshot_list;%s;1]",
            W - 0.6, list_h,
            table.concat(cells, ",")
        ),

        -- Action buttons
        string.format("box[0,%f;%f,0.05;#444466]", H - 2.1, W),  -- divider
        string.format("button[0.3,%f;3.5,0.8;btn_commit;  Commit Snapshot]",  H - 1.9),
        string.format("button[4.2,%f;3.5,0.8;btn_revert;  Revert to Selected]", H - 1.9),
        string.format("button[8.1,%f;3.5,0.8;btn_refresh; Refresh]",           H - 1.9),
        string.format("button_exit[%f,%f;1.5,0.8;btn_close;Close]", W - 1.8,  H - 1.9),
    }, "")

    return form
end

-- Builds the confirmation dialog for a revert action.
local function build_confirm_form(hash, timestamp)
    local W, H = 8, 4
    return table.concat({
        "formspec_version[4]",
        string.format("size[%f,%f]", W, H),
        "bgcolor[#1a1a2e;true]",

        string.format("box[0,0;%f,0.7;#16213e]", W),
        "label[0.3,0.4;Confirm Revert]",

        "label[0.3,1.2;Are you sure you want to revert to:]",
        string.format("label[0.3,1.8;Hash:  %s]",      minetest.formspec_escape(hash)),
        string.format("label[0.3,2.4;Time:  %s]",      minetest.formspec_escape(timestamp)),

        string.format("button[0.5,%f;3,0.8;btn_confirm_yes;Yes, Revert]", H - 1.1),
        string.format("button[4.5,%f;3,0.8;btn_confirm_no;Cancel]",       H - 1.1),
    }, "")
end

-- ============================================================
-- SNAPSHOT FETCHER
-- ============================================================

-- Fetches snapshot list from Git and returns a table of {hash, timestamp, relative}.
function auto_git_backup_get_snapshots(count)
    count = count or 20
    local raw = auto_git_backup_shell_exec(string.format(
        "cd %q && git log --format='%%h|%%ai|%%ar' -n %d",
        auto_git_backup_world_path, count
    ))

    local snapshots = {}
    for line in raw:gmatch("[^\n]+") do
        local hash, timestamp, relative = line:match("([^|]+)|([^|]+)|([^|]+)")
        if hash then
            table.insert(snapshots, {
                hash      = hash:gsub("^%s*(.-)%s*$", "%1"),
                timestamp = timestamp:gsub("^%s*(.-)%s*$", "%1"),
                relative  = relative:gsub("^%s*(.-)%s*$", "%1"),
            })
        end
    end
    return snapshots
end

-- ============================================================
-- SHOW / REFRESH GUI
-- ============================================================

function auto_git_backup_show_gui(player)
    local snapshots = auto_git_backup_get_snapshots(50)
    local form      = build_main_form(player, snapshots)
    -- Cache snapshots on the player for row → hash lookup.
    player:get_meta():set_string("agb_snapshots", minetest.serialize(snapshots))
    minetest.show_formspec(player:get_player_name(), FORMNAME_MAIN, form)
end

-- ============================================================
-- FORMSPEC RECEIVE
-- ============================================================

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()

    -- Guard: only server-privileged players.
    if not minetest.check_player_privs(name, {server = true}) then return end

    -- --------------------------------------------------------
    -- MAIN FORM
    -- --------------------------------------------------------
    if formname == FORMNAME_MAIN then

        if fields.btn_commit then
            local short_hash, timestamp = auto_git_backup_do_commit()
            if short_hash == "skipped" then
                minetest.chat_send_player(name, MOD_TAG .. " No changes to commit.")
            else
                minetest.chat_send_player(name, string.format(
                    "%s Snapshot created — %s [%s]", MOD_TAG, short_hash, timestamp
                ))
            end
            -- Refresh the list after committing.
            auto_git_backup_show_gui(player)
            return
        end

        if fields.btn_refresh then
            auto_git_backup_show_gui(player)
            return
        end

        if fields.btn_revert then
            -- Read which row is selected in the table.
            local selected_raw = fields.snapshot_list
            if not selected_raw then
                minetest.chat_send_player(name, MOD_TAG .. " Please select a snapshot first.")
                return
            end

            local row = tonumber(selected_raw:match("CHG:(%d+)") or selected_raw:match("(%d+)"))
            if not row then
                minetest.chat_send_player(name, MOD_TAG .. " Please select a snapshot first.")
                return
            end

            local snapshots = minetest.deserialize(player:get_meta():get_string("agb_snapshots")) or {}
            local snap      = snapshots[row]
            if not snap then
                minetest.chat_send_player(name, MOD_TAG .. " Invalid selection.")
                return
            end

            -- Store for confirmation dialog.
            pending_revert[name] = snap
            minetest.show_formspec(name, FORMNAME_CONFIRM, build_confirm_form(snap.hash, snap.timestamp))
            return
        end

        if fields.btn_close or fields.quit then
            return
        end
    end

    -- --------------------------------------------------------
    -- CONFIRMATION DIALOG
    -- --------------------------------------------------------
    if formname == FORMNAME_CONFIRM then

        if fields.btn_confirm_yes then
            local snap = pending_revert[name]
            pending_revert[name] = nil
            if not snap then return end

            auto_git_backup_do_revert(snap.hash, snap.timestamp, name)
            return
        end

        if fields.btn_confirm_no or fields.quit then
            pending_revert[name] = nil
            -- Return to main GUI.
            auto_git_backup_show_gui(player)
            return
        end
    end
end)
