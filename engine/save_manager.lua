require "love.system"

if (love.system.getOS() == 'OS X' ) and (jit.arch == 'arm64' or jit.arch == 'arm') then jit.off() end

require "love.timer"
-- require "love.thread" -- Threading model will change for web
require 'love.filesystem' -- Still needed for STR_UNPACK potentially, or local fallbacks
require "engine.object" -- Corrected path
require "engine.string_packer"
local WebAPI = require "web_api" -- Our new module for web communication

-- Global callbacks for WebAPI
-- These need to be globally accessible by the names provided to WebAPI.save_data_to_web
_G.generic_save_callback = function(success, message_or_data)
    if success then
        print("Save Manager: Save successful - " .. message_or_data)
    else
        print("Save Manager: Save failed - " .. message_or_data)
    end
    -- Potentially push to a channel if other parts of the game expect a signal
    -- For now, just logging.
end

_G.generic_load_callback = function(success, message_or_data_str)
    if success then
        if message_or_data_str then
            print("Save Manager: Load successful. Data string length: " .. #message_or_data_str)
            -- Here you would typically STR_UNPACK(message_or_data_str) and populate game state
            -- For example: local loaded_table = STR_UNPACK(message_or_data_str)
            -- G.STATE = loaded_table.STATE -- or however game state is managed
        else
            print("Save Manager: Load successful - No save data found on server.")
        end
    else
        print("Save Manager: Load failed - " .. message_or_data_str)
    end
end


-- Check if running in a web environment (Love.js sets love.system.getOS() to "Web")
local IS_WEB_ENVIRONMENT = love.system.getOS() == "Web"

-- Keep a reference to the original file-based save/load if needed for non-web or as fallback
local function original_compress_and_save(file_path, data_table)
    local save_string = type(data_table) == 'table' and STR_PACK(data_table) or data_table
    if love.data and love.data.compress then
        save_string = love.data.compress('string', 'deflate', save_string, 1)
    else
        print("Warning: love.data.compress not available. Saving uncompressed.")
    end
    love.filesystem.write(file_path, save_string)
end

local function original_get_compressed(file_path)
    local file_data_info = love.filesystem.getInfo(file_path)
    if file_data_info ~= nil then
        local file_string = love.filesystem.read(file_path)
        if file_string and file_string ~= '' then
            if string.sub(file_string, 1, 6) ~= 'return' then
                local success, decompressed_string
                if love.data and love.data.decompress then
                    success, decompressed_string = pcall(love.data.decompress, 'string', 'deflate', file_string)
                else
                    print("Warning: love.data.decompress not available. Assuming uncompressed.")
                    return file_string -- Assume it's already uncompressed STR_PACK string
                end
                if not success then return nil end
                return decompressed_string
            end
            return file_string
        end
    end
    return nil -- Return nil if file doesn't exist or is empty
end


-- The main save/load logic will now be event-driven or called directly,
-- rather than running in a continuous loop demanding from a channel.
-- The CHANNEL logic from the original file is removed for web adaptation.

-- Example of how you might trigger saves now:
-- This function would be called by the game when it wants to save progress.
function SaveProgressWeb(save_data_tables)
    if not IS_WEB_ENVIRONMENT then
        print("Save Manager: Not in web environment. Using original file save for save_progress.")
        -- Fallback to original logic (simplified example)
        local prefix_profile = (save_data_tables.SETTINGS.profile or 1)..''
        if not love.filesystem.getInfo(prefix_profile) then love.filesystem.createDirectory( prefix_profile ) end
        prefix_profile = prefix_profile..'/'
        original_compress_and_save('settings.jkr', save_data_tables.SETTINGS)
        original_compress_and_save(prefix_profile..'profile.jkr', save_data_tables.PROFILE)
        -- Meta saving would also need to be here
        print("SaveProgressWeb: Fallback save complete.")
        return
    end

    print("Save Manager: Saving progress to web...")
    if save_data_tables.SETTINGS then
        WebAPI.save_data_to_web('settings', STR_PACK(save_data_tables.SETTINGS), "_G.generic_save_callback")
    end
    if save_data_tables.PROFILE then
        local profile_id = "profile" .. (save_data_tables.SETTINGS.profile or 1)
        WebAPI.save_data_to_web(profile_id, STR_PACK(save_data_tables.PROFILE), "_G.generic_save_callback")
    end
    -- Example for meta data (UDA) - this needs careful handling due to its read-modify-write nature
    -- For simplicity, direct save of meta is omitted here but would involve loading first, modifying, then saving.
end

function SaveRunWeb(profile_num, run_table)
    if not IS_WEB_ENVIRONMENT then
        print("Save Manager: Not in web environment. Using original file save for save_run.")
        local prefix_profile = (profile_num or 1)..''
        if not love.filesystem.getInfo(prefix_profile) then love.filesystem.createDirectory( prefix_profile ) end
        prefix_profile = prefix_profile..'/'
        original_compress_and_save(prefix_profile..'save.jkr', run_table)
        print("SaveRunWeb: Fallback save complete.")
        return
    end

    print("Save Manager: Saving run to web...")
    local run_id = "run_profile" .. (profile_num or 1)
    WebAPI.save_data_to_web(run_id, STR_PACK(run_table), "_G.generic_save_callback")
end

-- Example Load function (to be called by game logic)
-- identifier: e.g., 'run_profile1', 'settings'
-- user_callback: function(success, lua_table_or_error_msg) that will receive the STR_UNPACKed data
function LoadDataWeb(identifier, user_callback_name_str)
    if not IS_WEB_ENVIRONMENT then
        print("Save Manager: Not in web environment. Using original file load for: " .. identifier)
        -- Fallback to original loading logic
        local file_path = identifier .. ".jkr" -- This mapping needs to be robust
        if identifier:find("run_profile") then
            local profile_num = identifier:match("run_profile(%d+)")
            file_path = (profile_num or "1") .. "/save.jkr"
        elseif identifier == "settings" then
            file_path = "settings.jkr"
        end

        local data_str = original_get_compressed(file_path)
        if data_str then
            local data_table = STR_UNPACK(data_str)
            if _G[user_callback_name_str] then _G[user_callback_name_str](true, data_table) end
        else
            if _G[user_callback_name_str] then _G[user_callback_name_str](false, "Failed to load from file or file not found.") end
        end
        return
    end

    print("Save Manager: Loading '" .. identifier .. "' from web...")
    -- The actual callback for WebAPI.load_data_from_web will be generic_load_callback,
    -- which then needs to call the user_callback with the unpacked data.
    -- This requires a bit more sophisticated callback handling in WebAPI or here.

    -- For now, let's make a specific load callback that then calls the user_callback
    local temp_load_cb_name = "_G.temp_specific_load_cb_" .. identifier
    _G[temp_load_cb_name:gsub("[%.%s]", "_")] = function(success, data_str_or_error)
        if success then
            if data_str_or_error then
                local data_table = STR_UNPACK(data_str_or_error)
                if _G[user_callback_name_str] then _G[user_callback_name_str](true, data_table) end
            else
                 if _G[user_callback_name_str] then _G[user_callback_name_str](true, nil) end -- No data found
            end
        else
            if _G[user_callback_name_str] then _G[user_callback_name_str](false, data_str_or_error) end
        end
        _G[temp_load_cb_name:gsub("[%.%s]", "_")] = nil -- Clean up temporary callback
    end
    WebAPI.load_data_from_web(identifier, temp_load_cb_name:gsub("[%.%s]", "_"))
end


-- The old threaded model is removed. The game must now call functions like
-- G.SaveManager.SaveRunWeb(profile_num, G.GAME) when it needs to save.
-- And G.SaveManager.LoadDataWeb('run_profile1', "_G.my_game_load_handler") when it needs to load.

-- The original file's loop `while true do ... CHANNEL:demand() ... end` is no longer suitable
-- for a web environment and has been removed. The responsibility to trigger saves
-- and handle loads is now shifted to the main game logic, calling these new functions.

-- It's important to find where the game currently triggers saves (i.e., puts requests onto the CHANNEL)
-- and replace those calls with direct calls to G.SaveManager.SaveProgressWeb, G.SaveManager.SaveRunWeb, etc.
-- Similarly, initial game loading needs to be adapted to use G.SaveManager.LoadDataWeb.

-- Expose functions for global access
G.SaveManager = {
    SaveProgressWeb = SaveProgressWeb,
    SaveRunWeb = SaveRunWeb,
    LoadDataWeb = LoadDataWeb,
    -- Potentially add more specific save/load functions if needed e.g. for settings, profile, meta separately
    SaveSettingsWeb = function(settings_table)
        if not IS_WEB_ENVIRONMENT then
            print("Save Manager: Not in web environment. Using original file save for settings.")
            original_compress_and_save('settings.jkr', settings_table)
            return
        end
        WebAPI.save_data_to_web('settings', STR_PACK(settings_table), "_G.generic_save_callback")
    end,
    SaveProfileWeb = function(profile_num, profile_table)
        if not IS_WEB_ENVIRONMENT then
            print("Save Manager: Not in web environment. Using original file save for profile " .. profile_num)
            local prefix_profile = (profile_num or 1)..''
            if not love.filesystem.getInfo(prefix_profile) then love.filesystem.createDirectory( prefix_profile ) end
            prefix_profile = prefix_profile..'/'
            original_compress_and_save(prefix_profile..'profile.jkr', profile_table)
            return
        end
        WebAPI.save_data_to_web('profile'..profile_num, STR_PACK(profile_table), "_G.generic_save_callback")
    end,
    SaveMetaWeb = function(profile_num, meta_table)
        if not IS_WEB_ENVIRONMENT then
            print("Save Manager: Not in web environment. Using original file save for meta " .. profile_num)
            local prefix_profile = (profile_num or 1)..''
            if not love.filesystem.getInfo(prefix_profile) then love.filesystem.createDirectory( prefix_profile ) end
            prefix_profile = prefix_profile..'/'
            original_compress_and_save(prefix_profile..'meta.jkr', meta_table)
            return
        end
        WebAPI.save_data_to_web('meta'..profile_num, STR_PACK(meta_table), "_G.generic_save_callback")
    end
}

print("Save Manager (Web Adapted) Loaded. IS_WEB_ENVIRONMENT: ", IS_WEB_ENVIRONMENT)
