-- ============================================================
--  lunati_git_backups | gui.lua
--  Formspec GUI for managing Git snapshots.
-- ============================================================

local M              = lunati_git_backups
local FORMNAME_MAIN  = "lunati_git_backups:main"
local FORMNAME_CONF  = "lunati_git_backups:confirm"

-- Stores the selected snapshot per-player pending confirmation.
local pending_revert = {}


-- ============================================================
-- SNAPSHOT FETCHER
-- ============================================================

local function get_snapshots(count)
    count = count or 50
    local raw = M.shell_exec(string.format(
        "cd %q && git log --format='%%h|%%ai|%%ar' -n %d",
        M.world_path, count
    ))

    local snapshots = {}
    for line in raw:gmatch("[^\n]+") do
        local hash, timestamp, relative = line:match("([^|]+)|([^|]+)|([^|]+)")
        if hash then
            table.insert(snapshots, {
                hash      = hash:gsub("^%s*(.-)%s*$",      "%1"),
                timestamp = timestamp:gsub("^%s*(.-)%s*$", "%1"),
                relative  = relative:gsub("^%s*(.-)%s*$",  "%1"),
            })
        end
    end
    return snapshots
end


-- ============================================================
-- FORMSPEC BUILDERS
-- ============================================================

local function build_main_form(player, snapshots)
    local W, H   = 14, 9
    local list_y = 1.3
    local list_h = H - 3.5
    local btn_y  = H - 1.9

    local cells = {}
    for _, s in ipairs(snapshots) do
        table.insert(cells, minetest.formspec_escape(s.hash))
        table.insert(cells, minetest.formspec_escape(s.timestamp))
        table.insert(cells, minetest.formspec_escape(s.relative))
    end

    return table.concat({
        "formspec_version[4]",
        string.format("size[%f,%f]", W, H),
        "bgcolor[#1a1a2e;true]",

        -- Title bar
        string.format("box[0,0;%f,0.7;#16213e]", W),
        string.format("label[0.3,0.4;%s  —  World Snapshots]",
            minetest.formspec_escape(M.MOD_TAG)),

        -- Column headers
        "label[0.3,1.0;Hash]",
        "label[3.8,1.0;Timestamp]",
        "label[10.2,1.0;Age]",
        string.format("box[0,1.2;%f,0.05;#444466]", W),

        -- Snapshot table
        string.format(
            "tablecolumns[text,width=3.2;text,width=6.1;text,width=4]" ..
            "table[0.3,%f;%f,%f;snapshot_list;%s;1]",
            list_y, W - 0.6, list_h,
            table.concat(cells, ",")
        ),

        -- Divider above buttons
        string.format("box[0,%f;%f,0.05;#444466]", H - 2.1, W),

        -- Action buttons
        string.format("button[0.3,%f;3.2,0.8;btn_commit;  Commit Snapshot]",  btn_y),
        string.format("button[3.8,%f;3.2,0.8;btn_revert;  Revert to Selected]", btn_y),
        string.format("button[7.3,%f;3.2,0.8;btn_refresh;  Refresh]",           btn_y),
        string.format("button_exit[10.8,%f;2.8,0.8;btn_close;Close]",           btn_y),
    }, "")
end

local function build_confirm_form(hash, timestamp)
    local W, H = 8, 4.5
    return table.concat({
        "formspec_version[4]",
        string.format("size[%f,%f]", W, H),
        "bgcolor[#1a1a2e;true]",

        string.format("box[0,0;%f,0.7;#16213e]", W),
        "label[0.3,0.4;Confirm Revert]",

        "label[0.3,1.3;Are you sure you want to revert to this snapshot?]",
        string.format("label[0.3,2.0;Hash:   %s]", minetest.formspec_escape(hash)),
        string.format("label[0.3,2.6;Time:   %s]", minetest.formspec_escape(timestamp)),
        string.format("label[0.3,3.2;This will restart the server and roll back all]"),
        string.format("label[0.3,3.65;world data to this point.]"),

        string.format("button[0.5,%f;3.2,0.8;btn_confirm_yes;Yes, Revert]", H - 0.9),
        string.format("button[4.3,%f;3.2,0.8;btn_confirm_no;Cancel]",       H - 0.9),
    }, "")
end


-- ============================================================
-- SHOW GUI  (exposed on namespace so init.lua can call it)
-- ============================================================

function M.show_gui(player)
    local snapshots = get_snapshots(50)
    -- Cache on player meta for row → snapshot lookup.
    player:get_meta():set_string("lgb_snapshots", minetest.serialize(snapshots))
    minetest.show_formspec(
        player:get_player_name(),
        FORMNAME_MAIN,
        build_main_form(player, snapshots)
    )
end


-- ============================================================
-- FORMSPEC INPUT HANDLER
-- ============================================================

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()

    if not minetest.check_player_privs(name, { server = true }) then return end

    -- --------------------------------------------------------
    -- MAIN FORM
    -- --------------------------------------------------------
    if formname == FORMNAME_MAIN then

        if fields.btn_refresh then
            M.show_gui(player)
            return
        end

        if fields.btn_commit then
            local short_hash, timestamp = M.do_commit()
            if short_hash == "skipped" then
                minetest.chat_send_player(name, M.MOD_TAG .. " No changes to commit.")
            else
                minetest.chat_send_player(name, string.format(
                    "%s Snapshot created — %s [%s]", M.MOD_TAG, short_hash, timestamp
                ))
            end
            M.show_gui(player)
            return
        end

        if fields.btn_revert then
            local selected_raw = fields.snapshot_list
            local row = selected_raw and tonumber(
                selected_raw:match("CHG:(%d+)") or selected_raw:match("(%d+)")
            )
            if not row then
                minetest.chat_send_player(name, M.MOD_TAG .. " Please select a snapshot first.")
                return
            end

            local snapshots = minetest.deserialize(
                player:get_meta():get_string("lgb_snapshots")
            ) or {}
            local snap = snapshots[row]
            if not snap then
                minetest.chat_send_player(name, M.MOD_TAG .. " Invalid selection.")
                return
            end

            pending_revert[name] = snap
            minetest.show_formspec(name, FORMNAME_CONF,
                build_confirm_form(snap.hash, snap.timestamp))
            return
        end

        if fields.btn_close or fields.quit then return end
    end

    -- --------------------------------------------------------
    -- CONFIRMATION DIALOG
    -- --------------------------------------------------------
    if formname == FORMNAME_CONF then

        if fields.btn_confirm_yes then
            local snap = pending_revert[name]
            pending_revert[name] = nil
            if not snap then return end
            M.do_revert(snap.hash, snap.timestamp, name)
            return
        end

        if fields.btn_confirm_no or fields.quit then
            pending_revert[name] = nil
            M.show_gui(player)
            return
        end
    end
end)
