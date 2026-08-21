-- Server Script inside the Tool
--
-- A skinned-mesh hand is a Bone, not a BasePart. Roblox's normal RightGrip and
-- physical constraints therefore cannot make a Tool Handle follow that hand.
-- This script keeps the Handle anchored and renders it at the bone attachment.

local RunService = game:GetService("RunService")

local tool = script.Parent
local HAND_ATTACHMENT_NAME = tool:GetAttribute("HandAttachmentName") or "ToolGrip"
local HANDLE_ATTACHMENT_NAME = "HandleAttachment"

local updateConnection = nil
local equippedHandle = nil
local originalHandleProperties = nil

local function disconnectUpdate()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end
end

local function restoreHandle()
	if equippedHandle and equippedHandle.Parent and originalHandleProperties then
		equippedHandle.Anchored = originalHandleProperties.Anchored
		equippedHandle.CanCollide = originalHandleProperties.CanCollide
		equippedHandle.CanTouch = originalHandleProperties.CanTouch
		equippedHandle.Massless = originalHandleProperties.Massless
	end
	equippedHandle = nil
	originalHandleProperties = nil
end

local function cleanup()
	disconnectUpdate()
	restoreHandle()
end

local function findHandAttachment(character)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Bone") then
			local attachment = descendant:FindFirstChild(HAND_ATTACHMENT_NAME)
			if attachment and attachment:IsA("Attachment") then
				return attachment
			end
		end
	end
	return nil
end

tool.Equipped:Connect(function()
	cleanup()

	local character = tool.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local handle = tool:FindFirstChild("Handle")
	local handAttachment = character and findHandAttachment(character)

	if not humanoid or not handle or not handle:IsA("BasePart") then
		warn(("%s needs a Humanoid and a BasePart named Handle"):format(tool:GetFullName()))
		return
	end
	if not handAttachment then
		warn(("No Attachment named %q was found under a Bone in %s"):format(
			HAND_ATTACHMENT_NAME,
			character:GetFullName()
			))
		return
	end

	local handleAttachment = handle:FindFirstChild(HANDLE_ATTACHMENT_NAME)
	if not handleAttachment then
		handleAttachment = Instance.new("Attachment")
		handleAttachment.Name = HANDLE_ATTACHMENT_NAME
		handleAttachment.Parent = handle
	elseif not handleAttachment:IsA("Attachment") then
		warn(("%s must be an Attachment"):format(handleAttachment:GetFullName()))
		return
	end

	equippedHandle = handle
	originalHandleProperties = {
		Anchored = handle.Anchored,
		CanCollide = handle.CanCollide,
		CanTouch = handle.CanTouch,
		Massless = handle.Massless,
	}
	handle.Anchored = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.Massless = true

	-- Positioning formula: handle world CFrame * local attachment CFrame = hand attachment world CFrame.
	local function updateHandle()
		if tool.Parent ~= character or not handle.Parent or not handAttachment.Parent then
			cleanup()
			return
		end
		handle.CFrame = handAttachment.WorldCFrame * handleAttachment.CFrame:Inverse()
	end

	updateHandle()
	updateConnection = RunService.PreSimulation:Connect(updateHandle)
end)

tool.Unequipped:Connect(cleanup)
tool.Destroying:Connect(cleanup)
