local Req        = require(script.Parent.Req)
local TypeSystem = require(script.Parent.TypeSystem)
local Theme      = require(script.Parent.Theme)

local dropdown:    Frame?        = nil
local listLayout:  UIListLayout? = nil
local itemPool: { { btn: TextButton, conn: RBXScriptConnection? } } = {}

local candidates:  { string } = {}
local selectedIdx: number     = 0
local _textBox:    TextBox?   = nil
local _screenGui:  ScreenGui? = nil 
local _consoleFrame: Frame?   = nil

local function fuzzyScore(candidate: string, query: string): number
	if query == "" then return 1 end
	local c = candidate:lower()
	local q = query:lower()
	if c == q then return 100 end
	if c:sub(1, #q) == q then return 50 end
	if c:find(q, 1, true) then return 10 end
	local ci = 1
	for qi = 1, #q do
		local ch = q:sub(qi, qi)
		local found = c:find(ch, ci, true)
		if not found then return 0 end
		ci = found + 1
	end
	return 1
end

local function lastSegmentRaw(raw: string): string
	local segStart = 1
	local i = 1
	while i <= #raw do
		local two = raw:sub(i, i + 1)
		if two == "&&" or two == "||" then
			segStart = i + 2; i += 2
		elseif raw:sub(i, i) == "&" then
			segStart = i + 1; i += 1
		else
			i += 1
		end
	end
	return raw:sub(segStart)
end

local function tokenise(seg: string): { string }
	local tokens: { string } = {}
	local current = ""
	local i = 1
	while i <= #seg do
		local c = seg:sub(i, i)
		if c == '"' then
			local j = seg:find('"', i + 1, true)
			if j then
				if current ~= "" then table.insert(tokens, current); current = "" end
				table.insert(tokens, seg:sub(i + 1, j - 1))
				i = j + 1
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
	return tokens
end

local function getCandidates(input: string): { string }
	local segRaw = lastSegmentRaw(input)
	local seg    = segRaw:match("^%s*(.-)%s*$") or ""
	local tokens = tokenise(seg)
	local endsWithSpace = segRaw:sub(-1) == " "

	if #tokens == 0 or (#tokens == 1 and not endsWithSpace) then
		local partial = (#tokens == 0) and "" or tokens[1]:lower()
		local ok, Registry = pcall(Req.get, "Registry")
		if not ok or not Registry then return {} end
		local all = Registry.getAll()

		local scored: { { name: string, score: number } } = {}
		for _, def in all do
			local s = fuzzyScore(def.Name, partial)
			if s > 0 then table.insert(scored, { name = def.Name, score = s }) end
			if def.Aliases then
				for _, alias in def.Aliases do
					local as = fuzzyScore(alias, partial)
					if as > 0 then table.insert(scored, { name = alias, score = as }) end
				end
			end
		end
		table.sort(scored, function(a, b)
			return a.score ~= b.score and a.score > b.score or a.name < b.name
		end)
		local out: { string } = {}
		for _, s in scored do table.insert(out, s.name) end
		return out
	end

	local cmdName = tokens[1]:lower()
	local ok, Registry = pcall(Req.get, "Registry")
	if not ok or not Registry then return {} end
	local def = Registry.get(cmdName)
	if not def then return {} end

	local typedFlags: { [string]: boolean } = {}
	local argTokens:  { string } = {}
	for i = 2, #tokens do
		local t = tokens[i]
		if t:sub(1, 1) == "-" then
			typedFlags[t:sub(2):lower()] = true
		else
			table.insert(argTokens, t)
		end
	end

	local lastToken  = tokens[#tokens]
	local isFlag     = lastToken:sub(1, 1) == "-"
	local isNewToken = endsWithSpace

	if isFlag then
		local partial = lastToken:sub(2):lower()
		if def.Flags and #def.Flags > 0 then
			local out: { string } = {}
			for _, f in def.Flags do
				local alreadySet = typedFlags[f.Short:lower()] or typedFlags[f.Name:lower()]
				if not alreadySet then
					if fuzzyScore(f.Short, partial) > 0 or fuzzyScore(f.Name, partial) > 0 then
						table.insert(out, "-" .. f.Short)
					end
				end
			end
			return out
		end
		return {}
	end

	local argDefs  = def.Args or {}
	local argIdx   = isNewToken and (#argTokens + 1) or math.max(1, #argTokens)
	local targetDef: any? = nil
	for i, ad in argDefs do
		if (ad :: any).Variadic then
			if argIdx >= i then targetDef = ad; break end
		elseif i == argIdx then
			targetDef = ad; break
		end
	end
	if not targetDef then return {} end

	local partial = (not isNewToken and #argTokens > 0) and argTokens[#argTokens] or ""
	local out: { string } = {}
	for _, typeName in targetDef.Types do
		local typeDef = TypeSystem.get(typeName)
		if typeDef and (typeDef :: any).Autocomplete then
			local ok2, results = pcall((typeDef :: any).Autocomplete, partial)
			if ok2 and type(results) == "table" then
				for _, r in results do
					if fuzzyScore(tostring(r), partial) > 0 then
						table.insert(out, tostring(r))
					end
				end
			end
		end
	end

	local seen: { [string]: boolean } = {}
	local deduped: { string } = {}
	for _, v in out do
		if not seen[v] then seen[v] = true; table.insert(deduped, v) end
	end
	return deduped
end

local function repositionDropdown(h: number)
	if not dropdown or not _consoleFrame or not _screenGui then return end
	local p  = Theme.get()
	local sz = p.Sizes

	local viewH = _screenGui.AbsoluteSize.Y - sz.InputHeight
	local cfAbs = _consoleFrame.AbsolutePosition
	local inputRowTop = cfAbs.Y + _consoleFrame.AbsoluteSize.Y - sz.InputHeight

	dropdown.Position = UDim2.new(
		0, cfAbs.X,
		0, inputRowTop - h - 2
	)

	dropdown.Size = UDim2.new(0, _consoleFrame.AbsoluteSize.X, 0, h)
end

local MAX_VISIBLE  = 8
local ITEM_HEIGHT  = 22
local DROPDOWN_PAD = 4

local function getThemeColors()
	local p = Theme.get()
	return {
		bg           = p.Colors.Background,
		bgTransp     = 0.08,
		selectedBg   = p.Colors.Arrow,
		selectedText = Color3.fromRGB(255, 255, 255),
		normalText   = Color3.fromRGB(220, 220, 220),
		border       = p.Colors.Scrollbar,
		fontSize     = p.Sizes.FontSize,
		font         = p.Fonts.InputFont,
	}
end

local function clearItems()
	for _, entry in itemPool do
		entry.btn.Visible = false
		if entry.conn then
			entry.conn:Disconnect()
			entry.conn = nil
		end
	end
end

local function getEntry(idx: number): { btn: TextButton, conn: RBXScriptConnection? }
	if not itemPool[idx] then
		local btn = Instance.new("TextButton")
		btn.Name               = "AcItem_" .. idx
		btn.Size               = UDim2.new(1, 0, 0, ITEM_HEIGHT)
		btn.BackgroundColor3   = Color3.fromRGB(30, 30, 30)
		btn.BackgroundTransparency = 1
		btn.BorderSizePixel    = 0
		btn.TextXAlignment     = Enum.TextXAlignment.Left
		btn.TextTruncate       = Enum.TextTruncate.AtEnd
		btn.AutoButtonColor    = false
		btn.ZIndex             = 20
		if dropdown then btn.Parent = dropdown end
		itemPool[idx] = { btn = btn, conn = nil }
	end
	return itemPool[idx]
end

local hide: () -> ()
local acceptCandidate: (candidate: string, currentInput: string) -> ()

local function renderDropdown()
	if not dropdown then return end
	clearItems()

	if #candidates == 0 then
		dropdown.Visible = false
		return
	end

	local tc      = getThemeColors()
	local visible = math.min(#candidates, MAX_VISIBLE)
	local h       = visible * ITEM_HEIGHT + DROPDOWN_PAD * 2

	dropdown.BackgroundColor3       = tc.bg
	dropdown.BackgroundTransparency = tc.bgTransp
	dropdown.Visible                = true

	repositionDropdown(h)

	for i = 1, visible do
		local candidate = candidates[i]
		local entry = getEntry(i)
		local btn   = entry.btn

		btn.Text      = "  " .. candidate
		btn.TextSize  = tc.fontSize
		btn.Font      = tc.font
		btn.Visible   = true
		btn.LayoutOrder = i

		if i == selectedIdx then
			btn.BackgroundTransparency = 0
			btn.BackgroundColor3       = tc.selectedBg
			btn.TextColor3             = tc.selectedText
		else
			btn.BackgroundTransparency = tc.bgTransp
			btn.BackgroundColor3       = tc.bg
			btn.TextColor3             = tc.normalText
		end

		if entry.conn then
			entry.conn:Disconnect()
			entry.conn = nil
		end
		entry.conn = btn.MouseButton1Click:Connect(function()
			if _textBox then
				acceptCandidate(candidate, _textBox.Text)
			end
		end)
	end
end

acceptCandidate = function(candidate: string, currentInput: string)
	if not _textBox then return end

	local segRaw    = lastSegmentRaw(currentInput)
	local seg       = segRaw:match("^%s*(.-)%s*$") or ""
	local tokens    = tokenise(seg)
	local endsSpace = segRaw:sub(-1) == " "

	local replaced: string

	if #tokens == 0 or endsSpace then
		replaced = currentInput .. candidate .. " "
	else
		-- Replace the last token in the full input string
		local lastToken = tokens[#tokens]
		local replaceFrom = #currentInput - #lastToken + 1
		while replaceFrom > 1 and currentInput:sub(replaceFrom - 1, replaceFrom - 1) ~= " " do
			replaceFrom -= 1
		end
		replaced = currentInput:sub(1, replaceFrom - 1) .. candidate .. " "
	end

	_textBox.Text = replaced
	task.defer(function()
		if _textBox then _textBox.CursorPosition = #_textBox.Text + 1 end
	end)

	hide()
end

local Autocomplete = {}

function Autocomplete.mount(sg: ScreenGui, cf: Frame, tb: TextBox)
	_textBox      = tb
	_screenGui    = sg
	_consoleFrame = cf

	if dropdown then dropdown:Destroy() end

	dropdown = Instance.new("Frame")
	dropdown.Name                   = "AcDropdown"
	dropdown.BackgroundColor3       = Theme.get().Colors.Background
	dropdown.BackgroundTransparency = 0.08
	dropdown.BorderSizePixel        = 1
	dropdown.BorderColor3           = Theme.get().Colors.Scrollbar
	dropdown.ClipsDescendants       = true
	dropdown.Visible                = false
	dropdown.ZIndex                 = 50
	dropdown.Parent                 = sg

	listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding   = UDim.new(0, 0)
	listLayout.Parent    = dropdown

	itemPool      = {}
	candidates    = {}
	selectedIdx   = 0
end

function Autocomplete.onInputChanged(input: string)
	candidates  = getCandidates(input)
	selectedIdx = 0
	renderDropdown()
end

function Autocomplete.onKeyDown(keyCode: Enum.KeyCode, tb: TextBox): boolean
	if keyCode == Enum.KeyCode.Tab then
		if #candidates == 0 then return true end
		local idx = selectedIdx > 0 and selectedIdx or 1
		if candidates[idx] then
			acceptCandidate(candidates[idx], tb.Text)
		end
		return true
	end

	if keyCode == Enum.KeyCode.Escape then
		if dropdown and dropdown.Visible then
			hide()
			return true
		end
		return false
	end

	if #candidates == 0 or not (dropdown and dropdown.Visible) then
		return false
	end

	if keyCode == Enum.KeyCode.Up then
		selectedIdx = selectedIdx <= 1 and #candidates or selectedIdx - 1
		renderDropdown()
		return true
	end

	if keyCode == Enum.KeyCode.Down then
		selectedIdx = selectedIdx >= #candidates and 1 or selectedIdx + 1
		renderDropdown()
		return true
	end

	return false
end

function Autocomplete.hide()
	hide()
end

function Autocomplete.applyTheme()
	if not dropdown then return end
	local p = Theme.get()
	dropdown.BackgroundColor3 = p.Colors.Background
	dropdown.BorderColor3     = p.Colors.Scrollbar
	renderDropdown()
end

function Autocomplete.destroy()
	clearItems()
	if dropdown then dropdown:Destroy(); dropdown = nil end
	itemPool   = {}
	candidates = {}
	_textBox      = nil
	_screenGui    = nil
	_consoleFrame = nil
end

hide = function()
	candidates  = {}
	selectedIdx = 0
	if dropdown then dropdown.Visible = false end
	clearItems()
end

return Autocomplete