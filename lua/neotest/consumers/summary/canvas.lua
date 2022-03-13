local M = {}

local _mappings = {}
local api = vim.api
M.namespace = api.nvim_create_namespace("neotest-render")

---@class Canvas
---@field lines table
---@field matches table
---@field mappings table
---@field valid boolean
---@field config table
local Canvas = {}

---@return Canvas
function Canvas:new(config)
  local mappings = {}
  local canvas = {
    lines = { "" },
    matches = {},
    mappings = mappings,
    valid = true,
    config = config,
  }
  setmetatable(canvas, self)
  self.__index = self
  return canvas
end

-- Used by components waiting on canvas update to render.
-- This is to avoid flickering updates as information is updated.
function Canvas:invalidate()
  self.valid = false
end

function Canvas:write(text, opts)
  opts = opts or {}
  local lines = vim.split(text, "[\r]?\n", false)
  for i, line in pairs(lines) do
    local cur_line = self.lines[#self.lines]
    self.lines[#self.lines] = cur_line .. line
    if opts.group and #line > 0 then
      self.matches[#self.matches + 1] = { opts.group, { #self.lines, #cur_line + 1, #line } }
    end
    if i < #lines then
      table.insert(self.lines, "")
    end
  end
end

--- Remove the last line from canvas
function Canvas:remove_line()
  self.lines[#self.lines] = nil
end

function Canvas:reset()
  self.lines = {}
  self.matches = {}
  self.mappings = {}
end

---Add a mapping for a specific line
---@param action string Name of mapping action to use key for
---@param callback function Callback for when mapping is used
---@param opts table Optional extra arguments
-- Extra arguments currently accepts:
--   `line` Line to map to, defaults to last in canvas
function Canvas:add_mapping(action, callback, opts)
  opts = opts or {}
  local line = opts["line"] or self:length()
  if not self.mappings[action] then
    self.mappings[action] = {}
  end
  self.mappings[action][line] = self.mappings[action][line] or {}
  self.mappings[action][line][#self.mappings[action][line] + 1] = callback
end

---Get the number of lines in canvas
function Canvas:length()
  return #self.lines
end

---Get the length of the longest line in canvas
function Canvas:width()
  local width = 0
  for _, line in pairs(self.lines) do
    width = width < #line and #line or width
  end
  return width
end

---Apply a render canvas to a buffer
---@param self Canvas
---@param buffer number
function Canvas:render_buffer(buffer)
  local success, err = pcall(api.nvim_buf_set_option, buffer, "modifiable", true)
  if not success then
    return false, err
  end
  if self:length() == 0 then
    return false, "No lines to render"
  end
  if buffer < 0 then
    return false, "Invalid buffer"
  end
  local win = vim.fn.bufwinnr(buffer)
  if win == -1 then
    return false, "Window not found"
  end

  _mappings[buffer] = self.mappings
  for action, _ in pairs(self.mappings) do
    local mappings = self.config.mappings[action]
    if type(mappings) ~= "table" then
      mappings = { mappings }
    end
    for _, key in pairs(mappings) do
      vim.api.nvim_buf_set_keymap(
        buffer,
        "n",
        key,
        "<cmd>lua require('neotest.consumers.summary.canvas')._mapping('" .. action .. "')<CR>",
        { noremap = true }
      )
    end
  end

  local lines = self.lines
  local matches = self.matches
  api.nvim_buf_clear_namespace(buffer, M.namespace, 0, -1)
  api.nvim_buf_set_lines(buffer, 0, #lines, false, lines)
  local last_line = vim.fn.getbufinfo(buffer)[1].linecount
  if last_line > #lines then
    api.nvim_buf_set_lines(buffer, #lines, last_line, false, {})
  end
  for _, match in pairs(matches) do
    local pos = match[2]
    api.nvim_buf_set_extmark(
      buffer,
      M.namespace,
      pos[1] - 1,
      (pos[2] or 1) - 1,
      { end_col = pos[3] and (pos[2] + pos[3] - 1), hl_group = match[1] }
    )
  end
  api.nvim_buf_set_option(buffer, "modifiable", false)
  api.nvim_buf_set_option(buffer, "buftype", "nofile")
  return true
end

--- @return Canvas
function M.new(config)
  return Canvas:new(config)
end

function M._mapping(action)
  local buffer = api.nvim_get_current_buf()
  local line = vim.fn.line(".")
  local callbacks = _mappings[buffer][action] and _mappings[buffer][action][line] or nil
  if not callbacks then
    return
  end
  for _, callback in pairs(callbacks) do
    callback()
  end
end

return M
