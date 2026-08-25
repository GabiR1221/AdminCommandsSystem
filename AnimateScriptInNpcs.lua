---drd Animate Localscript
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = game.Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local rootPart = character:WaitForChild("HumanoidRootPart")

character:SetAttribute("MorphType", "DrD")

-- ⚙️ Speed Settings
local normalWalkSpeed = 16
local sprintSpeed = 36
local isSprinting = false
local isEmoting = false -- New Emote Lock Variable

-- Footsteps are cosmetic and are intentionally controlled by this LocalScript.
-- This keeps network traffic at zero and makes the sound match the animation as
-- perceived by the morphed player without trusting client input on the server.
local FOOTSTEP_SOUND_ID = "rbxassetid://91882016473062"
local FOOTSTEP_VOLUME = 0.33
local FOOTSTEP_ROLLOFF_MAX_DISTANCE = 55
local WALK_CYCLE_SPEED = 16 -- speed at which the uploaded walk animation was authored
local SPRINT_CYCLE_SPEED = 36
local FALLBACK_STEP_DISTANCE = 4.5 -- studs between individual footfalls
local STEP_MARKER_NAMES = { "Footstep", "LeftFootstep", "RightFootstep" }

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
anims.Walk.AnimationId = "rbxassetid://123282108256275"--  126565077597307
anims.Sprint.AnimationId = "rbxassetid://105803049139607" 
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

-- Animation markers are the most accurate way to synchronize footsteps. In the
-- Animation Editor, add LeftFootstep and RightFootstep events on foot contact.
-- The distance-based fallback below also works when the animations have no events.
local leftFoot = character:FindFirstChild("LeftFoot", true)
local rightFoot = character:FindFirstChild("RightFoot", true)
local nextFootIsLeft = true
local distanceSinceStep = 0
local lastMarkerStepAt = -math.huge

local function makeFootstepSound(parent, name)
	local configuredSoundId = character:GetAttribute("FootstepSoundId")
	local configuredVolume = character:GetAttribute("FootstepVolume")
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = typeof(configuredSoundId) == "string" and configuredSoundId or FOOTSTEP_SOUND_ID
	sound.Volume = typeof(configuredVolume) == "number"
		and math.clamp(configuredVolume, 0, 3)
		or FOOTSTEP_VOLUME
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = FOOTSTEP_ROLLOFF_MAX_DISTANCE
	sound.Parent = parent
	return sound
end

local leftSound = makeFootstepSound(leftFoot or rootPart, "MorphLeftFootstep")
local rightSound = makeFootstepSound(rightFoot or rootPart, "MorphRightFootstep")

-- Roblox's RbxCharacterSounds creates a looping sound named Running. Leaving it
-- enabled produces the old, continuous footsteps on top of these timed steps.
local function muteDefaultRunningSound(child)
	if child:IsA("Sound") and child.Name == "Running" then
		child.SoundId = ""
		child.Volume = 0
		child:Stop()
	end
end

for _, child in ipairs(rootPart:GetChildren()) do
	muteDefaultRunningSound(child)
end
rootPart.ChildAdded:Connect(muteDefaultRunningSound)

local function isGroundedAndMoving()
	local state = humanoid:GetState()
	return humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > 0.05
		and humanoid.FloorMaterial ~= Enum.Material.Air
		and state ~= Enum.HumanoidStateType.Jumping
		and state ~= Enum.HumanoidStateType.Freefall
		and state ~= Enum.HumanoidStateType.Swimming
end

local function playFootstep(requestedFoot)
	if not isGroundedAndMoving() then
		return
	end

	local useLeft = requestedFoot == "Left" or (requestedFoot == nil and nextFootIsLeft)
	local sound = useLeft and leftSound or rightSound
	nextFootIsLeft = not useLeft
	distanceSinceStep = 0

	-- Small deterministic bounds keep repeated steps natural without creating or
	-- destroying Sound instances every frame.
	sound.PlaybackSpeed = 0.96 + math.random() * 0.08
	sound.TimePosition = 0
	sound:Play()
end

local function connectFootstepMarkers(track)
	for _, markerName in ipairs(STEP_MARKER_NAMES) do
		track:GetMarkerReachedSignal(markerName):Connect(function()
			lastMarkerStepAt = time()
			if markerName == "LeftFootstep" then
				playFootstep("Left")
			elseif markerName == "RightFootstep" then
				playFootstep("Right")
			else
				playFootstep()
			end
		end)
	end
end

connectFootstepMarkers(tracks.Walk)
connectFootstepMarkers(tracks.Sprint)

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
			tracks.Sprint:AdjustSpeed(math.clamp(speed / SPRINT_CYCLE_SPEED, 0.5, 2))
		else
			playTrack(tracks.Walk)
			tracks.Walk:AdjustSpeed(math.clamp(speed / WALK_CYCLE_SPEED, 0.5, 2))
		end
	else
		playTrack(tracks.Idle)
	end
end)

-- Marker-free animations use distance travelled rather than a timer. Steps
-- therefore stay aligned when WalkSpeed, slopes, buffs, or character scale change.
RunService.Heartbeat:Connect(function(deltaTime)
	if not isGroundedAndMoving() then
		distanceSinceStep = 0
		return
	end

	-- Once a marker has fired recently, markers own synchronization. If an
	-- animation is swapped at runtime and no longer has markers, fallback resumes.
	if time() - lastMarkerStepAt < 1 then
		return
	end

	local horizontalVelocity = Vector3.new(
		rootPart.AssemblyLinearVelocity.X,
		0,
		rootPart.AssemblyLinearVelocity.Z
	).Magnitude
	distanceSinceStep += horizontalVelocity * math.min(deltaTime, 0.1)
	if distanceSinceStep >= FALLBACK_STEP_DISTANCE then
		playFootstep()
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
