local RUSE = {
	Editor = {
		TabSize = 4,
		SoftTabs = true,
		LineNumbers = true,
		RelativeNumbers = true,  -- like nvim relativenumber
		WrapLines = false,
		ScrollOff = 8,           -- lines kept above/below cursor
	},
	Appearance = {
		Theme = "dark",          -- pulls from ThemeManager
		CursorLine = true,
		Colorscheme = "default",
	},
	Modes = {
		Default = "normal",      -- "normal" | "insert"
		EscapeKey = "Escape",
	},
	Keybinds = {
		-- normal mode
		Normal = {
			["i"] = "insert",
			["v"] = "visual",
			["dd"] = "deleteline",
			["yy"] = "yankline",
			["p"] = "paste",
			["u"] = "undo",
			["<C-r>"] = "redo",
			["gg"] = "gotop",
			["G"] = "gobottom",
			["<C-s>"] = "save",
			["<C-w>"] = "newwindow",
			[":"] = "command",   -- enters CEL command mode
		},
		-- insert mode
		Insert = {
			["Escape"] = "normal",
			["<C-s>"] = "save",
		},
		-- visual mode
		Visual = {
			["Escape"] = "normal",
			["y"] = "yank",
			["d"] = "delete",
			["c"] = "change",
		},
	},
	IntelliSense = {
		Enabled = true,
		TriggerChars = {".", ":", "("},
		MaxSuggestions = 10,
	},
	Buffers = {
		MaxOpen = 10,
		AutoSave = false,
	},
}

return RUSE