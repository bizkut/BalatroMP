-- web_api.lua
-- Handles communication with the web server for saving and loading game data
-- using fetch.lua from 2dengine/love.js

local json = require("engine.json") -- Assuming a JSON library is available.
                                    -- If not, a simple one needs to be included or written.
                                    -- For now, let's assume one exists at this path.
                                    -- If it's part of the main game files, it will be in game.love

local M = {}
local fetch_module_loaded = false
local fetch -- Stores the fetch module

-- Attempt to load fetch.lua. It should be at the root of the .love file.
local success, err = pcall(function()
    fetch = require("fetch")
    if fetch and fetch.request and fetch.update then
        fetch_module_loaded = true
        print("web_api.lua: fetch.lua loaded successfully.")
    else
        print("web_api.lua: Failed to load fetch.lua or module is invalid.")
        fetch = nil -- Ensure it's nil if not fully loaded
    end
end)

if not success then
    print("web_api.lua: Error requiring fetch.lua: " .. tostring(err))
end


-- Saves game data to the web server.
-- save_identifier: e.g., 'run', 'profile', 'settings'
-- data_to_save_str: The string representation of the data (e.g., from STR_PACK).
-- user_callback_name_str: Name of the global Lua function to call upon completion.
function M.save_data_to_web(save_identifier, data_to_save_str, user_callback_name_str)
    if not fetch_module_loaded or not fetch then
        print("WebAPI Error: fetch.lua not available for saving.")
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "fetch.lua not available") end
        return
    end

    if not json then
        print("WebAPI Error: JSON library not available for saving.")
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "JSON library not available") end
        return
    end

    local payload_table = { id = save_identifier, data = data_to_save_str }
    local payload_json_str, err_json = json.encode(payload_table)

    if err_json then
        print("WebAPI Error: Failed to encode JSON for saving: " .. tostring(err_json))
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "JSON encoding error") end
        return
    end

    local headers = { ["Content-Type"] = "application/json" }

    print("WebAPI: Attempting to save data for ID: " .. save_identifier)
    fetch.request("/api/save", "POST", payload_json_str, headers, function(code, body)
        print("WebAPI Save Callback: HTTP Status Code: ", code)
        -- print("WebAPI Save Callback: Body: ", body) -- Can be very verbose
        if not _G[user_callback_name_str] then return end

        if code >= 200 and code < 300 then
            local success_parse, parsed_body = pcall(json.decode, body)
            if success_parse and parsed_body and parsed_body.success then
                _G[user_callback_name_str](true, parsed_body.message or "Save successful.")
            elseif success_parse and parsed_body and parsed_body.message then
                 _G[user_callback_name_str](false, "Save request failed on server: " .. parsed_body.message)
            else
                _G[user_callback_name_str](false, "Save failed with HTTP " .. code .. ". Malformed server response.")
            end
        else
            _G[user_callback_name_str](false, "Save failed with HTTP status " .. code .. ". Body: " .. body)
        end
    end)
end

-- Loads game data from the web server.
-- save_identifier: e.g., 'run', 'profile', 'settings'
-- user_callback_name_str: Name of the global Lua function(success, data_str_or_error_msg)
function M.load_data_from_web(save_identifier, user_callback_name_str)
    if not fetch_module_loaded or not fetch then
        print("WebAPI Error: fetch.lua not available for loading.")
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "fetch.lua not available") end
        return
    end

     if not json then
        print("WebAPI Error: JSON library not available for loading.")
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "JSON library not available") end
        return
    end

    local url = "/api/load?id=" .. fetch.urlencode(save_identifier) -- Assuming fetch.urlencode exists or using a simple one.
                                                                   -- fetch.lua from 2dengine might not have urlencode.
                                                                   -- For simple IDs, it might not be strictly necessary.

    print("WebAPI: Attempting to load data for ID: " .. save_identifier .. " from URL: " .. url)
    fetch.request(url, "GET", nil, {}, function(code, body)
        print("WebAPI Load Callback: HTTP Status Code: ", code)
        -- print("WebAPI Load Callback: Body: ", body) -- Can be very verbose
        if not _G[user_callback_name_str] then return end

        if code >= 200 and code < 300 then
            local success_parse, parsed_body = pcall(json.decode, body)
            if success_parse and parsed_body and parsed_body.success then
                if parsed_body.data and parsed_body.data.data then -- Server returns { success: true, data: { id: "...", data: "STR_PACK_str" } }
                    _G[user_callback_name_str](true, parsed_body.data.data)
                elseif parsed_body.data == nil then -- No save file found
                     _G[user_callback_name_str](true, nil)
                else
                    _G[user_callback_name_str](false, "Load failed: Malformed data structure in server response.")
                end
            elseif success_parse and parsed_body and parsed_body.message then
                _G[user_callback_name_str](false, "Load request failed on server: " .. parsed_body.message)
            else
                 _G[user_callback_name_str](false, "Load failed with HTTP " .. code .. ". Malformed server response body.")
            end
        else
            _G[user_callback_name_str](false, "Load failed with HTTP status " .. code .. ". Body: " .. body)
        end
    end)
end

-- Ensure this file is required by the game (e.g. in main.lua or game.lua)
-- And fetch.lua must be available in the .love archive at the root.
-- Also, a JSON library (here assumed as engine.json) must be available.

return M
