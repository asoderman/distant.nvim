--- @class BufVar
--- @field set fun(value:any) #sets buffer variable to value
--- @field get fun():any #retrieves buffer variable value (or nil if not set)
--- @field set_if_unset fun(value:any) #sets buffer variable to value if it is not set
--- @field is_set fun():boolean #returns true if variable is set
--- @field is_unset fun():boolean #returns true if variable is not set
--- @field unset fun() #unsets the variable

--- @alias BufVarType 'string'|'number'|'boolean'

--- @param buf number #buffer number
--- @param name string #name of the variable
--- @param ty BufVarType|BufVarType[] #type(s) that the variable can be
--- @return BufVar
local function buf_var(buf, name, ty)
    --- Fails with error if not valid type
    --- @type fun(value:any)
    local validate_var

    if vim.tbl_islist(ty) then
        validate_var = function(value)
            for _, t in ipairs(ty) do
                if type(value) == t then
                    return
                end
            end

            error('value of type ' .. type(value) .. ' was not any of ' .. table.concat(ty, ', '))
        end
    elseif type(ty) == 'string' then
        validate_var = function(value)
            assert(type(value) == ty, 'value of type ' .. type(value) .. ' was not ' .. ty)
        end
    else
        error('BufVar(' .. tostring(name) .. ', ' .. tostring(ty) .. ') -- type must be string or string[]')
    end

    local function set_buf_var(value)
        if value ~= nil then
            validate_var(value)
        end

        vim.api.nvim_buf_set_var(buf, 'distant_' .. name, value)
    end

    local function get_buf_var()
        local ret, value = pcall(vim.api.nvim_buf_get_var, buf, 'distant_' .. name)
        if ret then
            return value
        end
    end

    local function is_buf_var_set()
        return get_buf_var() ~= nil
    end

    local function set_buf_var_if_unset(value)
        if not is_buf_var_set() then
            set_buf_var(value)
        end
    end

    return {
        is_set = is_buf_var_set,
        is_unset = function() return not is_buf_var_set() end,
        get = get_buf_var,
        set = set_buf_var,
        set_if_unset = set_buf_var_if_unset,
        unset = function() return set_buf_var(nil) end,
    }
end

-- GLOBAL DEFINITIONS ---------------------------------------------------------

--- Contains getters and setters for variables used by this plugin
local vars = {}

-- BUF LOCAL DEFINITIONS ------------------------------------------------------

vars.Buf = {}
vars.Buf.__index = vars.buf
vars.Buf.__call = function(_, bufnr)
    bufnr = bufnr or 0
    local buf_vars = {
        remote_path = buf_var(bufnr, 'remote_path', 'string'),
        remote_type = buf_var(bufnr, 'remote_type', 'string'),
        remote_alt_paths = buf_var(bufnr, 'remote_alt_paths', 'table'),
    }

    --- Returns true if remote buffer variables have been set
    --- @return boolean
    buf_vars.is_initialized = function()
        return buf_vars.remote_path.is_set()
    end

    --- @param path string
    --- @return boolean
    buf_vars.has_matching_remote_path = function(path)
        if buf_vars.is_initialized() then
            local matches_primary_path = path == buf_vars.remote_path.get()
            if matches_primary_path then
                return true
            end

            local alt_paths = vars.buf(bufnr).remote_alt_paths.get() or {}
            if alt_paths[path] == true then
                return true
            end
        end

        return false
    end

    return buf_vars
end

vars.buf = (function()
    local instance = {}
    setmetatable(instance, vars.Buf)

    --- Search all buffers for path or alt path match
    --- @param path string #looks for distant://path and path itself
    --- @return number|nil #bufnr of first match if found
    instance.find_with_path = function(path)
        assert(not vim.startswith(path, 'distant://'), 'path cannot start with distant://')

        -- Check if we have a buffer in the form of distant://path
        local bufnr = vim.fn.bufnr('^distant://' .. path .. '$', 0)
        if bufnr ~= -1 then
            return bufnr
        end

        -- Otherwise, we look through all buffers to see if the path is set
        -- as the primary or one of the alternate paths
        --- @diagnostic disable-next-line:redefined-local
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            vim.pretty_print('Does buf', bufnr, 'match path', path)
            vim.pretty_print('Remote Path', vars.buf(bufnr).remote_path.get())
            vim.pretty_print('Remote Alt paths', vars.buf(bufnr).remote_alt_paths.get())
            if vars.buf(bufnr).has_matching_remote_path(path) then
                print('Yes')
                return bufnr
            end
            print('No')
        end
    end

    return instance
end)()

return vars
