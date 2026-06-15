local M = {}
local term_mod = nil

-- タブ名管理用の状態
-- デフォルトでは何も入れず、リネームされたものだけここに乗る
local state = {
  names = {},
}

local function ensure_term_mod()
  if term_mod then
    return true
  end
  local ok, tm = pcall(require, "toggleterm.terminal")
  if not ok then
    return false
  end
  term_mod = tm
  return true
end

-- bottom タブ（direction=horizontal）の ID 一覧
local function list_bottom_term_ids()
  if not ensure_term_mod() then
    return {}
  end
  local ids = {}
  for _, t in pairs(term_mod.get_all()) do
    if t.id ~= nil and t.id > 0 and t.direction == "horizontal" then
      table.insert(ids, t.id)
    end
  end
  table.sort(ids)
  return ids
end

-- statusline 用: Term タブ一覧表示
--   - デフォルトは番号のみ: 1 2 3
--   - 名前を付けたタブだけ 1:dev のように表示
--   - 現在タブは >1, >1:dev のようにプレフィックスを付ける
function M.statusline()
  local ids = list_bottom_term_ids()

  -- 基本のステータスライン（ファイル名など）
  local base = "%f %m%r %= "

  if #ids == 0 then
    return base
  end

  local cur = vim.g._term_last_id
  local parts = {}
  table.insert(parts, "Term:")

  for _, id in ipairs(ids) do
    local name = state.names[id]
    local label

    if name and name ~= "" then
      -- ユーザが明示的に名前を付けたタブだけ 1:dev のように表示
      label = string.format("%d:%s", id, name)
    else
      -- それ以外は番号だけ
      label = tostring(id)
    end

    if id == cur then
      label = ">" .. label
    end
    table.insert(parts, label)
  end

  return base .. table.concat(parts, " ")
end

-- setup: toggleterm + キーマップ + autocmd
function M.setup()
  local ok, toggleterm = pcall(require, "toggleterm")
  if not ok then
    return
  end

  toggleterm.setup({
    -- デフォルト: 画面下部に horizontal split で表示
    direction = "horizontal",
    size = function(term)
      if term.direction == "horizontal" then
        return vim.g._term_last_height or 12
      elseif term.direction == "vertical" then
        return 35
      end
      return 20
    end,
    shade_terminals = false,
    start_in_insert = true,
    persist_size = true,
  })

  local opts = { silent = true, noremap = true }

  if not ensure_term_mod() then
    return
  end
  local Terminal = term_mod.Terminal

  -- bottom ターミナル群の管理
  local function close_all_bottom_terms()
    for _, t in pairs(term_mod.get_all()) do
      if t.direction == "horizontal" and t.window and vim.api.nvim_win_is_valid(t.window) then
        pcall(function()
          t:close()
        end)
      end
    end
  end

  local function open_bottom_term(id)
    vim.o.splitbelow = true
    close_all_bottom_terms()

    local term = term_mod.get(id)
    if not term then
      term = Terminal:new({
        id = id,
        direction = "horizontal",
      })
    else
      term.direction = "horizontal"
    end

    term:open()

    local win = term.window
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      vim.cmd("wincmd J")
      local h = vim.g._term_last_height or 12
      if h > 0 then
        vim.api.nvim_win_set_height(win, h)
      end
    end

    vim.g._term_last_id = id
  end

  local function toggle_last_bottom_term()
    -- 既に bottom term が開いていれば全部閉じる
    for _, t in pairs(term_mod.get_all()) do
      if t.direction == "horizontal" and t.window and vim.api.nvim_win_is_valid(t.window) then
        close_all_bottom_terms()
        return
      end
    end
    -- 何も開いていなければ、最後に使った ID か 1 番を開く
    local ids = list_bottom_term_ids()
    local id = vim.g._term_last_id
    if not id then
      id = ids[1] or 1
    end
    open_bottom_term(id)
  end

  -- 新規 / 次 / 前 / 削除 / リネーム
  local function new_bottom_term()
    local ids = list_bottom_term_ids()
    local new_id
    if #ids == 0 then
      new_id = 1
    else
      new_id = ids[#ids] + 1
    end
    open_bottom_term(new_id)
  end

  local function cycle_bottom_term(dir)
    local ids = list_bottom_term_ids()
    if #ids == 0 then
      new_bottom_term()
      return
    end

    local current = vim.g._term_last_id
    if not current then
      open_bottom_term(ids[1])
      return
    end

    local idx = 1
    for i, id in ipairs(ids) do
      if id == current then
        idx = i
        break
      end
    end

    local next_idx = ((idx - 1 + dir) % #ids) + 1
    open_bottom_term(ids[next_idx])
  end

  local function close_current_tab()
    local current = vim.g._term_last_id
    if not current then
      vim.notify("No current term tab", vim.log.levels.INFO)
      return
    end

    local term = term_mod.get(current)
    if term then
      pcall(function()
        term:shutdown()
      end)
    end
    state.names[current] = nil

    local ids = list_bottom_term_ids()
    if #ids == 0 then
      close_all_bottom_terms()
      vim.g._term_last_id = nil
      return
    end

    table.sort(ids)
    local next_id = ids[1]
    for _, id in ipairs(ids) do
      if id > current then
        next_id = id
        break
      end
    end
    open_bottom_term(next_id)
  end

  local function rename_current_tab()
    local current = vim.g._term_last_id
    if not current then
      vim.notify("No current term tab", vim.log.levels.INFO)
      return
    end
    local current_name = state.names[current] or ""
    local new_name = vim.fn.input("Term name: ", current_name)
    if new_name ~= nil then
      new_name = vim.fn.trim(new_name)
    end
    if new_name ~= nil and new_name ~= "" then
      state.names[current] = new_name
    else
      state.names[current] = nil
    end
  end

  vim.keymap.set({ "n", "t" }, "<M-j>", toggle_last_bottom_term, opts)
  vim.keymap.set({ "n", "t" }, "<M-t>", new_bottom_term, opts)
  vim.keymap.set({ "n", "t" }, "<M-d>", close_current_tab, opts)
  vim.keymap.set({ "n", "t" }, "<M-r>", rename_current_tab, opts)
  vim.keymap.set({ "n", "t" }, "<M-n>", function()
    cycle_bottom_term(1)
  end, opts)
  vim.keymap.set({ "n", "t" }, "<M-p>", function()
    cycle_bottom_term(-1)
  end, opts)

  for n = 1, 9 do
    vim.keymap.set("n", "<leader>" .. n, function()
      open_bottom_term(n)
    end, opts)
  end

  -- autocmd: TermOpen / 高さ記憶
  vim.api.nvim_create_autocmd("TermOpen", {
    pattern = "term://*",
    callback = function(ev)
      local t_opts = { buffer = ev.buf, silent = true, noremap = true }
      vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], t_opts)
      vim.keymap.set("t", "<C-w>h", [[<C-\><C-n><C-w>h]], t_opts)
      vim.keymap.set("t", "<C-w>j", [[<C-\><C-n><C-w>j]], t_opts)
      vim.keymap.set("t", "<C-w>k", [[<C-\><C-n><C-w>k]], t_opts)
      vim.keymap.set("t", "<C-w>l", [[<C-\><C-n><C-w>l]], t_opts)
    end,
  })

  vim.api.nvim_create_autocmd("WinLeave", {
    pattern = "term://*",
    callback = function()
      if vim.bo.buftype == "terminal" then
        vim.g._term_last_height = vim.api.nvim_win_get_height(0)
      end
    end,
  })
end

return M
