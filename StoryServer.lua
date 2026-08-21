--[[
	StoryHorrorServer.lua
	Place this Script in ServerScriptService.

	What this system does:
	- Spawns collectible parts at chosen spawn positions and random times.
	- Each collectible uses a ClickDetector and disappears globally when collected.
	- Tracks each player's story points on the server.
	- Lets only players with enough points register for the story countdown.
	- Shares the same countdown with every registered player.
	- Starts a first shared task for all registered players when the countdown ends.
	- Keeps all important validation server-side for exploit resistance.

	Recommended Explorer setup:
	Workspace
	  StoryCollectibleSpawns          Folder containing Parts used only as spawn points
	  StoryStartPart                  Part that players use to register for the story
	  Task1Part                       Waypoint Part touched by story players for Task 1
	ServerStorage
	  StoryCollectibleTemplate        Optional Part/Model template for collectibles
	  StoryStorage                    Folder containing map folders, for example Task2Map
	  Skyboxes                        Folder containing skybox models, each with
	                                 StringValues "Brightness" and "Density"

	If folders/parts are missing, the script still runs and prints warnings.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local CONFIG = {
	PointsRequired = 30,
	PointsPerCollectible = 10,
	CountdownSeconds = 5,

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
	CollectibleClickDistance = 16,

	-- Optional fallback positions used if Workspace.StoryCollectibleSpawns does not exist or is empty.
	FallbackSpawnPositions = {
		Vector3.new(0, 4, 0),
		Vector3.new(12, 4, 0),
		Vector3.new(-12, 4, 0),
	},

	-- Story registration prompt.
	StoryStartPartName = "StoryStartPart",
	StoryStartPromptActionText = "Start Story",
	StoryStartPromptObjectText = "Story Gate",

	-- Task 1: when any active story player reaches this waypoint, every story player advances.
	FirstTaskId = "FirstTask",
	FirstTaskTitle = "dute in cancelarie",
	FirstTaskDescription = "cancelaria este pe hol in capat",
	Task1WaypointPartName = "Task1Part",
	Task1TeleportPartName = "Task1TeleportPart",

	-- Task 2: players draw on the UI and every registered story player must confirm.
	SecondTaskId = "DrawSigil",
	SecondTaskTitle = "Semneaza",
	SecondTaskDescription = "Semneaza si apoi asteapta-i pe ceilalti ca sa semneze",
	Task2Image = "rbxassetid://0", -- replace 0 with your ImageLabel asset id
	Task2CompleteTeleportPartName = "Task2CompleteTeleport",

	-- Task 3: automatic wait task after the Task 2 transition.
	ThirdTaskId = "WaitInDarkness",
	ThirdTaskTitle = "Excursie",
	ThirdTaskDescription = "Asteapta pana la destinatie",
	ThirdTaskWaitSeconds = 25,

	-- Task 4: starts after Task 3, fades to black with text, teleports players, then shows the next shared task.
	FourthTaskId = "AfterDarkness",
	FourthTaskTitle = "Exploreaza Tacaul",
	FourthTaskDescription = "Asteapta sa vina DoamnaN",
	Task4TeleportPartName = "Task4TeleportPart",
	Task4FadeText = "Ati ajuns la destinatie...",
	Task4FadeInSeconds = 1,
	Task4FadeHoldSeconds = 3,
	Task4FadeOutSeconds = 1,
	Task4TeleportDelaySeconds = 1.4,

	-- Map loading. Put map folders in ServerStorage.StoryStorage and set Task2MapFolderName to the one you want.
	StoryStorageFolderName = "StoryStorage",
	Task2MapFolderName = "strada",
	Task4MapFolderName = "TacauCityResidence",
	LoadedMapFolderName = "LoadedStoryMap",
	MoveMapInsteadOfClone = false,

	-- Optional teleport when the countdown finishes. Create a Part named StoryStartTeleport in Workspace.
	StartTeleportPartName = "StoryStartTeleport",
	TeleportPlayersOnStart = false,

	-- Data-driven story tasks. Change Type to "Waypoint", "Drawing", "Wait", "Instant", or "Delivery".
	-- StartActions run when a task begins. EndActions run after that task completes.
	-- Supported actions: Fade, Teleport, LoadMap, UnloadMap, UnloadAllMaps, Conversation, Cutscene, CloseCutscene, PlayAnimation, StopAnimation, CloseDrawing, CloseConversation, Message, PlaySound, SetLighting.
	Tasks = {
		{
			Id = "FirstTask",
			Type = "Waypoint",
			Title = "du-te in cancelarie",
			Description = "Pregateste-te pentru excursie",
			WaypointPartName = "Task1Part",
			Required = 1,
			CompleteMessage = "Ati ajuns in cancelarie",
			EndActions = {
				{ Type = "Teleport", PartName = "Task1TeleportPart" },
			},
		},
		{
			Id = "AfterDarkness0",
			Type = "Wait",
			Title = "",
			Description = "",
			Duration = 20,
			StartActions = {
				{
					Type = "Conversation",
					Delay = 1,
					CameraPartName = "CancelarieCameraPart",
					TypewriterSpeed = 0.035,
					Pages = {
						{ Text = "Bun dragilor.... acum ca ati adus banii de excursie, trebuie sa semnati un acord prin care sa aratati ca sunteti de acord cu excursia si toate cele legate de excursie.", Duration = 6 },
						{ Text = "O sa va dau foaia imediat, doar stati putin(sunete mici chiar inauzibile fara un microscop de demon)", Duration = 5 },
					},
				},
			},
		},
		{
			Id = "DrawSigil",
			Type = "Drawing",
			Title = "Semneaza Acordul",
			Description = "Semneaza pe partea alba pentru a lua in consimtamant cele mentionate in acordul de mai sus",
			Image = "rbxassetid://3440288322",
			CompleteMessage = "Toata lumea a semnat acordul",
			EndActions = {
				{ Type = "CloseDrawing" },
				{ Type = "Fade", FadeInSeconds = 1, HoldSeconds = 2, FadeOutSeconds = 1, Text = "Ziua Urmatoare..."},
				{ Type = "Teleport", PartName = "Task2CompleteTeleport", Delay = 2 },
				{ Type = "LoadMap", MapName = "strada", LoadedName = "LoadedStoryMap", Delay = 1 },
			},
		},
		{
			Id = "WaitInDarkness",
			Type = "Wait",
			Title = "Asteptati pana la destinatia excursiei",
			Description = "Destinatia: Tacau",
			Duration = 15,
			CompleteMessage = "Ati ajuns",
			StartActions = {
				{ Type = "Fade", FadeInSeconds = 1, HoldSeconds = 3, FadeOutSeconds = 1, Text = "Dupa ceva timp...." },
				{ Type = "Teleport", PartName = "Task4TeleportPart", Delay = 1.4 },
				{
					Type = "PlayAnimation",
					ModelName = "masinblej2",
					AnimationName = "MasinaBlej",
					ModelRootName = "LoadedStoryMap", -- must match LoadMap.LoadedName
					TrackName = "masinablej", -- unique ID used to stop/replace this track
					Looped = true,
					Speed = 1,
					FadeTime = 0.25,
					Priority = "Action",
					Duration = 30,        -- optional; automatically stops after 8 seconds or = Duration
				},
				{
					Type = "PlayAnimation",
					ModelRootName = "LoadedStoryMap", -- must match LoadMap.LoadedName
					ModelName = "pigon",
					AnimationName = "Pigon",  -- Animation is inside the pigon Model
					TrackName = "PigonIdleTrack",
					Looped = true,
					WaitForModelSeconds = 5,
					Duration = 30,
				},
			},
			EndActions = {
				{
					Type = "StopAnimation",
					TrackName = "masinablej",
					Delay = 1,
					FadeTime = 0.5,
				},
				{
					Type = "StopAnimation",
					TrackName = "pigon",
					Delay = 1,
					FadeTime = 0.5,
				}
			},
		},
		{
			Id = "WaitInDarkness2",
			Type = "Wait",
			Title = "Explorati tacaul sau asteptati sa vina DoamnaN",
			Description = "alup",
			Duration = 15,
			StartActions = {
				{ Type = "Fade", FadeInSeconds = 1, HoldSeconds = 3, FadeOutSeconds = 1, Text = "Dupa ceva timp...." },
				{ Type = "LoadMap", MapName = "TacauCityResidence", LoadedName = "LoadedStoryMap", Delay = 1 },
				{ Type = "Teleport", PartName = "Task4TeleportPart", Delay = 1.4 },
			},
		},
		{
			Id = "AfterDarkness",
			Type = "Wait",
			Title = "Dialog cu DoamnaN",
			Description = "...",
			Duration = 30,
			StartActions = {
				{ Type = "Teleport", PartName = "Task4TeleportPart", Delay = 1.4 },
				{ Type = "LoadMap", MapName = "DoamnaN", LoadedName = "DoamnaNLoaded", Delay = 1 },
				{
					Type = "Conversation",
					Delay = 2.5,
					CameraPartName = "Task4CameraPart",
					TypewriterSpeed = 0.035,
					Pages = {
						{ Text = "Bine ati venit la Tacau! sper ca nu v-a fost greu drumul deoarece va fi o excursie lunga si frumoasa!", Duration = 6 },
						{ Text = "Bun dragilor, acum problema este ca trebuie sa ajungem pe partea cealalta a dunarii si nu avem cu ce, este o barca acolo dar nu incapem toti, puteti face pod cu lemnele pe care le gasiti in padure?", Duration = 8 },
					},
				},
			},
		},
		-- Delivery task example. No StageDisplayPart is needed – stages appear exactly where they were in ServerStorage.
		{
			Id = "CarryRelics",
			Type = "Delivery",
			Title = "Luati 3 lemne",
			Description = "luati lemne pentru a face pod spre cabana in care veti dormi in aceasta excursie mirobolanta",
			ItemsFolderName = "RelicItems", -- Folder in ServerStorage.StoryStorage or Workspace.
			DeliveryPartName = "RelicDeliveryPart",
			RequiredDeliveries = 3,
			StageFolderName = "RelicStages", -- Contains Stage1, Stage2, Stage3 models.
			EndActions = {
				-- Example of a sound that plays 3 times with 2 seconds between each:
				-- { Type = "PlaySound", SoundName = "RelicCompleteSound", PlayCount = 3, PlayInterval = 2 },
			},
		},
		{
			Id = "AfterDarkness2",
			Type = "Wait",
			Title = "Dialog cu DoamnaN2",
			Description = "...",
			Duration = 15,
			StartActions = {
				{
					Type = "Conversation",
					Delay = 4,
					CameraPartName = "Task4CameraPart",
					TypewriterSpeed = 0.035,
					Pages = {
						{ Text = "Bravo ca ati facut podul dragilor!", Duration = 4 },
						{ Text = "acum trebuie sa ma duc undeva, m-a chemat doamna directoare, duceti-va la cabana ca voi veni eu dragilor!", Duration = 6 },
					},
				},
			},
		},
		{
			Id = "AfterRelics",
			Type = "Waypoint",
			Title = "dute la cabana",
			Description = "Dormiti la cabana k idee",
			WaypointPartName = "CabanaWaypointPart",
			Required = 1,
			CompleteMessage = "Ati ajuns la cabana",
			EndActions = {
				{ Type = "Teleport", PartName = "TaskCabanaTeleportPart" },
				-- Unload map (works with "UnloadMap" or "UnLoadMap", etc.)
				{ Type = "UnLoadMap", MapName = "DoamnaN", LoadedName = "DoamnaNLoaded", Delay = 1 },
				{ Type = "SetLighting", SkyboxName = "Black" },
				--{ Type = "LoadMap", MapName = "police", LoadedName = "policeLoaded", Delay = 1 },
				--{ Type = "PlaySound", SoundName = "RelicCompleteSound", PlayCount = 3, PlayInterval = 2 },
			},
		},
		{
			Id = "WaitInDarkness3",
			Type = "Wait",
			Title = "Explorati cabana",
			Description = "Asteptati putintel in cabana pentru a va culca linistiti",
			Duration = 15,
			CompleteMessage = "...",
			StartActions = {
				{ Type = "Teleport", PartName = "CabanaTeleportPart", Delay = 1.4 },
				{ Type = "LoadMap", MapName = "PeretiCabana", LoadedName = "PeretiLoaded", Delay = 1 },

			},
			
		},
		{
			Id = "AfterDarkness3",
			Type = "Wait",
			Title = "...",
			Description = "...",
			Duration = 150,
			StartActions = {
				--{ Type = "PlaySound", SoundName = "RelicCompleteSound", PlayCount = 3, PlayInterval = 2 },
				{
					Type = "Cutscene",
					Delay = 1,                  -- optional delay before the whole action
					FreezeControls = true,      -- default true
					Shots = {
						{
							CameraPartName = "CabanaCamera1",
							MoveDuration = 0,   -- 0 snaps to this point
							HoldDuration = 5,
							FieldOfView = 70,
						},
						{
							CameraPartName = "CabanaCamera2",
							MoveDuration = 2,
							HoldDuration = 5,
							EasingStyle = "Sine",
							EasingDirection = "InOut",
							FieldOfView = 80,
						},
					},
					Events = {
						{
							Type = "BlackScreen",
							Time = 8,
							TransitionType = "Wink", -- top/bottom eyelids close and open
							FadeInSeconds = 0.25,
							HoldSeconds = 1,
							FadeOutSeconds = 0.4,
						},
					},
				},
			},
			EndActions = {
				{ Type = "LoadMap", MapName = "police", LoadedName = "policeLoaded", Delay = 1 },
				{ Type = "CloseCutscene", Delay = 1 }
				--{ Type = "PlaySound", SoundName = "RelicCompleteSound", PlayCount = 3, PlayInterval = 2 },
			},
		},
	},
}


--[[
{
	Type = "Cutscene",
	Delay = 1,                  -- optional delay before the whole action
	FreezeControls = true,      -- default true
	Shots = {
		{
			CameraPartName = "IntroCamera1",
			MoveDuration = 0,   -- 0 snaps to this point
			HoldDuration = 2,
			FieldOfView = 70,
			SoundName = "IntroBoom", -- optional Sound in ServerStorage.StoryStorage
			Volume = 0.8,              -- optional per-shot override
			PlaybackSpeed = 1,         -- optional per-shot override
		},
		{
			CameraPartName = "IntroCamera2",
			MoveDuration = 4,
			HoldDuration = 1.5,
			EasingStyle = "Sine",
			EasingDirection = "InOut",
			FieldOfView = 55,
		},
		{
			CameraPartName = "IntroCamera3",
			MoveDuration = 2,
			HoldDuration = 3,
			EasingStyle = "Quad",
			EasingDirection = "Out",
		},
	},
	    Events = {
        {
            Type = "BlackScreen",
            Time = 1.5,
            TransitionType = "Normal", -- regular fade to/from black
            FadeInSeconds = 0.4,
            HoldSeconds = 1,
            FadeOutSeconds = 0.5,
        },
        {
            Type = "BlackScreen",
            Time = 6,
            TransitionType = "Wink", -- top/bottom eyelids close and open
            FadeInSeconds = 0.25,
            HoldSeconds = 0.6,
            FadeOutSeconds = 0.4,
        },
    },
},
--]]

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
local loadedStoryMaps = {}
local currentTaskConnection = nil
local currentTaskToken = 0
local currentTaskConnections = {}
local currentDeliveryState = nil
local activeStoryAnimationTracks = {}

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

local function removePromptDescendants(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end
end

local function disablePromptDescendants(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		end
	end
end

local function disablePromptOnPart(partName)
	local part = Workspace:FindFirstChild(partName)
	if not part then
		return
	end

	if part:IsA("BasePart") then
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = false
		end
	end

	disablePromptDescendants(part)
end

local function disableUnusedStoryPrompts()
	disablePromptOnPart(CONFIG.Task1WaypointPartName)
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
	removePromptDescendants(collectible)
	configureCollectiblePhysics(collectible)
	collectible.Parent = collectiblesFolder
	setInstanceCFrame(collectible, spawnEntry.cframe)

	local clickParent = collectible
	if collectible:IsA("Model") then
		clickParent = collectible.PrimaryPart or collectible:FindFirstChildWhichIsA("BasePart", true)
		if not clickParent then
			warn("StoryHorror: Collectible template has no BasePart for the ClickDetector.")
			releaseSpawnEntry(spawnEntry)
			collectible:Destroy()
			return nil
		end
	end

	local clickDetectors = {}
	for _, descendant in ipairs(collectible:GetDescendants()) do
		if descendant:IsA("ClickDetector") then
			table.insert(clickDetectors, descendant)
		end
	end

	if #clickDetectors == 0 and clickParent:IsA("BasePart") then
		local clickDetector = Instance.new("ClickDetector")
		clickDetector.Parent = clickParent
		table.insert(clickDetectors, clickDetector)
	end

	for _, clickDetector in ipairs(clickDetectors) do
		clickDetector.MaxActivationDistance = CONFIG.CollectibleClickDistance
	end

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
	local function collect(player)
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
	end

	for _, clickDetector in ipairs(clickDetectors) do
		clickDetector.MouseClick:Connect(collect)
	end

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

local function storyPlayerCount()
	local count = 0
	for player in pairs(activeStoryPlayers) do
		if player.Parent == Players then
			count += 1
		end
	end
	return count
end


local function getTaskAt(index)
	return CONFIG.Tasks and CONFIG.Tasks[index] or nil
end

local function getTaskType(taskConfig)
	return tostring(taskConfig.Type or "Instant")
end

local function getTaskRequired(taskConfig)
	local taskType = getTaskType(taskConfig)
	if taskType == "Drawing" then
		return storyPlayerCount()
	elseif taskType == "Wait" then
		return tonumber(taskConfig.Duration) or 0
	elseif taskType == "Delivery" then
		return tonumber(taskConfig.RequiredDeliveries or taskConfig.Required) or 1
	end

	return tonumber(taskConfig.Required) or 1
end

local function buildTaskState(taskConfig, taskIndex)
	local taskType = getTaskType(taskConfig)
	local state = {
		taskId = tostring(taskConfig.Id or ("Task" .. tostring(taskIndex))),
		taskIndex = taskIndex,
		taskType = taskType,
		title = tostring(taskConfig.Title or "Task"),
		description = tostring(taskConfig.Description or ""),
		progress = 0,
		required = getTaskRequired(taskConfig),
	}

	if taskType == "Wait" then
		state.endsAt = Workspace:GetServerTimeNow() + state.required
	end

	return state
end

local function clearDeliveryState(destroyStageModel)
	if not currentDeliveryState then
		return
	end

	for _, carried in pairs(currentDeliveryState.carriedByPlayer or {}) do
		if carried.item and carried.item.Parent then
			carried.item:Destroy()
		end
	end

	if currentDeliveryState.runtimeFolder and currentDeliveryState.runtimeFolder.Parent then
		currentDeliveryState.runtimeFolder:Destroy()
	end

	if destroyStageModel and currentDeliveryState.stageModel and currentDeliveryState.stageModel.Parent then
		currentDeliveryState.stageModel:Destroy()
	end

	currentDeliveryState = nil
end

local function disconnectCurrentTaskConnection()
	if currentTaskConnection then
		currentTaskConnection:Disconnect()
		currentTaskConnection = nil
	end

	for _, connection in ipairs(currentTaskConnections) do
		connection:Disconnect()
	end
	table.clear(currentTaskConnections)

	clearDeliveryState(false)
end

local function trackCurrentTaskConnection(connection)
	if connection then
		table.insert(currentTaskConnections, connection)
	end
	return connection
end

local function teleportStoryPlayersToPart(partName)
	local teleportPart = Workspace:FindFirstChild(partName)
	if not teleportPart or not teleportPart:IsA("BasePart") then
		warn("StoryHorror: Missing teleport BasePart named " .. tostring(partName))
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

local function getStoryStorageFolder()
	local folder = ServerStorage:FindFirstChild(CONFIG.StoryStorageFolderName)
	if not folder or not folder:IsA("Folder") then
		warn("StoryHorror: Missing ServerStorage." .. CONFIG.StoryStorageFolderName .. " Folder for story maps.")
		return nil
	end

	return folder
end

local function findStoryStorageChild(childName)
	local storageFolder = getStoryStorageFolder()
	if not storageFolder or not childName or childName == "" then
		return nil
	end

	local directChild = storageFolder:FindFirstChild(childName)
	if directChild then
		return directChild
	end

	for _, descendant in ipairs(storageFolder:GetDescendants()) do
		if descendant.Name == childName then
			return descendant
		end
	end

	return nil
end

local function findFirstBasePart(instance)
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function setModelOrPartCFrame(instance, cframe)
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

local function unloadStoryMap(loadedName)
	local key = loadedName or CONFIG.LoadedMapFolderName
	local record = loadedStoryMaps[key]
	if not record then
		return
	end

	if CONFIG.MoveMapInsteadOfClone and record.originalParent and record.instance and record.instance.Parent then
		record.instance.Parent = record.originalParent
	elseif record.instance then
		record.instance:Destroy()
	end

	loadedStoryMaps[key] = nil
end

local function unloadAllStoryMaps()
	local keys = {}
	for key in pairs(loadedStoryMaps) do
		table.insert(keys, key)
	end

	for _, key in ipairs(keys) do
		unloadStoryMap(key)
	end
end

local function loadStoryMap(mapName, loadedName)
	local key = loadedName or CONFIG.LoadedMapFolderName
	unloadStoryMap(key)

	if not mapName or mapName == "" then
		return true
	end

	local storageFolder = getStoryStorageFolder()
	if not storageFolder then
		return false
	end

	local mapFolder = storageFolder:FindFirstChild(mapName)
	if not mapFolder or not mapFolder:IsA("Folder") then
		warn("StoryHorror: Missing map Folder named " .. tostring(mapName) .. " inside ServerStorage." .. CONFIG.StoryStorageFolderName)
		return false
	end

	local loadedInstance
	local originalParent = nil
	if CONFIG.MoveMapInsteadOfClone then
		loadedInstance = mapFolder
		originalParent = mapFolder.Parent
		loadedInstance.Parent = Workspace
	else
		loadedInstance = mapFolder:Clone()
		loadedInstance.Name = key
		loadedInstance.Parent = Workspace
	end

	loadedStoryMaps[key] = {
		instance = loadedInstance,
		originalParent = originalParent,
		mapName = mapName,
	}

	return true
end

local function getPartCFramePayload(partName)
	local part = Workspace:FindFirstChild(partName)
	if not part or not part:IsA("BasePart") then
		warn("StoryHorror: Missing camera BasePart named " .. tostring(partName))
		return nil
	end

	return { part.CFrame:GetComponents() }
end

local function fireConversation(action)
	local payload = {
		typewriterSpeed = tonumber(action.TypewriterSpeed) or 0.035,
		pages = action.Pages or {},
	}

	if action.CameraPartName then
		payload.cameraCFrame = getPartCFramePayload(action.CameraPartName)
	end

	fireUiToStoryPlayers("ConversationStart", payload)
end

local function getCutsceneSoundPayload(soundName)
	if not soundName then return nil end
	local sound = findStoryStorageChild(soundName)
	if not sound or not sound:IsA("Sound") then
		warn("StoryHorror: Missing cutscene Sound named " .. tostring(soundName) .. " inside ServerStorage." .. CONFIG.StoryStorageFolderName)
		return nil
	end
	return {
		soundId = sound.SoundId,
		volume = sound.Volume,
		playbackSpeed = sound.PlaybackSpeed,
		looped = sound.Looped,
	}
end

local function fireCutscene(action)
	local payload = {
		freezeControls = action.FreezeControls ~= false,
		shots = {},
		events = {},
	}

	for index, shot in ipairs(action.Shots or {}) do
		if index > 100 then
			warn("StoryHorror: Cutscene limited to 100 shots.")
			break
		end
		local cameraCFrame = getPartCFramePayload(shot.CameraPartName)
		if cameraCFrame then
			local soundPayload = getCutsceneSoundPayload(shot.SoundName)
			if soundPayload then
				soundPayload.volume = math.clamp(tonumber(shot.Volume) or soundPayload.volume, 0, 10)
				soundPayload.playbackSpeed = math.clamp(tonumber(shot.PlaybackSpeed) or soundPayload.playbackSpeed, 0.05, 4)
				if shot.Looped ~= nil then soundPayload.looped = shot.Looped == true end
			end
			table.insert(payload.shots, {
				cameraCFrame = cameraCFrame,
				moveDuration = math.clamp(tonumber(shot.MoveDuration) or 0, 0, 120),
				holdDuration = math.clamp(tonumber(shot.HoldDuration) or 0, 0, 120),
				easingStyle = tostring(shot.EasingStyle or "Sine"),
				easingDirection = tostring(shot.EasingDirection or "InOut"),
				fieldOfView = shot.FieldOfView and math.clamp(tonumber(shot.FieldOfView) or 70, 1, 120) or nil,
				sound = soundPayload,
			})
		end
	end

	for index, event in ipairs(action.Events or {}) do
		if index > 50 then
			warn("StoryHorror: Cutscene limited to 50 timed events.")
			break
		end
		if string.lower(tostring(event.Type or "")) == "blackscreen" then
			local transitionType = string.lower(tostring(event.TransitionType or "Normal"))
			if transitionType ~= "normal" and transitionType ~= "wink" then
				warn("StoryHorror: Unknown black-screen TransitionType " .. tostring(event.TransitionType) .. "; using Normal.")
				transitionType = "normal"
			end
			table.insert(payload.events, {
				time = math.clamp(tonumber(event.Time or event.At) or 0, 0, 600),
				type = "BlackScreen",
				transitionType = transitionType,
				fadeInSeconds = math.clamp(tonumber(event.FadeInSeconds) or 0.35, 0.01, 10),
				holdSeconds = math.clamp(tonumber(event.HoldSeconds) or 1, 0, 120),
				fadeOutSeconds = math.clamp(tonumber(event.FadeOutSeconds) or 0.35, 0.01, 10),
			})
		else
			warn("StoryHorror: Unknown cutscene event Type " .. tostring(event.Type))
		end
	end

	if #payload.shots > 0 then
		fireUiToStoryPlayers("CutsceneStart", payload)
	else
		warn("StoryHorror: Cutscene has no valid camera shots.")
	end
end

local function stopStoryAnimation(trackName, fadeTime)
	local track = activeStoryAnimationTracks[trackName]
	if not track then return end
	activeStoryAnimationTracks[trackName] = nil
	if track.IsPlaying then
		track:Stop(math.clamp(tonumber(fadeTime) or 0.2, 0, 10))
	end
end

local function findAnimationModel(action)
	local modelName = tostring(action.ModelName or "")
	local rootName = tostring(action.ModelRootName or action.LoadedMapName or "")
	local searchRoot = Workspace

	if rootName ~= "" then
		local loadedRecord = loadedStoryMaps[rootName]
		searchRoot = loadedRecord and loadedRecord.instance or Workspace:FindFirstChild(rootName, true)
		if not searchRoot then return nil end
	end

	if searchRoot:IsA("Model") and searchRoot.Name == modelName then
		return searchRoot
	end
	local model = searchRoot:FindFirstChild(modelName, true)
	return model and model:IsA("Model") and model or nil
end

local function playStoryAnimationWhenReady(action)
	local modelName = tostring(action.ModelName or "")
	local animationName = tostring(action.AnimationName or action.Name or "")
	local waitSeconds = math.clamp(tonumber(action.WaitForModelSeconds) or 5, 0, 30)
	local deadline = os.clock() + waitSeconds
	local model = findAnimationModel(action)

	-- PlayAnimation may be listed before LoadMap in the same StartActions table.
	-- Poll asynchronously so it never blocks the later LoadMap action from running.
	while not model and os.clock() < deadline do
		task.wait(0.1)
		model = findAnimationModel(action)
	end
	if not model then
		local rootName = action.ModelRootName or action.LoadedMapName
		warn("StoryHorror: Missing Workspace model named " .. modelName
			.. (rootName and (" inside loaded root " .. tostring(rootName)) or "")
			.. " after waiting " .. tostring(waitSeconds) .. " seconds")
		return
	end

	-- Keep each animation with the rig that uses it. This avoids global name
	-- collisions and makes a story model self-contained when maps are loaded.
	local animation = model:FindFirstChild(animationName, true)
	if not animation or not animation:IsA("Animation") or animation.AnimationId == "" then
		warn("StoryHorror: Model " .. model:GetFullName() .. " is missing a valid descendant Animation named " .. animationName)
		return
	end

	local host = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not host then
		host = Instance.new("AnimationController")
		host.Name = "StoryAnimationController"
		host.Parent = model
	end
	local animator = host:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = host
	end

	local trackName = tostring(action.TrackName or (modelName .. ":" .. animationName))
	stopStoryAnimation(trackName, action.FadeTime)
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if not ok or not track then
		warn("StoryHorror: Could not load animation " .. animationName .. " on " .. model:GetFullName())
		return
	end
	activeStoryAnimationTracks[trackName] = track
	track.Looped = action.Looped == true
	track.Priority = Enum.AnimationPriority.Action
	if action.Priority then
		local priorityOk, priority = pcall(function() return Enum.AnimationPriority[tostring(action.Priority)] end)
		if priorityOk and priority then track.Priority = priority end
	end
	track:Play(math.clamp(tonumber(action.FadeTime) or 0.2, 0, 10), 1, math.clamp(tonumber(action.Speed) or 1, 0.05, 10))
	track.Stopped:Once(function()
		if activeStoryAnimationTracks[trackName] == track then activeStoryAnimationTracks[trackName] = nil end
	end)

	local duration = tonumber(action.Duration)
	if duration and duration >= 0 then
		task.delay(math.clamp(duration, 0, 3600), function()
			if activeStoryAnimationTracks[trackName] == track then stopStoryAnimation(trackName, action.StopFadeTime or action.FadeTime) end
		end)
	end
end

local function playStoryAnimation(action)
	task.spawn(playStoryAnimationWhenReady, action)
end

local function playStorySound(action)
	local soundName = action.SoundName or action.Name
	local soundTemplate = findStoryStorageChild(soundName)
	if not soundTemplate or not soundTemplate:IsA("Sound") then
		warn("StoryHorror: Missing Sound named " .. tostring(soundName) .. " inside ServerStorage." .. CONFIG.StoryStorageFolderName)
		return
	end

	local playCount = tonumber(action.PlayCount) or 1
	local playInterval = tonumber(action.PlayInterval) or 0
	local parentPartName = action.ParentPartName
	local parentPart = parentPartName and Workspace:FindFirstChild(parentPartName)

	local function playOne(index)
		if index > playCount then return end
		local sound = soundTemplate:Clone()
		sound.Name = (action.LoadedName or soundTemplate.Name) .. "_" .. index
		if action.Volume then
			sound.Volume = tonumber(action.Volume) or sound.Volume
		end
		if action.PlaybackSpeed then
			sound.PlaybackSpeed = tonumber(action.PlaybackSpeed) or sound.PlaybackSpeed
		end
		if parentPart and parentPart:IsA("BasePart") then
			sound.Parent = parentPart
		else
			sound.Parent = SoundService
		end
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)

		local cleanupAfter = tonumber(action.CleanupAfter)
		if cleanupAfter then
			task.delay(cleanupAfter, function()
				if sound.Parent then
					sound:Destroy()
				end
			end)
		end

		if index < playCount then
			if playInterval > 0 then
				task.delay(playInterval, function()
					playOne(index + 1)
				end)
			else
				playOne(index + 1)
			end
		end
	end

	playOne(1)
end

-- NEW: Apply lighting from a skybox model in ServerStorage.Skyboxes
local function setLightingFromSkybox(skyboxName)
	local skyboxesFolder = ServerStorage:FindFirstChild("Skyboxes")
	if not skyboxesFolder then
		warn("StoryHorror: Missing ServerStorage.Skyboxes folder.")
		return
	end
	local skybox = skyboxesFolder:FindFirstChild(skyboxName)
	if not skybox then
		warn("StoryHorror: Skybox '" .. skyboxName .. "' not found in ServerStorage.Skyboxes.")
		return
	end

	-- Apply brightness
	local brightnessValue = skybox:FindFirstChild("Brightness")
	if brightnessValue and brightnessValue:IsA("StringValue") then
		local b = tonumber(brightnessValue.Value)
		if b then
			Lighting.Brightness = math.clamp(b, 0, 100)
		end
	end

	-- Apply density
	local densityValue = skybox:FindFirstChild("Density")
	if densityValue and densityValue:IsA("StringValue") then
		local d = tonumber(densityValue.Value)
		if d then
			local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
			if not atmosphere then
				atmosphere = Instance.new("Atmosphere")
				atmosphere.Parent = Lighting
			end
			atmosphere.Density = math.clamp(d, 0, 1)
		end
	end

	-- Change the sky (the visible skybox)
	-- The skybox model can either be a Sky object itself, or contain a child of type Sky.
	local newSky = nil
	if skybox:IsA("Sky") then
		newSky = skybox:Clone()
	else
		local skyChild = skybox:FindFirstChildOfClass("Sky")
		if skyChild then
			newSky = skyChild:Clone()
		end
	end

	if newSky then
		-- Remove any existing Sky objects from Lighting
		for _, existing in ipairs(Lighting:GetChildren()) do
			if existing:IsA("Sky") then
				existing:Destroy()
			end
		end
		newSky.Parent = Lighting
	end
end

local function runTaskAction(action)
	local actionType = string.lower(tostring(action.Type or ""))
	if actionType == "fade" then
		fireUiToStoryPlayers("FadeTransition", {
			fadeInSeconds = action.FadeInSeconds or action.fadeInSeconds or 1,
			holdSeconds = action.HoldSeconds or action.holdSeconds or 2,
			fadeOutSeconds = action.FadeOutSeconds or action.fadeOutSeconds or 1,
			text = action.Text or action.text or "",
		})
	elseif actionType == "teleport" then
		teleportStoryPlayersToPart(action.PartName)
	elseif actionType == "loadmap" then
		loadStoryMap(action.MapName, action.LoadedName)
	elseif actionType == "unloadmap" then
		unloadStoryMap(action.LoadedName or action.Name)
	elseif actionType == "unloadallmaps" then
		unloadAllStoryMaps()
	elseif actionType == "conversation" then
		fireConversation(action)
	elseif actionType == "cutscene" then
		fireCutscene(action)
	elseif actionType == "closecutscene" then
		fireUiToStoryPlayers("CutsceneEnd", {})
	elseif actionType == "playanimation" then
		playStoryAnimation(action)
	elseif actionType == "stopanimation" then
		stopStoryAnimation(tostring(action.TrackName or ""), action.FadeTime)
	elseif actionType == "closeconversation" then
		fireUiToStoryPlayers("ConversationEnd", {})
	elseif actionType == "closedrawing" then
		fireUiToStoryPlayers("Task2End", {})
	elseif actionType == "message" then
		fireUiToStoryPlayers("Message", { text = action.Text or "" })
	elseif actionType == "playsound" then
		playStorySound(action)
	elseif actionType == "setlighting" then
		setLightingFromSkybox(action.SkyboxName or action.Name)
	end
end			

local function runTaskActions(actions)
	if not actions then
		return
	end

	for _, action in ipairs(actions) do
		local delaySeconds = tonumber(action.Delay) or 0
		if delaySeconds > 0 then
			task.delay(delaySeconds, function()
				runTaskAction(action)
			end)
		else
			runTaskAction(action)
		end
	end
end

local startTaskByIndex

local function completeCurrentTask(message)
	if not currentTask then
		return
	end

	local finishedTask = currentTask
	local taskConfig = getTaskAt(finishedTask.taskIndex)
	disconnectCurrentTaskConnection()

	fireUiToStoryPlayers("TaskComplete", {
		taskId = finishedTask.taskId,
		title = finishedTask.title,
		message = message or (taskConfig and taskConfig.CompleteMessage) or "Task complete.",
	})

	if taskConfig then
		runTaskActions(taskConfig.EndActions)
	end

	currentTask = nil
	currentTaskToken += 1
	local nextTaskDelay = tonumber(taskConfig and taskConfig.NextTaskDelay) or 0
	task.delay(nextTaskDelay, function()
		startTaskByIndex(finishedTask.taskIndex + 1)
	end)
end

local function getPlayerFromTouchedPart(touchedPart)
	local character = touchedPart and touchedPart.Parent
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function prepareWaypointTask(taskConfig)
	local waypointPartName = taskConfig.WaypointPartName or taskConfig.PartName
	local waypointPart = Workspace:FindFirstChild(waypointPartName)
	if not waypointPart or not waypointPart:IsA("BasePart") then
		warn("StoryHorror: Missing Workspace." .. tostring(waypointPartName) .. " BasePart for waypoint task")
		return
	end

	disablePromptDescendants(waypointPart)
	disconnectCurrentTaskConnection()

	currentTaskConnection = waypointPart.Touched:Connect(function(touchedPart)
		local player = getPlayerFromTouchedPart(touchedPart)
		if player and currentTask and activeStoryPlayers[player] then
			completeCurrentTask(taskConfig.CompleteMessage or "The waypoint has been reached.")
		end
	end)
end

local function getDeliverySourceFolder(taskConfig)
	local folderName = taskConfig.ItemsFolderName or taskConfig.CarryItemsFolderName
	local storageFolder = ServerStorage:FindFirstChild(CONFIG.StoryStorageFolderName)
	local folder = storageFolder and storageFolder:FindFirstChild(folderName)
	if not folder then
		folder = Workspace:FindFirstChild(folderName)
	end

	if not folder or not folder:IsA("Folder") then
		warn("StoryHorror: Missing delivery items Folder named " .. tostring(folderName) .. " in ServerStorage." .. CONFIG.StoryStorageFolderName .. " or Workspace")
		return nil
	end

	return folder
end

local function getInstanceCFrame(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	elseif instance:IsA("BasePart") then
		return instance.CFrame
	end

	return CFrame.new()
end

local function configureCarriedItemPhysics(item)
	for _, descendant in ipairs(item:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end

	if item:IsA("BasePart") then
		item.Anchored = false
		item.CanCollide = false
		item.Massless = true
	end
end

local function attachItemToPlayer(player, item, taskConfig)
	local character = player.Character
	local rootPart = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"))
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local mainPart = findFirstBasePart(item)
	if not mainPart then
		return false
	end

	local offset = taskConfig.CarryOffset or CFrame.new(0, -0.6, -1.15)
	item.Parent = character
	setInstanceCFrame(item, rootPart.CFrame * offset)
	configureCarriedItemPhysics(item)

	for _, descendant in ipairs(item:GetDescendants()) do
		if descendant:IsA("ClickDetector") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end

	if item:IsA("BasePart") then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = item
		weld.Parent = item
	end

	return true
end

-- UPDATED: Stage models now appear at their original ServerStorage position when no StageDisplayPart is provided.
local function updateDeliveryStage(taskConfig, progress)
	if not currentDeliveryState or not taskConfig.StageFolderName then
		return
	end

	local loadedStageName = taskConfig.LoadedStageName or "CurrentDeliveryStage"
	if currentDeliveryState.stageModel and currentDeliveryState.stageModel.Parent then
		currentDeliveryState.stageModel:Destroy()
		currentDeliveryState.stageModel = nil
	end
	loadedStoryMaps[loadedStageName] = nil

	local stageFolder = findStoryStorageChild(taskConfig.StageFolderName)
	if not stageFolder or not stageFolder:IsA("Folder") then
		warn("StoryHorror: Missing stage Folder named " .. tostring(taskConfig.StageFolderName) .. " inside ServerStorage." .. CONFIG.StoryStorageFolderName)
		return
	end

	local stageNamePrefix = taskConfig.StageNamePrefix or "Stage"
	local stageTemplate = stageFolder:FindFirstChild(stageNamePrefix .. tostring(progress))
	if not stageTemplate then
		warn("StoryHorror: Missing stage model named " .. stageNamePrefix .. tostring(progress) .. " inside " .. taskConfig.StageFolderName)
		return
	end

	-- Determine where to place the stage
	local targetCFrame
	local displayPartName = taskConfig.StageDisplayPartName
	if displayPartName then
		local displayPart = Workspace:FindFirstChild(displayPartName)
		if displayPart and displayPart:IsA("BasePart") then
			targetCFrame = displayPart.CFrame
		else
			warn("StoryHorror: Missing stage display BasePart named " .. tostring(displayPartName))
			return
		end
	else
		-- Use the template's original position from ServerStorage
		targetCFrame = getInstanceCFrame(stageTemplate)
	end

	local stageModel = stageTemplate:Clone()
	stageModel.Name = loadedStageName
	stageModel.Parent = Workspace
	setModelOrPartCFrame(stageModel, targetCFrame)
	currentDeliveryState.stageModel = stageModel
	loadedStoryMaps[loadedStageName] = {
		instance = stageModel,
		originalParent = nil,
		mapName = taskConfig.StageFolderName .. ":" .. stageNamePrefix .. tostring(progress),
	}
end

local function deliverCarriedItem(player, taskConfig)
	if not currentTask or not currentDeliveryState then
		return
	end

	local carried = currentDeliveryState.carriedByPlayer[player]
	if not carried then
		return
	end

	currentDeliveryState.carriedByPlayer[player] = nil
	if carried.item and carried.item.Parent then
		carried.item:Destroy()
	end

	currentDeliveryState.delivered += 1
	currentTask.progress = currentDeliveryState.delivered
	currentTask.required = getTaskRequired(taskConfig)
	updateDeliveryStage(taskConfig, currentDeliveryState.delivered)
	fireUiToStoryPlayers("TaskUpdate", currentTask)

	if currentTask.progress >= currentTask.required then
		if taskConfig.ClearStageOnComplete and currentDeliveryState.stageModel and currentDeliveryState.stageModel.Parent then
			currentDeliveryState.stageModel:Destroy()
			currentDeliveryState.stageModel = nil
			loadedStoryMaps[taskConfig.LoadedStageName or "CurrentDeliveryStage"] = nil
		end
		completeCurrentTask(taskConfig.CompleteMessage or "Everything has been delivered.")
	end
end

local addDeliveryClickDetector
local returnCarriedItemToWorld

local function pickupDeliveryItem(player, item, taskConfig)
	if not currentTask or not currentDeliveryState or not activeStoryPlayers[player] then
		return
	end

	if currentDeliveryState.carriedByPlayer[player] then
		fireUi(player, "Message", { text = taskConfig.AlreadyCarryingMessage or "Deliver what you are carrying first." })
		return
	end

	if not item or not item.Parent or currentDeliveryState.claimedItems[item] then
		return
	end

	currentDeliveryState.claimedItems[item] = true
	local originCFrame = getInstanceCFrame(item)
	if attachItemToPlayer(player, item, taskConfig) then
		currentDeliveryState.carriedByPlayer[player] = { item = item, originCFrame = originCFrame }
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			trackCurrentTaskConnection(humanoid.Died:Connect(function()
				if returnCarriedItemToWorld then
					returnCarriedItemToWorld(player, taskConfig)
				end
			end))
		end
		fireUi(player, "Message", { text = taskConfig.PickupMessage or "You picked it up. Bring it to the delivery point." })
	else
		currentDeliveryState.claimedItems[item] = nil
		fireUi(player, "Message", { text = "Could not pick that up right now." })
	end
end

addDeliveryClickDetector = function(item, taskConfig)
	local clickParent = findFirstBasePart(item)
	if not clickParent then
		warn("StoryHorror: Delivery item " .. item.Name .. " has no BasePart for a ClickDetector.")
		return
	end

	local clickDetector = clickParent:FindFirstChildOfClass("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("ClickDetector")
		clickDetector.Parent = clickParent
	end
	clickDetector.MaxActivationDistance = tonumber(taskConfig.ClickDistance) or CONFIG.CollectibleClickDistance
	trackCurrentTaskConnection(clickDetector.MouseClick:Connect(function(player)
		pickupDeliveryItem(player, item, taskConfig)
	end))
end

returnCarriedItemToWorld = function(player, taskConfig)
	if not currentDeliveryState then
		return
	end

	local carried = currentDeliveryState.carriedByPlayer[player]
	if not carried or not carried.item or not carried.item.Parent then
		return
	end

	currentDeliveryState.carriedByPlayer[player] = nil
	currentDeliveryState.claimedItems[carried.item] = nil
	for _, descendant in ipairs(carried.item:GetDescendants()) do
		if descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	if carried.item:IsA("BasePart") then
		carried.item.Anchored = true
		carried.item.CanCollide = false
	end

	carried.item.Parent = currentDeliveryState.runtimeFolder
	setInstanceCFrame(carried.item, carried.originCFrame or CFrame.new())
	addDeliveryClickDetector(carried.item, taskConfig)
end

local function prepareDeliveryTask(taskConfig)
	local sourceFolder = getDeliverySourceFolder(taskConfig)
	if not sourceFolder then
		return
	end

	local deliveryPartName = taskConfig.DeliveryPartName or taskConfig.DropoffPartName
	local deliveryPart = deliveryPartName and Workspace:FindFirstChild(deliveryPartName)
	if not deliveryPart or not deliveryPart:IsA("BasePart") then
		warn("StoryHorror: Missing delivery BasePart named " .. tostring(deliveryPartName))
		return
	end

	local runtimeName = tostring(currentTask.taskId) .. "DeliveryItems"
	local runtimeContainer = Workspace:FindFirstChild(CONFIG.RuntimeFolderName) or Workspace
	local deliveryRuntimeFolder = runtimeContainer:FindFirstChild(runtimeName)
	if deliveryRuntimeFolder then
		deliveryRuntimeFolder:Destroy()
	end
	deliveryRuntimeFolder = Instance.new("Folder")
	deliveryRuntimeFolder.Name = runtimeName
	deliveryRuntimeFolder.Parent = runtimeContainer

	currentDeliveryState = {
		runtimeFolder = deliveryRuntimeFolder,
		carriedByPlayer = {},
		claimedItems = {},
		delivered = 0,
		stageModel = nil,
	}

	for _, template in ipairs(sourceFolder:GetChildren()) do
		if template:IsA("BasePart") or template:IsA("Model") then
			local item = template:Clone()
			item.Parent = deliveryRuntimeFolder
			removePromptDescendants(item)
			addDeliveryClickDetector(item, taskConfig)
		end
	end

	trackCurrentTaskConnection(deliveryPart.Touched:Connect(function(touchedPart)
		local player = getPlayerFromTouchedPart(touchedPart)
		if player and activeStoryPlayers[player] then
			deliverCarriedItem(player, taskConfig)
		end
	end))
end

local function startDrawingTask(taskConfig)
	task2ConfirmedByUserId = {}
	task2ConfirmedCount = 0
	fireUiToStoryPlayers("Task2Start", {
		image = taskConfig.Image or CONFIG.Task2Image,
		confirmed = task2ConfirmedCount,
		total = storyPlayerCount(),
	})
end

startTaskByIndex = function(taskIndex)
	local taskConfig = getTaskAt(taskIndex)
	if not taskConfig then
		currentTask = nil
		fireUiToStoryPlayers("Message", { text = "The story sequence is complete." })
		return
	end

	disconnectCurrentTaskConnection()
	currentTaskToken += 1
	local token = currentTaskToken
	currentTask = buildTaskState(taskConfig, taskIndex)

	runTaskActions(taskConfig.StartActions)
	fireUiToStoryPlayers("TaskUpdate", currentTask)

	local taskType = getTaskType(taskConfig)
	if taskType == "Waypoint" then
		prepareWaypointTask(taskConfig)
	elseif taskType == "Drawing" then
		startDrawingTask(taskConfig)
	elseif taskType == "Delivery" then
		prepareDeliveryTask(taskConfig)
	elseif taskType == "Wait" then
		local duration = tonumber(taskConfig.Duration) or 0
		task.delay(duration, function()
			if token == currentTaskToken and currentTask and currentTask.taskIndex == taskIndex then
				completeCurrentTask(taskConfig.CompleteMessage or "The wait is over.")
			end
		end)
	elseif taskType == "Instant" then
		local autoCompleteDelay = taskConfig.AutoCompleteDelay
		if autoCompleteDelay then
			task.delay(tonumber(autoCompleteDelay) or 0, function()
				if token == currentTaskToken and currentTask and currentTask.taskIndex == taskIndex then
					completeCurrentTask(taskConfig.CompleteMessage)
				end
			end)
		end
	else
		warn("StoryHorror: Unknown task Type " .. tostring(taskType) .. " for task " .. tostring(currentTask.taskId))
	end
end

local function sendTask2ConfirmUpdate()
	fireUiToStoryPlayers("Task2ConfirmUpdate", {
		confirmed = task2ConfirmedCount,
		total = storyPlayerCount(),
	})
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
		if currentTask.taskType == "Drawing" then
			local taskConfig = getTaskAt(currentTask.taskIndex) or {}
			fireUi(player, "Task2Start", {
				image = taskConfig.Image or CONFIG.Task2Image,
				confirmed = task2ConfirmedCount,
				total = currentTask.required,
			})
		end
	end
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
	startTaskByIndex(1)
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

	if currentDeliveryState and currentDeliveryState.carriedByPlayer[player] then
		local carried = currentDeliveryState.carriedByPlayer[player]
		currentDeliveryState.carriedByPlayer[player] = nil
		if carried.item and carried.item.Parent then
			carried.item:Destroy()
		end
	end

	if currentTask and currentTask.taskType == "Drawing" then
		currentTask.required = storyPlayerCount()
		sendTask2ConfirmUpdate()
		if currentTask.required > 0 and task2ConfirmedCount >= currentTask.required then
			completeCurrentTask()
		end
	end
end)

remoteEvent.OnServerEvent:Connect(function(player, action)
	if action ~= "Task2Confirm" then
		return
	end

	if not currentTask or currentTask.taskType ~= "Drawing" or not activeStoryPlayers[player] then
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
		completeCurrentTask()
	end
end)

disableSpawnMarkerPrompts()
disableUnusedStoryPrompts()

local startPrompt = getStoryStartPrompt()
if startPrompt then
	startPrompt.Triggered:Connect(registerForCountdown)
end

for _ = 1, math.min(CONFIG.MaxActiveCollectibles, 3) do
	createCollectible()
end

task.spawn(spawnLoop)
