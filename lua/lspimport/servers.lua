local M = {}

---@class lspimport.Server
---@field is_unresolved_import_error fun(diagnostic: vim.Diagnostic): boolean
---@field is_auto_import_completion_item fun(item: any): boolean

local function pyright_server()
    -- Reports undefined variables as unresolved imports.
    ---@param diagnostic vim.Diagnostic
    ---@return boolean
    local function is_unresolved_import_error(diagnostic)
        return diagnostic.code == "reportUndefinedVariable"
    end

    --- Returns "Auto-import" menu item as import completion.
    ---@param item any
    ---@return boolean
    local function is_auto_import_completion_item(item)
        print('pyright item')
        return item.menu == "Auto-import"
    end

    return {
        is_unresolved_import_error = is_unresolved_import_error,
        is_auto_import_completion_item = is_auto_import_completion_item,
    }
end

local function ruff_server()
    ---@param diagnostic vim.Diagnostic
    ---@return boolean
    local function is_unresolved_import_error(diagnostic)
        print(diagnostic.code)
        return diagnostic.code == "F821"
    end

    ---@param item any
    ---@return boolean
    local function is_auto_import_completion_item(item)
        print('ruff item')
        return item.menu == "Auto-import"
    end

    return {
        is_unresolved_import_error = is_unresolved_import_error,
        is_auto_import_completion_item = is_auto_import_completion_item,
    }
end

local function string_in_table(str, tbl)
    for _, value in ipairs(tbl) do
        if string.lower(value) == string.lower(str) then
            return true
        end
    end
    return false
end


---Returns a server class.
---@param diagnostics table[vim.Diagnostic]
---@return lspimport.Server|nil
function M.get_servers(diagnostics, opts)
    local servers = {}
    for _, diagnostic in ipairs(diagnostics) do
        if string_in_table("pyright", opts.lsps) and diagnostic.source == "Pyright" then
            table.insert(servers, pyright_server())
        end
        if string_in_table("ruff", opts.lsps) and diagnostic.source == "Ruff" then
            table.insert(servers, ruff_server())
        end
    end
    return servers
end

return M
