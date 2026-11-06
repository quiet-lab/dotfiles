-- Буфер ввода Claude Code: локальный плагин, команда ClaudeInput.
return {
  {
    name = "claude-input",
    dir = vim.fn.stdpath("config") .. "/local/claude-input",
    cmd = "ClaudeInput",
    config = function()
      require("claude_input").setup()
    end,
  },
}
