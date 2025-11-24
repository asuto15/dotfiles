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
      tree.setup({
        view = { width = 35, preserve_window_proportions = true },
        renderer = { group_empty = true, highlight_git = true },
        update_focused_file = { enable = true },
        actions = { open_file = { resize_window = true } },
      })
      vim.g.nvim_tree_setup_done = true
    end
  end
EOF
nnoremap <silent> <C-b> :NvimTreeToggle<CR>
nnoremap <silent> <leader>e :NvimTreeFindFileToggle<CR>
" VSCode風レイアウト: 左にツリー、右上エディタ、右下ターミナル
lua << EOF
  vim.api.nvim_create_user_command("VscodeLayout", function()
    vim.o.equalalways = false
    vim.cmd("wincmd l")
    vim.cmd("botright 12split | terminal")
    vim.cmd("NvimTreeOpen")
  end, {})
EOF
nnoremap <silent> <leader>vl :VscodeLayout<CR>
