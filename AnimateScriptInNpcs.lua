--AnimateScript in npc model using new character system
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

-- Animation IDs from your original script
local animData = {
	Idle = "rbxassetid://121915690413471",
	Walk = "rbxassetid://126565077597307",
	Jump = "rbxassetid://111667101453616"
}

local tracks = {}
for name, id in pairs(animData) do
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	tracks[name] = animator:LoadAnimation(anim)
end

local currentTrack = nil

local function play(track)
	if currentTrack == track then return end
	if currentTrack then currentTrack:Stop(0.2) end
	track:Play(0.2)
	currentTrack = track
end

-- Connect to movement
humanoid.Running:Connect(function(speed)
	if speed > 0.1 then
		play(tracks.Walk)
	else
		play(tracks.Idle)
	end
end)

humanoid.Jumping:Connect(function()
	play(tracks.Jump)
end)

-- Start with Idle
play(tracks.Idle)
