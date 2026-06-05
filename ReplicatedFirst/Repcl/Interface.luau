--[[
	Interface.lua
	UI  : full-width top-mounted terminal (topbar + output + hint + input)
	Code: Doc 1 stability (RenderStepped dirty-flush, direct label creation)
	      + Doc 2 features (hooks, timestamps, chain hints, history,
	        Autocomplete, SettingsMenu, lock/unlock, broadcast, per-player output)
--]]

local Req          = require(script.Parent.Req)
local Grammar      = require(script.Parent.Grammar)
local Autocomplete = require(script.Parent.Autocomplete)
local SettingsMenu = require(script.Parent.SettingsMenu)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")

local IS_CLIENT = RunService:IsClient()

-- ─── Visual constants ─────────────────────────────────────────────────────────
local FONT         = Enum.Font.Code
local TEXT_SIZE    = 13
local BG           = Color3.fromHex("111111")
local FG           = Color3.fromHex("EEEEEE")
local WARN_COLOR   = Color3.fromHex("FFCC00")
local ERR_COLOR    = Color3.fromHex("FF4444")
local NOTIFY_COLOR = Color3.fromHex("4488FF")
local REPLY_COLOR  = Color3.fromHex("AAAAAA")
local OK_COLOR     = Color3.fromHex("44FF88")
local DIM_COLOR    = Color3.fromHex("666666")
local HINT_BG      = Color3.fromHex("1A1A2E")
local PURPLE       = Color3.fromHex("6C3EF4")
local INPUT_BG     = Color3.fromHex("1A1A1A")
local OUTPUT_BG    = Color3.fromHex("0D0D0D")

local KIND_COLOR: { [string]: Color3 } = {
	print  = FG,
	warn   = WARN_COLOR,
	error  = ERR_COLOR,
	err    = ERR_COLOR,
	notify = NOTIFY_COLOR,
	info   = NOTIFY_COLOR,
	reply  = REPLY_COLOR,
	ok     = OK_COLOR,
	cmd    = PURPLE,
	dim    = DIM_COLOR,
}

-- ─── Layout constants ─────────────────────────────────────────────────────────
local TERMINAL_HEIGHT = 300   -- total height of the terminal panel in px
local TOPBAR_H        = 20
local INPUT_H         = 26
local HINT_H          = 18
local OUTPUT_H        = TERMINAL_HEIGHT - TOPBAR_H - HINT_H - INPUT_H  -- 236

-- ─── State ────────────────────────────────────────────────────────────────────
local MAX_LINES = 200

local _outputLines: { { kind: string, message: string, ts: string } } = {}
local _dirty   = false
local _visible = false
local _locked  = false
local _history: { string } = {}
local _histIdx = 0

local _gui:         ScreenGui?      = nil
local _outputFrame: ScrollingFrame? = nil
local _inputBox:    TextBox?        = nil
local _hintBar:     Frame?          = nil
local _hintLabel:   TextLabel?      = nil

-- ─── Hooks ────────────────────────────────────────────────────────────────────
local _onShow:    { () -> () }               = {}
local _onHide:    { () -> () }               = {}
local _onSubmit:  { (string) -> () }         = {}
local _onReceive: { (string, string) -> () } = {}
local _onClear:   { () -> () }               = {}

local function fireHooks(hooks: { () -> () })
	for _, fn in hooks do pcall(fn) end
end
local function fireHooks2(hooks: { (string, string) -> () }, a: string, b: string)
	for _, fn in hooks do pcall(fn, a, b) end
end
local function fireHookStr(hooks: { (string) -> () }, s: string)
	for _, fn in hooks do pcall(fn, s) end
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────
local function ts(): string
	local t = os.date("*t") :: any
	return string.format("%02d:%02d", t.hour, t.min)
end

local function pushLine(kind: string, msg: string)
	if #_outputLines >= MAX_LINES then
		table.remove(_outputLines, 1)
	end
	table.insert(_outputLines, { kind = kind, message = msg, ts = ts() })
	_dirty = true
	fireHooks2(_onReceive, kind, msg)
end

-- ─── Output rebuild (RenderStepped dirty-flush, Doc 1 pattern) ───────────────
local function rebuildOutput()
	if not _dirty then return end
	_dirty = false

	local scroll = _outputFrame
	if not scroll then return end

	for _, child in scroll:GetChildren() do
		if child:IsA("TextLabel") then child:Destroy() end
	end

	local idx = 0
	for _, entry in _outputLines do
		local color = KIND_COLOR[entry.kind] or FG
		for _, seg in string.split(entry.message, "\n") do
			idx += 1
			local lbl = Instance.new("TextLabel")
			lbl.Size               = UDim2.new(1, 0, 0, TEXT_SIZE + 2)
			lbl.BackgroundTransparency = 1
			lbl.TextXAlignment     = Enum.TextXAlignment.Left
			lbl.TextColor3         = color
			lbl.Font               = FONT
			lbl.TextSize           = TEXT_SIZE
			lbl.Text               = string.format("[%s] %s", entry.ts, seg)
			lbl.RichText           = false
			lbl.LayoutOrder        = idx
			lbl.Parent             = scroll
		end
	end

	task.defer(function()
		if scroll then
			scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
		end
	end)
end

-- ─── Hint (chain-aware, variadic, flag-filtering) ────────────────────────────
local function updateHint(input: string)
	if not _hintLabel or not _hintBar then return end

	local trimmed = input:match("^%s*(.-)%s*$") or ""
	if trimmed == "" then
		_hintLabel.Text  = ""
		_hintBar.Visible = false
		return
	end

	-- Find last chain segment (&&, ||, &)
	local lastSeg = trimmed
	do
		local i = 1; local segStart = 1
		while i <= #trimmed do
			local two = trimmed:sub(i, i + 1)
			if two == "&&" or two == "||" then
				local s = trimmed:sub(segStart, i - 1):match("^%s*(.-)%s*$") or ""
				if s ~= "" then lastSeg = s end
				segStart = i + 2; i += 2
			elseif trimmed:sub(i, i) == "&" then
				local s = trimmed:sub(segStart, i - 1):match("^%s*(.-)%s*$") or ""
				if s ~= "" then lastSeg = s end
				segStart = i + 1; i += 1
			else
				i += 1
			end
		end
		local tail = trimmed:sub(segStart):match("^%s*(.-)%s*$") or ""
		if tail ~= "" then lastSeg = tail end
	end

	-- Tokenise last segment (handles quoted strings)
	local tokens: { string } = {}
	do
		local current = ""
		local i = 1
		while i <= #lastSeg do
			local c = lastSeg:sub(i, i)
			if c == '"' then
				local j = lastSeg:find('"', i + 1, true)
				if j then
					if current ~= "" then table.insert(tokens, current); current = "" end
					table.insert(tokens, lastSeg:sub(i + 1, j - 1)); i = j + 1
				else
					current ..= c; i += 1
				end
			elseif c == " " or c == "\t" then
				if current ~= "" then table.insert(tokens, current); current = "" end
				i += 1
			else
				current ..= c; i += 1
			end
		end
		if current ~= "" then table.insert(tokens, current) end
	end

	local cmdName = tokens[1] and tokens[1]:lower() or ""
	if cmdName == "" then
		_hintLabel.Text  = ""
		_hintBar.Visible = false
		return
	end

	local Registry = Req("Registry")
	local def      = Registry.get(cmdName)
	if not def then
		_hintLabel.Text  = ""
		_hintBar.Visible = false
		return
	end

	local argTokens:   { string }            = {}
	local activeFlags: { [string]: boolean } = {}
	for i = 2, #tokens do
		local t = tokens[i]
		if t:sub(1, 1) == "-" then
			activeFlags[t:sub(2):lower()] = true
		else
			table.insert(argTokens, t)
		end
	end

	local endsWithSpace = lastSeg:sub(-1) == " "
	local argCount      = #argTokens
	local currentArgIdx = endsWithSpace and (argCount + 1) or math.max(1, argCount)

	local parts: { string } = {}

	if argCount == 0 and not endsWithSpace and def.Description and def.Description ~= "" then
		table.insert(parts, def.Description)
	end

	if def.Args and #def.Args > 0 then
		local targetDef: any? = nil
		for idx, ad in def.Args do
			if (ad :: any).Variadic then
				if currentArgIdx >= idx then targetDef = ad; break end
			elseif idx == currentArgIdx then
				targetDef = ad; break
			end
		end
		if targetDef then
			local typesStr = table.concat(targetDef.Types, "|")
			local reqMark  = targetDef.Required and "" or "?"
			local varMark  = (targetDef :: any).Variadic and "…" or ""
			table.insert(parts, string.format("arg %d: <%s: %s%s%s>",
				currentArgIdx, targetDef.Name, typesStr, reqMark, varMark))
		end
	end

	if def.Flags and #def.Flags > 0 then
		local remaining: { string } = {}
		for _, f in def.Flags do
			if not (activeFlags[f.Short:lower()] or activeFlags[f.Name:lower()]) then
				table.insert(remaining, "-" .. f.Short)
			end
		end
		if #remaining > 0 then
			table.insert(parts, "flags: " .. table.concat(remaining, " "))
		end
	end

	if #parts == 0 then
		_hintLabel.Text  = ""
		_hintBar.Visible = false
		return
	end

	_hintLabel.Text  = table.concat(parts, "  |  ")
	_hintBar.Visible = true
end

-- ─── Submit ───────────────────────────────────────────────────────────────────
local function submitInput(raw: string)
	local trimmed = raw:match("^%s*(.-)%s*$")
	if trimmed == "" then return end

	_histIdx = 0
	table.insert(_history, 1, trimmed)
	if #_history > 200 then table.remove(_history) end

	pushLine("cmd", "> " .. trimmed)
	fireHookStr(_onSubmit, trimmed)

	local Parser   = Req("Parser")
	local Registry = Req("Registry")
	local Executor = Req("Executor")
	local Network  = Req("Network")

	-- Server path (Studio server-side testing)
	if RunService:IsServer() then
		local def, parsed = Parser.parse(trimmed, Registry)
		if def then
			local output = Executor.run(def, parsed, nil)
			if output then
				for _, entry in output do
					pushLine(entry.kind or "print", entry.text or "")
				end
			end
		else
			pushLine("error", tostring(parsed))
		end
		return
	end

	-- Client path: chain parser → correct Executor.run(def, parsed, player) signature
	local ok, ast = pcall(function() return Parser.Parse(trimmed) end)
	if ok and ast and Parser.Execute then
		Parser.Execute(ast, function(cmdName, argTokens, flagTokens)
			local def = Registry.get(cmdName)
			if not def then
				pushLine("err", "unknown command: " .. cmdName)
				return nil, "unknown command: " .. cmdName
			end

			-- Build ParseResult matching Executor.run's expected shape
			local parsed = {
				args  = argTokens  or {},
				flags = flagTokens or {},
				raw   = trimmed,
			}

			local defCtx = def.Context
			if defCtx == "Client" or defCtx == "Shared" or defCtx == "Bridge" then
				-- ← correct signature: (def, parsed, player?)
				local output = Executor.run(def, parsed, Players.LocalPlayer)
				if output then
					for _, entry in output do
						pushLine(entry.kind or "print", entry.text or "")
					end
				end
				return nil, nil
			end

			-- Server-context: route over network
			local req = Network.sendToServer(cmdName, argTokens, flagTokens, trimmed)
			if req then
				req.next(function(res: any)
					if res and res.err then pushLine("err", res.err) end
				end)
			end
			return nil, nil
		end)
	else
		-- Fallback for older Parser without chain support
		Network.sendInvoke(trimmed)
	end
end

-- ─── GUI construction (full-width top-mounted terminal) ───────────────────────
local function buildGui()
	local lp   = Players.LocalPlayer
	local pGui = lp:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name           = "RepclInterface"
	gui.ResetOnSpawn   = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder   = 100
	gui.Enabled        = false

	-- Root: full width, anchored to top of screen
	local root = Instance.new("Frame")
	root.Name             = "Root"
	root.Size             = UDim2.new(1, 0, 0, TERMINAL_HEIGHT)
	root.Position         = UDim2.new(0, 0, 0, 0)
	root.BackgroundColor3 = BG
	root.BorderSizePixel  = 0
	root.Parent           = gui

	-- Purple title bar
	local topBar = Instance.new("Frame")
	topBar.Name             = "TopBar"
	topBar.Size             = UDim2.new(1, 0, 0, TOPBAR_H)
	topBar.Position         = UDim2.new(0, 0, 0, 0)
	topBar.BackgroundColor3 = PURPLE
	topBar.BorderSizePixel  = 0
	topBar.Parent           = root

	local title = Instance.new("TextLabel")
	title.Size                   = UDim2.new(1, -8, 1, 0)
	title.Position               = UDim2.new(0, 8, 0, 0)
	title.BackgroundTransparency = 1
	title.TextColor3             = FG
	title.Font                   = FONT
	title.TextSize               = 12
	title.Text                   = "Repcl"
	title.TextXAlignment         = Enum.TextXAlignment.Left
	title.Parent                 = topBar

	-- Output area
	local outputBg = Instance.new("Frame")
	outputBg.Name             = "OutputBg"
	outputBg.Size             = UDim2.new(1, 0, 0, OUTPUT_H)
	outputBg.Position         = UDim2.new(0, 0, 0, TOPBAR_H)
	outputBg.BackgroundColor3 = OUTPUT_BG
	outputBg.BorderSizePixel  = 0
	outputBg.Parent           = root

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                   = "Output"
	scroll.Size                   = UDim2.new(1, -4, 1, -4)
	scroll.Position               = UDim2.new(0, 2, 0, 2)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness     = 4
	scroll.ScrollBarImageColor3   = PURPLE
	scroll.CanvasSize             = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scroll.Parent                 = outputBg

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding   = UDim.new(0, 1)
	listLayout.Parent    = scroll

	-- Hint bar (between output and input, hidden until active)
	local hintBar = Instance.new("Frame")
	hintBar.Name             = "HintBar"
	hintBar.Size             = UDim2.new(1, 0, 0, HINT_H)
	hintBar.Position         = UDim2.new(0, 0, 0, TOPBAR_H + OUTPUT_H)
	hintBar.BackgroundColor3 = HINT_BG
	hintBar.BorderSizePixel  = 0
	hintBar.Visible          = false
	hintBar.Parent           = root

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name                   = "HintLabel"
	hintLabel.Size                   = UDim2.new(1, -8, 1, 0)
	hintLabel.Position               = UDim2.new(0, 4, 0, 0)
	hintLabel.BackgroundTransparency = 1
	hintLabel.TextColor3             = REPLY_COLOR
	hintLabel.Font                   = FONT
	hintLabel.TextSize               = 11
	hintLabel.Text                   = ""
	hintLabel.TextXAlignment         = Enum.TextXAlignment.Left
	hintLabel.TextTruncate           = Enum.TextTruncate.AtEnd
	hintLabel.Parent                 = hintBar

	-- Input bar (pinned to bottom of root)
	local inputBg = Instance.new("Frame")
	inputBg.Name             = "InputBg"
	inputBg.Size             = UDim2.new(1, 0, 0, INPUT_H)
	inputBg.Position         = UDim2.new(0, 0, 0, TOPBAR_H + OUTPUT_H + HINT_H)
	inputBg.BackgroundColor3 = INPUT_BG
	inputBg.BorderSizePixel  = 0
	inputBg.Parent           = root

	local prompt = Instance.new("TextLabel")
	prompt.Size                   = UDim2.new(0, 18, 1, 0)
	prompt.BackgroundTransparency = 1
	prompt.TextColor3             = PURPLE
	prompt.Font                   = FONT
	prompt.TextSize               = TEXT_SIZE
	prompt.Text                   = ">"
	prompt.TextXAlignment         = Enum.TextXAlignment.Center
	prompt.Parent                 = inputBg

	local inputBox = Instance.new("TextBox")
	inputBox.Name              = "InputBox"
	inputBox.Size              = UDim2.new(1, -22, 1, 0)
	inputBox.Position          = UDim2.new(0, 20, 0, 0)
	inputBox.BackgroundTransparency = 1
	inputBox.TextColor3        = FG
	inputBox.PlaceholderText   = "enter command..."
	inputBox.PlaceholderColor3 = Color3.fromHex("555555")
	inputBox.Font              = FONT
	inputBox.TextSize          = TEXT_SIZE
	inputBox.TextXAlignment    = Enum.TextXAlignment.Left
	inputBox.ClearTextOnFocus  = false
	inputBox.Text              = ""
	inputBox.Parent            = inputBg

	-- Store handles
	_outputFrame = scroll
	_inputBox    = inputBox
	_hintBar     = hintBar
	_hintLabel   = hintLabel
	_gui         = gui

	-- Mount autocomplete dropdown anchored to root
	Autocomplete.mount(root, inputBox)

	gui.Parent = pGui
end

-- ─── Wire input events ────────────────────────────────────────────────────────
local function wireInput()
	local box = _inputBox
	if not box then return end

	box:GetPropertyChangedSignal("Text"):Connect(function()
		Autocomplete.onInputChanged(box.Text)
		updateHint(box.Text)
	end)

	box.FocusLost:Connect(function(enterPressed: boolean)
		if not enterPressed then return end
		local text = box.Text
		if text == "" then return end

		box.Text         = ""
		_hintLabel.Text  = ""
		_hintBar.Visible = false
		Autocomplete.hide()

		submitInput(text)

		task.defer(function()
			if _visible and box then box:CaptureFocus() end
		end)
	end)

	-- History recall + autocomplete key routing
	UIS.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not _visible or not box then return end

		if Autocomplete.onKeyDown(input.KeyCode, box) then return end

		if input.KeyCode == Enum.KeyCode.Up then
			if #_history == 0 then return end
			_histIdx = math.min(_histIdx + 1, #_history)
			box.Text = _history[_histIdx] or ""
			task.defer(function()
				if box then box.CursorPosition = #box.Text + 1 end
			end)
		elseif input.KeyCode == Enum.KeyCode.Down then
			if _histIdx <= 0 then return end
			_histIdx -= 1
			box.Text = _histIdx == 0 and "" or (_history[_histIdx] or "")
			task.defer(function()
				if box then box.CursorPosition = #box.Text + 1 end
			end)
		end
	end)

	-- Backtick toggle
	UIS.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Backquote then
			Interface.toggle()
		end
	end)
end

-- ─── RenderStepped flush ──────────────────────────────────────────────────────
local _bound = false
local function bindRenderStep()
	if _bound then return end
	_bound = true
	RunService.RenderStepped:Connect(function()
		if _visible and _dirty then
			rebuildOutput()
		end
	end)
end

-- ─── Public API ───────────────────────────────────────────────────────────────
local Interface = {}

function Interface.init(_config: any?)
	_visible = false
	_locked  = false
	_dirty   = false
	_histIdx = 0

	if not IS_CLIENT then return end

	buildGui()
	wireInput()
	bindRenderStep()
	SettingsMenu.init()

	pushLine("info", "Repcl ready.")
end

function Interface.show()
	if not _gui then return end
	_visible     = true
	_dirty       = true
	_gui.Enabled = true
	if _inputBox then
		task.defer(function() if _inputBox then _inputBox:CaptureFocus() end end)
	end
	fireHooks(_onShow)
end

function Interface.hide()
	if _locked then return end
	_visible = false
	if _gui then _gui.Enabled = false end
	if _inputBox then _inputBox:ReleaseFocus() end
	Autocomplete.hide()
	fireHooks(_onHide)
end

function Interface.toggle()
	if _visible then Interface.hide() else Interface.show() end
end

function Interface.isVisible(): boolean return _visible end
function Interface.isLocked():  boolean return _locked  end
function Interface.lock()   _locked = true  end
function Interface.unlock() _locked = false end

-- Output (accepts both Doc 1 {kind,text} tables and plain kind+msg calls)
function Interface.receiveOutput(entries: any)
	for _, entry in entries do
		pushLine(entry.kind or "print", entry.text or entry.message or "")
	end
end

function Interface.receive(kind: string, msg: string)
	pushLine(kind, msg)
end

function Interface.broadcast(kind: string, msg: string)
	if IS_CLIENT then
		pushLine(kind, msg)
	else
		Req("Network").broadcastOutput(kind, msg)
	end
end

function Interface.printTo(player: Player, kind: string, msg: string)
	if IS_CLIENT then
		pushLine(kind, msg)
	else
		Req("Network").sendOutput(player, kind, msg)
	end
end

function Interface.clear()
	_outputLines = {}
	_dirty       = true
	fireHooks(_onClear)
end

function Interface.clearAll()
	if IS_CLIENT then
		Interface.clear()
	else
		local Network = Req("Network")
		for _, p in Players:GetPlayers() do
			Network.sendClear(p)
		end
	end
end

function Interface.clearFor(player: Player)
	if IS_CLIENT then
		Interface.clear()
	else
		Req("Network").sendClear(player)
	end
end

function Interface.clearLocal()
	Interface.clear()
end

function Interface.log(tag: string, ctx: any)
	pushLine("dim", string.format("[%s] %s ran /%s", tag, ctx.Player.Name, ctx.Command))
end

function Interface.getLines()
	return table.clone(_outputLines)
end

-- Hooks
function Interface.onShow(fn: () -> ()): () -> ()
	table.insert(_onShow, fn)
	return function() table.remove(_onShow, table.find(_onShow, fn)) end
end

function Interface.onHide(fn: () -> ()): () -> ()
	table.insert(_onHide, fn)
	return function() table.remove(_onHide, table.find(_onHide, fn)) end
end

function Interface.onSubmit(fn: (string) -> ()): () -> ()
	table.insert(_onSubmit, fn)
	return function() table.remove(_onSubmit, table.find(_onSubmit, fn)) end
end

function Interface.onReceive(fn: (string, string) -> ()): () -> ()
	table.insert(_onReceive, fn)
	return function() table.remove(_onReceive, table.find(_onReceive, fn)) end
end

function Interface.onClear(fn: () -> ()): () -> ()
	table.insert(_onClear, fn)
	return function() table.remove(_onClear, table.find(_onClear, fn)) end
end

function Interface.destroy()
	Autocomplete.destroy()
	if _gui then _gui:Destroy() end
	_gui         = nil
	_outputFrame = nil
	_inputBox    = nil
	_hintBar     = nil
	_hintLabel   = nil
	_outputLines = {}
	_visible     = false
	_dirty       = false
end

return Interface