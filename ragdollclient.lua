repeat task.wait() until script.Parent.Parent.Parent:IsA("Player")
repeat task.wait() until script.Parent.Parent.Parent.Character and script.Parent.Parent.Parent.Character:FindFirstChild("Humanoid")

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local variables = script.Parent:WaitForChild("variables")
local variables_ragdoll = variables:WaitForChild("ragdoll")
local variables_ragdollonclient = variables:WaitForChild("ragdollonclient")

local events = script.Parent:WaitForChild("events")
local events_variableserver = events:WaitForChild("variableserver")
local events_resetclient = events:WaitForChild("resetclient")

local functions = script.Parent:WaitForChild("functions")
local functions_remoteragdoll = functions:WaitForChild("remoteragdoll")
local functions_remoteragdollvelocity = functions:WaitForChild("remoteragdollvelocity")

local function killRagdoll(inst)
	if string.match(inst.Name, "'s Ragdoll") then
		local hum = inst:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = 0
		end
	end
end

for _, v in pairs(workspace:GetChildren()) do
	killRagdoll(v)
end

workspace.ChildAdded:Connect(function(child)
	killRagdoll(child)
end)

local function stopAnimations()
	for _, track in pairs(humanoid:GetPlayingAnimationTracks()) do
		if track.Name ~= "DummyAnim" and track.Animation and track.Animation.AnimationId ~= "rbxassetid://0" then
			track:Stop(0)
		end
	end
end

function functions_remoteragdoll.OnClientInvoke(mode, velocity)
	if mode then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		humanoid.AutoRotate = false

		pcall(function()
			character.Animate.Disabled = true
		end)

		stopAnimations()

		if velocity and character:FindFirstChild("HumanoidRootPart") then
			character.HumanoidRootPart.AssemblyLinearVelocity = velocity
		end

		variables_ragdollonclient.Value = true
	else
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		humanoid.AutoRotate = true

		pcall(function()
			character.Animate.Disabled = false
		end)

		variables_ragdollonclient.Value = false

		for _, v in pairs(character:GetDescendants()) do
			if v:IsA("BasePart") then
				v.AssemblyLinearVelocity = Vector3.zero
				v.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
end

function functions_remoteragdollvelocity.OnClientInvoke(velocity)
	if character:FindFirstChild("HumanoidRootPart") then
		character.HumanoidRootPart.AssemblyLinearVelocity = velocity
	end
end

game:GetService("ContextActionService"):BindAction("RagdollToggle", function(_, input)
	if input == Enum.UserInputState.Begin then
		variables_ragdoll.Value = not variables_ragdoll.Value
		events_variableserver:FireServer("ragdoll", variables_ragdoll.Value)
	end
end, true, Enum.KeyCode.R)

game:GetService("ContextActionService"):SetTitle("RagdollToggle", "Ragdoll")
game:GetService("ContextActionService"):SetPosition("RagdollToggle", UDim2.new(1, -110, 0, 15))

script.Parent.events.variableserver.OnClientEvent:Connect(function()
	events_variableserver:FireServer("ragdoll", variables_ragdoll.Value)
end)
