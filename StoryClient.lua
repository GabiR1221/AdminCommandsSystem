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

	collectibleCounter.Text = string.format("Story Points: %d / %d", points, required)
	collectibleCounter.Visible = true
end

local function updateTaskLabel()
	if not taskState then
		taskLabel.Visible = false
		return
	end

	local progressText = string.format("Progress: %d / %d", taskState.progress or 0, taskState.required or 0)
	if taskState.endsAt then
		local remaining = math.max(0, math.ceil(taskState.endsAt - Workspace:GetServerTimeNow()))
		progressText = string.format("Time left: %02d:%02d", math.floor(remaining / 60), remaining % 60)
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
	task2Gui.Size = UDim2.new(0, 560, 0, 520)
	task2Gui.Position = UDim2.new(0.5, -280, 0.5, -260)
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
	title.Text = "Draw on the page, then confirm"
	title.TextColor3 = Color3.fromRGB(245, 245, 245)
	title.TextSize = 20
	title.Parent = task2Gui

	local image = Instance.new("ImageLabel")
	image.Name = "ReferenceImage"
	image.Size = UDim2.new(0, 170, 0, 170)
	image.Position = UDim2.fromOffset(20, 62)
	image.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
	image.BorderSizePixel = 0
	image.ScaleType = Enum.ScaleType.Fit
	image.Image = tostring(payload.image or "")
	image.Parent = task2Gui

	task2DrawingFrame = Instance.new("Frame")
	task2DrawingFrame.Name = "DrawingCanvas"
	task2DrawingFrame.Size = UDim2.new(0, 330, 0, 330)
	task2DrawingFrame.Position = UDim2.fromOffset(210, 62)
	task2DrawingFrame.BackgroundColor3 = Color3.fromRGB(245, 242, 232)
	task2DrawingFrame.BorderSizePixel = 0
	task2DrawingFrame.ClipsDescendants = true
	task2DrawingFrame.Parent = task2Gui

	local instructions = Instance.new("TextLabel")
	instructions.Name = "Instructions"
	instructions.Size = UDim2.new(0, 170, 0, 100)
	instructions.Position = UDim2.fromOffset(20, 245)
	instructions.BackgroundTransparency = 1
	instructions.Font = Enum.Font.Gotham
	instructions.Text = "Hold left click and draw anything, even one dot."
	instructions.TextWrapped = true
	instructions.TextColor3 = Color3.fromRGB(230, 230, 230)
	instructions.TextSize = 16
	instructions.Parent = task2Gui

	task2ConfirmLabel = Instance.new("TextLabel")
	task2ConfirmLabel.Name = "ConfirmLabel"
	task2ConfirmLabel.Size = UDim2.new(1, -40, 0, 28)
	task2ConfirmLabel.Position = UDim2.fromOffset(20, 405)
	task2ConfirmLabel.BackgroundTransparency = 1
	task2ConfirmLabel.Font = Enum.Font.GothamBold
	task2ConfirmLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
	task2ConfirmLabel.TextSize = 18
	task2ConfirmLabel.Parent = task2Gui

	task2ConfirmButton = Instance.new("TextButton")
	task2ConfirmButton.Name = "ConfirmButton"
	task2ConfirmButton.Size = UDim2.new(0, 220, 0, 52)
	task2ConfirmButton.Position = UDim2.new(0.5, -110, 1, -72)
	task2ConfirmButton.BackgroundColor3 = Color3.fromRGB(85, 25, 120)
	task2ConfirmButton.BorderSizePixel = 0
	task2ConfirmButton.Font = Enum.Font.GothamBold
	task2ConfirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	task2ConfirmButton.TextSize = 20
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
	end

	overlay.BackgroundTransparency = 1
	overlay.Visible = true

	local fadeIn = tonumber(payload.fadeInSeconds) or 1
	local hold = tonumber(payload.holdSeconds) or 2
	local fadeOut = tonumber(payload.fadeOutSeconds) or 1
	local startTime = os.clock()

	task.spawn(function()
		while os.clock() - startTime < fadeIn do
			overlay.BackgroundTransparency = 1 - ((os.clock() - startTime) / fadeIn)
			RunService.RenderStepped:Wait()
		end
		overlay.BackgroundTransparency = 0
		task.wait(hold)

		local fadeOutStart = os.clock()
		while os.clock() - fadeOutStart < fadeOut do
			overlay.BackgroundTransparency = (os.clock() - fadeOutStart) / fadeOut
			RunService.RenderStepped:Wait()
		end
		overlay.Visible = false
		overlay.BackgroundTransparency = 1
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
		showNotification("You registered for the story countdown.")
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
		showNotification("The story has started...")
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
		countdownLabel.Text = string.format("Story starts in: %02d:%02d", math.floor(remaining / 60), remaining % 60)
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
