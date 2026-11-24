--[[
	StoryHorrorClient.lua
	Place this LocalScript in StarterPlayerScripts or StarterGui.

	Displays story UI and plays local camera/actor cutscene visuals.
	The server still validates everything, so exploiters cannot start the story without enough points.
]]

local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remoteEvent = ReplicatedStorage:WaitForChild("StoryHorrorUIEvent")

local UI_CONFIG = {
	ScreenGuiName = "StoryHorrorGui",
	StoryStartPartName = "StoryStartPart",
	NotificationSeconds = 4,
}

local points = 0
local required = 0
local pointsUiUnlocked = false
local countdownEndsAt = nil
local taskState = nil
local notificationHideAt = 0
local task2Gui = nil
local task2DrawingFrame = nil
local task2ConfirmButton = nil
local task2ConfirmLabel = nil
local task2HasDrawn = false
local task2Confirmed = false
local task2IsDrawing = false
local conversationGui = nil
local conversationToken = 0
local savedCameraType = nil
local savedCameraSubject = nil
local savedCameraCFrame = nil
local cutsceneToken = 0
local cutsceneActive = false
local cutsceneServerStartedAt = nil
local cutsceneSavedCamera = nil
local cutsceneSounds = {}
local cutsceneEffectGui = nil
local cutsceneAnimationTrack = nil
local cutsceneTimelineTracks = {}
local cutsceneAnimationConnection = nil
local CUTSCENE_CAMERA_BINDING = "StoryCutsceneCamera"
local controlsWereDisabled = false
local CUTSCENE_CONTROL_ACTION = "StoryCutsceneBlockControls"
local activeHarvestSwings = setmetatable({}, { __mode = "k" })
local activeTreeShakes = setmetatable({}, { __mode = "k" })

local function tweenValue(value, duration, style, direction, goal)
	local tween = TweenService:Create(value, TweenInfo.new(duration, style, direction), { Value = goal })
	tween:Play()
	tween.Completed:Wait()
end

-- Animate only the owner's replicated Tool. Damage and target selection have already
-- been accepted by the server; this function is deliberately cosmetic.
local function playHarvestSwing(tool)
	if not tool or not tool:IsA("Tool") or tool.Parent ~= player.Character then return end
	local previous = activeHarvestSwings[tool]
	if previous then previous.cancelled = true end
	local state = { cancelled = false }
	activeHarvestSwings[tool] = state

	local offset = Instance.new("CFrameValue")
	local originalGrip = tool.Grip
	local handle = tool:FindFirstChild("Handle")
	local handleAttachment = handle and handle:FindFirstChild("HandleAttachment")
	local handAttachment
	if player.Character then
		for _, descendant in ipairs(player.Character:GetDescendants()) do
			if descendant:IsA("Bone") then
				local candidate = descendant:FindFirstChild(tool:GetAttribute("HandAttachmentName") or "ToolGrip")
				if candidate and candidate:IsA("Attachment") then handAttachment = candidate break end
			end
		end
	end

	local renderConnection = RunService.RenderStepped:Connect(function()
		if state.cancelled or tool.Parent ~= player.Character then return end
		if handle and handle:IsA("BasePart") and handleAttachment and handAttachment then
			handle.CFrame = handAttachment.WorldCFrame * offset.Value * handleAttachment.CFrame:Inverse()
		else
			tool.Grip = originalGrip * offset.Value
		end
	end)

	task.spawn(function()
		tweenValue(offset, 0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, CFrame.Angles(math.rad(28), 0, math.rad(10)))
		if not state.cancelled then
			tweenValue(offset, 0.11, Enum.EasingStyle.Quart, Enum.EasingDirection.In, CFrame.Angles(math.rad(-62), 0, math.rad(-7)))
		end
		if not state.cancelled then
			tweenValue(offset, 0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out, CFrame.identity)
		end
		renderConnection:Disconnect()
		-- A newer swing may already own the Grip. Only this invocation may restore it.
		if activeHarvestSwings[tool] == state and tool.Parent and not (handleAttachment and handAttachment) then
			tool.Grip = originalGrip
		end
		offset:Destroy()
		if activeHarvestSwings[tool] == state then activeHarvestSwings[tool] = nil end
	end)
end

local function playTreeShake(tree, basePivot, angleDegrees)
	if not tree or not (tree:IsA("Model") or tree:IsA("BasePart")) or not tree:IsDescendantOf(Workspace) then return end
	if typeof(basePivot) ~= "CFrame" then basePivot = tree:GetPivot() end
	local previous = activeTreeShakes[tree]
	if previous then previous.cancelled = true end
	local state = { cancelled = false }
	activeTreeShakes[tree] = state
	local value = Instance.new("CFrameValue")
	value.Value = basePivot
	local changed = value:GetPropertyChangedSignal("Value"):Connect(function()
		if not state.cancelled and tree.Parent then tree:PivotTo(value.Value) end
	end)
	local angle = math.rad(math.clamp(tonumber(angleDegrees) or 2.5, 0, 8))

	task.spawn(function()
		tweenValue(value, 0.055, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, basePivot * CFrame.Angles(0, 0, angle))
		if not state.cancelled then tweenValue(value, 0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, basePivot * CFrame.Angles(0, 0, -angle * 0.65)) end
		if not state.cancelled then tweenValue(value, 0.11, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, basePivot) end
		changed:Disconnect()
		value:Destroy()
		if activeTreeShakes[tree] == state then activeTreeShakes[tree] = nil end
	end)
end

local function createLabel(parent, name, size, position, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	label.BackgroundTransparency = 0.15
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(245, 245, 245)
	label.TextScaled = false
	label.TextSize = textSize
	label.TextWrapped = true
	label.Visible = false
	label.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.Parent = label

	return label
end

local function ensureGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(UI_CONFIG.ScreenGuiName)
	if gui then
		return gui
	end

	gui = Instance.new("ScreenGui")
	gui.Name = UI_CONFIG.ScreenGuiName
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 50
	gui.Parent = playerGui

	createLabel(gui, "CollectibleCounter", UDim2.new(0, 260, 0, 50), UDim2.new(0, 18, 0, 18), 18)
	createLabel(gui, "CountdownLabel", UDim2.new(0, 280, 0, 58), UDim2.new(0.5, -140, 0, 18), 22)
	createLabel(gui, "TaskLabel", UDim2.new(0, 420, 0, 105), UDim2.new(1, -440, 0, 18), 18)
	createLabel(gui, "NotificationLabel", UDim2.new(0, 420, 0, 58), UDim2.new(0.5, -210, 0.18, 0), 18)

	return gui
end

local gui = ensureGui()
local collectibleCounter = gui:WaitForChild("CollectibleCounter")
local countdownLabel = gui:WaitForChild("CountdownLabel")
local taskLabel = gui:WaitForChild("TaskLabel")
local notificationLabel = gui:WaitForChild("NotificationLabel")

-- A server story action can suppress the complete GUI or selected elements.
-- Internal state continues updating while hidden, so showing it later restores
-- the current task/countdown rather than stale text.
local elementVisibility = {
	Points = true,
	Countdown = true,
	Task = true,
	Notifications = true,
	Drawing = true,
}

local function elementIsEnabled(name)
	return elementVisibility[name] ~= false
end

local function applyUiVisibility(payload)
	local visible = payload.visible == true
	local elements = payload.elements
	if type(elements) ~= "table" or #elements == 0 then
		gui.Enabled = visible
		return
	end

	for _, name in ipairs(elements) do
		if elementVisibility[name] ~= nil then
			elementVisibility[name] = visible
		end
	end
	collectibleCounter.Visible = elementIsEnabled("Points") and pointsUiUnlocked and required > 0
	countdownLabel.Visible = elementIsEnabled("Countdown") and countdownEndsAt ~= nil
	taskLabel.Visible = elementIsEnabled("Task") and taskState ~= nil
	notificationLabel.Visible = elementIsEnabled("Notifications") and notificationLabel.Text ~= "" and os.clock() < notificationHideAt
	if task2Gui then
		task2Gui.Visible = elementIsEnabled("Drawing")
	end
end

local function showNotification(text)
	notificationLabel.Text = tostring(text or "")
	notificationLabel.Visible = elementIsEnabled("Notifications") and notificationLabel.Text ~= ""
	notificationHideAt = os.clock() + UI_CONFIG.NotificationSeconds
end

local function updateCollectibleCounter()
	if required <= 0 or not pointsUiUnlocked then
		collectibleCounter.Visible = false
		return
	end

	collectibleCounter.Text = string.format("Bani: %d / %d", points, required)
	collectibleCounter.Visible = elementIsEnabled("Points")
end

local function updateTaskLabel()
	if not taskState then
		taskLabel.Visible = false
		return
	end

	local progressText = string.format("Progres: %d / %d", taskState.progress or 0, taskState.required or 0)
	if taskState.endsAt then
		local remaining = math.max(0, math.ceil(taskState.endsAt - Workspace:GetServerTimeNow()))
		progressText = string.format("Timp ramas: %02d:%02d", math.floor(remaining / 60), remaining % 60)
	end

	taskLabel.Text = string.format(
		"%s\n%s\n%s",
		tostring(taskState.title or "Task"),
		tostring(taskState.description or ""),
		progressText
	)
	taskLabel.Visible = elementIsEnabled("Task")
end

local function destroyTask2Gui()
	if task2Gui then
		task2Gui:Destroy()
		task2Gui = nil
	end

	task2DrawingFrame = nil
	task2ConfirmButton = nil
	task2ConfirmLabel = nil
	task2HasDrawn = false
	task2Confirmed = false
	task2IsDrawing = false
end

local function updateTask2ConfirmText(confirmed, total)
	local text = string.format("Confirm (%d/%d)", confirmed or 0, total or 0)
	if task2ConfirmButton then
		task2ConfirmButton.Text = text
	end
	if task2ConfirmLabel then
		task2ConfirmLabel.Text = string.format("Confirmed: %d / %d", confirmed or 0, total or 0)
	end
end

local function drawTask2Pixel(screenPosition)
	if not task2DrawingFrame or task2Confirmed then
		return
	end

	local framePosition = task2DrawingFrame.AbsolutePosition
	local frameSize = task2DrawingFrame.AbsoluteSize
	local localX = screenPosition.X - framePosition.X
	local localY = screenPosition.Y - framePosition.Y
	if localX < 0 or localY < 0 or localX > frameSize.X or localY > frameSize.Y then
		return
	end

	local pixel = Instance.new("Frame")
	pixel.Name = "InkPixel"
	pixel.Size = UDim2.fromOffset(6, 6)
	pixel.Position = UDim2.fromOffset(localX - 3, localY - 3)
	pixel.BackgroundColor3 = Color3.new(0, 0, 0)
	pixel.BorderSizePixel = 0
	pixel.Parent = task2DrawingFrame

	if not task2HasDrawn then
		task2HasDrawn = true
		if task2ConfirmButton then
			task2ConfirmButton.Visible = true
		end
	end
end

local function createTask2Gui(payload)
	destroyTask2Gui()

	task2Gui = Instance.new("Frame")
	task2Gui.Name = "Task2DrawingPanel"
	task2Gui.Size = UDim2.new(0, 620, 0, 720)
	task2Gui.Position = UDim2.new(0.5, -310, 0.5, -360)
	task2Gui.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
	task2Gui.BorderSizePixel = 0
	task2Gui.Parent = gui
	task2Gui.Visible = elementIsEnabled("Drawing")

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = task2Gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 42)
	title.Position = UDim2.fromOffset(10, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "Citeste acordul(daca vrei) si semneaza mai jos"
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.TextSize = 20
	title.Parent = task2Gui

	local image = Instance.new("ImageLabel")
	image.Name = "ReferenceImage"
	image.Size = UDim2.new(1, -40, 0, 285)
	image.Position = UDim2.fromOffset(20, 58)
	image.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = tostring(payload.image or "")
	image.Parent = task2Gui

	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(0, 10)
	imageCorner.Parent = image

	task2DrawingFrame = Instance.new("Frame")
	task2DrawingFrame.Name = "DrawingCanvas"
	task2DrawingFrame.Size = UDim2.new(1, -40, 0, 285)
	task2DrawingFrame.Position = UDim2.fromOffset(20, 353)
	task2DrawingFrame.BackgroundColor3 = Color3.fromRGB(245, 242, 232)
	task2DrawingFrame.BorderSizePixel = 0
	task2DrawingFrame.ClipsDescendants = true
	task2DrawingFrame.Parent = task2Gui

	local canvasCorner = Instance.new("UICorner")
	canvasCorner.CornerRadius = UDim.new(0, 10)
	canvasCorner.Parent = task2DrawingFrame

	local instructions = Instance.new("TextLabel")
	instructions.Name = "Instructions"
	instructions.Size = UDim2.new(1, -40, 0, 24)
	instructions.Position = UDim2.fromOffset(20, 646)
	instructions.BackgroundTransparency = 1
	instructions.Font = Enum.Font.Gotham
	instructions.Text = "Semneaza te rog"
	instructions.TextWrapped = true
	instructions.TextColor3 = Color3.fromRGB(230, 230, 230)
	instructions.TextSize = 14
	instructions.Parent = task2Gui

	task2ConfirmLabel = Instance.new("TextLabel")
	task2ConfirmLabel.Name = "ConfirmLabel"
	task2ConfirmLabel.Size = UDim2.new(0, 190, 0, 40)
	task2ConfirmLabel.Position = UDim2.fromOffset(20, 672)
	task2ConfirmLabel.BackgroundTransparency = 1
	task2ConfirmLabel.Font = Enum.Font.GothamBold
	task2ConfirmLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
	task2ConfirmLabel.TextSize = 16
	task2ConfirmLabel.TextXAlignment = Enum.TextXAlignment.Left
	task2ConfirmLabel.Parent = task2Gui

	task2ConfirmButton = Instance.new("TextButton")
	task2ConfirmButton.Name = "ConfirmButton"
	task2ConfirmButton.Size = UDim2.new(0, 220, 0, 42)
	task2ConfirmButton.Position = UDim2.new(1, -240, 1, -52)
	task2ConfirmButton.BackgroundColor3 = Color3.fromRGB(85, 25, 120)
	task2ConfirmButton.BorderSizePixel = 0
	task2ConfirmButton.Font = Enum.Font.GothamBold
	task2ConfirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	task2ConfirmButton.TextSize = 18
	task2ConfirmButton.Visible = false
	task2ConfirmButton.Parent = task2Gui

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 10)
	buttonCorner.Parent = task2ConfirmButton

	updateTask2ConfirmText(payload.confirmed or 0, payload.total or 0)

	task2ConfirmButton.MouseButton1Click:Connect(function()
		if task2Confirmed or not task2HasDrawn then
			return
		end

		task2Confirmed = true
		task2ConfirmButton.Visible = false
		remoteEvent:FireServer("Task2Confirm")
	end)

	task2DrawingFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			task2IsDrawing = true
			drawTask2Pixel(input.Position)
		end
	end)
end

local function playFadeTransition(payload)
	local overlay = gui:FindFirstChild("StoryFadeTransition")
	if not overlay then
		overlay = Instance.new("Frame")
		overlay.Name = "StoryFadeTransition"
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.Position = UDim2.fromScale(0, 0)
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BorderSizePixel = 0
		overlay.ZIndex = 1000
		overlay.Parent = gui

		local transitionText = Instance.new("TextLabel")
		transitionText.Name = "TransitionText"
		transitionText.AnchorPoint = Vector2.new(0.5, 0.5)
		transitionText.Size = UDim2.new(0.8, 0, 0, 120)
		transitionText.Position = UDim2.fromScale(0.5, 0.5)
		transitionText.BackgroundTransparency = 1
		transitionText.Font = Enum.Font.GothamBold
		transitionText.TextColor3 = Color3.fromRGB(245, 245, 245)
		transitionText.TextScaled = true
		transitionText.TextWrapped = true
		transitionText.TextTransparency = 1
		transitionText.ZIndex = overlay.ZIndex + 1
		transitionText.Parent = overlay
	end

	local transitionText = overlay:FindFirstChild("TransitionText")
	local fadeText = tostring(payload.text or "")
	overlay.BackgroundTransparency = 1
	overlay.Visible = true

	if transitionText and transitionText:IsA("TextLabel") then
		transitionText.Text = fadeText
		transitionText.Visible = fadeText ~= ""
		transitionText.TextTransparency = 1
	end

	local fadeIn = math.max(0.05, tonumber(payload.fadeInSeconds) or 1)
	local hold = math.max(0, tonumber(payload.holdSeconds) or 2)
	local fadeOut = math.max(0.05, tonumber(payload.fadeOutSeconds) or 1)
	local startTime = os.clock()

	task.spawn(function()
		while os.clock() - startTime < fadeIn do
			local alpha = (os.clock() - startTime) / fadeIn
			overlay.BackgroundTransparency = 1 - alpha
			if transitionText and transitionText:IsA("TextLabel") then
				transitionText.TextTransparency = 1 - alpha
			end
			RunService.RenderStepped:Wait()
		end
		overlay.BackgroundTransparency = 0
		if transitionText and transitionText:IsA("TextLabel") then
			transitionText.TextTransparency = 0
		end
		task.wait(hold)

		local fadeOutStart = os.clock()
		while os.clock() - fadeOutStart < fadeOut do
			local alpha = (os.clock() - fadeOutStart) / fadeOut
			overlay.BackgroundTransparency = alpha
			if transitionText and transitionText:IsA("TextLabel") then
				transitionText.TextTransparency = alpha
			end
			RunService.RenderStepped:Wait()
		end
		overlay.Visible = false
		overlay.BackgroundTransparency = 1
		if transitionText and transitionText:IsA("TextLabel") then
			transitionText.TextTransparency = 1
		end
	end)
end

local function cframeFromPayload(payload)
	if type(payload) ~= "table" or #payload < 12 then
		return nil
	end

	return CFrame.new(table.unpack(payload, 1, 12))
end

local function restoreConversationCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	if savedCameraType then
		camera.CameraType = savedCameraType
	end
	if savedCameraSubject then
		camera.CameraSubject = savedCameraSubject
	end
	if savedCameraCFrame then
		camera.CFrame = savedCameraCFrame
	end
end

local function destroyConversationGui()
	conversationToken += 1
	if conversationGui then
		conversationGui:Destroy()
		conversationGui = nil
	end

	restoreConversationCamera()
	savedCameraType = nil
	savedCameraSubject = nil
	savedCameraCFrame = nil
end

local function createConversationGui()
	if conversationGui then
		conversationGui:Destroy()
	end

	conversationGui = Instance.new("Frame")
	conversationGui.Name = "StoryConversationPanel"
	conversationGui.AnchorPoint = Vector2.new(0.5, 1)
	conversationGui.Size = UDim2.new(0.78, 0, 0, 150)
	conversationGui.Position = UDim2.new(0.5, 0, 1, -36)
	conversationGui.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
	conversationGui.BorderSizePixel = 2
	conversationGui.BorderColor3 = Color3.fromRGB(245, 245, 245)
	conversationGui.ZIndex = 900
	conversationGui.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.PaddingTop = UDim.new(0, 18)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.Parent = conversationGui

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "ConversationText"
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.Arcade
	textLabel.Text = ""
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextSize = 26
	textLabel.TextWrapped = true
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.ZIndex = conversationGui.ZIndex + 1
	textLabel.Parent = conversationGui

	return textLabel
end

local function getConversationGlitch(page)
	local glitch = page.Glitch or page.glitch
	local shorthandWords = page.GlitchWords or page.glitchWords
	if type(glitch) ~= "table" and type(shorthandWords) ~= "table" then
		return nil
	end

	glitch = type(glitch) == "table" and glitch or {}
	local words = glitch.Words or glitch.words or shorthandWords
	if type(words) ~= "table" or #words == 0 then
		return nil
	end

	local validWords = {}
	for _, word in ipairs(words) do
		word = tostring(word)
		if word ~= "" and #word <= 64 then
			table.insert(validWords, word)
		end
		if #validWords >= 20 then break end
	end
	if #validWords == 0 then return nil end

	local characters = tostring(glitch.Characters or glitch.characters or "#@$%!?01")
	if characters == "" then characters = "#" end
	return {
		words = validWords,
		chance = math.clamp(tonumber(glitch.Chance or glitch.chance) or 0.4, 0, 1),
		interval = math.clamp(tonumber(glitch.Interval or glitch.interval) or 0.05, 0.025, 0.5),
		jitterPixels = math.clamp(math.floor(tonumber(glitch.JitterPixels or glitch.jitterPixels) or 2), 0, 12),
		characters = string.sub(characters, 1, 64),
	}
end

local function getMarkedCharacters(text, glitch)
	local marked = {}
	if not glitch then return marked end
	local lowerText = string.lower(text)
	for _, word in ipairs(glitch.words) do
		local searchFrom = 1
		while true do
			local first, last = string.find(lowerText, string.lower(word), searchFrom, true)
			if not first then break end
			for index = first, last do marked[index] = true end
			searchFrom = last + 1
		end
	end
	return marked
end

-- Each visible word gets its own label. This is slightly more work when a page
-- begins, but lets a scary word move without shifting the surrounding sentence.
local function layoutConversationWords(textLabel, fullText, glitch)
	for _, child in ipairs(textLabel:GetChildren()) do
		if child.Name == "ConversationWord" then child:Destroy() end
	end
	textLabel.Text = ""
	if textLabel.AbsoluteSize.X <= 1 then
		RunService.RenderStepped:Wait()
	end

	local availableWidth = math.max(1, textLabel.AbsoluteSize.X)
	local lineHeight = math.ceil(textLabel.TextSize * 1.25)
	local spaceWidth = TextService:GetTextSize(" ", textLabel.TextSize, textLabel.Font, Vector2.new(10000, lineHeight)).X
	local entries = {}
	local x, y, cursor = 0, 0, 1

	while cursor <= #fullText do
		local whitespaceStart, whitespaceEnd = string.find(fullText, "%s+", cursor)
		if whitespaceStart == cursor then
			local whitespace = string.sub(fullText, whitespaceStart, whitespaceEnd)
			for index = 1, #whitespace do
				if string.sub(whitespace, index, index) == "\n" then x, y = 0, y + lineHeight else x += spaceWidth end
			end
			cursor = whitespaceEnd + 1
		end
		if cursor > #fullText then break end

		local wordStart, wordEnd = string.find(fullText, "%S+", cursor)
		if wordStart ~= cursor then break end
		local word = string.sub(fullText, wordStart, wordEnd)
		local width = math.max(1, TextService:GetTextSize(word, textLabel.TextSize, textLabel.Font, Vector2.new(10000, lineHeight)).X)
		if x > 0 and x + width > availableWidth then x, y = 0, y + lineHeight end

		local label = Instance.new("TextLabel")
		label.Name = "ConversationWord"
		label.BackgroundTransparency = 1
		label.Font = textLabel.Font
		label.TextColor3 = textLabel.TextColor3
		label.TextSize = textLabel.TextSize
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Size = UDim2.fromOffset(width + 2, lineHeight)
		label.Position = UDim2.fromOffset(x, y)
		label.ZIndex = textLabel.ZIndex
		label.Parent = textLabel

		table.insert(entries, {
			label = label,
			text = word,
			startIndex = wordStart,
			endIndex = wordEnd,
			basePosition = label.Position,
			marked = getMarkedCharacters(word, glitch),
		})
		x += width
		cursor = wordEnd + 1
	end
	return entries
end

local function renderConversationWords(entries, visibleLength, glitch)
	for _, entry in ipairs(entries) do
		local count = math.clamp(visibleLength - entry.startIndex + 1, 0, #entry.text)
		local output, hasVisibleGlitch = table.create(count), false
		for index = 1, count do
			local character = string.sub(entry.text, index, index)
			if entry.marked[index] then
				hasVisibleGlitch = true
				if character:match("[%w]") and math.random() < glitch.chance then
					local replacementIndex = math.random(1, #glitch.characters)
					character = string.sub(glitch.characters, replacementIndex, replacementIndex)
				end
			end
			output[index] = character
		end
		entry.label.Text = table.concat(output)
		if hasVisibleGlitch and glitch.jitterPixels > 0 then
			entry.label.Position = entry.basePosition + UDim2.fromOffset(
				math.random(-glitch.jitterPixels, glitch.jitterPixels),
				math.random(-glitch.jitterPixels, glitch.jitterPixels)
			)
		else
			entry.label.Position = entry.basePosition
		end
	end
end

local function playConversation(payload)
	destroyConversationGui()
	conversationToken += 1
	local token = conversationToken

	local camera = Workspace.CurrentCamera
	local cameraCFrame = cframeFromPayload(payload.cameraCFrame)
	if camera and cameraCFrame then
		savedCameraType = camera.CameraType
		savedCameraSubject = camera.CameraSubject
		savedCameraCFrame = camera.CFrame
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = cameraCFrame
	end

	local textLabel = createConversationGui()
	local pages = payload.pages or {}
	local typewriterSpeed = math.max(0.005, tonumber(payload.typewriterSpeed) or 0.035)

	task.spawn(function()
		for _, page in ipairs(pages) do
			if token ~= conversationToken then
				return
			end

			local fullText = tostring(page.Text or page.text or "")
			local glitch = getConversationGlitch(page)
			local wordEntries = layoutConversationWords(textLabel, fullText, glitch)
			for index = 1, #fullText do
				if token ~= conversationToken then
					return
				end
				renderConversationWords(wordEntries, index, glitch)
				task.wait(typewriterSpeed)
			end

			local pageEndsAt = os.clock() + math.max(0, tonumber(page.Duration or page.duration) or 4)
			while token == conversationToken and os.clock() < pageEndsAt do
				renderConversationWords(wordEntries, #fullText, glitch)
				task.wait(glitch and glitch.interval or 0.1)
			end
			for _, entry in ipairs(wordEntries) do entry.label.Position = entry.basePosition end
		end

		if token == conversationToken then
			destroyConversationGui()
		end
	end)
end

local function getEnumItem(enumType, value, fallback)
	if typeof(value) == "EnumItem" and value.EnumType == enumType then
		return value
	end
	local ok, item = pcall(function()
		return enumType[tostring(value or "")]
	end)
	return (ok and item) or fallback
end

local function setCutsceneControlsEnabled(enabled)
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	local ok, controls = pcall(function()
		return playerModule and require(playerModule):GetControls()
	end)

	if ok and controls then
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
		controlsWereDisabled = not enabled
	end

	if enabled then
		ContextActionService:UnbindAction(CUTSCENE_CONTROL_ACTION)
	else
		ContextActionService:BindActionAtPriority(
			CUTSCENE_CONTROL_ACTION,
			function() return Enum.ContextActionResult.Sink end,
			false,
			Enum.ContextActionPriority.High.Value,
			table.unpack(Enum.PlayerActions:GetEnumItems())
		)
	end
end

local function stopCutscene()
	cutsceneToken += 1
	cutsceneServerStartedAt = nil
	RunService:UnbindFromRenderStep(CUTSCENE_CAMERA_BINDING)
	if cutsceneAnimationConnection then
		cutsceneAnimationConnection:Disconnect()
		cutsceneAnimationConnection = nil
	end
	for _, track in ipairs(cutsceneTimelineTracks) do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(cutsceneTimelineTracks)
	if cutsceneAnimationTrack then
		cutsceneAnimationTrack:Stop(0.1)
		cutsceneAnimationTrack = nil
	end
	if not cutsceneActive then
		return
	end
	cutsceneActive = false

	for _, sound in ipairs(cutsceneSounds) do
		if sound.Parent then sound:Destroy() end
	end
	table.clear(cutsceneSounds)
	if cutsceneEffectGui then
		cutsceneEffectGui:Destroy()
		cutsceneEffectGui = nil
	end

	local camera = Workspace.CurrentCamera
	if camera and cutsceneSavedCamera then
		camera.CameraType = cutsceneSavedCamera.cameraType
		camera.CameraSubject = cutsceneSavedCamera.cameraSubject
		camera.CFrame = cutsceneSavedCamera.cframe
		camera.FieldOfView = cutsceneSavedCamera.fieldOfView
		if cutsceneSavedCamera.focus then camera.Focus = cutsceneSavedCamera.focus end
	end
	cutsceneSavedCamera = nil

	if controlsWereDisabled then
		setCutsceneControlsEnabled(true)
	else
		ContextActionService:UnbindAction(CUTSCENE_CONTROL_ACTION)
	end
end

local function playCameraRigShot(shot, camera, token)
	local model = shot.cameraModel
	local cameraPart = shot.cameraPart
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(Workspace) then return false end
	if typeof(cameraPart) ~= "Instance" or not cameraPart:IsA("BasePart") or not cameraPart:IsDescendantOf(model) then return false end

	local controller = model:FindFirstChildOfClass("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	if not animator then
		warn("StoryHorror: Camera rig " .. model.Name .. " needs an AnimationController with an Animator.")
		return false
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = tostring(shot.animationId or "")
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	animation:Destroy()
	if not ok or not track then
		warn("StoryHorror: Could not load the camera animation for " .. model.Name)
		return false
	end

	cutsceneAnimationTrack = track
	track.Looped = shot.looped == true
	track:Play(math.max(0, tonumber(shot.animationFadeTime) or 0.1), 1, math.max(0.05, tonumber(shot.animationSpeed) or 1))
	if shot.fieldOfView then camera.FieldOfView = math.clamp(tonumber(shot.fieldOfView) or 70, 1, 120) end

	-- Duration is explicit so every client ends at the same time even if an asset is
	-- still loading. When omitted, use the loaded animation length (maximum 120s).
	local duration = math.max(0, tonumber(shot.duration) or 0)
	if duration == 0 then
		local loadDeadline = os.clock() + 3
		while token == cutsceneToken and track.Length <= 0 and os.clock() < loadDeadline do RunService.RenderStepped:Wait() end
		duration = math.clamp(track.Length > 0 and track.Length or 10, 0, 120)
	end
	local finishAt = os.clock() + duration
	while token == cutsceneToken and os.clock() < finishAt and cameraPart:IsDescendantOf(Workspace) do
		camera.CFrame = cameraPart.CFrame
		RunService.RenderStepped:Wait()
	end
	track:Stop(math.max(0, tonumber(shot.animationFadeTime) or 0.1))
	if cutsceneAnimationTrack == track then cutsceneAnimationTrack = nil end
	return token == cutsceneToken
end

local function playCutsceneSound(soundData, elapsedSeconds)
	if type(soundData) ~= "table" or tostring(soundData.soundId or "") == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "StoryCutsceneSound"
	sound.SoundId = tostring(soundData.soundId)
	sound.Volume = math.clamp(tonumber(soundData.volume) or 0.5, 0, 10)
	sound.PlaybackSpeed = math.clamp(tonumber(soundData.playbackSpeed) or 1, 0.05, 4)
	sound.Looped = soundData.looped == true
	sound.Parent = SoundService
	table.insert(cutsceneSounds, sound)
	sound:Play()
	if elapsedSeconds and elapsedSeconds > 0 then
		sound.TimePosition = elapsedSeconds * sound.PlaybackSpeed
	end
	if not sound.Looped then
		sound.Ended:Once(function()
			if sound.Parent then sound:Destroy() end
		end)
	end
end

local function waitForCutscene(token, duration)
	local finishAt = os.clock() + math.max(0, duration)
	while token == cutsceneToken and os.clock() < finishAt do
		RunService.RenderStepped:Wait()
	end
	return token == cutsceneToken
end

local function playBlackScreenEffect(event, token, startedAt)
	if token ~= cutsceneToken then return end
	if cutsceneEffectGui then cutsceneEffectGui:Destroy() end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	local effectGui = Instance.new("ScreenGui")
	effectGui.Name = "StoryCutsceneEffect"
	effectGui.IgnoreGuiInset = true
	effectGui.ResetOnSpawn = false
	effectGui.DisplayOrder = 10000
	effectGui.Parent = playerGui
	cutsceneEffectGui = effectGui

	local fadeIn = tonumber(event.fadeInSeconds) or 0.35
	local hold = tonumber(event.holdSeconds) or 1
	local fadeOut = tonumber(event.fadeOutSeconds) or 0.35
	startedAt = startedAt or Workspace:GetServerTimeNow()
	local transitionType = string.lower(tostring(event.transitionType or "normal"))
	local top, bottom, black
	if transitionType == "wink" then
		-- Fixed half-screen panels work across different viewport sizes.
		top = Instance.new("Frame")
		top.Name = "TopEyelid"
		top.Size = UDim2.fromScale(1, 0.505)
		top.Position = UDim2.fromScale(0, -0.505)
		top.BackgroundColor3 = Color3.new(0, 0, 0)
		top.BorderSizePixel = 0
		top.ZIndex = 10
		top.Parent = effectGui

		bottom = Instance.new("Frame")
		bottom.Name = "BottomEyelid"
		bottom.Size = UDim2.fromScale(1, 0.505)
		bottom.Position = UDim2.fromScale(0, 1)
		bottom.BackgroundColor3 = Color3.new(0, 0, 0)
		bottom.BorderSizePixel = 0
		bottom.ZIndex = 10
		bottom.Parent = effectGui
	else
		black = Instance.new("Frame")
		black.Name = "BlackScreen"
		black.Size = UDim2.fromScale(1, 1)
		black.BackgroundColor3 = Color3.new(0, 0, 0)
		black.BackgroundTransparency = 1
		black.BorderSizePixel = 0
		black.Parent = effectGui
	end
	while token == cutsceneToken and cutsceneEffectGui == effectGui do
		local elapsed = Workspace:GetServerTimeNow() - startedAt
		if elapsed >= fadeIn + hold + fadeOut then break end
		local coverage = 1
		if elapsed < fadeIn then
			coverage = math.clamp(elapsed / fadeIn, 0, 1)
		elseif elapsed > fadeIn + hold then
			coverage = fadeOut > 0 and 1 - math.clamp((elapsed - fadeIn - hold) / fadeOut, 0, 1) or 0
		end
		if top then
			coverage = TweenService:GetValue(coverage, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			top.Position = UDim2.fromScale(0, -0.505 * (1 - coverage))
			bottom.Position = UDim2.fromScale(0, 1 - 0.505 * coverage)
		else
			black.BackgroundTransparency = 1 - coverage
		end
		RunService.RenderStepped:Wait()
	end
	if cutsceneEffectGui == effectGui then cutsceneEffectGui = nil end
	effectGui:Destroy()
end

local function describeCutsceneAnimation(data)
	return tostring(data.modelName or "camera") .. "/" .. tostring(data.animationName or "Animation")
		.. " [" .. tostring(data.animationId or "missing animation ID") .. "]"
end

local function isCutsceneTimelineRigReady(model, data)
	local expectedParts = tonumber(data.rigPartCount) or 0
	local expectedJoints = tonumber(data.rigJointCount) or 0
	if expectedParts == 0 and expectedJoints == 0 then return true end
	local parts, joints = 0, 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then parts += 1 end
		if descendant:IsA("Motor6D") or descendant:IsA("Bone") then joints += 1 end
	end
	return parts >= expectedParts and joints >= expectedJoints
end

local function findCutsceneTimelineRig(data)
	local model = data.model or data.cameraModel
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(Workspace) then
		local root = Workspace
		if data.modelRootName and data.modelRootName ~= "" then
			root = Workspace:FindFirstChild(data.modelRootName, true)
		end
		local name = tostring(data.modelName or "")
		model = root and name ~= "" and (root.Name == name and root or root:FindFirstChild(name, true)) or nil
	end
	if not model or not model:IsA("Model") then return nil end
	local cameraPart = data.cameraPart
	if typeof(cameraPart) ~= "Instance" or not cameraPart:IsA("BasePart") or not cameraPart:IsDescendantOf(model) then
		cameraPart = data.animatedRig and model:FindFirstChild(data.cameraPartName or "CameraPart", true) or nil
	end
	return model, cameraPart and cameraPart:IsA("BasePart") and cameraPart or nil
end

local function loadCutsceneTimelineTrack(data, token)
	local deadline = os.clock() + 15
	local model, cameraPart
	repeat
		if token ~= cutsceneToken then return nil end
		model, cameraPart = findCutsceneTimelineRig(data)
		if model and (not data.animatedRig or cameraPart) and isCutsceneTimelineRigReady(model, data) then break end
		if os.clock() >= deadline then
			error("Rig missing or incompletely replicated after 15 seconds (root=" .. tostring(data.modelRootName or "Workspace")
				.. ", StreamingEnabled=" .. tostring(Workspace.StreamingEnabled) .. ")")
		end
		RunService.Heartbeat:Wait()
	until false

	local host = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not host then
		host = Instance.new("AnimationController")
		host.Parent = model
	end
	local animator = host:FindFirstChildOfClass("Animator")
	if not animator then
		-- A local fallback also handles the Animator not having replicated yet.
		animator = Instance.new("Animator")
		animator.Parent = host
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = tostring(data.animationId or "")
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	animation:Destroy()
	if not ok or not track then
		error("Animator:LoadAnimation failed for " .. tostring(data.animationId) .. ": " .. tostring(track))
	end
	if token ~= cutsceneToken then track:Destroy(); return nil end
	table.insert(cutsceneTimelineTracks, track)
	track.Priority = getEnumItem(Enum.AnimationPriority, data.priority, Enum.AnimationPriority.Action)
	track.Looped = data.looped == true
	-- Start loading/evaluating BEFORE checking Length. Zero weight prevents an
	-- upcoming camera shot from overriding the current shot on the same rig.
	track:Play(0, 0, 0)
	return { track = track, model = model, cameraPart = cameraPart, deadline = deadline }
end

local function playCutsceneTimeline(payload, camera, token)
	local startedAt = tonumber(payload.startedAt) or Workspace:GetServerTimeNow()
	local experienceContext = "universe=" .. tostring(payload.universeId or "?") .. ", place=" .. tostring(payload.placeId or "?")
	if payload.diagnostics then
		print("StoryHorror: client cutscene-v3 received " .. tostring(payload.serverRevision) .. " scene (" .. experienceContext
			.. ", published version=" .. tostring(payload.placeVersion) .. ", StreamingEnabled=" .. tostring(Workspace.StreamingEnabled) .. ")")
	end
	local states, shots = {}, {}
	local duration, effectsEnd = 0, 0
	local activeShot

	local function newState(data)
		local state = {
			data = data,
			speed = math.max(0.05, tonumber(data.speed or data.animationSpeed) or 1),
			startTime = 0,
			endTime = math.huge,
		}
		table.insert(states, state)
		return state
	end
	for _, shot in ipairs(payload.shots or {}) do
		local entry = { data = shot }
		if shot.animatedRig then entry.state = newState(shot) end
		table.insert(shots, entry)
	end
	for _, actor in ipairs(payload.actors or {}) do newState(actor) end
	for _, event in ipairs(payload.events or {}) do
		effectsEnd = math.max(effectsEnd, (tonumber(event.time) or 0)
			+ (tonumber(event.fadeInSeconds) or 0) + (tonumber(event.holdSeconds) or 0) + (tonumber(event.fadeOutSeconds) or 0))
	end

	local function refreshSchedule()
		local shotEnd = 0
		for _, entry in ipairs(shots) do
			entry.startTime = shotEnd
			local shot = entry.data
			if entry.state then
				local shotDuration = tonumber(shot.duration) or 0
				if shotDuration <= 0 then
					local info = entry.state.info
					shotDuration = info and info.track.Length > 0 and info.track.Length / entry.state.speed or 10
				end
				shotEnd += shotDuration
				entry.state.startTime, entry.state.endTime = entry.startTime, shotEnd
			else
				shotEnd += math.max(0, tonumber(shot.moveDuration) or 0) + math.max(0, tonumber(shot.holdDuration) or 0)
			end
			entry.endTime = shotEnd
		end
		duration = math.max(shotEnd, effectsEnd)
	end
	refreshSchedule()
	if Workspace:GetServerTimeNow() - startedAt >= duration then stopCutscene(); return end

	local function releaseState(state, reason)
		local info = state.info
		state.info = nil
		state.failed = true
		if info then
			local index = table.find(cutsceneTimelineTracks, info.track)
			if index then table.remove(cutsceneTimelineTracks, index) end
			info.track:Stop(0)
			info.track:Destroy()
		end
		warn("StoryHorror: " .. describeCutsceneAnimation(state.data) .. ": " .. reason
			.. " (" .. experienceContext .. "); continuing the camera cutscene.")
	end

	local function updateAnimations()
		if token ~= cutsceneToken then return end
		local elapsed = math.max(0, Workspace:GetServerTimeNow() - startedAt)
		local active = {}
		local resync = false
		for _, state in ipairs(states) do
			local info = state.info
			if not info then continue end
			local track = info.track
			if track.Length > 0 and not state.lengthReady then
				state.lengthReady = true
				refreshSchedule()
			end
			if not info.model:IsDescendantOf(Workspace) then
				releaseState(state, "rig unloaded")
			elseif track.Length <= 0 then
				if os.clock() >= info.deadline then
					releaseState(state, "animation length stayed zero; check this experience's animation access, published ID, moderation, and F9 asset-fetch errors")
				end
			elseif elapsed >= state.startTime and elapsed < state.endTime then
				local position = (elapsed - state.startTime) * state.speed
				local speed = state.speed
				if state.data.looped then
					position %= track.Length
				elseif position >= track.Length - 0.00001 then
					position = math.max(0, track.Length - 0.00001)
					speed = 0 -- Hold the last pose instead of restarting a finished clip.
				end
				local difference = math.abs(track.TimePosition - position)
				if state.data.looped then difference = math.min(difference, math.abs(track.Length - difference)) end
				if not state.started or not track.IsPlaying or difference > 1 / 30 then resync = true end
				table.insert(active, { state = state, position = position, speed = speed })
			elseif state.started then
				track:Stop(0)
				state.started = false
			end
		end
		for _, entry in ipairs(active) do
			local state = entry.state
			local track = state.info.track
			if not state.started or not track.IsPlaying then
				track:Play(0, 1, entry.speed)
				state.started = true
				state.playbackSpeed = entry.speed
			end
			if resync then track.TimePosition = entry.position end
			if state.playbackSpeed ~= entry.speed then
				track:AdjustSpeed(entry.speed)
				state.playbackSpeed = entry.speed
			end
		end
	end

	local function updateCamera()
		if token ~= cutsceneToken then return end
		local elapsed = math.max(0, Workspace:GetServerTimeNow() - startedAt)
		if elapsed >= duration then stopCutscene(); return end
		camera = Workspace.CurrentCamera or camera
		camera.CameraType = Enum.CameraType.Scriptable
		for _, entry in ipairs(shots) do
			if elapsed < entry.startTime or elapsed >= entry.endTime then continue end
			local shot = entry.data
			if activeShot ~= entry then
				activeShot = entry
				entry.fromCFrame, entry.fromFieldOfView = camera.CFrame, camera.FieldOfView
				playCutsceneSound(shot.sound, elapsed - entry.startTime)
			end
			if entry.state then
				local _, part = findCutsceneTimelineRig(shot)
				-- Redirect immediately, even while actors or animations are loading.
				local target = part and part.CFrame or cframeFromPayload(shot.cameraCFrame)
				if target then camera.CFrame = target; camera.Focus = target end
				if shot.fieldOfView then camera.FieldOfView = shot.fieldOfView end
			else
				local target = cframeFromPayload(shot.cameraCFrame)
				local moveDuration = math.max(0, tonumber(shot.moveDuration) or 0)
				local alpha = moveDuration > 0 and math.clamp((elapsed - entry.startTime) / moveDuration, 0, 1) or 1
				alpha = TweenService:GetValue(alpha, getEnumItem(Enum.EasingStyle, shot.easingStyle, Enum.EasingStyle.Sine),
					getEnumItem(Enum.EasingDirection, shot.easingDirection, Enum.EasingDirection.InOut))
				if target then camera.CFrame = entry.fromCFrame:Lerp(target, alpha) end
				if shot.fieldOfView then camera.FieldOfView = entry.fromFieldOfView + (shot.fieldOfView - entry.fromFieldOfView) * alpha end
			end
			break
		end
	end

	cutsceneAnimationConnection = RunService.PreAnimation:Connect(updateAnimations)
	RunService:BindToRenderStep(CUTSCENE_CAMERA_BINDING, Enum.RenderPriority.Camera.Value + 1, updateCamera)
	updateCamera()

	-- Streaming can omit Instance references for viewers away from the scene.
	-- Request the initial camera area without blocking camera ownership or playback.
	local firstShot = shots[1] and shots[1].data
	if Workspace.StreamingEnabled and firstShot and firstShot.cameraCFrame then
		local target = cframeFromPayload(firstShot.cameraCFrame)
		if target then
			task.spawn(function() pcall(function() player:RequestStreamAroundAsync(target.Position, 5) end) end)
		end
	end
	for _, state in ipairs(states) do
		task.spawn(function()
			local ok, info = pcall(loadCutsceneTimelineTrack, state.data, token)
			if token ~= cutsceneToken then return end
			if not ok or not info then
				state.failed = true
				warn("StoryHorror: Could not load local cutscene rig " .. describeCutsceneAnimation(state.data)
					.. (ok and "; check the model and animation names." or (": " .. tostring(info))))
				return
			end
			state.info = info
			refreshSchedule()
		end)
	end
	-- Asset warming is optional background work; playback never waits for this.
	task.spawn(function()
		local assets = {}
		for _, state in ipairs(states) do
			local animation = Instance.new("Animation")
			animation.AnimationId = tostring(state.data.animationId or "")
			table.insert(assets, animation)
		end
		local ok, message = pcall(function()
			ContentProvider:PreloadAsync(assets, function(assetId, status)
				if token ~= cutsceneToken or status == Enum.AssetFetchStatus.Success then return end
				warn("StoryHorror: Asset fetch " .. tostring(status) .. " for " .. tostring(assetId) .. " (" .. experienceContext
					.. "). Verify the published experience has access to this animation; client playback cannot bypass Roblox asset permissions.")
			end)
		end)
		if not ok and token == cutsceneToken then warn("StoryHorror: Background animation preload failed: " .. tostring(message)) end
		for _, animation in ipairs(assets) do animation:Destroy() end
	end)
	for _, event in ipairs(payload.events or {}) do
		local eventTime = math.max(0, tonumber(event.time) or 0)
		local eventEnd = eventTime + (tonumber(event.fadeInSeconds) or 0) + (tonumber(event.holdSeconds) or 0) + (tonumber(event.fadeOutSeconds) or 0)
		task.delay(math.max(0, startedAt + eventTime - Workspace:GetServerTimeNow()), function()
			if token == cutsceneToken and event.type == "BlackScreen" and Workspace:GetServerTimeNow() < startedAt + eventEnd then
				playBlackScreenEffect(event, token, startedAt + eventTime)
			end
		end)
	end
end

local function playCutscene(payload)
	local serverStartedAt = tonumber(payload.startedAt)
	if cutsceneActive and serverStartedAt and cutsceneServerStartedAt == serverStartedAt then return end
	stopCutscene()
	destroyConversationGui()
	cutsceneToken += 1
	local token = cutsceneToken
	local camera = Workspace.CurrentCamera
	local cameraDeadline = os.clock() + 5
	while not camera and token == cutsceneToken and os.clock() < cameraDeadline do
		RunService.Heartbeat:Wait()
		camera = Workspace.CurrentCamera
	end
	if token ~= cutsceneToken then return end
	if not camera then
		warn("StoryHorror: Cutscene received, but Workspace.CurrentCamera was unavailable for 5 seconds.")
		return
	end

	cutsceneActive = true
	cutsceneServerStartedAt = serverStartedAt
	cutsceneSavedCamera = {
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		cframe = camera.CFrame,
		fieldOfView = camera.FieldOfView,
		focus = camera.Focus,
	}
	if payload.freezeControls ~= false then
		setCutsceneControlsEnabled(false)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if payload.clientTimeline == true or #(payload.actors or {}) > 0 then
		task.spawn(function()
			local ok, message = pcall(playCutsceneTimeline, payload, camera, token)
			if not ok and token == cutsceneToken then
				warn("StoryHorror: " .. tostring(message))
				stopCutscene()
			end
		end)
		return
	end

	local cutsceneStartedAt = os.clock()
	local latestEventEnd = 0
	for _, event in ipairs(payload.events or {}) do
		local eventTime = math.max(0, tonumber(event.time) or 0)
		latestEventEnd = math.max(latestEventEnd, eventTime
			+ math.max(0, tonumber(event.fadeInSeconds) or 0)
			+ math.max(0, tonumber(event.holdSeconds) or 0)
			+ math.max(0, tonumber(event.fadeOutSeconds) or 0))
		task.delay(eventTime, function()
			if token == cutsceneToken and event.type == "BlackScreen" then
				playBlackScreenEffect(event, token)
			end
		end)
	end

	task.spawn(function()
		for _, shot in ipairs(payload.shots or {}) do
			if token ~= cutsceneToken then return end
			if shot.animatedRig then
				playCutsceneSound(shot.sound)
				if not playCameraRigShot(shot, camera, token) then
					if token ~= cutsceneToken then return end
					warn("StoryHorror: Invalid animated camera rig; skipping shot.")
					if not waitForCutscene(token, math.max(0, tonumber(shot.duration) or 0)) then return end
				end
				continue
			end
			local target = cframeFromPayload(shot.cameraCFrame)
			if target then
				local duration = math.max(0, tonumber(shot.moveDuration) or 0)
				local goal = { CFrame = target }
				if shot.fieldOfView then goal.FieldOfView = math.clamp(tonumber(shot.fieldOfView) or 70, 1, 120) end
				if duration == 0 then
					for property, value in pairs(goal) do camera[property] = value end
				else
					local tween = TweenService:Create(camera, TweenInfo.new(
						duration,
						getEnumItem(Enum.EasingStyle, shot.easingStyle, Enum.EasingStyle.Sine),
						getEnumItem(Enum.EasingDirection, shot.easingDirection, Enum.EasingDirection.InOut)
						), goal)
					tween:Play()
					local started = os.clock()
					while token == cutsceneToken and os.clock() - started < duration do RunService.RenderStepped:Wait() end
					if token ~= cutsceneToken then tween:Cancel(); return end
				end
			end
			playCutsceneSound(shot.sound)
			local holdUntil = os.clock() + math.max(0, tonumber(shot.holdDuration) or 0)
			while token == cutsceneToken and os.clock() < holdUntil do RunService.RenderStepped:Wait() end
		end


		-- A timed effect may intentionally outlast the final camera shot. Keep the
		-- cutscene alive until that effect finishes instead of deleting its GUI early.
		local remainingEffectTime = latestEventEnd - (os.clock() - cutsceneStartedAt)
		if remainingEffectTime > 0 and not waitForCutscene(token, remainingEffectTime) then return end
		if token == cutsceneToken then stopCutscene() end
	end)
end

player.CharacterAdded:Connect(function()
	if cutsceneActive then
		stopCutscene()
	end
end)


local function setStoryStartPromptEnabled(enabled)
	local startPart = Workspace:FindFirstChild(UI_CONFIG.StoryStartPartName)
	if not startPart then
		return
	end

	local prompt = startPart:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = enabled
	end
end

local function hasEnoughCollectibles()
	return required > 0 and points >= required
end

local function refreshPromptVisibility()
	setStoryStartPromptEnabled(hasEnoughCollectibles())
end

ProximityPromptService.PromptShown:Connect(function(prompt)
	local parent = prompt.Parent
	if parent and parent:IsDescendantOf(Workspace) then
		local startPart = Workspace:FindFirstChild(UI_CONFIG.StoryStartPartName)
		if startPart and parent == startPart then
			prompt.Enabled = hasEnoughCollectibles()
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not task2IsDrawing then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		drawTask2Pixel(input.Position)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		task2IsDrawing = false
	end
end)

remoteEvent.OnClientEvent:Connect(function(action, payload)
	payload = payload or {}

	if action == "StoryReady" then
		print("StoryHorror: client cutscene-v3 ready; server=" .. tostring(payload.serverRevision)
			.. ", place=" .. tostring(payload.placeId) .. ", published version=" .. tostring(payload.placeVersion)
			.. ", universe=" .. tostring(payload.universeId))
	elseif action == "PointsUpdate" or action == "CollectibleCount" then
		local newPoints = tonumber(payload.points)
		if not newPoints and payload.collected then
			newPoints = (tonumber(payload.collected) or 0) * (tonumber(payload.pointsPerCollectible) or 10)
		end

		points = newPoints or points
		required = tonumber(payload.required) or required
		pointsUiUnlocked = pointsUiUnlocked or points > 0
		updateCollectibleCounter()
		refreshPromptVisibility()
	elseif action == "Registered" then
		showNotification("Te-ai inscris pentru excursie")
	elseif action == "Countdown" then
		countdownEndsAt = tonumber(payload.endsAt)
		countdownLabel.Visible = elementIsEnabled("Countdown") and countdownEndsAt ~= nil
	elseif action == "HidePoints" then
		pointsUiUnlocked = false
		collectibleCounter.Visible = false
	elseif action == "StoryStarted" then
		countdownEndsAt = nil
		pointsUiUnlocked = false
		collectibleCounter.Visible = false
		countdownLabel.Visible = false
		showNotification("Excursia a inceput")
	elseif action == "TaskUpdate" then
		taskState = payload
		updateTaskLabel()
	elseif action == "Task2Start" then
		createTask2Gui(payload)
	elseif action == "Task2ConfirmUpdate" then
		updateTask2ConfirmText(payload.confirmed or 0, payload.total or 0)
	elseif action == "Task2End" then
		destroyTask2Gui()
	elseif action == "FadeTransition" then
		playFadeTransition(payload)
	elseif action == "ConversationStart" then
		playConversation(payload)
	elseif action == "ConversationEnd" then
		destroyConversationGui()
	elseif action == "CutsceneStart" then
		playCutscene(payload)
	elseif action == "CutsceneError" then
		warn("StoryHorror: " .. tostring(payload.message))
	elseif action == "CutsceneEnd" then
		stopCutscene()
	elseif action == "TaskComplete" then
		taskState = nil
		updateTaskLabel()
		showNotification(payload.message or "Task complete.")
	elseif action == "Message" then
		showNotification(payload.text or "")
	elseif action == "UIVisibility" then
		applyUiVisibility(payload)
	elseif action == "HarvestSwing" then
		playHarvestSwing(payload.tool)
	elseif action == "HarvestImpact" then
		playTreeShake(payload.tree, payload.pivot, payload.angleDegrees)
	end
end)

-- Register the listener before asking for state. Published clients can finish
-- loading after CutsceneStart was originally broadcast; the server replays it.
print("StoryHorror: client cutscene-v3 loaded; requesting server state.")
remoteEvent:FireServer("StoryClientReady")

RunService.RenderStepped:Connect(function()
	if countdownEndsAt then
		local remaining = math.max(0, math.ceil(countdownEndsAt - Workspace:GetServerTimeNow()))
		countdownLabel.Text = string.format("Excursia incepe in: %02d:%02d", math.floor(remaining / 60), remaining % 60)
		countdownLabel.Visible = elementIsEnabled("Countdown") and remaining > 0
		if remaining <= 0 then
			countdownEndsAt = nil
		end
	end

	if taskState and taskState.endsAt then
		updateTaskLabel()
	end

	if notificationLabel.Visible and os.clock() >= notificationHideAt then
		notificationLabel.Visible = false
	end
end)

updateCollectibleCounter()
refreshPromptVisibility()
