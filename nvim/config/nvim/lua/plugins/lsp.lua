return {
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    opts = {
      PATH = "prepend",
      ui = {
        border = "rounded",
      },
    },
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    cmd = {
      "MasonToolsClean",
      "MasonToolsInstall",
      "MasonToolsInstallSync",
      "MasonToolsUpdate",
    },
    dependencies = {
      "williamboman/mason.nvim",
    },
    opts = {
      ensure_installed = {
        "astro-language-server",
        "basedpyright",
        "bash-language-server",
        "biome",
        "black",
        "clang-format",
        "clangd",
        "cmake-language-server",
        "css-lsp",
        "docker-compose-language-service",
        "dockerfile-language-server",
        "emmet-language-server",
        "eslint-lsp",
        "fixjson",
        "gofumpt",
        "goimports",
        "gopls",
        "graphql-language-service-cli",
        "html-lsp",
        "intelephense",
        "isort",
        "jdtls",
        "json-lsp",
        "lemminx",
        "lua-language-server",
        "marksman",
        "markdownlint",
        "phpcbf",
        "prettierd",
        "ruff",
        "ruby-lsp",
        "rust-analyzer",
        "rustfmt",
        "shellcheck",
        "shellharden",
        "shfmt",
        "sqlls",
        "sqlfluff",
        "sql-formatter",
        "stylua",
        "tailwindcss-language-server",
        "taplo",
        "terraform-ls",
        "typescript-language-server",
        "vue-language-server",
        "yamlfmt",
        "yaml-language-server",
        "zls",
      },
      run_on_start = false,
      auto_update = false,
      start_delay = 3000,
      debounce_hours = 24,
    },
  },
  {
    "b0o/schemastore.nvim",
    lazy = true,
  },
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "rafamadriz/friendly-snippets",
      "saadparwaiz1/cmp_luasnip",
      "windwp/nvim-autopairs",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      local cmp_autopairs = require("nvim-autopairs.completion.cmp")

      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        preselect = cmp.PreselectMode.None,
        completion = {
          completeopt = "menu,menuone,noinsert",
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
          ["<C-j>"] = cmp.mapping.select_next_item(),
          ["<C-k>"] = cmp.mapping.select_prev_item(),
          ["<CR>"] = cmp.mapping.confirm({ select = false }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "path" },
        }, {
          { name = "buffer" },
        }),
        formatting = {
          format = function(entry, vim_item)
            local menu = {
              buffer = "[BUF]",
              luasnip = "[SNIP]",
              nvim_lsp = "[LSP]",
              path = "[PATH]",
            }

            vim_item.menu = menu[entry.source.name]
            return vim_item
          end,
        },
        experimental = {
          ghost_text = true,
        },
      })

      cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
    end,
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      require("config.lsp").setup()
    end,
  },
  {
    "stevearc/conform.nvim",
    branch = "nvim-0.9",
    event = { "BufWritePre" },
    keys = {
      {
        "<leader>fm",
        function()
          require("conform").format({ async = true, lsp_fallback = true })
        end,
        desc = "Format buffer",
      },
    },
    opts = {
      notify_on_error = false,
      formatters_by_ft = {
        astro = { "prettierd", "prettier", stop_after_first = true },
        c = { "clang_format" },
        cpp = { "clang_format" },
        css = { "biome", "prettierd", "prettier", stop_after_first = true },
        go = { "gofumpt", "goimports" },
        graphql = { "biome", "prettierd", "prettier", stop_after_first = true },
        html = { "prettierd", "prettier", stop_after_first = true },
        javascript = { "biome", "prettierd", "prettier", stop_after_first = true },
        javascriptreact = { "biome", "prettierd", "prettier", stop_after_first = true },
        json = { "biome", "fixjson", "prettierd", "prettier", stop_after_first = true },
        jsonc = { "biome", "fixjson", "prettierd", "prettier", stop_after_first = true },
        lua = { "stylua" },
        markdown = { "prettierd", "prettier", stop_after_first = true },
        php = { "phpcbf" },
        python = { "ruff_fix", "ruff_organize_imports", "ruff_format", "isort", "black" },
        rust = { "rustfmt" },
        scss = { "prettierd", "prettier", stop_after_first = true },
        sh = { "shfmt", "shellharden" },
        sql = { "sql_formatter", "sqlfluff", stop_after_first = true },
        svelte = { "prettierd", "prettier", stop_after_first = true },
        terraform = { "terraform_fmt" },
        toml = { "taplo" },
        typescript = { "biome", "prettierd", "prettier", stop_after_first = true },
        typescriptreact = { "biome", "prettierd", "prettier", stop_after_first = true },
        vue = { "prettierd", "prettier", stop_after_first = true },
        xml = { "prettierd", "prettier", stop_after_first = true },
        yaml = { "yamlfmt", "prettierd", "prettier", stop_after_first = true },
        zsh = { "shfmt" },
      },
      format_on_save = function()
        return {
          timeout_ms = 800,
          lsp_fallback = true,
        }
      end,
    },
  },
}
