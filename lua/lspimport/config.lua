local M = {}

---@class Config
---@field lsps table<string> Lsps to use
---@field show_source_lsps boolean Show source lsps in the dropdown
local config = {
    lsps = {"Pyright"},
    show_source_lsps = false,
}

---@param opts Config | nil
M.setup = function(opts)
    M.opts= vim.tbl_deep_extend("force", config, opts  or {})
end

return M
