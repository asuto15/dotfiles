local M = {}

local rust_analyzer_settings = {
  ["rust-analyzer"] = {
    cargo = { allFeatures = true },
    procMacro = { enable = true },
    check = { command = "clippy" },
    inlayHints = {
      maxLength = 80,
      lifetimeElisionHints = { enable = "always", useParameterNames = true },
      closureReturnTypeHints = { enable = "always" },
      bindingModeHints = { enable = true },
      chainingHints = { enable = true },
      closingBraceHints = { enable = true },
      parameterHints = { enable = true },
      reborrowHints = { enable = "mutable" },
      typeHints = {
        enable = true,
        hideClosureInitialization = false,
        hideNamedConstructor = false,
      },
    },
  },
}

local function enable_inlay_hints(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.lsp.inlay_hint and vim.lsp.inlay_hint.enable then
    pcall(vim.lsp.inlay_hint.enable, true, { bufnr = bufnr })
    return
  end
  if vim.lsp.inlay_hint then
    pcall(vim.lsp.inlay_hint, bufnr, true)
  end
end

local function rust_analyzer_root_dir(fname)
  local markers = { "Cargo.toml", "rust-project.json", "rust-toolchain.toml" }
  local util_ok, util = pcall(require, "lspconfig.util")
  if util_ok and util.root_pattern then
    return util.root_pattern(unpack(markers))(fname)
  end
  local found = vim.fs.find(markers, { path = vim.fs.dirname(fname), upward = true })[1]
  return found and vim.fs.dirname(found) or nil
end

local function rust_analyzer_cmd()
  if vim.fn.executable("rust-analyzer") == 1 then
    return { vim.fn.exepath("rust-analyzer") }
  end
  if vim.fn.executable("rustup") == 1 then
    return { "rustup", "run", "stable", "rust-analyzer" }
  end
  return nil
end

function M.setup()
  local ra_cmd = rust_analyzer_cmd()
  if not ra_cmd then
    vim.notify(
      "rust-analyzer not found. Install with `rustup component add rust-analyzer --toolchain stable`",
      vim.log.levels.WARN
    )
    return
  end

  local base_config = {
    cmd = ra_cmd,
    settings = rust_analyzer_settings,
    root_dir = rust_analyzer_root_dir,
    single_file_support = false,
    on_attach = function(_, bufnr)
      enable_inlay_hints(bufnr)
    end,
  }

  if vim.fn.has("nvim-0.11") == 1 and vim.lsp and vim.lsp.config and vim.lsp.enable then
    vim.lsp.config("rust_analyzer", base_config)
    vim.lsp.enable("rust_analyzer")
  else
    local ok, lspconfig = pcall(require, "lspconfig")
    if ok and lspconfig.rust_analyzer then
      lspconfig.rust_analyzer.setup(base_config)
    end
  end
end

return M
