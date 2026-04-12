return {
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = { "BufReadPost", "BufNewFile" },
    keys = {
      {
        "<leader>tc",
        "<cmd>TSContext toggle<cr>",
        desc = "Toggle sticky context",
      },
      {
        "[c",
        function()
          require("treesitter-context").go_to_context(vim.v.count1)
        end,
        desc = "Go to context",
      },
    },
    opts = {
      max_lines = 4,
      min_window_height = 20,
      multiline_threshold = 4,
      line_numbers = false,
      trim_scope = "outer",
      mode = "cursor",
      separator = "─",
    },
  },
  {
    "SmiteshP/nvim-navic",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      highlight = true,
      separator = " > ",
      depth_limit = 5,
      lsp = {
        auto_attach = true,
        preference = {
          "ts_ls",
          "volar",
          "astro",
          "lua_ls",
          "gopls",
          "basedpyright",
          "pyright",
          "rust_analyzer",
          "clangd",
          "jdtls",
          "intelephense",
          "ruby_lsp",
        },
      },
    },
  },
  {
    "stevearc/aerial.nvim",
    cmd = {
      "AerialOpen",
      "AerialToggle",
      "AerialPrev",
      "AerialNext",
    },
    keys = {
      {
        "<leader>xo",
        "<cmd>AerialToggle! right<cr>",
        desc = "Outline panel",
      },
      {
        "]s",
        "<cmd>AerialNext<cr>",
        desc = "Next symbol",
      },
      {
        "[s",
        "<cmd>AerialPrev<cr>",
        desc = "Previous symbol",
      },
    },
    dependencies = {
      "nvim-tree/nvim-web-devicons",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = {
      backends = { "treesitter", "lsp", "markdown", "man" },
      layout = {
        default_direction = "right",
        min_width = 28,
        max_width = { 38, 0.22 },
        resize_to_content = true,
      },
      attach_mode = "global",
      close_automatic_events = { "unsupported" },
      show_guides = true,
      highlight_mode = "split_width",
      autojump = false,
      filter_kind = {
        "Class",
        "Constructor",
        "Enum",
        "Function",
        "Interface",
        "Method",
        "Module",
        "Namespace",
        "Package",
        "Struct",
      },
    },
  },
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    keys = {
      {
        "<leader>xx",
        "<cmd>Trouble diagnostics toggle<cr>",
        desc = "Diagnostics panel",
      },
      {
        "<leader>xX",
        "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
        desc = "Buffer diagnostics panel",
      },
      {
        "<leader>xs",
        "<cmd>Trouble symbols toggle focus=false win.position=right<cr>",
        desc = "Symbols panel",
      },
      {
        "<leader>xl",
        "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
        desc = "LSP locations panel",
      },
      {
        "<leader>xq",
        "<cmd>Trouble qflist toggle<cr>",
        desc = "Quickfix panel",
      },
    },
    dependencies = {
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      focus = false,
      auto_close = true,
      auto_preview = false,
    },
  },
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    cmd = { "ToggleTerm", "TermExec" },
    keys = {
      {
        "<leader>tt",
        "<cmd>ToggleTerm direction=horizontal size=14<cr>",
        desc = "Terminal panel",
      },
      {
        "<leader>tf",
        "<cmd>ToggleTerm direction=float<cr>",
        desc = "Floating terminal",
      },
    },
    opts = {
      open_mapping = [[<c-\>]],
      direction = "horizontal",
      size = 14,
      shade_terminals = false,
      start_in_insert = true,
      persist_size = true,
      persist_mode = true,
      close_on_exit = false,
      float_opts = {
        border = "rounded",
      },
    },
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      indent = {
        char = "|",
      },
      whitespace = {
        remove_blankline_trail = false,
      },
      scope = {
        enabled = false,
      },
      exclude = {
        filetypes = {
          "neo-tree",
          "neo-tree-popup",
          "Trouble",
          "alpha",
          "help",
          "lazy",
          "mason",
          "oil",
          "qf",
          "toggleterm",
        },
      },
    },
  },
}
