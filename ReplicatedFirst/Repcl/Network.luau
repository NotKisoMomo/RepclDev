--!strict
local Req    = require(script.Parent.Req)
local Schema = require(script.Parent.deps.Schema)

local RunService = game:GetService("RunService")
local IS_SERVER  = RunService:IsServer()

local Network = {}

local CHANNELS = {
	Invoke  = "Repcl.Invoke",
	Output  = "Repcl.Output",
	Auth    = "Repcl.Auth",
	Bridge  = "Repcl.Bridge",
	Clear   = "Repcl.Clear",
}

local S = Schema.Type

local SHAPES = {
	Invoke  = { input   = S.string()  },
	Output  = { entries = S.table()   },
	Auth    = { token   = S.string()  },
	Bridge  = { cmd     = S.string(), payload = S.table() },
	Clear   = {},
}

local _defined  = false
local _initDone = false

local function ensureDefined()
	if _defined then return end
	_defined = true
	Schema.define(CHANNELS.Invoke, SHAPES.Invoke)
	Schema.define(CHANNELS.Output, SHAPES.Output)
	Schema.define(CHANNELS.Auth,   SHAPES.Auth)
	Schema.define(CHANNELS.Bridge, SHAPES.Bridge)
	Schema.define(CHANNELS.Clear,  SHAPES.Clear)
end

function Network.init()
	if _initDone then return end
	_initDone = true
	ensureDefined()

	if IS_SERVER then
		Schema.subscribe(CHANNELS.Bridge, function(player: Player?, data: any)
			if not player then return end
			local Executor = Req("Executor")
			task.spawn(Executor.runServerBridge, player, data.cmd, data.payload)
		end)

		Schema.subscribe(CHANNELS.Invoke, function(player: Player?, data: any)
			if not player then return end
			local Registry = Req("Registry")
			local Parser   = Req("Parser")
			local Executor = Req("Executor")
			local AuthMgr  = Req("AuthManager")

			if not AuthMgr.check(player, data.input) then
				Network.sendOutput(player, {{ kind = "error", text = "Permission denied." }})
				return
			end

			local def, parsed = Parser.parse(data.input:lower(), Registry)
			if not def then
				Network.sendOutput(player, {{ kind = "error", text = tostring(parsed) }})
				return
			end

			task.spawn(function()
				local output = Executor.run(def, parsed, player)
				if output then
					Network.sendOutput(player, output)
				end
			end)
		end)
	else
		Schema.subscribe(CHANNELS.Output, function(_player: Player?, data: any)
			local Interface = Req("Interface")
			if Interface and Interface.receiveOutput then
				Interface.receiveOutput(data.entries)
			end
		end)

		Schema.subscribe(CHANNELS.Clear, function(_player: Player?, _data: any)
			local Interface = Req("Interface")
			if Interface and Interface.clear then
				Interface.clear()
			end
		end)
	end
end

function Network.sendBridge(cmdName: string, payload: any)
	ensureDefined()
	Schema.post(CHANNELS.Bridge, { cmd = cmdName, payload = payload })
end

function Network.sendInvoke(input: string)
	ensureDefined()
	Schema.post(CHANNELS.Invoke, { input = input })
end

function Network.sendOutput(player: Player, entries: any)
	ensureDefined()
	Schema.post(CHANNELS.Output, player, { entries = entries })
end

function Network.broadcastClear()
	ensureDefined()
	Schema.postAll(CHANNELS.Clear, {})
end

function Network.listenServer()
	if not IS_SERVER then return end
	Network.init()
end

function Network.listenClient()
	if IS_SERVER then return end
	Network.init()
end

function Network.destroy()
	-- subscriptions are GC'd with the runtime -- no-op for now
end

Network.Channels = CHANNELS

return Network