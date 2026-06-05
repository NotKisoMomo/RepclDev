local Mandy = require(game:GetService("ReplicatedStorage"):WaitForChild("Mandy"))

local Player = game:GetService("Players").LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

Mandy.Define("Test", {
	Type = Mandy.Unlazy,
	Parses = {
		Message = Mandy.string()
	}
})

Mandy.Subscribe("Test", function(t)
	warn(t)
end)

Mandy.Post("Test", {
	Nessage = "Hello world!"
})