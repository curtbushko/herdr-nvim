local M = {}

M.defaults = { comment = "💬", sign = "▌", statusline = "●" }
local current = vim.deepcopy(M.defaults)

function M.resolve(value)
  if value == nil or value == true then return vim.deepcopy(M.defaults) end
  if value == false then return { comment = "", sign = "", statusline = "" } end
  assert(type(value) == "table", "herdr-nvim: icons must be a table or boolean")
  local resolved = vim.tbl_extend("force", M.defaults, value)
  for key, icon in pairs(resolved) do
    assert(M.defaults[key] ~= nil, "herdr-nvim: unknown icon " .. tostring(key))
    assert(type(icon) == "string" and not icon:find("[%c]"),
      "herdr-nvim: icons." .. key .. " must be a single-line string")
  end
  assert(vim.fn.strdisplaywidth(resolved.sign) <= 2,
    "herdr-nvim: icons.sign must fit in two display cells")
  return resolved
end

function M.configure(value)
  current = M.resolve(value)
end

function M.get(key)
  return current[key]
end

function M.prefix(key)
  local icon = current[key]
  return icon == "" and "" or icon .. " "
end

return M
