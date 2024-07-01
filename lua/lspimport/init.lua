local servers = require("lspimport.servers")
local ui = require("lspimport.ui")

local LspImport = {}

---@return vim.Diagnostic[]
local get_unresolved_import_errors = function()
    local line, _ = unpack(vim.api.nvim_win_get_cursor(0))
    local diagnostics = vim.diagnostic.get(0, { lnum = line - 1, severity = vim.diagnostic.severity.ERROR })
    if vim.tbl_isempty(diagnostics) then
        return {}
    end
    local servers_list = servers.get_servers(diagnostics)
    if servers_list == nil then
        return {}
    end
    if vim.tbl_isempty(servers_list) then
        return {}
    end
    return vim.tbl_filter(function(diagnostic)
        local all_false = true
        for _, server in ipairs(servers_list) do
            if server.is_unresolved_import_error(diagnostic) then
                all_false = false
                break
            end
        end
        return all_false == false
    end, diagnostics)
end

---@param diagnostics vim.Diagnostic[]
---@return table[vim.Diagnostic]
local get_diagnostics_under_cursor = function(diagnostics)
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor[1] - 1, cursor[2]
    local results = {}
    for _, d in ipairs(diagnostics) do
        if d.lnum <= row and d.end_lnum >= row then
            table.insert(results, d)
        end
    end

    return results
end

---@param result vim.lsp.CompletionResult Result of `textDocument/completion`
---@param prefix string prefix to filter the completion items
---@return table[]
local lsp_to_complete_items = function(result, prefix)
    if vim.fn.has("nvim-0.10.0") == 1 then
        return vim.lsp._completion._lsp_to_complete_items(result, prefix)
    else
        return require("vim.lsp.util").text_document_completion_list_to_complete_items(result, prefix)
    end
end

local is_auto_completion_item = function(servers_list, item)
    local is_any_true = false
    for _, server in ipairs(servers_list) do
        if server.is_auto_import_completion_item(item) then
            is_any_true = true
            -- break -- Exit the loop early if any server returns true
        end
    end
    return is_any_true
end

---@param server lspimport.Server
---@param result lsp.CompletionList|lsp.CompletionItem[] Result of `textDocument/completion`
---@param unresolved_import string
---@return table[]
local get_auto_import_complete_items = function(servers_list, result, unresolved_import)
    local items = lsp_to_complete_items(result, unresolved_import)
    if vim.tbl_isempty(items) then
        return {}
    end
    vim.tbl_filter(function(item)
        return item.word == unresolved_import
            and item.user_data
            and item.user_data.nvim
            and item.user_data.nvim.lsp.completion_item
            and item.user_data.nvim.lsp.completion_item.labelDetails
            and item.user_data.nvim.lsp.completion_item.labelDetails.description
            and item.user_data.nvim.lsp.completion_item.additionalTextEdits
            and not vim.tbl_isempty(item.user_data.nvim.lsp.completion_item.additionalTextEdits)
            -- and server.is_auto_import_completion_item(item)
            and is_auto_completion_item(servers_list, item)
    end, items)
    -- print("items", vim.inspect(items))
    return items
end

---@param item any|nil
---@param bufnr integer
local resolve_import = function(item, bufnr)
    if item == nil then
        return
    end
    local text_edits = item.user_data.nvim.lsp.completion_item.additionalTextEdits
    vim.lsp.util.apply_text_edits(text_edits, bufnr, "utf-8")
end

---@param server lspimport.Server
---@param result lsp.CompletionList|lsp.CompletionItem[] Result of `textDocument/completion`
---@param unresolved_import string
---@param bufnr integer
local lsp_completion_handler = function(servers_list, result, unresolved_import, bufnr, source)
    if vim.tbl_isempty(result or {}) then
        vim.notify("no import found for " .. unresolved_import)
        return
    end
    local items = get_auto_import_complete_items(servers_list, result, unresolved_import)
    if vim.tbl_isempty(items) then
        vim.notify("no import found for " .. unresolved_import)
        return
    end
    print("source", source)
    if #items == 1 then
        resolve_import(items[1], bufnr)
    else
        local item_texts = ui.create_items_text_with_header(items, unresolved_import, source)
        ui.create_floating_window(item_texts)
        ui.handle_floating_window_selection(items, bufnr, resolve_import)
    end
end

---@param diagnostics table[vim.Diagnostic]
local lsp_completion = function(diagnostics)
    local unresolved_imports = {}
    local import_map = {}

    for _, diagnostic in ipairs(diagnostics) do
        local unresolved_import = vim.api.nvim_buf_get_text(
            diagnostic.bufnr,
            diagnostic.lnum,
            diagnostic.col,
            diagnostic.end_lnum,
            diagnostic.end_col,
            {}
        )
        if not vim.tbl_isempty(unresolved_import) then
            local key = unresolved_import[1]
            local source = diagnostic.source

            if not import_map[key] then
                import_map[key] = { key, source }
                table.insert(unresolved_imports, import_map[key])
            else
                import_map[key][2] = import_map[key][2] .. ", " .. source
            end
        end
    end

    if vim.tbl_isempty(unresolved_imports) then
        vim.notify("cannot find diagnostic symbol")
        return
    end
    local servers_list = servers.get_servers(diagnostics)
    if servers_list == nil or vim.tbl_isempty(servers_list) then
        vim.notify("cannot find server implementation for lsp import")
        return
    end

    for _, unresolved_import in ipairs(unresolved_imports) do
        local params = {
            textDocument = vim.lsp.util.make_text_document_params(0),
            position = { line = diagnostics[1].lnum, character = diagnostics[1].end_col },
        }
        vim.lsp.buf_request(0, "textDocument/completion", params, function(_, result)
            lsp_completion_handler(
                servers_list,
                result,
                unresolved_import[1],
                diagnostics[1].bufnr,
                unresolved_import[2]
            )
        end)
    end
    -- local params = {
    --     textDocument = vim.lsp.util.make_text_document_params(0),
    --     position = { line = diagnostic.lnum, character = diagnostic.end_col },
    -- }
    -- return vim.lsp.buf_request(diagnostic.bufnr, "textDocument/completion", params, function(_, result)
    --     lsp_completion_handler(servers_list, result, unresolved_import[1], diagnostic.bufnr)
    -- end)
end

LspImport.import = function()
    vim.schedule(function()
        local diagnostics = get_unresolved_import_errors()
        if vim.tbl_isempty(diagnostics) then
            vim.notify("no unresolved import error")
            return
        end
        local diagnostics = get_diagnostics_under_cursor(diagnostics)
        lsp_completion(diagnostics or diagnostics)
    end)
end

return LspImport
