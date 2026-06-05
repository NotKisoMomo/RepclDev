local Mandy = require(game:GetService("ReplicatedStorage"):WaitForChild("Mandy"))


Mandy.Define("Test", {
	Type = Mandy.Unlazy,
	Parses = {
		Message = Mandy.string()
	}
})

Mandy.Subscribe("Test", function(plr, package)
	warn(plr, package)
	Mandy.Post("Test", {
		Nessage = "Hello world!"
	})
end)

