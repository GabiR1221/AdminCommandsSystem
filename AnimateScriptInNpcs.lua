---drd Animate Localscript
local UserInputService = game:GetService("UserInputService")
local player = game.Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

-- Keep the same attribute on the server-owned DrD template too. This local set
-- is only a fallback for the owner and does not replicate to observing clients.
character:SetAttribute("MorphType", "DrD")

-- ⚙️ Speed Settings
local normalWalkSpeed = 16
local sprintSpeed = 36
local isSprinting = false
local isEmoting = false -- New Emote Lock Variable

-- Set default speed on spawn
humanoid.WalkSpeed = normalWalkSpeed

-- 1. Create Animation Objects
local anims = {
	Idle = Instance.new("Animation"),
	Walk = Instance.new("Animation"),
	Sprint = Instance.new("Animation"), 
	Jump = Instance.new("Animation"),
	Fall = Instance.new("Animation"),
	Emote = Instance.new("Animation") -- Added Emote
}

-- 🛑 REPLACE IDs HERE 🛑
anims.Idle.AnimationId = "rbxassetid://12191569041347"
anims.Walk.AnimationId = "rbxassetid://123282108256275"
anims.Sprint.AnimationId = "rbxassetid://121915690413471" 
anims.Jump.AnimationId = "rbxassetid://111667101453616"
anims.Fall.AnimationId = "rbxassetid://138130156212936"

anims.Emote.AnimationId = "rbxassetid://93888878701091" -- <--- PUT EMOTE ID HERE

-- 2. Load Animations onto the Animator
local tracks = {
	Idle = animator:LoadAnimation(anims.Idle),
	Walk = animator:LoadAnimation(anims.Walk),
	Sprint = animator:LoadAnimation(anims.Sprint), 
	Jump = animator:LoadAnimation(anims.Jump),
	Fall = animator:LoadAnimation(anims.Fall)
}
-- We load the Emote separately so it doesn't get accidentally stopped by the Idle track
local emoteTrack = animator:LoadAnimation(anims.Emote)

-- Helper function to crossfade animations smoothly
local function playTrack(trackToPlay)
	-- If we try to walk, sprint, jump, or fall, cancel the emote!
	if isEmoting and trackToPlay ~= tracks.Idle then
		emoteTrack:Stop(0.2)
	end

	for name, track in pairs(tracks) do
		if track ~= trackToPlay and track.IsPlaying then
			track:Stop(0.2) 
		end
	end
	if not trackToPlay.IsPlaying then
		trackToPlay:Play(0.2)
	end
end

-- 3. Handle Running vs Sprinting vs Idling
humanoid.Running:Connect(function(speed)
	local currentState = humanoid:GetState()
	if currentState == Enum.HumanoidStateType.Freefall or currentState == Enum.HumanoidStateType.Jumping then
		return 
	end

	if speed > 0.1 then
		if isSprinting then
			playTrack(tracks.Sprint)
		else
			playTrack(tracks.Walk)
		end
	else
		playTrack(tracks.Idle)
	end
end)

-- 4. Handle Jumping, Falling, and Landing
humanoid.StateChanged:Connect(function(oldState, newState)
	if newState == Enum.HumanoidStateType.Jumping then
		playTrack(tracks.Jump)

	elseif newState == Enum.HumanoidStateType.Freefall then
		playTrack(tracks.Fall)

	elseif newState == Enum.HumanoidStateType.Landed then
		if humanoid.MoveDirection.Magnitude > 0 then
			if isSprinting then
				playTrack(tracks.Sprint)
			else
				playTrack(tracks.Walk)
			end
		else
			playTrack(tracks.Idle)
		end
	end
end)

-- 5. User Input Detection (Shift & E)
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end -- Ignores if typing in chat

	--[[ SPRINT LOGIC
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.LeftAlt then
		isSprinting = true
		humanoid.WalkSpeed = sprintSpeed

		local currentState = humanoid:GetState()
		if currentState ~= Enum.HumanoidStateType.Freefall and currentState ~= Enum.HumanoidStateType.Jumping then
			if humanoid.MoveDirection.Magnitude > 0 then
				playTrack(tracks.Sprint)
			end
		end
	end]]

	-- EMOTE LOGIC
	if input.KeyCode == Enum.KeyCode.E then
		-- Only play if we aren't already emoting, and we aren't falling/jumping
		local currentState = humanoid:GetState()
		if not isEmoting and currentState ~= Enum.HumanoidStateType.Freefall and currentState ~= Enum.HumanoidStateType.Jumping then
			isEmoting = true
			emoteTrack:Play(0.2)

			-- This line halts the E key logic until the animation naturally finishes OR is canceled by walking
			emoteTrack.Stopped:Wait() 

			isEmoting = false -- Unlocks the ability to emote again
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessedEvent)
	-- SPRINT STOP LOGIC
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = false
		humanoid.WalkSpeed = normalWalkSpeed

		local currentState = humanoid:GetState()
		if currentState ~= Enum.HumanoidStateType.Freefall and currentState ~= Enum.HumanoidStateType.Jumping then
			if humanoid.MoveDirection.Magnitude > 0 then
				playTrack(tracks.Walk)
			end
		end
	end
end)

-- 6. Kickstart the Idle animation
playTrack(tracks.Idle)
