local _Config = script.Parent
local _Repcl = _Config.Parent._Repcl

local Managers = _Repcl.Managers
local Types = require(_Repcl.Types)

local SessionManager = require(Managers.SessionManager)

function Register(config: Types.CELRegistry)
	SessionManager.Register(config)
end

local CEL = {}

...


Register({
	Name = "list",
	Aliases = {"ls"},
	Description = "List all registered commands",
	ContextType = "Server" | "Client" | "Shared",
	Parsed = {},
	Handler = function(ctx)
		ctx.Output
		
	end,
	ClientHandler = function(ctx)
		ctx.Commit({"Hello From Client"})
		ctx.Pushed(function(data)
			
		end)
	end,
	ServerHandler = function(ctx)
		ctx.Push({Message = "Hello From Server"})
		ctx.Committed(function(data)
			print(data)
		end)
	end,
})


return CEL