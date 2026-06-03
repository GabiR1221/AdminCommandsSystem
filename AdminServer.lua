-- ===========================================
--  SERVER SCRIPT  (with Void event support)
-- ===========================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local buttonPart = workspace:WaitForChild("ButtonPart")
local clickDetector = buttonPart:WaitForChild("ClickDetector")

local adminPanelToggle = ReplicatedStorage:WaitForChild("AdminPanelToggle")
local jumpscareAll = ReplicatedStorage:WaitForChild("JumpscareAll")
local freezeAndChatAll = ReplicatedStorage:WaitForChild("FreezeAndChatAll")
local sendCustomChatMessage = ReplicatedStorage:WaitForChild("SendCustomChatMessage")
local showBubbleAll = ReplicatedStorage:WaitForChild("ShowBubbleAll")
local kickAllPlayers = ReplicatedStorage:WaitForChild("KickAllPlayers")
local changeSkybox = ReplicatedStorage:WaitForChild("ChangeSkybox")
local spawnNPC = ReplicatedStorage:WaitForChild("SpawnNPC")
local despawnNPCs = ReplicatedStorage:WaitForChild("DespawnNPCs")
local playCommandSound = ReplicatedStorage:WaitForChild("PlayCommandSound")
local scalePlayer = ReplicatedStorage:WaitForChild("ScalePlayer")
local triggerEventCommand = ReplicatedStorage:WaitForChild("TriggerEventCommand")
local stealHeadCommand = ReplicatedStorage:WaitForChild("StealHeadCommand")

local skyboxesFolder = ServerStorage:WaitForChild("Skyboxes")
local npcsFolder = ReplicatedStorage:WaitForChild("NPCS")
local commandSoundsFolder = ReplicatedStorage:WaitForChild("CommandSounds")
local npcSpawnPart = workspace:WaitForChild("NPCSpawn")
local soundPart = workspace:WaitForChild("SoundPart")
local eventStorage = ServerStorage:WaitForChild("EventStorage")

local activeEventsFolder = workspace:FindFirstChild("ActiveEvents")
if not activeEventsFolder then
	activeEventsFolder = Instance.new("Folder")
	activeEventsFolder.Name = "ActiveEvents"
	activeEventsFolder.Parent = workspace
end

local ALLOWED_USER_IDS = {
	-- put your UserIds here
}

local TROLL_MESSAGE = "13"
local DEFAULT_KICK_MESSAGE = "You were removed from this server."

local desiredScaleByUserId = {}

-- ========== NEW: Void event variables ==========
local voidActive = false
local voidPartsContainer = nil
local voidOriginalGravity = workspace.Gravity
local voidPartData = {}   -- table: part -> {parent, cframe}
-- ===============================================

-- ========== HELPER FUNCTIONS (existing) ==========
local function isAllowed(player)
	if #ALLOWED_USER_IDS == 0 then
		return true
	end

	for _, id in ipairs(ALLOWED_USER_IDS) do
		if player.UserId == id then
			return true
		end
	end

	return false
end

local function sanitizeText(text, maxLen)
	text = tostring(text or "")
	text = text:gsub("[\r\n]", " ")
	text = text:sub(1, maxLen)
	return text
end

local function normalizeHexColor(input)
	input = tostring(input or ""):gsub("%s+", ""):upper()

	if input:sub(1, 1) == "#" then
		input = input:sub(2)
	end

	if input:match("^[0-9A-F]{6}$") then
		return input
	end

	if input:match("^[0-9A-F]{3}$") then
		return input:gsub(".", function(c)
			return c .. c
		end)
	end

	return nil
end

local function clearActiveEvents()
	for _, child in ipairs(activeEventsFolder:GetChildren()) do
		child:Destroy()
	end
end

local function readStringValue(folder, name, defaultValue)
	local obj = folder:FindFirstChild(name)
	if obj and obj:IsA("StringValue") then
		return obj.Value
	end
	return defaultValue
end

local function readBoolValue(folder, name, defaultValue)
	local obj = folder:FindFirstChild(name)
	if obj and obj:IsA("BoolValue") then
		return obj.Value
	end
	return defaultValue
end

local function getModelFromEventFolder(eventFolder, preferredName)
	local model = eventFolder:FindFirstChild(preferredName)
	if model and model:IsA("Model") then
		return model
	end

	for _, child in ipairs(eventFolder:GetChildren()) do
		if child:IsA("Model") then
			return child
		end
	end

	return nil
end

local function getAnimationId(eventFolder)
	local animObj = eventFolder:FindFirstChild("Animation")
	if animObj and animObj:IsA("Animation") and animObj.AnimationId ~= "" then
		return animObj.AnimationId
	end

	local id = readStringValue(eventFolder, "AnimationId", "")
	if id == "" then
		return ""
	end

	if id:match("^rbxassetid://") then
		return id
	end

	return "rbxassetid://" .. id
end

local function setupStaticAnimatedNPC(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		humanoid.PlatformStand = false
	end

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.Anchored = true
		hrp.CanCollide = false
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
			desc.Massless = true
			if desc ~= hrp then
				desc.Anchored = false
			end
		elseif desc:IsA("Script") and desc.Name == "Animate" then
			desc.Disabled = true
		end
	end
end

local function playLoopingAnimation(model, animationId)
	if animationId == "" then
		return
	end

	local animatorHost = model:FindFirstChildOfClass("Humanoid")
	if not animatorHost then
		animatorHost = model:FindFirstChildOfClass("AnimationController")
	end

	if not animatorHost then
		animatorHost = Instance.new("AnimationController")
		animatorHost.Parent = model
	end

	local animator = animatorHost:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = animatorHost
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = true
	task.wait()
	track:Play()
end

local function weldRootToBaseplate(model)
	local baseplate = workspace:FindFirstChild("Baseplate")
	if not baseplate or not baseplate:IsA("BasePart") then
		return
	end

	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root or not root:IsA("BasePart") then
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = baseplate
	weld.Parent = root
end

local function freezeCharacter(character, duration)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not hrp then
		return
	end

	local oldWalkSpeed = humanoid.WalkSpeed
	local oldJumpPower = humanoid.JumpPower
	local oldAutoRotate = humanoid.AutoRotate
	local oldAnchored = hrp.Anchored

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	hrp.Anchored = true

	task.delay(duration, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = oldWalkSpeed
			humanoid.JumpPower = oldJumpPower
			humanoid.AutoRotate = oldAutoRotate
		end

		if hrp and hrp.Parent then
			hrp.Anchored = oldAnchored
		end
	end)
end

local function findPlayerByNameOrDisplayName(text)
	text = tostring(text or ""):lower()

	if text == "" then
		return nil
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Name:lower() == text or plr.DisplayName:lower() == text then
			return plr
		end
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Name:lower():find(text, 1, true) or plr.DisplayName:lower():find(text, 1, true) then
			return plr
		end
	end

	return nil
end

local function applySkybox(skyName)
	local sourceSky = skyboxesFolder:FindFirstChild(skyName)
	if not sourceSky or not sourceSky:IsA("Sky") then
		return false
	end

	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") then
			child:Destroy()
		end
	end

	local newSky = sourceSky:Clone()
	newSky.Parent = Lighting

	local brightnessValue = sourceSky:FindFirstChild("Brightness")
	if not brightnessValue and sourceSky.Parent then
		brightnessValue = sourceSky.Parent:FindFirstChild("Brightness")
	end

	if brightnessValue and brightnessValue:IsA("StringValue") then
		local brightnessNumber = tonumber(brightnessValue.Value)
		if brightnessNumber then
			Lighting.Brightness = brightnessNumber
		end
	end

	local densityValue = sourceSky:FindFirstChild("Density")
	if not densityValue and sourceSky.Parent then
		densityValue = sourceSky.Parent:FindFirstChild("Density")
	end

	if densityValue and densityValue:IsA("StringValue") then
		local densityNumber = tonumber(densityValue.Value)
		if densityNumber then
			local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
			if not atmosphere then
				atmosphere = Instance.new("Atmosphere")
				atmosphere.Parent = Lighting
			end

			atmosphere.Density = math.clamp(densityNumber, 0, 1)
		end
	end

	return true
end

local function setCharacterScale(character, scaleValue)
	if not character or not character:IsA("Model") then
		return false
	end

	local ok = pcall(function()
		character:ScaleTo(scaleValue)
	end)

	return ok
end

local function applySavedScaleToPlayer(player)
	local scaleValue = desiredScaleByUserId[player.UserId]
	if not scaleValue then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	task.defer(function()
		task.wait(0.1)
		setCharacterScale(character, scaleValue)
	end)
end

local function spawnNpcByName(npcName)
	local sourceNpc = npcsFolder:FindFirstChild(npcName)
	if not sourceNpc or not sourceNpc:IsA("Model") then
		return false
	end

	local npcClone = sourceNpc:Clone()
	npcClone:SetAttribute("IsAdminNPC", true)
	npcClone.Parent = workspace
	npcClone:PivotTo(npcSpawnPart.CFrame)

	return true
end

local function despawnSpawnedNpcs()
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("Model") and inst:GetAttribute("IsAdminNPC") then
			inst:Destroy()
		end
	end
end

local function playNamedCommandSound(soundName)
	local sourceSound = commandSoundsFolder:FindFirstChild(soundName)
	if not sourceSound or not sourceSound:IsA("Sound") then
		return false
	end

	local soundClone = sourceSound:Clone()
	soundClone.Parent = soundPart
	soundClone:Play()

	soundClone.Ended:Connect(function()
		if soundClone then
			soundClone:Destroy()
		end
	end)

	task.delay(20, function()
		if soundClone and soundClone.Parent then
			soundClone:Destroy()
		end
	end)

	return true
end

local function createEventAnchor(spawnPart)
	local anchor = Instance.new("Part")
	anchor.Name = "EventAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CFrame = spawnPart.CFrame
	anchor.Parent = activeEventsFolder
	return anchor
end

local function anchorModelForAnimation(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		humanoid.PlatformStand = false
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = true
			desc.CanCollide = false
			desc.Massless = true
		end
	end
end

local function getSpawnTargetFromInstance(inst)
	local spawnValue = inst:FindFirstChild("Spawnpoint")
	if spawnValue and spawnValue:IsA("ObjectValue") then
		return spawnValue.Value
	end

	return nil
end

local function getCFrameFromTarget(target)
	if not target then
		return nil
	end

	if target:IsA("BasePart") then
		return target.CFrame
	end

	if target:IsA("Attachment") then
		return target.WorldCFrame
	end

	if target:IsA("Model") then
		local part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
		if part then
			return part.CFrame
		end
	end

	return nil
end

local function placeSpawnedInstance(inst)
	local target = getSpawnTargetFromInstance(inst)
	if not target then
		return
	end

	local cf = getCFrameFromTarget(target)
	if not cf then
		return
	end

	if inst:IsA("Model") then
		inst:PivotTo(cf)
	elseif inst:IsA("BasePart") then
		inst.CFrame = cf
	end
end

local function getSoundTarget(sound)
	local objectValue = sound:FindFirstChildWhichIsA("ObjectValue")
	if objectValue then
		return objectValue.Value
	end

	return nil
end

local function parentAndLoopSound(sound)
	local target = getSoundTarget(sound)
	if not target then
		return
	end

	if target:IsA("BasePart") or target:IsA("Attachment") then
		sound.Parent = target
	elseif target:IsA("Model") then
		local part = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
		if part then
			sound.Parent = part
		else
			return
		end
	else
		return
	end

	sound.Looped = true
	sound:Play()
end

local function runEventByCode(eventCode)
	clearActiveEvents()

	local eventFolder = eventStorage:FindFirstChild(eventCode)
	if not eventFolder or not eventFolder:IsA("Folder") then
		return false
	end

	local eventClone = eventFolder:Clone()
	eventClone.Name = eventCode .. "_Active"
	eventClone.Parent = activeEventsFolder

	-- ---------- Handle generic placement & sounds ----------
	for _, child in ipairs(eventClone:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			placeSpawnedInstance(child)
		elseif child:IsA("Sound") then
			parentAndLoopSound(child)
		end
	end

	-- ---------- BigMEvent (original) ----------
	if eventCode == "BigMEvent" then
		local modelClone = getModelFromEventFolder(eventClone, "BigM")
		if modelClone then
			setupStaticAnimatedNPC(modelClone)

			local animationId = getAnimationId(eventClone)
			if readBoolValue(eventClone, "LoopAnimation", true) then
				playLoopingAnimation(modelClone, animationId)
			end
		end

		-- ---------- NEW: Party Event ----------
	elseif eventCode == "Party" then
		local animationId = getAnimationId(eventClone)

		-- Animate ALL models inside the event folder
		for _, child in ipairs(eventClone:GetChildren()) do
			if child:IsA("Model") then
				setupStaticAnimatedNPC(child)
				playLoopingAnimation(child, animationId)
			end
		end

		-- Give every player the tool from the event folder
		local sourceTool = eventClone:FindFirstChildWhichIsA("Tool")
		if sourceTool then
			for _, plr in ipairs(Players:GetPlayers()) do
				local toolClone = sourceTool:Clone()
				toolClone.Parent = plr:WaitForChild("Backpack")
			end
		end

		-- Show the BillboardGui above every player's head
		local sourceBillboard = eventClone:FindFirstChildWhichIsA("BillboardGui")
		if sourceBillboard then
			for _, plr in ipairs(Players:GetPlayers()) do
				local character = plr.Character
				if character then
					local head = character:FindFirstChild("Head")
					if head then
						local billboardClone = sourceBillboard:Clone()
						billboardClone.Adornee = head
						billboardClone.Parent = head
						billboardClone.Enabled = true
					end
				end
			end
		end
	end

	return true
end

local HEAD_SNATCHER_MODEL_NAME = "HeadSnatcher"   -- change if you name it differently

local function getHeadSnatcherModel()
	local model = ReplicatedStorage:FindFirstChild(HEAD_SNATCHER_MODEL_NAME)
	if not model or not model:IsA("Model") then
		warn("HeadSnatch: Missing model in ReplicatedStorage named", HEAD_SNATCHER_MODEL_NAME)
		return nil
	end
	if not model.PrimaryPart then
		warn("HeadSnatch: Model", HEAD_SNATCHER_MODEL_NAME, "has no PrimaryPart set.")
		return nil
	end
	return model
end

local function tweenModelTo(model, targetCFrame, duration, onComplete)
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)
	local goal = { CFrame = targetCFrame }
	local tween = TweenService:Create(model.PrimaryPart, tweenInfo, goal)
	tween:Play()
	if onComplete then
		tween.Completed:Connect(onComplete)
	end
end

local function killPlayer(player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

local function getHeadOrRoot(character)
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return character:FindFirstChild("HumanoidRootPart")
end

-- ========== NEW: Void event helper functions ==========
local function isPartInsideCharacter(part)
	-- Returns true if the part belongs to a player character model
	local model = part:FindFirstAncestorOfClass("Model")
	if model then
		local plr = Players:GetPlayerFromCharacter(model)
		if plr then
			return true
		end
	end
	return false
end

local function safePartCollection()
	-- Collect all BaseParts in workspace that are NOT inside a player character
	local parts = {}
	for _, part in ipairs(workspace:GetDescendants()) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			-- Skip parts that are already inside ServerStorage (shouldn't happen)
			if part:IsDescendantOf(ServerStorage) then continue end
			-- Skip parts that belong to a player
			if not isPartInsideCharacter(part) then
				table.insert(parts, part)
			end
		end
	end
	return parts
end

local function toggleVoid()
	if voidActive then
		-- ---------- RESTORE EVERYTHING ----------
		if voidPartsContainer then
			for _, part in ipairs(voidPartsContainer:GetChildren()) do
				if part:IsA("BasePart") then
					local saved = voidPartData[part]
					if saved then
						local originalParent = saved.parent
						if not originalParent or not originalParent:IsDescendantOf(game) then
							originalParent = workspace
						end
						part.Parent = originalParent
						part.CFrame = saved.cframe
						voidPartData[part] = nil
					else
						part.Parent = workspace
					end
				end
			end
			voidPartsContainer:Destroy()
			voidPartsContainer = nil
		end

		workspace.Gravity = voidOriginalGravity
		voidActive = false
		warn("Void deactivated – world restored.")
	else
		-- ---------- ACTIVATE VOID ----------
		voidOriginalGravity = workspace.Gravity
		voidPartsContainer = Instance.new("Model")
		voidPartsContainer.Name = "VoidParts"
		voidPartsContainer.Parent = ServerStorage

		for _, part in ipairs(safePartCollection()) do
			voidPartData[part] = {
				parent = part.Parent,
				cframe = part.CFrame
			}
			part.Parent = voidPartsContainer
		end

		workspace.Gravity = 0.1   -- you can change this value
		voidActive = true
		warn("Void activated – map hidden, gravity lowered.")
	end
end
-- ====================================================

-- ==========================================
-- Existing event connections
-- ==========================================
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		applySavedScaleToPlayer(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	desiredScaleByUserId[player.UserId] = nil
end)

clickDetector.MouseClick:Connect(function(player)
	if not isAllowed(player) then
		return
	end

	adminPanelToggle:FireClient(player)
end)

jumpscareAll.OnServerEvent:Connect(function(player)
	if not isAllowed(player) then
		return
	end

	jumpscareAll:FireAllClients()
end)

freezeAndChatAll.OnServerEvent:Connect(function(player)
	if not isAllowed(player) then
		return
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			freezeCharacter(plr.Character, 3)
			showBubbleAll:FireAllClients(plr.Character, TROLL_MESSAGE)
		end
	end
end)

sendCustomChatMessage.OnServerEvent:Connect(function(player, nameText, messageText, colorText)
	if not isAllowed(player) then
		return
	end

	nameText = sanitizeText(nameText, 20)
	messageText = sanitizeText(messageText, 120)
	local hex = normalizeHexColor(colorText)

	if nameText == "" or messageText == "" or not hex then
		return
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		sendCustomChatMessage:FireClient(plr, nameText, messageText, hex)
	end
end)

kickAllPlayers.OnServerEvent:Connect(function(player, reasonText)
	if not isAllowed(player) then
		return
	end

	reasonText = sanitizeText(reasonText, 120)

	if reasonText == "" then
		reasonText = DEFAULT_KICK_MESSAGE
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		plr:Kick(reasonText)
	end
end)

changeSkybox.OnServerEvent:Connect(function(player, skyName)
	if not isAllowed(player) then
		return
	end

	skyName = sanitizeText(skyName, 60)
	if skyName == "" then
		return
	end

	applySkybox(skyName)
end)

spawnNPC.OnServerEvent:Connect(function(player, npcName)
	if not isAllowed(player) then
		return
	end

	npcName = sanitizeText(npcName, 60)
	if npcName == "" then
		return
	end

	spawnNpcByName(npcName)
end)

despawnNPCs.OnServerEvent:Connect(function(player)
	if not isAllowed(player) then
		return
	end

	despawnSpawnedNpcs()
end)

playCommandSound.OnServerEvent:Connect(function(player, soundName, userText)
	if not isAllowed(player) then
		return
	end

	soundName = sanitizeText(soundName, 60)
	userText = sanitizeText(userText, 60)

	if soundName == "" then
		return
	end

	local targetPlayer = findPlayerByNameOrDisplayName(userText)

	if targetPlayer then
		playCommandSound:FireClient(targetPlayer, soundName)
	else
		for _, plr in ipairs(Players:GetPlayers()) do
			playCommandSound:FireClient(plr, soundName)
		end
	end
end)

scalePlayer.OnServerEvent:Connect(function(player, scaleText)
	if not isAllowed(player) then
		return
	end

	local scaleValue = tonumber(scaleText)
	if not scaleValue then
		return
	end

	scaleValue = math.clamp(scaleValue, 0.1, 10)

	for _, plr in ipairs(Players:GetPlayers()) do
		desiredScaleByUserId[plr.UserId] = scaleValue

		if plr.Character then
			setCharacterScale(plr.Character, scaleValue)
		end
	end
end)

stealHeadCommand.OnServerEvent:Connect(function(adminPlayer, targetName)
	if not isAllowed(adminPlayer) then
		return
	end

	local target = findPlayerByNameOrDisplayName(targetName)
	if not target then
		warn("HeadSnatch: Player not found:", targetName)
		return
	end

	local character = target.Character
	if not character then
		warn("HeadSnatch: Target has no character")
		return
	end

	freezeCharacter(character, 3)

	local template = getHeadSnatcherModel()
	if not template then
		return
	end

	local snatcher = template:Clone()
	local spawnOffset = CFrame.new(character:GetPivot().Position + Vector3.new(5, 2, 0))
	snatcher:PivotTo(spawnOffset)
	snatcher.Parent = workspace

	local sound = snatcher:FindFirstChildWhichIsA("Sound")
	if sound then
		sound:Play()
	end

	local targetPart = getHeadOrRoot(character)
	if not targetPart then
		snatcher:Destroy()
		return
	end

	local targetCF = targetPart.CFrame * CFrame.new(0, 0.5, 0)
	tweenModelTo(snatcher, targetCF, 1.2, function()
		killPlayer(target)
		local flyAwayCF = targetCF * CFrame.new(0, 10, -15) * CFrame.Angles(0, math.rad(45), 0)
		tweenModelTo(snatcher, flyAwayCF, 1.5, function()
			snatcher:Destroy()
		end)
	end)
end)

-- ========== MODIFIED: Event trigger now supports Void ==========
triggerEventCommand.OnServerEvent:Connect(function(player, eventCode)
	if not isAllowed(player) then
		return
	end

	eventCode = sanitizeText(eventCode, 60)

	if eventCode == "" then
		clearActiveEvents()
		return
	end

	-- NEW: Togglable Void event
	if eventCode == "Void" then
		toggleVoid()
		return
	end

	-- All other events (Party, BigMEvent, etc.)
	runEventByCode(eventCode)
end)
