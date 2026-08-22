-- Server Script: animation and server-authoritative NPC following.
-- Put this Script directly inside an NPC model containing a Humanoid and HumanoidRootPart.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

-- This controller must be a server Script. A LocalScript inside a workspace NPC
-- does not have a valid execution context and will never run the follower loop.
if not script:IsA("Script") then
	warn(("NPCFollower: %s must use a Script, not a LocalScript."):format(character:GetFullName()))
	return
end

character:SetAttribute("NPCFollowerRunning", true)

local CONFIG = {
	DetectionRadius = character:GetAttribute("DetectionRadius") or 120,
	StopDistance = character:GetAttribute("StopDistance") or 2,
	RepathInterval = character:GetAttribute("RepathInterval") or 0.75,
	TargetMoveThreshold = character:GetAttribute("TargetMoveThreshold") or 5,
	WaypointTimeout = character:GetAttribute("WaypointTimeout") or 2.5,
	AgentRadius = character:GetAttribute("AgentRadius") or 2.5,
	AgentHeight = character:GetAttribute("AgentHeight") or 5,
	AgentCanJump = character:GetAttribute("AgentCanJump") ~= false,
	SeparationRadius = character:GetAttribute("SeparationRadius") or 6,
	SeparationStrength = character:GetAttribute("SeparationStrength") or 3,
}

local animations = {
	Idle = "rbxassetid://12191569041347",
	Walk = "rbxassetid://12656507759730",
	Jump = "rbxassetid://11166710145361",
}

local tracks = {}
for name, animationId in pairs(animations) do
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local track = animator:LoadAnimation(animation)
	track.Looped = name ~= "Jump"
	track.Priority = name == "Jump" and Enum.AnimationPriority.Action or Enum.AnimationPriority.Movement
	tracks[name] = track
	animation:Destroy()
end

local currentTrack
local function play(track)
	if currentTrack == track then
		return
	end
	if currentTrack then
		currentTrack:Stop(0.2)
	end
	track:Play(0.2)
	currentTrack = track
end

humanoid.Running:Connect(function(speed)
	play(speed > 0.1 and tracks.Walk or tracks.Idle)
end)
humanoid.Jumping:Connect(function()
	play(tracks.Jump)
end)
play(tracks.Idle)

-- Network ownership applies to the whole welded assembly. CanSetNetworkOwnership
-- avoids terminating the entire AI when a badly rigged NPC is welded to an
-- anchored part; pathfinding can still start and Studio Output gets a useful warning.
local canSetOwnership, ownershipReason = root:CanSetNetworkOwnership()
if canSetOwnership then
	root:SetNetworkOwner(nil)
else
	warn(("NPCFollower: Could not set server network ownership for %s: %s")
		:format(character:GetFullName(), tostring(ownershipReason)))
end
CollectionService:AddTag(character, "FollowingNPC")

local pathParams = {
	AgentRadius = CONFIG.AgentRadius,
	AgentHeight = CONFIG.AgentHeight,
	AgentCanJump = CONFIG.AgentCanJump,
	WaypointSpacing = 4,
	Costs = {
		NPCForbidden = math.huge,
	},
}

local function getEligibleTarget(player)
	local targetCharacter = player.Character
	local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHumanoid or targetHumanoid.Health <= 0 or not targetRoot then
		return nil
	end
	if targetCharacter:GetAttribute("IgnoreNPCs") then
		return nil
	end

	-- Do not chase targets through water or toward positions which are not on a
	-- walkable surface. FloorMaterial also covers freefall and most jump states;
	-- checking Swimming explicitly handles characters at the bottom of water.
	local targetState = targetHumanoid:GetState()
	if targetState == Enum.HumanoidStateType.Swimming
		or targetHumanoid.FloorMaterial == Enum.Material.Air then
		return nil
	end
	return targetRoot
end

local function candidatePlayers()
	local candidates = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local targetRoot = getEligibleTarget(player)
		if targetRoot then
			local distance = (targetRoot.Position - root.Position).Magnitude
			if distance <= CONFIG.DetectionRadius then
				table.insert(candidates, { player = player, distance = distance })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.distance < b.distance
	end)
	return candidates
end

local function computePath(destination)
	local path = PathfindingService:CreatePath(pathParams)
	local ok, errorMessage = pcall(function()
		path:ComputeAsync(root.Position, destination)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		return path
	end
	if not ok then
		warn(("NPCFollower: Path computation failed for %s: %s")
			:format(character:GetFullName(), tostring(errorMessage)))
	end
	return nil
end

local function crossesForbiddenVolume(destination, targetCharacter)
	local delta = destination - root.Position
	local distance = delta.Magnitude
	if distance < 0.1 then
		return false
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character, targetCharacter }
	local center = root.Position + delta * 0.5
	local scanCFrame = CFrame.lookAt(center, destination)
	local scanSize = Vector3.new(CONFIG.AgentRadius * 2, CONFIG.AgentHeight, distance)
	for _, part in ipairs(Workspace:GetPartBoundsInBox(scanCFrame, scanSize, overlapParams)) do
		local modifier = part:FindFirstChildOfClass("PathfindingModifier")
		if modifier and modifier.Label == "NPCForbidden" then
			return true
		end
	end
	return false
end

-- Pathfinding can occasionally reject a route because decorative/query geometry
-- influenced the navigation mesh even though the geometry is non-collidable. A
-- collision-respecting line test provides a safe direct fallback: it ignores
-- CanCollide=false decoration, but never ignores a real wall or NPCForbidden zone.
local function hasClearDirectRoute(destination, targetCharacter)
	if crossesForbiddenVolume(destination, targetCharacter) then
		return false
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character, targetCharacter }
	rayParams.RespectCanCollide = true
	local origin = root.Position + Vector3.new(0, 1, 0)
	local direction = (destination + Vector3.new(0, 1, 0)) - origin
	local right = direction.Magnitude > 0.1 and direction.Unit:Cross(Vector3.yAxis) or Vector3.xAxis
	for _, offset in ipairs({ Vector3.zero, right * CONFIG.AgentRadius, -right * CONFIG.AgentRadius }) do
		if Workspace:Raycast(origin + offset, direction, rayParams) then
			return false
		end
	end

	-- A clear horizontal ray alone could cross a pit. Sample supporting ground so
	-- direct movement is only used across continuous, non-water walking surface.
	local sampleCount = math.clamp(math.ceil(direction.Magnitude / 4), 1, 30)
	for sampleIndex = 0, sampleCount do
		local alpha = sampleIndex / sampleCount
		local samplePosition = root.Position:Lerp(destination, alpha)
		local sampleOrigin = samplePosition + Vector3.new(0, CONFIG.AgentHeight, 0)
		local ground = Workspace:Raycast(
			sampleOrigin,
			Vector3.new(0, -(CONFIG.AgentHeight * 2 + 4), 0),
			rayParams
		)
		if not ground or ground.Material == Enum.Material.Water then
			return false
		end
	end
	return true
end

-- Pick the nearest reachable player. NPCForbidden modifiers make a bridge or
-- other unsafe region unreachable, so the next candidate is tried automatically.
local function chooseTargetAndPath()
	for _, candidate in ipairs(candidatePlayers()) do
		local targetRoot = getEligibleTarget(candidate.player)
		if targetRoot then
			if hasClearDirectRoute(targetRoot.Position, targetRoot.Parent) then
				return candidate.player, nil, targetRoot.Position, true
			end
			local path = computePath(targetRoot.Position)
			if path then
				return candidate.player, path, targetRoot.Position, false
			end
		end
	end
	return nil, nil, nil, false
end

local function separationOffset()
	local offset = Vector3.zero
	for _, other in ipairs(CollectionService:GetTagged("FollowingNPC")) do
		if other ~= character and other:IsA("Model") then
			local otherRoot = other:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local delta = root.Position - otherRoot.Position
				local flatDelta = Vector3.new(delta.X, 0, delta.Z)
				local distance = flatDelta.Magnitude
				if distance > 0.05 and distance < CONFIG.SeparationRadius then
					offset += flatDelta.Unit * (1 - distance / CONFIG.SeparationRadius) * CONFIG.SeparationStrength
				end
			end
		end
	end
	return offset
end

local function moveToWaypoint(position, targetPlayer, plannedTargetPosition)
	local finished = false
	local reached = false
	local outcome
	local connection = humanoid.MoveToFinished:Connect(function(didReach)
		finished = true
		reached = didReach
	end)
	humanoid:MoveTo(position + separationOffset())
	local startedAt = time()
	while not finished and time() - startedAt < CONFIG.WaypointTimeout and humanoid.Health > 0 do
		local targetRoot = getEligibleTarget(targetPlayer)
		if not targetRoot then
			outcome = "TargetInvalid"
			break
		end
		if (targetRoot.Position - root.Position).Magnitude <= CONFIG.StopDistance then
			outcome = "InRange"
			break
		end
		if time() - startedAt >= CONFIG.RepathInterval
			and (targetRoot.Position - plannedTargetPosition).Magnitude >= CONFIG.TargetMoveThreshold then
			-- Leave the current MoveTo active while ComputeAsync builds the next
			-- route. This is what prevents the old one-step/start-stop movement.
			outcome = "Repath"
			break
		end
		task.wait(0.05)
	end
	connection:Disconnect()
	return outcome or (reached and "Reached" or "Stuck")
end

local function stopMoving()
	humanoid:MoveTo(root.Position)
	-- Remove only horizontal drift. Keeping Y velocity avoids fighting gravity,
	-- slopes, jumping, or the Humanoid's floor solver.
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
	root.AssemblyAngularVelocity = Vector3.zero
end

while character.Parent and humanoid.Health > 0 do
	local targetPlayer, path, plannedTargetPosition, useDirectRoute = chooseTargetAndPath()
	if not targetPlayer then
		stopMoving()
		play(tracks.Idle)
		task.wait(CONFIG.RepathInterval)
		continue
	end
	if useDirectRoute then
		local result = moveToWaypoint(plannedTargetPosition, targetPlayer, plannedTargetPosition)
		if result == "TargetInvalid" or result == "InRange" then
			stopMoving()
		end
		if result == "InRange" then
			task.wait(CONFIG.RepathInterval)
		end
		continue
	end

	local blockedWaypointIndex
	local currentWaypointIndex = 1
	local reachedFollowDistance = false
	local blockedConnection = path.Blocked:Connect(function(waypointIndex)
		if waypointIndex >= currentWaypointIndex then
			blockedWaypointIndex = waypointIndex
		end
	end)
	for waypointIndex, waypoint in ipairs(path:GetWaypoints()) do
		currentWaypointIndex = waypointIndex
		local targetRoot = getEligibleTarget(targetPlayer)
		if not targetRoot or (blockedWaypointIndex and blockedWaypointIndex >= waypointIndex) then
			break
		end
		if (targetRoot.Position - root.Position).Magnitude <= CONFIG.StopDistance then
			stopMoving()
			reachedFollowDistance = true
			break
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		local result = moveToWaypoint(waypoint.Position, targetPlayer, plannedTargetPosition)
		if result ~= "Reached" then
			if result == "TargetInvalid" or result == "InRange" then
				stopMoving()
			end
			if result == "InRange" then
				reachedFollowDistance = true
			end
			break
		end
	end
	blockedConnection:Disconnect()
	if reachedFollowDistance then
		task.wait(CONFIG.RepathInterval)
	end
end

CollectionService:RemoveTag(character, "FollowingNPC")
