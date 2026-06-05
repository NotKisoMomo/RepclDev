local Shared = require(script.Parent.Shared)

local Janitor = {}

export type JanitorInstance = {
	Add     : (self: JanitorInstance, item: any) -> (),
	Remove  : (self: JanitorInstance, item: any) -> (),
	Bind    : (self: JanitorInstance, instance: Instance) -> (),
	Cleanup : (self: JanitorInstance) -> (),
}

type JanitorImpl = JanitorInstance & {
	_items       : { any },
	_connection  : RBXScriptConnection?,
}

local function getDestructor(item: any): (() -> ())?
	if type(item) == "function" then
		return item
	end
	if type(item) == "table" then
		if type(item.Destroy)     == "function" then return function() item:Destroy()     end end
		if type(item.Unload)      == "function" then return function() item:Unload()      end end
		if type(item.Disconnect)  == "function" then return function() item:Disconnect()  end end
		if type(item.Cleanup)     == "function" then return function() item:Cleanup()     end end
	end
	if typeof(item) == "RBXScriptConnection" then
		return function() item:Disconnect() end
	end
	return nil
end

function Janitor.new(): JanitorInstance
	local self: JanitorImpl = {
		_items      = {},
		_connection = nil,
	} :: any

	function self:Add(item: any)
		Shared.expectNotNil(item, "item")
		assert(getDestructor(item) ~= nil, "[Mandy] Janitor:Add -- item has no known destructor method")
		table.insert(self._items, item)
	end

	function self:Remove(item: any)
		Shared.expectNotNil(item, "item")
		for i, v in self._items do
			if v == item then
				table.remove(self._items, i)
				return
			end
		end
	end

	function self:Bind(instance: Instance)
		assert(typeof(instance) == "Instance", "[Mandy] Janitor:Bind expects an Instance")
		if self._connection then
			self._connection:Disconnect()
		end
		self._connection = instance.Destroying:Connect(function()
			self:Cleanup()
		end)
	end

	function self:Cleanup()
		if self._connection then
			self._connection:Disconnect()
			self._connection = nil
		end
		for i = #self._items, 1, -1 do
			local item       = self._items[i]
			local destructor = getDestructor(item)
			if destructor then
				local ok, err = pcall(destructor)
				if not ok then
					warn(string.format("[Mandy] Janitor cleanup error: %s", tostring(err)))
				end
			end
			self._items[i] = nil
		end
		self._items = {}
	end

	return self
end

return Janitor