local M = {}

local function local_typescript_lib(root_dir)
  local root_ts = vim.fs.find("node_modules/typescript/lib", { path = root_dir, upward = true })[1]
  if root_ts then
    return root_ts
  end

  local mason_data = vim.fn.stdpath("data") .. "/mason/packages"
  local candidates = {
    mason_data .. "/vue-language-server/node_modules/typescript/lib",
    mason_data .. "/vue-language-server/node_modules/@vue/language-server/node_modules/typescript/lib",
    mason_data .. "/typescript-language-server/node_modules/typescript/lib",
    mason_data .. "/astro-language-server/node_modules/typescript/lib",
  }

  for _, path in ipairs(candidates) do
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
  end

  return ""
end

local function map(bufnr, mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
end

function M.setup()
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  local ok_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
  local ok_schemastore, schemastore = pcall(require, "schemastore")

  if ok_cmp then
    capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
  end

  vim.diagnostic.config({
    severity_sort = true,
    underline = true,
    update_in_insert = false,
    float = {
      border = "rounded",
      source = "if_many",
    },
    virtual_text = {
      spacing = 2,
      source = "if_many",
      prefix = ">>",
    },
  })

  vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
    border = "rounded",
  })
  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
    border = "rounded",
  })

  local signs = {
    Error = "E",
    Warn = "W",
    Hint = "H",
    Info = "I",
  }

  for type, icon in pairs(signs) do
    local hl = "DiagnosticSign" .. type
    vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = "" })
  end

  local on_attach = function(client, bufnr)
    local disable_formatting_for = {
      astro = true,
      biome = true,
      cssls = true,
      dockerls = true,
      emmet_ls = true,
      eslint = true,
      graphql = true,
      html = true,
      jsonls = true,
      ts_ls = true,
      volar = true,
      yamlls = true,
    }

    if disable_formatting_for[client.name] then
      client.server_capabilities.documentFormattingProvider = false
      client.server_capabilities.documentRangeFormattingProvider = false
    end

    if client.server_capabilities.documentFormattingProvider then
      map(bufnr, "n", "<leader>lf", function()
        vim.lsp.buf.format({ async = true })
      end, "Format with LSP")
    end

    if client.server_capabilities.documentHighlightProvider then
      local highlight_group = vim.api.nvim_create_augroup("user_lsp_document_highlight", { clear = false })

      vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
        buffer = bufnr,
        group = highlight_group,
        callback = vim.lsp.buf.document_highlight,
      })
      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave" }, {
        buffer = bufnr,
        group = highlight_group,
        callback = vim.lsp.buf.clear_references,
      })
    end

    map(bufnr, "n", "K", vim.lsp.buf.hover, "Hover")
    map(bufnr, "n", "gK", vim.lsp.buf.signature_help, "Signature help")
    map(bufnr, "n", "gd", vim.lsp.buf.definition, "Goto definition")
    map(bufnr, "n", "gD", vim.lsp.buf.declaration, "Goto declaration")
    map(bufnr, "n", "gi", vim.lsp.buf.implementation, "Goto implementation")
    map(bufnr, "n", "gr", vim.lsp.buf.references, "List references")
    map(bufnr, "n", "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map(bufnr, "n", "<leader>ca", vim.lsp.buf.code_action, "Code action")
    map(bufnr, "n", "<leader>ld", vim.diagnostic.open_float, "Line diagnostics")
    map(bufnr, "n", "[d", vim.diagnostic.goto_prev, "Previous diagnostic")
    map(bufnr, "n", "]d", vim.diagnostic.goto_next, "Next diagnostic")
  end

  local lspconfig = require("lspconfig")
  local servers = {
    astro = {
      bin = "astro-ls",
      on_new_config = function(new_config, new_root_dir)
        new_config.init_options = new_config.init_options or {}
        new_config.init_options.typescript = new_config.init_options.typescript or {}

        if not new_config.init_options.typescript.tsdk or new_config.init_options.typescript.tsdk == "" then
          new_config.init_options.typescript.tsdk = local_typescript_lib(new_root_dir)
        end
      end,
    },
    bashls = {
      bin = "bash-language-server",
    },
    basedpyright = {
      bin = "basedpyright-langserver",
    },
    clangd = {
      bin = "clangd",
      cmd = { "clangd", "--background-index", "--clang-tidy", "--completion-style=detailed" },
    },
    cmake = {
      bin = "cmake-language-server",
    },
    cssls = {
      bin = "vscode-css-language-server",
    },
    docker_compose_language_service = {
      bin = "docker-compose-langserver",
    },
    dockerls = {
      bin = "docker-langserver",
    },
    emmet_ls = {
      bin = "emmet-ls",
      filetypes = {
        "astro",
        "css",
        "eruby",
        "html",
        "javascriptreact",
        "less",
        "php",
        "scss",
        "svelte",
        "typescriptreact",
        "vue",
      },
    },
    eslint = {
      bin = "vscode-eslint-language-server",
      settings = {
        workingDirectory = {
          mode = "auto",
        },
      },
    },
    gopls = {
      bin = "gopls",
      settings = {
        gopls = {
          analyses = {
            unusedparams = true,
          },
          gofumpt = true,
          staticcheck = true,
        },
      },
    },
    graphql = {
      bin = "graphql-lsp",
      filetypes = { "graphql", "javascriptreact", "typescriptreact", "vue", "svelte" },
    },
    html = {
      bin = "vscode-html-language-server",
    },
    intelephense = {
      bin = "intelephense",
    },
    jdtls = {
      bin = "jdtls",
    },
    jsonls = {
      bin = "vscode-json-language-server",
      settings = {
        json = {
          schemas = ok_schemastore and schemastore.json.schemas() or nil,
          validate = {
            enable = true,
          },
        },
      },
    },
    lemminx = {
      bin = "lemminx",
    },
    lua_ls = {
      bin = "lua-language-server",
      settings = {
        Lua = {
          completion = {
            callSnippet = "Replace",
          },
          diagnostics = {
            globals = { "vim" },
          },
          telemetry = {
            enable = false,
          },
          workspace = {
            checkThirdParty = false,
            library = vim.api.nvim_get_runtime_file("", true),
          },
        },
      },
    },
    marksman = {
      bin = "marksman",
    },
    pyright = {
      bin = "pyright-langserver",
    },
    rust_analyzer = {
      bin = "rust-analyzer",
      settings = {
        ["rust-analyzer"] = {
          cargo = {
            allFeatures = true,
          },
          checkOnSave = {
            command = "clippy",
          },
        },
      },
    },
    ruby_lsp = {
      bin = "ruby-lsp",
    },
    sqlls = {
      bin = "sql-language-server",
    },
    svelte = {
      bin = "svelteserver",
    },
    tailwindcss = {
      bin = "tailwindcss-language-server",
    },
    taplo = {
      bin = "taplo",
    },
    terraformls = {
      bin = "terraform-ls",
    },
    ts_ls = {
      bin = "typescript-language-server",
    },
    vimls = {
      bin = "vim-language-server",
    },
    volar = {
      bin = "vue-language-server",
      init_options = {
        vue = {
          hybridMode = false,
        },
        typescript = {
          tsdk = "",
        },
      },
      on_new_config = function(new_config, new_root_dir)
        new_config.init_options = new_config.init_options or {}
        new_config.init_options.typescript = new_config.init_options.typescript or {}

        if not new_config.init_options.typescript.tsdk or new_config.init_options.typescript.tsdk == "" then
          new_config.init_options.typescript.tsdk = local_typescript_lib(new_root_dir)
        end
      end,
    },
    yamlls = {
      bin = "yaml-language-server",
      settings = {
        yaml = {
          keyOrdering = false,
          schemaStore = {
            enable = false,
            url = "",
          },
          schemas = ok_schemastore and schemastore.yaml.schemas() or nil,
        },
      },
    },
    zls = {
      bin = "zls",
    },
  }

  if vim.fn.executable("basedpyright-langserver") == 1 then
    servers.pyright = nil
  end

  for server, config in pairs(servers) do
    if lspconfig[server] and (not config.bin or vim.fn.executable(config.bin) == 1) then
      local server_opts = vim.tbl_deep_extend("force", {
        capabilities = capabilities,
        on_attach = on_attach,
      }, config)

      server_opts.bin = nil
      lspconfig[server].setup(server_opts)
    end
  end
end

return M
