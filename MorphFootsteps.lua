-- LocalScript: place once in StarterPlayer > StarterPlayerScripts.
-- It controls footsteps for every replicated morph on this client, not only the
-- LocalPlayer's character. That is necessary to replace sounds heard from others.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DEFAULT_SOUND_ID = "rbxassetid://86328160903034"
local DEFAULT_VOLUME = 0.65
local DEFAULT_STEP_DISTANCE = 4.5
local MARKER_FALLBACK_DELAY = 1
local MARKER_NAMES = { "Footstep", "LeftFootstep", "RightFootstep" }

local controllers = {}

local function usesCustomFootsteps(character)
	local explicitSetting = character:GetAttribute("UseCustomFootsteps")
	if explicitSetting ~= nil then
		return explicitSetting == true
	end

	-- Backwards compatibility for templates already configured by the previous
	-- version. MorphType may be any non-empty name; it is not limited to DrD.
	local morphType = character:GetAttribute("MorphType")
	return typeof(morphType) == "string" and morphType ~= ""
end

local function readStringAttribute(instance, name, fallback)
	local value = instance:GetAttribute(name)
	return typeof(value) == "string" and value ~= "" and value or fallback
end

local function readNumberAttribute(instance, name, fallback, minimum, maximum)
	local value = instance:GetAttribute(name)
	if typeof(value) ~= "number" then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function createSound(character, parent, name)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = readStringAttribute(character, "FootstepSoundId", DEFAULT_SOUND_ID)
	sound.Volume = readNumberAttribute(character, "FootstepVolume", DEFAULT_VOLUME, 0, 3)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 5
	sound.RollOffMaxDistance = readNumberAttribute(character, "FootstepMaxDistance", 55, 10, 150)
	sound.Archivable = false
	sound.Parent = parent
	return sound
end

local function findFoot(character, attributeName, r15Name, r6Name)
	local configuredName = character:GetAttribute(attributeName)
	if typeof(configuredName) == "string" and configuredName ~= "" then
		local configuredPart = character:FindFirstChild(configuredName, true)
		if configuredPart and configuredPart:IsA("BasePart") then
			return configuredPart
		end
	end
	for _, partName in ipairs({ r15Name, r6Name }) do
		local part = character:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return nil
end

local function disconnectController(character)
	local controller = controllers[character]
	if not controller then
		return
	end
	controllers[character] = nil
	for _, connection in ipairs(controller.connections) do
		connection:Disconnect()
	end
	for sound, original in pairs(controller.mutedSounds) do
		if sound.Parent then
			sound.SoundId = original.soundId
			sound.Volume = original.volume
		end
	end
	for _, sound in ipairs(controller.sounds) do
		sound:Destroy()
	end
end

local function setupCharacter(character)
	if controllers[character] or not usesCustomFootsteps(character) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local leftFoot = findFoot(character, "FootstepLeftPartName", "LeftFoot", "Left Leg")
	local rightFoot = findFoot(character, "FootstepRightPartName", "RightFoot", "Right Leg")
	local controller = {
		character = character,
		humanoid = humanoid,
		root = root,
		leftSound = createSound(character, leftFoot or root, "MorphLeftFootstep"),
		rightSound = createSound(character, rightFoot or root, "MorphRightFootstep"),
		nextFootIsLeft = true,
		distanceSinceStep = 0,
		lastMarkerAt = -math.huge,
		markerTracks = {},
		mutedSounds = {},
		connections = {},
	}
	controller.sounds = { controller.leftSound, controller.rightSound }
	controllers[character] = controller

	local function isAbleToStep()
		local state = humanoid:GetState()
		return humanoid.Health > 0
			and humanoid.FloorMaterial ~= Enum.Material.Air
			and state ~= Enum.HumanoidStateType.Jumping
			and state ~= Enum.HumanoidStateType.Freefall
			and state ~= Enum.HumanoidStateType.Swimming
	end

	local function playStep(requestedFoot)
		if not isAbleToStep() then
			return
		end
		local useLeft = requestedFoot == "Left"
			or (requestedFoot == nil and controller.nextFootIsLeft)
		local sound = useLeft and controller.leftSound or controller.rightSound
		controller.nextFootIsLeft = not useLeft
		controller.distanceSinceStep = 0
		sound.PlaybackSpeed = 0.96 + math.random() * 0.08
		sound.TimePosition = 0
		sound:Play()
	end

	local function watchTrack(track)
		if controller.markerTracks[track] then
			return
		end
		controller.markerTracks[track] = true
		for _, markerName in ipairs(MARKER_NAMES) do
			table.insert(controller.connections, track:GetMarkerReachedSignal(markerName):Connect(function()
				controller.lastMarkerAt = time()
				if markerName == "LeftFootstep" then
					playStep("Left")
				elseif markerName == "RightFootstep" then
					playStep("Right")
				else
					playStep()
				end
			end))
		end
	end

	local function silenceRunningSound(instance)
		if not instance:IsA("Sound") or instance.Name ~= "Running" then
			return
		end
		if not controller.mutedSounds[instance] then
			controller.mutedSounds[instance] = {
				soundId = instance.SoundId,
				volume = instance.Volume,
			}
		end
		-- RbxCharacterSounds can start the same instance again after Stop(). An
		-- empty SoundId guarantees it remains silent without destroying an object
		-- still referenced by Roblox's CoreScript.
		instance.SoundId = ""
		instance.Volume = 0
		instance:Stop()
	end

	for _, child in ipairs(root:GetChildren()) do
		silenceRunningSound(child)
	end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		watchTrack(track)
	end

	table.insert(controller.connections, root.ChildAdded:Connect(silenceRunningSound))
	table.insert(controller.connections, animator.AnimationPlayed:Connect(watchTrack))
	table.insert(controller.connections, character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			disconnectController(character)
		end
	end))
	controller.playStep = playStep
	controller.isAbleToStep = isAbleToStep
end

local function watchCharacter(character)
	local function trySetup()
		if usesCustomFootsteps(character) then
			task.defer(setupCharacter, character)
		else
			disconnectController(character)
		end
	end
	trySetup()
	character:GetAttributeChangedSignal("MorphType"):Connect(trySetup)
	character:GetAttributeChangedSignal("UseCustomFootsteps"):Connect(trySetup)
	-- Handles streaming/order differences when the attribute replicates before
	-- HumanoidRootPart or Animator becomes available.
	character.DescendantAdded:Connect(trySetup)
end

local function watchPlayer(player)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

-- One update for all morphs is cheaper than one Heartbeat connection per player.
RunService.Heartbeat:Connect(function(deltaTime)
	for character, controller in pairs(controllers) do
		if not character.Parent then
			disconnectController(character)
			continue
		end
		if not controller.isAbleToStep() then
			controller.distanceSinceStep = 0
			continue
		end
		if time() - controller.lastMarkerAt < MARKER_FALLBACK_DELAY then
			continue
		end

		local velocity = controller.root.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		if horizontalSpeed < 1 then
			controller.distanceSinceStep = 0
			continue
		end
		local stepDistance = readNumberAttribute(
			character,
			"FootstepDistance",
			DEFAULT_STEP_DISTANCE,
			1,
			12
		)
		controller.distanceSinceStep += horizontalSpeed * math.min(deltaTime, 0.1)
		if controller.distanceSinceStep >= stepDistance then
			controller.playStep()
		end
	end
end)
