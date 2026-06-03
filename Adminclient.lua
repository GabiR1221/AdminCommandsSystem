local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local SoundService = game:GetService("SoundService")
local commandSoundsFolder = ReplicatedStorage:WaitForChild("CommandSounds")

local player = Players.LocalPlayer
local gui = script.Parent

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
-- NEW Remote for head stealing
local stealHeadCommand = ReplicatedStorage:WaitForChild("StealHeadCommand")

local jumpscareButton = gui:WaitForChild("JumpscareAllButton")
local freezeChatButton = gui:WaitForChild("FreezeChatAllButton")

local chatFrame = gui:WaitForChild("ChatFrame")
local nameBox = chatFrame:WaitForChild("NameTextBox")
local messageBox = chatFrame:WaitForChild("MessageTextBox")
local colorBox = chatFrame:WaitForChild("ColorTextBox")
local sendButton = chatFrame:WaitForChild("SendButton")

local kickFrame = gui:WaitForChild("KickFrame")
local kickReasonBox = kickFrame:WaitForChild("KickReasonTextBox")
local kickButton = kickFrame:WaitForChild("KickAllButton")

local skyFrame = gui:WaitForChild("SkyFrame")
local skyNameBox = skyFrame:WaitForChild("SkyNameTextBox")
local changeSkyButton = skyFrame:WaitForChild("ChangeSkyButton")

local npcFrame = gui:WaitForChild("NPCFrame")
local npcNameBox = npcFrame:WaitForChild("NPCNameTextBox")
local spawnNpcButton = npcFrame:WaitForChild("SpawnButton")
local despawnButton = npcFrame:WaitForChild("DespawnButton")

local soundFrame = gui:WaitForChild("SoundFrame")
local soundNameBox = soundFrame:WaitForChild("SoundNameTextBox")
local playSoundButton = soundFrame:WaitForChild("PlaySoundButton")
local userTextBox = soundFrame:WaitForChild("UserTextBox")

local scaleFrame = gui:WaitForChild("ScaleFrame")
local scaleTextBox = scaleFrame:WaitForChild("ScaleTextBox")
local scaleButton = scaleFrame:WaitForChild("ScaleButton")

local eventFrame = gui:WaitForChild("EventFrame")
local eventTextBox = eventFrame:WaitForChild("EventTextBox")
local eventButton = eventFrame:WaitForChild("EventButton")

local headSnatchFrame = gui:WaitForChild("HeadSnatchFrame")
local targetNameBox = headSnatchFrame:WaitForChild("TargetNameBox")
local stealButton = headSnatchFrame:WaitForChild("StealButton")


-- ==========================================

local function escapeRichText(text)
	text = tostring(text or "")
	text = text:gsub("&", "&amp;")
	text = text:gsub("<", "&lt;")
	text = text:gsub(">", "&gt;")
	text = text:gsub('"', "&quot;")
	text = text:gsub("'", "&apos;")
	return text
end

local function hexToColor3(hex)
	hex = tostring(hex or ""):gsub("#", "")
	if #hex ~= 6 then
		return Color3.new(1, 1, 1)
	end

	local r = tonumber(hex:sub(1, 2), 16) or 255
	local g = tonumber(hex:sub(3, 4), 16) or 255
	local b = tonumber(hex:sub(5, 6), 16) or 255
	return Color3.fromRGB(r, g, b)
end

local function getGeneralChannel()
	local textChannels = TextChatService:FindFirstChild("TextChannels")
	if not textChannels then
		return nil
	end

	local channel = textChannels:FindFirstChild("RBXGeneral")
	if channel and channel:IsA("TextChannel") then
		return channel
	end

	for _, child in ipairs(textChannels:GetChildren()) do
		if child:IsA("TextChannel") then
			return child
		end
	end

	return nil
end

local function displayCustomChatMessage(nameText, messageText, hex)
	local formatted = string.format(
		'<font color="#%s"><b>%s</b></font>: %s',
		hex,
		escapeRichText(nameText),
		escapeRichText(messageText)
	)

	local channel
	for _ = 1, 20 do
		channel = getGeneralChannel()
		if channel then
			break
		end
		task.wait(0.1)
	end

	if channel then
		local ok = pcall(function()
			channel:DisplaySystemMessage(formatted)
		end)

		if ok then
			return
		end
	end

	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = string.format("%s: %s", nameText, messageText),
			Color = hexToColor3(hex),
			Font = Enum.Font.GothamBold,
		})
	end)
end

local function ensureOverlay()
	local playerGui = player:WaitForChild("PlayerGui")
	local overlay = playerGui:FindFirstChild("JumpscareOverlay")

	if overlay then
		return overlay
	end

	overlay = Instance.new("ScreenGui")
	overlay.Name = "JumpscareOverlay"
	overlay.ResetOnSpawn = false
	overlay.IgnoreGuiInset = true
	overlay.DisplayOrder = 9999
	overlay.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "BlackBackground"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.Parent = overlay

	local image = Instance.new("ImageLabel")
	image.Name = "ScareImage"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Position = UDim2.fromScale(0, 0)
	image.Image = "rbxassetid://77462224577583"
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = overlay

	local sound = Instance.new("Sound")
	sound.Name = "ScareSound"
	sound.SoundId = "rbxassetid://130586258888902"
	sound.Volume = 1
	sound.Parent = overlay

	return overlay
end

local function playJumpscare()
	local overlay = ensureOverlay()
	local sound = overlay:FindFirstChild("ScareSound")

	overlay.Enabled = true

	if sound then
		sound:Play()
	end

	task.delay(6, function()
		if overlay then
			overlay.Enabled = false
		end
	end)
end

local function playLocalCommandSound(soundName)
	local sourceSound = commandSoundsFolder:FindFirstChild(soundName)
	if not sourceSound or not sourceSound:IsA("Sound") then
		return
	end

	local soundClone = sourceSound:Clone()
	soundClone.Parent = SoundService
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
end

playCommandSound.OnClientEvent:Connect(function(soundName)
	if typeof(soundName) == "string" and soundName ~= "" then
		playLocalCommandSound(soundName)
	end
end)

adminPanelToggle.OnClientEvent:Connect(function()
	gui.Enabled = true
end)

jumpscareButton.MouseButton1Click:Connect(function()
	jumpscareAll:FireServer()
end)

freezeChatButton.MouseButton1Click:Connect(function()
	freezeAndChatAll:FireServer()
end)

sendButton.MouseButton1Click:Connect(function()
	local nameText = nameBox.Text
	local messageText = messageBox.Text
	local colorText = colorBox.Text

	if nameText ~= "" and messageText ~= "" and colorText ~= "" then
		local hex = colorText:gsub("%s+", ""):gsub("#", ""):upper()
		if #hex ~= 6 or not hex:match("^[0-9A-F]+$") then
			hex = "FFFFFF"
		end

		displayCustomChatMessage(nameText, messageText, hex)

		sendCustomChatMessage:FireServer(nameText, messageText, colorText)
	end
end)

kickButton.MouseButton1Click:Connect(function()
	local reasonText = kickReasonBox.Text
	kickAllPlayers:FireServer(reasonText)
end)

changeSkyButton.MouseButton1Click:Connect(function()
	local skyName = skyNameBox.Text
	if skyName ~= "" then
		changeSkybox:FireServer(skyName)
	end
end)

spawnNpcButton.MouseButton1Click:Connect(function()
	local npcName = npcNameBox.Text
	if npcName ~= "" then
		spawnNPC:FireServer(npcName)
	end
end)

despawnButton.MouseButton1Click:Connect(function()
	despawnNPCs:FireServer()
end)

playSoundButton.MouseButton1Click:Connect(function()
	local soundName = soundNameBox.Text
	local userText = userTextBox.Text

	if soundName ~= "" then
		playCommandSound:FireServer(soundName, userText)
	end
end)

jumpscareAll.OnClientEvent:Connect(function()
	playJumpscare()
end)

showBubbleAll.OnClientEvent:Connect(function(character, bubbleText)
	if character and typeof(bubbleText) == "string" then
		pcall(function()
			TextChatService:DisplayBubble(character, bubbleText)
		end)
	end
end)

sendCustomChatMessage.OnClientEvent:Connect(function(nameText, messageText, hex)
	if typeof(nameText) ~= "string" or typeof(messageText) ~= "string" or typeof(hex) ~= "string" then
		return
	end

	displayCustomChatMessage(nameText, messageText, hex)
end)

scaleButton.MouseButton1Click:Connect(function()
	local scaleText = scaleTextBox.Text
	if scaleText ~= "" then
		scalePlayer:FireServer(scaleText)
	end
end)

eventButton.MouseButton1Click:Connect(function()
	triggerEventCommand:FireServer(eventTextBox.Text)
end)

-- NEW: Head Snatch button handler
stealButton.MouseButton1Click:Connect(function()
	local targetName = targetNameBox.Text
	if targetName == "" then
		return
	end
	stealHeadCommand:FireServer(targetName)
end)
