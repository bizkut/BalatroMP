-- web_api.lua
-- Handles communication with the web server for saving and loading game data.
-- Uses js.eval to interact with browser's fetch API.

local M = {}

-- Helper to convert Lua table to JSON string for simple cases.
-- Note: This is a very basic JSON encoder. For complex tables, a robust library would be better.
local function table_to_json(tbl)
    if tbl == nil then return "null" end
    local parts = {}
    local is_array = true
    local n = 0
    for k, _ in pairs(tbl) do
        n = n + 1
        if type(k) ~= "number" or k > n or k < 1 then -- Simple check for array-like
            is_array = false
        end
    end
    if n == 0 and type(tbl) == 'table' then -- Empty table could be {} or []
        -- Heuristic: if metatable has __jsontype = 'object' or 'array', use that.
        -- Otherwise, default to object for empty tables unless specified.
        local mt = getmetatable(tbl)
        if mt and mt.__jsontype == 'array' then
            return "[]"
        else
            return "{}"
        end
    end


    if is_array then
        for i = 1, n do
            local v_str
            local v = tbl[i]
            if type(v) == "string" then v_str = string.format("%q", v)
            elseif type(v) == "number" or type(v) == "boolean" then v_str = tostring(v)
            elseif type(v) == "table" then v_str = table_to_json(v)
            elseif v == nil then v_str = "null"
            else error("Unsupported JSON array value type: " .. type(v)) end
            table.insert(parts, v_str)
        end
        return "[" .. table.concat(parts, ",") .. "]"
    else
        for k, v in pairs(tbl) do
            local key_str
            if type(k) == "string" then key_str = string.format("%q", k)
            elseif type(k) == "number" then key_str = tostring(k) -- Technically numbers as keys are not standard JSON, but JS objects allow it.
            else error("JSON object key must be string or number: " .. type(k)) end

            local val_str
            if type(v) == "string" then val_str = string.format("%q", v)
            elseif type(v) == "number" or type(v) == "boolean" then val_str = tostring(v)
            elseif type(v) == "table" then val_str = table_to_json(v)
            elseif v == nil then val_str = "null"
            else error("Unsupported JSON object value type: " .. type(v)) end
            table.insert(parts, key_str .. ":" .. val_str)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
end


-- Saves game data to the web server.
-- save_identifier: e.g., 'run', 'profile', 'settings'
-- data_to_save_str: The string representation of the data (e.g., from STR_PACK).
-- user_callback_name_str: Name of the global Lua function to call upon completion.
function M.save_data_to_web(save_identifier, data_to_save_str, user_callback_name_str)
    local payload_lua_table = { id = save_identifier, data = data_to_save_str }
    local payload_json_str = table_to_json(payload_lua_table)

    -- Ensure callback name is safe for JS string
    local safe_callback_name = string.gsub(user_callback_name_str, "\"", "\\\"")

    local js_code = string.format([[
        (async () => {
            try {
                const response = await fetch('/api/save', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: %s
                });
                const responseData = await response.json();
                if (typeof love !== 'undefined' && love.execute) { // Check for Love.js specific way to call Lua
                    love.execute('if _G["%s"] then _G["%s"](true, responseData.message || "Save successful.") else print("Lua callback %s not found.") end');
                } else if (typeof Module !== 'undefined' && Module.ccall) { // Fallback for typical Emscripten
                     // This part needs a C function callable from JS that can then call the Lua global function by name.
                     // For simplicity, this example assumes love.execute or direct global call if js.eval could do that.
                     // If direct global call: js.eval('_G["%s"](true, responseData.message || "Save successful.")')
                    print('Module.ccall method for Lua callback not fully implemented in this template for save.');
                    _G["%s"](responseData.success, responseData.message || (responseData.success and "Save successful." or "Save failed."));

                } else {
                     _G["%s"](responseData.success, responseData.message || (responseData.success and "Save successful." or "Save failed."));
                }
            } catch (error) {
                console.error('Error saving game via web API:', error);
                if (typeof love !== 'undefined' && love.execute) {
                    love.execute('if _G["%s"] then _G["%s"](false, "Network or server error during save: " + error.message) else print("Lua callback %s not found.") end');
                } else {
                     _G["%s"](false, "Network or server error during save: " + String(error));
                }
            }
        })();
    ]], payload_json_str,
    safe_callback_name, safe_callback_name, safe_callback_name, -- for love.execute
    safe_callback_name, -- for direct _G call
    safe_callback_name, -- for direct _G call (catch)
    safe_callback_name, safe_callback_name, safe_callback_name) -- for love.execute (catch)

    if js and js.eval then
        js.eval(js_code)
    elseif love.system and love.system.getOS() == "Web" and love.system.openURL then -- Fallback if js.eval not directly exposed but openURL is (less likely for POST)
        print("Web API: js.eval not available. Attempting save via other means not suitable for POST. Save might fail.")
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "js.eval not available for saving.") end
    else
        print("Web API: Not running in a suitable web environment, save skipped.")
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "Not in web environment") end
    end
end

-- Loads game data from the web server.
-- save_identifier: e.g., 'run', 'profile', 'settings'
-- user_callback_name_str: Name of the global Lua function(success, data_str_or_error_msg)
function M.load_data_from_web(save_identifier, user_callback_name_str)
    local safe_callback_name = string.gsub(user_callback_name_str, "\"", "\\\"")
    local safe_save_identifier = string.gsub(save_identifier, "\"", "\\\"")

    local js_code = string.format([[
        (async () => {
            try {
                const response = await fetch('/api/load?id=%s');
                const responseData = await response.json();
                let dataToPass = null;
                if (responseData.success && responseData.data && typeof responseData.data.data !== 'undefined') {
                    dataToPass = responseData.data.data; // This is the STR_PACKed string
                } else if (responseData.success && responseData.data === null) {
                    dataToPass = null; // Explicitly pass null for "no save file"
                } else if (!responseData.success) {
                    // Pass error message if not successful
                    dataToPass = responseData.message || 'Load failed on server.';
                }

                if (typeof love !== 'undefined' && love.execute) {
                    // Need to handle string and nil dataToPass carefully for Lua execution
                    let luaArg = typeof dataToPass === 'string' ? '"' + dataToPass.replace(/"/g, '\\"') + '"' : (dataToPass === null ? 'nil' : '""');
                    love.execute('if _G["%s"] then _G["%s"](' + responseData.success + ', ' + luaArg + ') else print("Lua callback %s not found.") end');
                } else {
                     _G["%s"](responseData.success, dataToPass);
                }
            } catch (error) {
                console.error('Error loading game via web API for %s:', error);
                 if (typeof love !== 'undefined' && love.execute) {
                    love.execute('if _G["%s"] then _G["%s"](false, "Network or server error during load: " + error.message) else print("Lua callback %s not found.") end');
                } else {
                    _G["%s"](false, "Network or server error during load: " + String(error));
                }
            }
        })();
    ]], safe_save_identifier,
    safe_callback_name, safe_callback_name, safe_callback_name, -- for love.execute
    safe_callback_name, -- for direct _G call
    safe_save_identifier, -- for error console log
    safe_callback_name, safe_callback_name, safe_callback_name, -- for love.execute (catch)
    safe_callback_name) -- for direct _G call (catch)

    if js and js.eval then
        js.eval(js_code)
    elseif love.system and love.system.getOS() == "Web" and love.system.openURL then
        -- love.system.openURL can only do GET requests and doesn't easily pass data back.
        -- This is not a viable path for the current load implementation.
        print("Web API: js.eval not available. Load will likely fail or not work as expected.")
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "js.eval not available for loading.") end
    else
        print("Web API: Not running in a suitable web environment, load skipped.")
        if _G[user_callback_name_str] then _G[user_callback_name_str](false, "Not in web environment") end
    end
end

return M
