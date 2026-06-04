--[[
	StoryHorrorServer.lua
	Place this Script in ServerScriptService.

	What this system does:
	- Spawns collectible parts at chosen spawn positions and random times.
	- Each collectible uses a ProximityPrompt and disappears globally when collected.
	- Tracks each player's story points on the server.
	- Lets only players with enough points register for the story countdown.
	- Shares the same countdown with every registered player.
	- Starts a first shared task for all registered players when the countdown ends.
	- Keeps all important validation server-side for exploit resistance.

	Recommended Explorer setup:
	Workspace
	  StoryCollectibleSpawns          Folder containing Parts used only as spawn points
	  StoryStartPart                  Part that players use to register for the story
	  StoryTaskParts                  Folder containing task Parts with ProximityPrompts
	ServerStorage
	  StoryCollectibleTemplate        Optional Part/Model template for collectibles

	If folders/parts are missing, the script still runs and prints warnings.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CONFIG = {
	PointsRequired = 30,
	PointsPerCollectible = 10,
	CountdownSeconds = 60,

	-- Collectible spawning. Put invisible anchored Parts in Workspace.StoryCollectibleSpawns.
	SpawnPointsFolderName = "StoryCollectibleSpawns",
	CollectibleTemplateName = "StoryCollectibleTemplate",
	DisablePromptsOnSpawnMarkers = true,
	AnchorSpawnedCollectibles = true,
	RuntimeFolderName = "StoryHorrorRuntime",
	MaxActiveCollectibles = 8,
	SpawnBatchMin = 1,
	SpawnBatchMax = 2,
	SpawnDelayMin = 8,
	SpawnDelayMax = 20,
	CollectibleLifetimeSeconds = 120,
	CollectiblePromptText = "Collect",
	CollectibleObjectText = "Strange Part",

	-- Optional fallback positions used if Workspace.StoryCollectibleSpawns does not exist or is empty.
	-- Change these Vector3 values to whatever positions you want.
	FallbackSpawnPositions = {
		Vector3.new(0, 4, 0),
		Vector3.new(12, 4, 0),
		Vector3.new(-12, 4, 0),
	},

	-- Story registration prompt.
	StoryStartPartName = "StoryStartPart",
	StoryStartPromptActionText = "Start Story",
	StoryStartPromptObjectText = "Story Gate",

	-- Task 1: one clue part teleports all registered story players, then Task 2 starts.
	FirstTaskId = "FirstTask",
	FirstTaskTitle = "dute in cancelarie",
	FirstTaskDescription = "Find the clue and inspect it.",
	Task1CluePartName = "Task1Part",
	Task1TeleportPartName = "Task1TeleportPart",
	FirstTaskPromptText = "Find the clue",
	FirstTaskObjectText = "Clue",

	-- Task 2: players draw on the UI and every registered story player must confirm.
	SecondTaskId = "DrawSigil",
	SecondTaskTitle = "Draw the Sigil",
	SecondTaskDescription = "Draw anything on the page, then confirm with the others.",
	Task2Image = "rbxassetid://0", -- replace 0 with your ImageLabel asset id
	Task2CompleteTeleportPartName = "Task2CompleteTeleport",

	-- Task 3: automatic wait task after the Task 2 transition.
	ThirdTaskId = "WaitInDarkness",
	ThirdTaskTitle = "Wait in the Darkness",
	ThirdTaskDescription = "Stay alive and wait.",
	ThirdTaskWaitSeconds = 120,

	-- Optional teleport when the countdown finishes. Create a Part named StoryStartTeleport in Workspace.
	StartTeleportPartName = "StoryStartTeleport",
	TeleportPlayersOnStart = false,
}

local REMOTE_EVENT_NAME = "StoryHorrorUIEvent"

local rng = Random.new()
local playerData = {}
local registeredPlayers = {}
local countdownEndsAt = nil
local countdownTaskRunning = false
local storyActive = false
local activeStoryPlayers = {}
local currentTask = nil
local occupiedSpawnKeys = {}
local task2ConfirmedByUserId = {}
local task2ConfirmedCount = 0

local runtimeFolder = Workspace:FindFirstChild(CONFIG.RuntimeFolderName)
if not runtimeFolder then
	runtimeFolder = Instance.new("Folder")
	runtimeFolder.Name = CONFIG.RuntimeFolderName
	runtimeFolder.Parent = Workspace
end

local collectiblesFolder = runtimeFolder:FindFirstChild("Collectibles")
if not collectiblesFolder then
	collectiblesFolder = Instance.new("Folder")
	collectiblesFolder.Name = "Collectibles"
	collectiblesFolder.Parent = runtimeFolder
end

local remoteEvent = ReplicatedStorage:FindFirstChild(REMOTE_EVENT_NAME)
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = REMOTE_EVENT_NAME
	remoteEvent.Parent = ReplicatedStorage
end

local function getData(player)
	local data = playerData[player]
	if not data then
		data = {
			points = 0,
			registered = false,
			inStory = false,
		}
		playerData[player] = data
	end
	return data
end

local function fireUi(player, action, payload)
	remoteEvent:FireClient(player, action, payload or {})
end

local function fireUiToRegistered(action, payload)
	for player in pairs(registeredPlayers) do
		if player.Parent == Players then
			fireUi(player, action, payload)
		end
	end
end

local function fireUiToStoryPlayers(action, payload)
	for player in pairs(activeStoryPlayers) do
		if player.Parent == Players then
			fireUi(player, action, payload)
		end
	end
end

local function fireUiToAllPlayers(action, payload)
	for _, player in ipairs(Players:GetPlayers()) do
		fireUi(player, action, payload)
	end
end

local function isCollectibleTemplateCandidate(instance)
	return instance:IsA("BasePart") or instance:IsA("Model")
end

local function findDescendantCaseInsensitive(parent, childName)
	local wanted = string.lower(childName)

	local exact = parent:FindFirstChild(childName)
	if exact and isCollectibleTemplateCandidate(exact) then
		return exact
	end

	for _, descendant in ipairs(parent:GetDescendants()) do
		if string.lower(descendant.Name) == wanted and isCollectibleTemplateCandidate(descendant) then
			return descendant
		end
	end

	return nil
end

local function getCollectibleTemplate()
	local searchRoots = {
		ServerStorage,
		ReplicatedStorage,
		Workspace,
	}

	for _, root in ipairs(searchRoots) do
		local template = findDescendantCaseInsensitive(root, CONFIG.CollectibleTemplateName)
		if template then
			return template
		end
	end

	return nil
end

local function disablePromptDescendants(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		end
	end
end

local function configureCollectiblePhysics(instance)
	if not CONFIG.AnchorSpawnedCollectibles then
		return
	end

	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		return
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
end

local function disableSpawnMarkerPrompts()
	if not CONFIG.DisablePromptsOnSpawnMarkers then
		return
	end

	local folder = Workspace:FindFirstChild(CONFIG.SpawnPointsFolderName)
	if not folder then
		return
	end

	for _, child in ipairs(folder:GetDescendants()) do
		if child:IsA("ProximityPrompt") then
			child.Enabled = false
		end
	end
end

local function getStoryStartPrompt()
	local part = Workspace:FindFirstChild(CONFIG.StoryStartPartName)
	if not part or not part:IsA("BasePart") then
		warn("StoryHorror: Missing Workspace." .. CONFIG.StoryStartPartName .. " BasePart")
		return nil
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = part
	end

	prompt.ActionText = CONFIG.StoryStartPromptActionText
	prompt.ObjectText = CONFIG.StoryStartPromptObjectText
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Enabled = true
	return prompt
end

local function getSpawnEntries()
	local entries = {}
	local folder = Workspace:FindFirstChild(CONFIG.SpawnPointsFolderName)
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(entries, {
					key = child:GetFullName(),
					cframe = child.CFrame,
				})
			end
		end
	end

	if #entries == 0 then
		for index, position in ipairs(CONFIG.FallbackSpawnPositions) do
			table.insert(entries, {
				key = "FallbackSpawn_" .. tostring(index),
				cframe = CFrame.new(position),
			})
		end
	end

	return entries
end

local function chooseAvailableSpawnEntry()
	local openEntries = {}
	for _, entry in ipairs(getSpawnEntries()) do
		if not occupiedSpawnKeys[entry.key] then
			table.insert(openEntries, entry)
		end
	end

	if #openEntries == 0 then
		return nil
	end

	local entry = openEntries[rng:NextInteger(1, #openEntries)]
	occupiedSpawnKeys[entry.key] = true
	return entry
end

local function releaseSpawnEntry(entry)
	if entry then
		occupiedSpawnKeys[entry.key] = nil
	end
end

local function setInstanceCFrame(instance, cframe)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

local function createDefaultCollectible()
	local part = Instance.new("Part")
	part.Name = "StoryCollectible"
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(130, 0, 180)
	part.Anchored = true
	part.CanCollide = false
	return part
end

local function createCollectible()
	local spawnEntry = chooseAvailableSpawnEntry()
	if not spawnEntry then
		return nil
	end

	local template = getCollectibleTemplate()
	local collectible
	if template then
		collectible = template:Clone()
	else
		collectible = createDefaultCollectible()
		warn("StoryHorror: Could not find a BasePart or Model named " .. CONFIG.CollectibleTemplateName .. " in ServerStorage, ReplicatedStorage, or Workspace. Using fallback sphere.")
	end

	collectible.Name = "StoryCollectible"
	disablePromptDescendants(collectible)
	configureCollectiblePhysics(collectible)
	collectible.Parent = collectiblesFolder
	setInstanceCFrame(collectible, spawnEntry.cframe)

	local promptParent = collectible
	if collectible:IsA("Model") then
		promptParent = collectible.PrimaryPart or collectible:FindFirstChildWhichIsA("BasePart", true)
		if not promptParent then
			warn("StoryHorror: Collectible template has no BasePart for the ProximityPrompt.")
			releaseSpawnEntry(spawnEntry)
			collectible:Destroy()
			return nil
		end
	end

	local prompt = promptParent:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = promptParent
	end

	prompt.ActionText = CONFIG.CollectiblePromptText
	prompt.ObjectText = CONFIG.CollectibleObjectText
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Enabled = true

	local releasedSpawn = false
	local function releaseOnce()
		if releasedSpawn then
			return
		end
		releasedSpawn = true
		releaseSpawnEntry(spawnEntry)
	end

	collectible.Destroying:Connect(releaseOnce)

	local collected = false
	prompt.Triggered:Connect(function(player)
		if collected or not player or player.Parent ~= Players then
			return
		end

		collected = true
		local data = getData(player)
		data.points += CONFIG.PointsPerCollectible
		fireUi(player, "PointsUpdate", {
			points = data.points,
			required = CONFIG.PointsRequired,
			pointsPerCollectible = CONFIG.PointsPerCollectible,
		})

		releaseOnce()
		collectible:Destroy()
	end)

	task.delay(CONFIG.CollectibleLifetimeSeconds, function()
		if collectible and collectible.Parent then
			releaseOnce()
			collectible:Destroy()
		end
	end)

	return collectible
end

local function activeCollectibleCount()
	local count = 0
	for _, child in ipairs(collectiblesFolder:GetChildren()) do
		if child.Name == "StoryCollectible" then
			count += 1
		end
	end
	return count
end

local function sendFullState(player)
	local data = getData(player)
	fireUi(player, "PointsUpdate", {
		points = data.points,
		required = CONFIG.PointsRequired,
		pointsPerCollectible = CONFIG.PointsPerCollectible,
	})

	if countdownEndsAt and data.registered then
		fireUi(player, "Countdown", {
			endsAt = countdownEndsAt,
		})
	end

	if currentTask and data.inStory then
		fireUi(player, "TaskUpdate", currentTask)
		if currentTask.taskId == CONFIG.SecondTaskId then
			fireUi(player, "Task2Start", {
				image = CONFIG.Task2Image,
				confirmed = task2ConfirmedCount,
				total = currentTask.required,
			})
		end
	end
end

local function storyPlayerCount()
	local count = 0
	for player in pairs(activeStoryPlayers) do
		if player.Parent == Players then
			count += 1
		end
	end
	return count
end

local function teleportStoryPlayersToPart(partName)
	local teleportPart = Workspace:FindFirstChild(partName)
	if not teleportPart or not teleportPart:IsA("BasePart") then
		warn("StoryHorror: Missing teleport BasePart named " .. partName)
		return false
	end

	for player in pairs(activeStoryPlayers) do
		if player.Parent == Players then
			local character = player.Character
			if character then
				character:PivotTo(teleportPart.CFrame + Vector3.new(0, 3, 0))
			end
		end
	end

	return true
end

local function teleportStoryPlayersIfConfigured()
	if CONFIG.TeleportPlayersOnStart then
		teleportStoryPlayersToPart(CONFIG.StartTeleportPartName)
	end
end

local function finishCurrentTask(message)
	if not currentTask then
		return
	end

	fireUiToStoryPlayers("TaskComplete", {
		taskId = currentTask.taskId,
		title = currentTask.title,
		message = message or "Task complete.",
	})
	currentTask = nil
end

local function startThirdTask()
	currentTask = {
		taskId = CONFIG.ThirdTaskId,
		title = CONFIG.ThirdTaskTitle,
		description = CONFIG.ThirdTaskDescription,
		progress = 0,
		required = CONFIG.ThirdTaskWaitSeconds,
		endsAt = Workspace:GetServerTimeNow() + CONFIG.ThirdTaskWaitSeconds,
	}

	fireUiToStoryPlayers("TaskUpdate", currentTask)

	task.delay(CONFIG.ThirdTaskWaitSeconds, function()
		if currentTask and currentTask.taskId == CONFIG.ThirdTaskId then
			finishCurrentTask("The wait is over.")
		end
	end)
end

local function completeSecondTask()
	if not currentTask or currentTask.taskId ~= CONFIG.SecondTaskId then
		return
	end

	finishCurrentTask("Everyone confirmed the drawing.")
	fireUiToStoryPlayers("Task2End", {})
	fireUiToStoryPlayers("FadeTransition", {
		fadeInSeconds = 1,
		holdSeconds = 2,
		fadeOutSeconds = 1,
	})

	task.delay(2, function()
		teleportStoryPlayersToPart(CONFIG.Task2CompleteTeleportPartName)
		startThirdTask()
	end)
end

local function sendTask2ConfirmUpdate()
	fireUiToStoryPlayers("Task2ConfirmUpdate", {
		confirmed = task2ConfirmedCount,
		total = storyPlayerCount(),
	})
end

local function startSecondTask()
	task2ConfirmedByUserId = {}
	task2ConfirmedCount = 0
	currentTask = {
		taskId = CONFIG.SecondTaskId,
		title = CONFIG.SecondTaskTitle,
		description = CONFIG.SecondTaskDescription,
		progress = 0,
		required = storyPlayerCount(),
	}

	fireUiToStoryPlayers("TaskUpdate", currentTask)
	fireUiToStoryPlayers("Task2Start", {
		image = CONFIG.Task2Image,
		confirmed = task2ConfirmedCount,
		total = storyPlayerCount(),
	})
end

local function completeFirstTask(player)
	if not currentTask or currentTask.taskId ~= CONFIG.FirstTaskId or not activeStoryPlayers[player] then
		return
	end

	finishCurrentTask("The clue has been inspected.")
	teleportStoryPlayersToPart(CONFIG.Task1TeleportPartName)
	startSecondTask()
end

local function prepareFirstTaskPrompt()
	local cluePart = Workspace:FindFirstChild(CONFIG.Task1CluePartName)
	if not cluePart or not cluePart:IsA("BasePart") then
		warn("StoryHorror: Missing Workspace." .. CONFIG.Task1CluePartName .. " BasePart for Task 1")
		return
	end

	local prompt = cluePart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = cluePart
	end

	prompt.ActionText = CONFIG.FirstTaskPromptText
	prompt.ObjectText = CONFIG.FirstTaskObjectText
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Enabled = true

	local triggered = false
	prompt.Triggered:Connect(function(player)
		if triggered then
			return
		end

		if not currentTask or currentTask.taskId ~= CONFIG.FirstTaskId or not activeStoryPlayers[player] then
			return
		end

		triggered = true
		prompt.Enabled = false
		completeFirstTask(player)
	end)
end

local function startFirstTask()
	currentTask = {
		taskId = CONFIG.FirstTaskId,
		title = CONFIG.FirstTaskTitle,
		description = CONFIG.FirstTaskDescription,
		progress = 0,
		required = 1,
	}

	prepareFirstTaskPrompt()
	fireUiToStoryPlayers("TaskUpdate", currentTask)
end

local function startStory()
	storyActive = true
	countdownEndsAt = nil
	countdownTaskRunning = false
	activeStoryPlayers = {}

	for player in pairs(registeredPlayers) do
		if player.Parent == Players then
			local data = getData(player)
			data.inStory = true
			activeStoryPlayers[player] = true
		end
	end

	registeredPlayers = {}
	teleportStoryPlayersIfConfigured()
	fireUiToAllPlayers("HidePoints", {})
	fireUiToStoryPlayers("StoryStarted", {
		points = 0,
		required = CONFIG.PointsRequired,
	})
	startFirstTask()
end

local function startCountdownIfNeeded()
	if countdownTaskRunning then
		return
	end

	countdownTaskRunning = true
	countdownEndsAt = Workspace:GetServerTimeNow() + CONFIG.CountdownSeconds
	fireUiToRegistered("Countdown", {
		endsAt = countdownEndsAt,
	})

	task.spawn(function()
		while countdownEndsAt do
			local remaining = countdownEndsAt - Workspace:GetServerTimeNow()
			if remaining <= 0 then
				startStory()
				break
			end
			task.wait(0.5)
		end
	end)
end

local function registerForCountdown(player)
	if storyActive then
		fireUi(player, "Message", { text = "The story already started." })
		return
	end

	local data = getData(player)
	if data.points < CONFIG.PointsRequired then
		fireUi(player, "Message", {
			text = "You need " .. tostring(CONFIG.PointsRequired) .. " points first.",
		})
		return
	end

	data.registered = true
	registeredPlayers[player] = true
	fireUi(player, "Registered", {})

	if countdownEndsAt then
		fireUi(player, "Countdown", {
			endsAt = countdownEndsAt,
		})
	else
		startCountdownIfNeeded()
	end
end

local function spawnLoop()
	while true do
		local delaySeconds = rng:NextNumber(CONFIG.SpawnDelayMin, CONFIG.SpawnDelayMax)
		task.wait(delaySeconds)

		if storyActive then
			continue
		end

		local activeCount = activeCollectibleCount()
		local openSlots = CONFIG.MaxActiveCollectibles - activeCount
		if openSlots > 0 then
			local batch = math.min(openSlots, rng:NextInteger(CONFIG.SpawnBatchMin, CONFIG.SpawnBatchMax))
			for _ = 1, batch do
				createCollectible()
			end
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	getData(player)
	task.defer(sendFullState, player)
end)

Players.PlayerRemoving:Connect(function(player)
	playerData[player] = nil
	registeredPlayers[player] = nil
	activeStoryPlayers[player] = nil

	if currentTask and currentTask.taskId == CONFIG.SecondTaskId then
		currentTask.required = storyPlayerCount()
		sendTask2ConfirmUpdate()
		if currentTask.required > 0 and task2ConfirmedCount >= currentTask.required then
			completeSecondTask()
		end
	end
end)

remoteEvent.OnServerEvent:Connect(function(player, action)
	if action ~= "Task2Confirm" then
		return
	end

	if not currentTask or currentTask.taskId ~= CONFIG.SecondTaskId or not activeStoryPlayers[player] then
		return
	end

	if task2ConfirmedByUserId[player.UserId] then
		return
	end

	task2ConfirmedByUserId[player.UserId] = true
	task2ConfirmedCount += 1
	currentTask.progress = task2ConfirmedCount
	currentTask.required = storyPlayerCount()
	sendTask2ConfirmUpdate()
	fireUiToStoryPlayers("TaskUpdate", currentTask)

	if currentTask.required > 0 and task2ConfirmedCount >= currentTask.required then
		completeSecondTask()
	end
end)

disableSpawnMarkerPrompts()

local startPrompt = getStoryStartPrompt()
if startPrompt then
	startPrompt.Triggered:Connect(registerForCountdown)
end

for _ = 1, math.min(CONFIG.MaxActiveCollectibles, 3) do
	createCollectible()
end

task.spawn(spawnLoop)
