local Req          = require(script.Parent.Req)
local IntelliSense = require(script.Parent.IntelliSense)

local Iris         = require(script.Parent.deps.Iris)
local Protocol: any

local Editor = {}
Editor.__index = Editor

export type EditorState = {
	_open:         boolean,
	_src:          string,
	_cursorPos:    number,
	_completions:  {IntelliSense.CompletionItem},
	_acOpen:       boolean,
	_acSelected:   number,
	_output:       string,
	_running:      boolean,
	_sigHint:      string?,
	_hoverHint:    string?,
	_history:      {string},
	_historyIdx:   number,
	_dirty:        boolean,
}

local function newState(): EditorState
	return {
		_open        = false,
		_src         = "",
		_cursorPos   = 0,
		_completions = {},
		_acOpen      = false,
		_acSelected  = 1,
		_output      = "",
		_running     = false,
		_sigHint     = nil,
		_hoverHint   = nil,
		_history     = {},
		_historyIdx  = 0,
		_dirty       = true,
	}
end

local _state: EditorState = newState()

local WINDOW_SIZE    = Vector2.new(640, 480)
local AC_MAX_VISIBLE = 8
local KIND_ICON: { [string]: string } = {
	keyword  = "[kw]",
	snippet  = "[sn]",
	builtin  = "[bi]",
	global   = "[gl]",
	method   = "[fn]",
	property = "[pr]",
	type     = "[ty]",
	repcl    = "[rc]",
}

local function refreshCompletions(src: string, pos: number)
	local result = IntelliSense.complete(src, pos)
	_state._completions = result.items
	_state._acSelected  = 1
	_state._acOpen      = #result.items > 0
	_state._dirty       = true
end

local function applyCompletion(item: IntelliSense.CompletionItem)
	local insert = item.insertText or item.label
	local src    = _state._src
	local pos    = _state._cursorPos
	local before = string.sub(src, 1, pos)
	local after  = string.sub(src, pos + 1)
	local wordStart = pos
	while wordStart > 1 and string.sub(before, wordStart - 1, wordStart - 1):match("[%w_]") do
		wordStart -= 1
	end
	_state._src       = string.sub(src, 1, wordStart - 1) .. insert .. after
	_state._cursorPos = wordStart - 1 + #insert
	_state._acOpen    = false
	_state._dirty     = true
end

local function onSrcChanged(newSrc: string, newPos: number)
	_state._src       = newSrc
	_state._cursorPos = newPos
	_state._dirty     = true

	local sigName, sigDetail = IntelliSense.signature(newSrc, newPos)
	_state._sigHint = sigDetail and (sigName .. " " .. sigDetail) or nil

	refreshCompletions(newSrc, newPos)
end

local function executeScript()
	if _state._running then return end
	_state._running = true
	_state._output  = ""
	_state._dirty   = true

	Protocol = Protocol or Req("Repl/Protocol")
	Protocol.execute(_state._src, function(line: string)
		_state._output ..= line .. "\n"
		_state._dirty = true
	end, function()
		_state._running = false
		_state._dirty   = true
	end)
end

local function pushHistory(src: string)
	if src == "" then return end
	if _state._history[#_state._history] == src then return end
	table.insert(_state._history, src)
	_state._historyIdx = #_state._history + 1
end

local function navigateHistory(delta: number): string?
	local h   = _state._history
	local idx = _state._historyIdx + delta
	idx = math.clamp(idx, 1, #h + 1)
	_state._historyIdx = idx
	if idx <= #h then return h[idx] end
	return nil
end

function Editor.open()
	_state._open  = true
	_state._dirty = true
end

function Editor.close()
	_state._open  = false
	_state._acOpen = false
end

function Editor.isOpen(): boolean
	return _state._open
end

function Editor.render()
	Iris = Iris or Req("deps/Iris")

	if not _state._open then return end

	local window = Iris.Window({
		"Repl -- Script Editor",
		[Iris.Args.NoScrollbar] = false,
		[Iris.Args.Size]        = WINDOW_SIZE,
	})

	if window.closed and window.closed.value then
		Editor.close()
		Iris.End()
		return
	end

	Iris.SameLine()
	do
		local runBtn = Iris.Button({ "Run (F5)" })
		if runBtn.clicked and runBtn.clicked.value and not _state._running then
			pushHistory(_state._src)
			executeScript()
		end

		local clearBtn = Iris.Button({ "Clear" })
		if clearBtn.clicked and clearBtn.clicked.value then
			_state._output = ""
			_state._dirty  = true
		end

		if _state._running then
			Iris.Text({ " [running...]" })
		end
	end
	Iris.End()

	Iris.Separator()

	local inputState = Iris.InputTextMultiline({
		"",
		[Iris.Args.Text]        = _state._src,
		[Iris.Args.Size]        = Vector2.new(-1, 260),
		[Iris.Args.NoHorizontalScroll] = false,
	})

	if inputState.textChanged and inputState.textChanged.value then
		local newSrc = inputState.text and inputState.text.value or _state._src
		local newPos = #newSrc
		onSrcChanged(newSrc, newPos)
	end

	if Iris.IsKeyPressed and Iris.IsKeyPressed(Enum.KeyCode.F5) then
		if not _state._running then
			pushHistory(_state._src)
			executeScript()
		end
	end

	if _state._acOpen and #_state._completions > 0 then
		local acWin = Iris.Window({
			"##repl_ac",
			[Iris.Args.NoTitleBar]    = true,
			[Iris.Args.NoResize]      = true,
			[Iris.Args.NoMove]        = false,
			[Iris.Args.Size]          = Vector2.new(300, math.min(AC_MAX_VISIBLE, #_state._completions) * 20 + 8),
			[Iris.Args.NoScrollbar]   = false,
		})

		local visStart = math.max(1, _state._acSelected - AC_MAX_VISIBLE + 1)
		local visEnd   = math.min(#_state._completions, visStart + AC_MAX_VISIBLE - 1)

		for i = visStart, visEnd do
			local item     = _state._completions[i]
			local icon     = KIND_ICON[item.kind] or "[??]"
			local label    = icon .. " " .. item.label
			local detail   = item.detail and ("  " .. item.detail) or ""
			local selected = i == _state._acSelected

			if selected then
				--Iris.PushStyleColor and Iris.PushStyleColor(Iris.Enum.StyleColor.Button, Color3.fromHex("6C3EF4"))
				local btn = Iris.Button({ label .. detail })
				if btn.clicked and btn.clicked.value then
					applyCompletion(item)
				end
				--Iris.PopStyleColor and Iris.PopStyleColor()
			else
				local btn = Iris.Button({ label })
				if btn.clicked and btn.clicked.value then
					_state._acSelected = i
					applyCompletion(item)
				end
			end
		end

		if Iris.IsKeyPressed then
			if Iris.IsKeyPressed(Enum.KeyCode.Up) then
				_state._acSelected = math.max(1, _state._acSelected - 1)
			elseif Iris.IsKeyPressed(Enum.KeyCode.Down) then
				_state._acSelected = math.min(#_state._completions, _state._acSelected + 1)
			elseif Iris.IsKeyPressed(Enum.KeyCode.Return) or Iris.IsKeyPressed(Enum.KeyCode.Tab) then
				applyCompletion(_state._completions[_state._acSelected])
			elseif Iris.IsKeyPressed(Enum.KeyCode.Escape) then
				_state._acOpen = false
			end
		end

		Iris.End()
	end

	if _state._sigHint then
		Iris.SameLine()
		Iris.Text({ "  " .. (_state._sigHint or "") })
		Iris.End()
	end

	Iris.Separator()

	Iris.Text({ "Output:" })
	Iris.InputTextMultiline({
		"##repl_out",
		[Iris.Args.Text]     = _state._output,
		[Iris.Args.Size]     = Vector2.new(-1, 140),
		[Iris.Args.ReadOnly] = true,
	})

	_state._dirty = false

	Iris.End()
end

return Editor