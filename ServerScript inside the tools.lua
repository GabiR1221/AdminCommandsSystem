--- Server Script inside the Tool
local tool = script.Parent

-- ⚙️ CONFIGURATION
local HOLD_ANIM_ID = "rbxassetid://123137603809441" -- <--- Put your Hold Animation ID here
local holdTrack = nil

tool.Equipped:Connect(function()
	local character = tool.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

	-- 1. Animation Logic
	if animator and HOLD_ANIM_ID ~= "" then
		local anim = Instance.new("Animation")
		anim.AnimationId = HOLD_ANIM_ID

		holdTrack = animator:LoadAnimation(anim)
		holdTrack.Priority = Enum.AnimationPriority.Action -- Overrides idle/walk
		holdTrack.Looped = true
		holdTrack:Play()
	end

	-- 2. Find the bone (searching the whole character)
	local handBone = character:FindFirstChild("RightHand", true) 

	if handBone and handBone:IsA("Bone") then
		local handle = tool:WaitForChild("Handle")

		-- 3. Create Attachment on Bone if it doesn't exist
		local handAttachment = handBone:FindFirstChild("ToolGrip")
		if not handAttachment then
			handAttachment = Instance.new("Attachment")
			handAttachment.Name = "ToolGrip"
			handAttachment.Parent = handBone
		end

		-- 4. Create Attachment on Handle if it doesn't exist
		local toolAttachment = handle:FindFirstChild("HandleAttachment")
		if not toolAttachment then
			toolAttachment = Instance.new("Attachment")
			toolAttachment.Name = "HandleAttachment"
			toolAttachment.Parent = handle
		end

		-- 5. Clean up the default Roblox "RightGrip" weld
		task.wait()
		local rightGrip = character:FindFirstChild("RightGrip", true)
		if rightGrip then
			rightGrip:Destroy()
		end

		-- 6. Create the RigidConstraint
		local grip = handle:FindFirstChild("ServerToolWeld") or Instance.new("RigidConstraint")
		grip.Name = "ServerToolWeld"
		grip.Attachment0 = toolAttachment
		grip.Attachment1 = handAttachment
		grip.Parent = handle

		print("Server: Tool welded and animation playing!")
	end
end)

-- Clean up when unequipped
tool.Unequipped:Connect(function()
	-- Stop the animation
	if holdTrack then
		holdTrack:Stop()
		holdTrack = nil
	end

	-- Remove the weld
	local handle = tool:FindFirstChild("Handle")
	if handle then
		local grip = handle:FindFirstChild("ServerToolWeld")
		if grip then grip:Destroy() end
	end
end)
