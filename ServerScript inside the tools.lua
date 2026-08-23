-- Server Script inside the Tool
--
-- A skinned-mesh hand is a Bone, not a BasePart. Roblox's normal RightGrip and
-- physical constraints therefore cannot make a Tool Handle follow that hand.
-- This script keeps the Handle anchored and renders it at the bone attachment.

local RunService = game:GetService("RunService")

local tool = script.Parent
local HAND_ATTACHMENT_NAME = tool:GetAttribute("HandAttachmentName") or "ToolGrip"
local HANDLE_ATTACHMENT_NAME = "HandleAttachment"
local DEFAULT_HOLD_ANIMATION_ID = "rbxassetid://123137603809441"

local updateConnection = nil
local equippedHandle = nil
local originalHandleProperties = nil
local holdTrack = nil
local holdAnimation = nil

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

local function stopHoldAnimation()
	if holdTrack then
		holdTrack:Stop(0.15)
		holdTrack:Destroy()
		holdTrack = nil
	end
	if holdAnimation then
		holdAnimation:Destroy()
		holdAnimation = nil
	end
end

local function cleanup()
	disconnectUpdate()
	stopHoldAnimation()
	restoreHandle()
end

local function getHoldAnimationId()
	local animationId = tool:GetAttribute("HoldAnimationId")
	if animationId == nil then
		animationId = DEFAULT_HOLD_ANIMATION_ID
	elseif typeof(animationId) == "number" then
		animationId = "rbxassetid://" .. tostring(animationId)
	end

	if typeof(animationId) ~= "string" or animationId == "" then
		return nil
	end
	if not animationId:match("^rbxassetid://%d+$") then
		warn(("%s has an invalid HoldAnimationId: %s"):format(tool:GetFullName(), tostring(animationId)))
		return nil
	end
	return animationId
end

local function playHoldAnimation(humanoid)
	local animationId = getHoldAnimationId()
	if not animationId then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		-- Creating the Animator on the server is important: tracks loaded through a
		-- client-created Animator do not replicate correctly.
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	holdAnimation = Instance.new("Animation")
	holdAnimation.Name = "ToolHoldAnimation"
	holdAnimation.AnimationId = animationId

	local loaded, result = pcall(function()
		return animator:LoadAnimation(holdAnimation)
	end)
	if not loaded then
		warn(("Could not load hold animation %s for %s: %s"):format(
			animationId,
			tool:GetFullName(),
			tostring(result)
			))
		holdAnimation:Destroy()
		holdAnimation = nil
		return
	end

	holdTrack = result
	holdTrack.Priority = Enum.AnimationPriority.Action4
	holdTrack.Looped = true
	holdTrack:Play(0.15, 1, 1)
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

	if not humanoid then
		warn(("%s needs a Humanoid in its character"):format(tool:GetFullName()))
		return
	end

	-- Start the animation before validating the custom grip. A grip setup error
	-- must never prevent the independent hold animation from playing.
	playHoldAnimation(humanoid)

	if not handle or not handle:IsA("BasePart") then
		warn(("%s needs a BasePart named Handle"):format(tool:GetFullName()))
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
