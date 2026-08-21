-- LocalScript inside the Tool
--
-- The server keeps the Handle correct and replicated for everybody else. The
-- owning client additionally aligns it immediately before rendering so that
-- server/network latency cannot make the Tool trail behind the local character.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local tool = script.Parent
local HAND_ATTACHMENT_NAME = tool:GetAttribute("HandAttachmentName") or "ToolGrip"
local HANDLE_ATTACHMENT_NAME = "HandleAttachment"
local BINDING_NAME = "SkinnedTool_" .. HttpService:GenerateGUID(false)
local DEFAULT_HOLD_ANIMATION_ID = "rbxassetid://140339180147790"

local isBound = false
local holdTrack = nil
local holdAnimation = nil

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

local function unbind()
	if isBound then
		RunService:UnbindFromRenderStep(BINDING_NAME)
		isBound = false
	end
end

local function playHoldAnimation(character)
	stopHoldAnimation()

	local animationId = tool:GetAttribute("HoldAnimationId")
	if animationId == nil then
		animationId = DEFAULT_HOLD_ANIMATION_ID
	end
	if typeof(animationId) == "number" then
		animationId = "rbxassetid://" .. tostring(animationId)
	end
	if typeof(animationId) ~= "string" or animationId == "" then
		return
	end
	if not animationId:match("^rbxassetid://%d+$") then
		warn(("%s has an invalid HoldAnimationId: %s"):format(tool:GetFullName(), tostring(animationId)))
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warn(("%s cannot play its hold animation because the character has no server-created Animator")
			:format(tool:GetFullName()))
		return
	end

	-- Player-character animations loaded on its server-created Animator replicate
	-- from the owning client. Loading locally also starts in the same visual frame
	-- as the locally evaluated skinned bones.
	holdAnimation = Instance.new("Animation")
	holdAnimation.Name = "ToolHoldAnimation"
	holdAnimation.AnimationId = animationId
	holdTrack = animator:LoadAnimation(holdAnimation)
	holdTrack.Priority = Enum.AnimationPriority.Action
	holdTrack.Looped = true
	holdTrack:Play(0.15)
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

local function beginLocalAlignment()
	unbind()

	local character = player.Character
	local handle = tool:FindFirstChild("Handle")
	local handleAttachment = handle and handle:FindFirstChild(HANDLE_ATTACHMENT_NAME)
	local handAttachment = character and findHandAttachment(character)

	if tool.Parent == character then
		playHoldAnimation(character)
	end

	-- The server Script reports detailed setup warnings. Silently returning here
	-- avoids showing every client warnings for a Tool that it does not own.
	if tool.Parent ~= character
		or not handle
		or not handle:IsA("BasePart")
		or not handleAttachment
		or not handleAttachment:IsA("Attachment")
		or not handAttachment
	then
		return
	end

	isBound = true
	RunService:BindToRenderStep(
		BINDING_NAME,
		Enum.RenderPriority.Character.Value + 1,
		function()
			if tool.Parent ~= character
				or not handle.Parent
				or not handleAttachment.Parent
				or not handAttachment.Parent
			then
				unbind()
				return
			end

			-- This local write is visual only. The server remains authoritative.
			handle.CFrame = handAttachment.WorldCFrame * handleAttachment.CFrame:Inverse()
		end
	)
end

tool.Equipped:Connect(beginLocalAlignment)
tool.Unequipped:Connect(function()
	unbind()
	stopHoldAnimation()
end)
tool.Destroying:Connect(function()
	unbind()
	stopHoldAnimation()
end)
