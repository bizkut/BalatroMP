-- web_api.lua
-- Handles communication with the web server for saving and loading game data.

local M = {}

-- Helper to convert Lua table to JSON string for simple cases.
-- Note: This is a very basic JSON encoder. For complex tables, a robust library would be better.
-- However, we are primarily sending STR_PACK'ed strings.
local function table_to_json(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        local key_str
        if type(k) == "string" then
            key_str = string.format("%q", k)
        elseif type(k) == "number" then
            key_str = tostring(k)
        else
            error("JSON key must be string or number")
        end

        local val_str
        if type(v) == "string" then
            val_str = string.format("%q", v)
        elseif type(v) == "number" or type(v) == "boolean" then
            val_str = tostring(v)
        elseif type(v) == "table" then
            -- Recursive call for nested tables (not deeply tested here)
            val_str = table_to_json(v)
        elseif v == nil then
            val_str = "null"
        else
            error("Unsupported JSON value type: " .. type(v))
        end
        table.insert(parts, key_str .. ":" .. val_str)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end


-- Saves game data to the web server.
-- save_identifier: e.g., 'run', 'profile', 'settings'
-- data_to_save_str: The string representation of the data (e.g., from STR_PACK).
function M.save_data_to_web(save_identifier, data_to_save_str, callback)
    local payload = table_to_json({ id = save_identifier, data = data_to_save_str })
    local js_code = string.format([[
        fetch('/api/save', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: %s
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                console.log('Save successful:', data.message);
                if (typeof %s === 'function') %s(true, data.message);
            } else {
                console.error('Save failed:', data.message);
                if (typeof %s === 'function') %s(false, data.message);
            }
        })
        .catch(error => {
            console.error('Error saving game via web API:', error);
            if (typeof %s === 'function') %s(false, 'Network or server error during save.');
        });
    ]], payload, callback, callback, callback, callback, callback, callback) -- Pass callback name multiple times

    -- love.system.getOS() can differentiate if more specific JS bridging is needed
    if js and js.eval then
        js.eval(js_code)
    elseif love.system and love.system.getOS() == "Web" then
        -- Potentially another way to execute JS if js.eval is not directly available
        -- For now, assume js.eval from Love.js context
        error("js.eval not available, cannot make HTTP POST request for saving.")
    else
        print("Web API: Not running in a web environment, save skipped.")
        if callback then callback(false, "Not in web environment") end
    }
end

-- Loads game data from the web server.
-- save_identifier: e.g., 'run', 'profile', 'settings'
-- callback: function(success, data_str_or_error_msg)
function M.load_data_from_web(save_identifier, callback)
    local js_code = string.format([[
        fetch('/api/load?id=%s') // Pass identifier as query param for GET
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    console.log('Load successful for %s');
                    if (typeof %s === 'function') {
                        // data.data here is the object { id: "...", data: "..." } from server
                        // or null if no save file was found.
                        if (data.data && data.data.data) {
                           %s(true, data.data.data); // Pass the actual STR_PACK'ed string
                        } else if (data.data === null) {
                           %s(true, null); // No save file found
                        } else {
                           %s(false, 'Received malformed data from server.');
                        }
                    }
                } else {
                    console.error('Load failed for %s:', data.message);
                    if (typeof %s === 'function') %s(false, data.message);
                }
            })
            .catch(error => {
                console.error('Error loading game via web API for %s:', error);
                if (typeof %s === 'function') %s(false, 'Network or server error during load.');
            });
    ]], save_identifier, save_identifier, callback, callback, callback, callback, save_identifier, callback, callback, save_identifier, callback, callback)

    if js and js.eval then
        js.eval(js_code)
    elseif love.system and love.system.getOS() == "Web" then
        error("js.eval not available, cannot make HTTP GET request for loading.")
    else
        print("Web API: Not running in a web environment, load skipped.")
        if callback then callback(false, "Not in web environment") end
    }
end

-- For this to work, the Lua functions passed as callbacks need to be globally accessible
-- or registered in a way that the JS environment can call them.
-- A common pattern is to register Lua callbacks with unique names and pass those names to JS.
-- Example:
-- local callbacks = {}
-- local next_callback_id = 1
-- function M.register_callback(cb_func)
--   local id = "lua_callback_" .. next_callback_id
--   callbacks[id] = cb_func
--   next_callback_id = next_callback_id + 1
--   return id
-- end
-- And then JS calls `Module.ccall('execute_lua_callback', null, ['string', 'boolean', 'string'], [callback_id, success, data_or_message])`
-- where `execute_lua_callback` is a C function exported from Lua via ffi that calls callbacks[callback_id](success, data_or_message).
-- For simplicity here, I am assuming the callback function name passed as string is globally accessible or js.eval handles it.
-- Love.js might provide a more direct way to do this. If not, the above pattern is more robust.

return M
