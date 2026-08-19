return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  cmd = "Neotree",
  opts = {
    sources = { "filesystem", "buffers", "git_status", "document_symbols" },
    open_files_do_not_replace_types = {
      "terminal",
      "Trouble",
      "trouble",
      "qf",
      "Outline",
    },
    filesystem = {
      bind_to_cwd = false,
      follow_current_file = { enabled = true },
      filtered_items = {
        visible = true,
      },
      use_libuv_file_watcher = true,
      window = {
        position = "float",
        width = 40,
        mappings = {
          ["o"] = {
            "open",
            nowait = true,
          },
        },
      },
    },
    buffers = {
      window = {
        position = "float",
      },
    },
    git_status = {
      window = {
        position = "float",
      },
    },
  },
}
