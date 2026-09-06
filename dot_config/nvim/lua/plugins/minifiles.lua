return {
  {
    "nvim-mini/mini.files",
    version = false,
    opts = {
      windows = {
        max_number = math.huge,
        preview = true,
        width_focus = 33,
        width_nofocus = 22,
        width_preview = 78,
      },
      mappings = {
        reset = "<Del>",
        go_in_plus = "l",
        go_in = "L",
        go_out_plus = "h",
        go_out = "H",
      },
      options = {
        -- Whether to use for editing directories
        -- Disabled by default in LazyVim because neo-tree is used for that
        use_as_default_explorer = false,
      },
    },

    config = function(_, opts)
      local mini_files = require("mini.files")
      mini_files.setup(opts)

      local show_dotfiles = true

      local filter_show = function(fs_entry)
        return true
      end

      local filter_hide = function(fs_entry)
        return not vim.startswith(fs_entry.name, ".")
      end

      local toggle_dotfiles = function()
        show_dotfiles = not show_dotfiles
        local new_filter = show_dotfiles and filter_show or filter_hide
        mini_files.refresh({ content = { filter = new_filter } })
      end

      local map_split = function(buf_id, lhs, direction, close_on_file)
        local rhs = function()
          -- Make new window and set it as target
          local cur_target = MiniFiles.get_explorer_state().target_window
          local new_target = vim.api.nvim_win_call(cur_target, function()
            vim.cmd(direction .. " split")
            return vim.api.nvim_get_current_win()
          end)

          mini_files.set_target_window(new_target)
          mini_files.go_in({ close_on_file = close_on_file })
        end

        -- Adding `desc` will result into `show_help` entries
        local desc = "Split " .. direction
        vim.keymap.set("n", lhs, rhs, { buffer = buf_id, desc = desc })
      end

      local files_set_cwd = function()
        local cur_entry_path = mini_files.get_fs_entry().path
        local cur_directory = vim.fs.dirname(cur_entry_path)
        if cur_directory ~= nil then
          vim.fn.chdir(cur_directory)
        end
      end

      local alt_bind = function(buf_id, lhs, mapping_name, args)
        vim.keymap.set("n", lhs, function()
          mini_files[mapping_name](args)
        end, { buffer = buf_id, desc = "Alt bind to " .. mapping_name })
      end

      local new_bind = function(buf_id, lhs, mapping_name, fn, msg)
        local keymap = opts.mappings and opts.mappings[mapping_name] or lhs
        vim.keymap.set("n", keymap, fn, { buffer = buf_id, desc = msg })
      end

      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesWindowOpen",
        callback = function(args)
          local win_id = args.data.win_id

          -- Customize window-local settings
          local config = vim.api.nvim_win_get_config(win_id)
          config.border, config.title_pos = "rounded", "right"
          vim.api.nvim_win_set_config(win_id, config)
        end,
      })

      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesBufferCreate",
        callback = function(args)
          local buf_id = args.data.buf_id

          map_split(buf_id, "<M-S-s>", "belowright horizontal", false)
          map_split(buf_id, "<M-S-v>", "belowright vertical", false)
          map_split(buf_id, "<M-S-t>", "tab", false)
          map_split(buf_id, "<M-s>", "belowright horizontal", true)
          map_split(buf_id, "<M-v>", "belowright vertical", true)
          map_split(buf_id, "<M-t>", "tab", true)

          alt_bind(buf_id, " ", "go_in", { close_on_file = true })
          alt_bind(buf_id, "<CR>", "go_in", { close_on_file = true })
          alt_bind(buf_id, "<S-CR>", "go_in", { close_on_file = false })
          alt_bind(buf_id, "<BS>", "go_out")
          alt_bind(buf_id, "<ESC>", "close")

          new_bind(buf_id, ".", "toggle_hidden", toggle_dotfiles, "Toggle hidden files")
          new_bind(buf_id, "gc", "change_cwd", files_set_cwd, "Set cwd")
        end,
      })

      vim.api.nvim_create_autocmd("User", {
        pattern = "MiniFilesActionRename",
        callback = function(event)
          Snacks.rename.on_rename_file(event.data.from, event.data.to)
        end,
      })
    end,
  },
}
