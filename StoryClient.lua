--[[
	StoryHorrorClient.lua
	Place this LocalScript in StarterPlayerScripts or StarterGui.

	This client only displays UI and locally hides/shows the story start ProximityPrompt.
	The server still validates everything, so exploiters cannot start the story without enough points.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

local function showNotification(text)
	notificationLabel.Text = tostring(text or "")
	notificationLabel.Visible = notificationLabel.Text ~= ""
	notificationHideAt = os.clock() + UI_CONFIG.NotificationSeconds
end

local function updateCollectibleCounter()
	if required <= 0 or not pointsUiUnlocked then
		collectibleCounter.Visible = false
		return
	end

	collectibleCounter.Text = string.format("Bani: %d / %d", points, required)
	collectibleCounter.Visible = true
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
	taskLabel.Visible = true
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
			textLabel.Text = ""
			for index = 1, #fullText do
				if token ~= conversationToken then
					return
				end
				textLabel.Text = string.sub(fullText, 1, index)
				task.wait(typewriterSpeed)
			end

			task.wait(math.max(0, tonumber(page.Duration or page.duration) or 4))
		end

		if token == conversationToken then
			destroyConversationGui()
		end
	end)
end

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

	if action == "PointsUpdate" or action == "CollectibleCount" then
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
		countdownLabel.Visible = countdownEndsAt ~= nil
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
	elseif action == "TaskComplete" then
		taskState = nil
		updateTaskLabel()
		showNotification(payload.message or "Task complete.")
	elseif action == "Message" then
		showNotification(payload.text or "")
	end
end)

RunService.RenderStepped:Connect(function()
	if countdownEndsAt then
		local remaining = math.max(0, math.ceil(countdownEndsAt - Workspace:GetServerTimeNow()))
		countdownLabel.Text = string.format("Excursia incepe in: %02d:%02d", math.floor(remaining / 60), remaining % 60)
		countdownLabel.Visible = remaining > 0
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
