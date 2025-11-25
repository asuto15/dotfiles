set number             "行番号を表示
set autoindent         "改行時に自動でインデントする
set tabstop=2          "タブを何文字の空白に変換するか
set shiftwidth=2       "自動インデント時に入力する空白の数
set expandtab          "タブ入力を空白に変換
set splitright         "画面を縦分割する際に右に開く
set clipboard=unnamed  "yank した文字列をクリップボードにコピー
set hls                "検索した文字をハイライトする
set noequalalways      "分割時に自動で高さを均等化しない
"nvim-tree 用に標準の netrw を無効化
let g:loaded_netrw = 1
let g:loaded_netrwPlugin = 1
"Neovim 0.9 環境向け: vim.loop が vim.uv に無い場合の互換対応
lua << EOF
  if vim.loop and not vim.uv then
    vim.uv = vim.loop
  end
EOF

let $CACHE = expand('~/.cache')
if !isdirectory($CACHE)
  call mkdir($CACHE, 'p')
endif
if &runtimepath !~# '/dein.vim'
  let s:dein_dir = fnamemodify('dein.vim', ':p')
  if !isdirectory(s:dein_dir)
    let s:dein_dir = $CACHE .. '/dein/repos/github.com/Shougo/dein.vim'
    if !isdirectory(s:dein_dir)
      execute '!git clone https://github.com/Shougo/dein.vim' s:dein_dir
    endif
  endif
  execute 'set runtimepath^=' .. substitute(
        \ fnamemodify(s:dein_dir, ':p') , '[/\\]$', '', '')
endif

if &compatible
  set nocompatible
endif
set runtimepath+=~/.cache/dein/repos/github.com/Shougo/dein.vim
if dein#load_state('~/.cache/dein')
  call dein#begin('~/.cache/dein')
  call dein#load_toml('~/.config/nvim/dein.toml', {'lazy': 0})
  call dein#load_toml('~/.config/nvim/dein_lazy.toml', {'lazy': 1})
  call dein#end()
  call dein#save_state()
endif
if dein#check_install()
  call dein#install()
endif
filetype plugin indent on
syntax enable

" nvim-tree setup (fallbackでここで必ず実行)
lua << EOF
  if not vim.g.nvim_tree_setup_done then
    local ok, tree = pcall(require, "nvim-tree")
    if ok then
      local tree_last_width = 35
      local function store_tree_width(win)
        if win and vim.api.nvim_win_is_valid(win) then
          tree_last_width = vim.api.nvim_win_get_width(win)
        else
          local view = require("nvim-tree.view")
          local vw = view.get_winnr()
          if vw and vim.api.nvim_win_is_valid(vw) then
            tree_last_width = vim.api.nvim_win_get_width(vw)
          end
        end
      end
      vim.api.nvim_create_autocmd("BufWinLeave", {
        pattern = "NvimTree_*",
        callback = function(ev) store_tree_width(ev.win) end,
      })
      local function toggle_tree_restore()
        local view = require("nvim-tree.view")
        if view.is_visible() then
          store_tree_width(view.get_winnr())
          vim.cmd("NvimTreeToggle")
        else
          vim.cmd("NvimTreeToggle")
          local win = view.get_winnr()
          if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_set_width(win, tree_last_width)
          end
        end
      end

      local function on_attach(bufnr)
        local api = require("nvim-tree.api")
        api.config.mappings.default_on_attach(bufnr)
        -- allow global <C-t> to reach terminal toggle
        pcall(vim.keymap.del, "n", "<C-t>", { buffer = bufnr })
      end
      tree.setup({
        on_attach = on_attach,
        view = { width = 35, preserve_window_proportions = true },
        renderer = { group_empty = true, highlight_git = true },
        update_focused_file = { enable = true },
        actions = { open_file = { resize_window = true } },
      })
      vim.g.nvim_tree_setup_done = true
      vim.keymap.set("n", "<C-b>", toggle_tree_restore, { silent = true })
      vim.keymap.set("n", "<leader>e", function()
        require("nvim-tree.api").tree.find_file({ open = true, focus = true })
        local view = require("nvim-tree.view")
        local win = view.get_winnr()
        if win and vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_set_width(win, tree_last_width)
        end
      end, { silent = true })
    end
  end
EOF
" VSCode風レイアウト: 左にツリー、右上エディタ、右下ターミナル
lua << EOF
  vim.api.nvim_create_user_command("VscodeLayout", function()
    vim.o.equalalways = false
    vim.cmd("NvimTreeOpen")
    vim.cmd("wincmd l")
    vim.cmd("botright 12split | terminal")
  end, {})
EOF
nnoremap <silent> <leader>vl :VscodeLayout<CR>

" nvim-tree 幅調整とターミナル制御
lua << EOF
  local term_bufid = nil
  local term_last_height = 12

  local function term_job_active(bufnr)
    if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
      return false
    end
    local ok, job_id = pcall(vim.api.nvim_buf_get_var, bufnr, "terminal_job_id")
    if not ok or job_id <= 0 then
      return false
    end
    local status = vim.fn.jobwait({ job_id }, 0)[1]
    return status == -1
  end

  local function toggle_bottom_term()
    local term_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.api.nvim_buf_get_option(buf, "buftype") == "terminal" then
        term_win = win
        term_last_height = vim.api.nvim_win_get_height(win)
        term_bufid = buf
        break
      end
    end
    if term_win then
      vim.api.nvim_win_close(term_win, true)
      return
    end
    vim.o.equalalways = false
    vim.cmd("botright 12split")
    local win = vim.api.nvim_get_current_win()
    if term_last_height and term_last_height > 0 then
      vim.api.nvim_win_set_height(win, term_last_height)
    end
    if term_job_active(term_bufid) then
      vim.api.nvim_win_set_buf(win, term_bufid)
    else
      vim.cmd("terminal")
      term_bufid = vim.api.nvim_get_current_buf()
    end
  end

  local function resize_width_current(delta)
    if delta >= 0 then
      vim.cmd("vertical resize +" .. delta)
    else
      vim.cmd("vertical resize " .. delta)
    end
  end

  local function resize_height_current(delta)
    if delta >= 0 then
      vim.cmd("resize +" .. delta)
    else
      vim.cmd("resize " .. delta)
    end
    local buf = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_get_option(buf, "buftype") == "terminal" then
      term_last_height = vim.api.nvim_win_get_height(0)
    end
  end

  vim.keymap.set("n", "<leader>]", function() resize_width_current(5) end, { silent = true })
  vim.keymap.set("n", "<leader>[", function() resize_width_current(-5) end, { silent = true })
  vim.keymap.set("n", "<leader>t", toggle_bottom_term, { silent = true })
  vim.keymap.set("n", "<C-t>", toggle_bottom_term, { silent = true })
  vim.keymap.set("n", "<leader>+", function() resize_height_current(2) end, { silent = true })
  vim.keymap.set("n", "<leader>-", function() resize_height_current(-2) end, { silent = true })
EOF

" カラースキーム適用後に背景を透明に上書き
function! s:set_transparent()
  highlight Normal guibg=none ctermbg=none
  highlight NormalNC guibg=none ctermbg=none
  highlight EndOfBuffer guibg=none ctermbg=none
  highlight SignColumn guibg=none ctermbg=none
endfunction
augroup TransparentBG
  autocmd!
  autocmd ColorScheme * call s:set_transparent()
  autocmd VimEnter * call s:set_transparent()
augroup END
