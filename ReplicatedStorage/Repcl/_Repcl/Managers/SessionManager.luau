local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local IS_SERVER = RunService:IsServer()
local IS_CLIENT = RunService:IsClient()

local _Managers = script.Parent
local _Repcl = _Managers.Parent
local _Packages = _Repcl.Parent._Packages
local _Utility = _Repcl.Parent._Utility

local Keep = require(_Packages.Keep)
local Structures = require(_Utility.Structures)

if IS_SERVER then
	Keep.Configure({

	})

	Keep.SetSchema(Structures.Profile)
end


local SessionManager = {}

function SessionManager.Register(config)
	
end

function SessionManager.GetSession(userId, schemaName)
	
end

function SessionManager.Start()
	
end

return SessionManager