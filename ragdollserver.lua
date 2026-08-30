repeat task.wait() until script.Parent.Parent.Parent:IsA("Player")
repeat task.wait() until script.Parent.Parent.Parent.Character and script.Parent.Parent.Parent.Character:FindFirstChild("Humanoid")

local player = script.Parent.Parent.Parent
local character = player.Character
local humanoid = character:WaitForChild("Humanoid")
humanoid.BreakJointsOnDeath = true

local variables = script.Parent:WaitForChild("variables")
local variables_ragdoll = variables:WaitForChild("ragdoll")

local events = script.Parent:WaitForChild("events")
local events_variableserver = events:WaitForChild("variableserver")

local functions = script.Parent:WaitForChild("functions")
local functions_remoteragdoll = functions:WaitForChild("remoteragdoll")
local functions_remoteragdollvelocity = functions:WaitForChild("remoteragdollvelocity")
local functions_ragdoll = functions:WaitForChild("ragdoll")

local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")

local constraintfolder = character:FindFirstChild("RagdollConstraints")
if not constraintfolder then
	constraintfolder = Instance.new("Folder")
	constraintfolder.Name = "RagdollConstraints"
	constraintfolder.Parent = character
end

local collisionfolder = character:FindFirstChild("CollisionConstraints")
if not collisionfolder then
	collisionfolder = Instance.new("Folder")
	collisionfolder.Name = "CollisionConstraints"
	collisionfolder.Parent = character
end

local ok = pcall(function()
	PhysicsService:GetCollisionGroupId("noclip")
end)

if not ok then
	PhysicsService:CreateCollisionGroup("noclip")
	PhysicsService:CollisionGroupSetCollidable("Default", "noclip", false)
end

local function isClassicR15(char)
	return char:FindFirstChild("UpperTorso") and char:FindFirstChild("LowerTorso")
end

local function findMorphMesh(char)
	local mesh = char:FindFirstChild("char1")
	if mesh and mesh:IsA("MeshPart") then
		return mesh
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("MeshPart") and d.Name ~= "HumanoidRootPart" then
			return d
		end
	end
	return nil
end

local rigMode = isClassicR15(character) and "ClassicR15" or "BoneMorph"

local classic = {}
local morph = {}

local function buildClassicRig()
	classic.bodyparts = {
		HumanoidRootPart = character:WaitForChild("HumanoidRootPart"),
		LowerTorso = character:WaitForChild("LowerTorso"),

		LeftUpperLeg = character:WaitForChild("LeftUpperLeg"),
		LeftLowerLeg = character:WaitForChild("LeftLowerLeg"),
		LeftFoot = character:WaitForChild("LeftFoot"),

		RightUpperLeg = character:WaitForChild("RightUpperLeg"),
		RightLowerLeg = character:WaitForChild("RightLowerLeg"),
		RightFoot = character:WaitForChild("RightFoot"),

		UpperTorso = character:WaitForChild("UpperTorso"),

		LeftUpperArm = character:WaitForChild("LeftUpperArm"),
		LeftLowerArm = character:WaitForChild("LeftLowerArm"),
		LeftHand = character:WaitForChild("LeftHand"),

		RightUpperArm = character:WaitForChild("RightUpperArm"),
		RightLowerArm = character:WaitForChild("RightLowerArm"),
		RightHand = character:WaitForChild("RightHand"),

		Head = character:WaitForChild("Head"),
	}

	classic.motors = {
		Root = classic.bodyparts.LowerTorso:WaitForChild("Root"),

		LeftHip = classic.bodyparts.LeftUpperLeg:WaitForChild("LeftHip"),
		LeftKnee = classic.bodyparts.LeftLowerLeg:WaitForChild("LeftKnee"),
		LeftAnkle = classic.bodyparts.LeftFoot:WaitForChild("LeftAnkle"),

		RightHip = classic.bodyparts.RightUpperLeg:WaitForChild("RightHip"),
		RightKnee = classic.bodyparts.RightLowerLeg:WaitForChild("RightKnee"),
		RightAnkle = classic.bodyparts.RightFoot:WaitForChild("RightAnkle"),

		Waist = classic.bodyparts.UpperTorso:WaitForChild("Waist"),

		LeftShoulder = classic.bodyparts.LeftUpperArm:WaitForChild("LeftShoulder"),
		LeftElbow = classic.bodyparts.LeftLowerArm:WaitForChild("LeftElbow"),
		LeftWrist = classic.bodyparts.LeftHand:WaitForChild("LeftWrist"),

		RightShoulder = classic.bodyparts.RightUpperArm:WaitForChild("RightShoulder"),
		RightElbow = classic.bodyparts.RightLowerArm:WaitForChild("RightElbow"),
		RightWrist = classic.bodyparts.RightHand:WaitForChild("RightWrist"),

		Neck = classic.bodyparts.Head:WaitForChild("Neck"),
	}

	classic.constraints = {
		Ankle = Instance.new("BallSocketConstraint"),
		Elbow = Instance.new("HingeConstraint"),
		Hip = Instance.new("BallSocketConstraint"),
		Knee = Instance.new("HingeConstraint"),
		Neck = Instance.new("BallSocketConstraint"),
		Shoulder = Instance.new("BallSocketConstraint"),
		Waist = Instance.new("BallSocketConstraint"),
		Wrist = Instance.new("BallSocketConstraint"),
	}

	classic.constraints.Ankle.LimitsEnabled = true
	classic.constraints.Ankle.TwistLimitsEnabled = true
	classic.constraints.Ankle.UpperAngle = 30
	classic.constraints.Ankle.TwistLowerAngle = -45
	classic.constraints.Ankle.TwistUpperAngle = 30

	classic.constraints.Elbow.LowerAngle = 0
	classic.constraints.Elbow.UpperAngle = 135
	classic.constraints.Elbow.LimitsEnabled = true

	classic.constraints.Hip.LimitsEnabled = true
	classic.constraints.Hip.TwistLimitsEnabled = true
	classic.constraints.Hip.UpperAngle = 50
	classic.constraints.Hip.TwistLowerAngle = 100
	classic.constraints.Hip.TwistUpperAngle = -45

	classic.constraints.Knee.LowerAngle = -140
	classic.constraints.Knee.UpperAngle = 0
	classic.constraints.Knee.LimitsEnabled = true

	classic.constraints.Neck.LimitsEnabled = true
	classic.constraints.Neck.TwistLimitsEnabled = true
	classic.constraints.Neck.MaxFrictionTorque = 4
	classic.constraints.Neck.UpperAngle = 60
	classic.constraints.Neck.TwistLowerAngle = -75
	classic.constraints.Neck.TwistUpperAngle = 60

	classic.constraints.Shoulder.LimitsEnabled = true
	classic.constraints.Shoulder.TwistLimitsEnabled = true
	classic.constraints.Shoulder.UpperAngle = 45
	classic.constraints.Shoulder.TwistLowerAngle = -90
	classic.constraints.Shoulder.TwistUpperAngle = 150

	classic.constraints.Waist.LimitsEnabled = true
	classic.constraints.Waist.TwistLimitsEnabled = true
	classic.constraints.Waist.UpperAngle = 30
	classic.constraints.Waist.TwistLowerAngle = -55
	classic.constraints.Waist.TwistUpperAngle = 25

	classic.constraints.Wrist.LimitsEnabled = true
	classic.constraints.Wrist.TwistLimitsEnabled = true
	classic.constraints.Wrist.UpperAngle = 30
	classic.constraints.Wrist.TwistLowerAngle = -45
	classic.constraints.Wrist.TwistUpperAngle = 45

	local function ragdollJoint(part0, part1, attachmentName)
		local constraintName
		for name, _ in pairs(classic.constraints) do
			if string.match(attachmentName, name) then
				constraintName = name
				break
			end
		end

		if not constraintName then
			return
		end

		local attName = attachmentName .. "RigAttachment"
		local a0 = part0:FindFirstChild(attName)
		local a1 = part1:FindFirstChild(attName)
		if not (a0 and a1) then
			return
		end

		local constraint = classic.constraints[constraintName]:Clone()
		constraint.Attachment0 = a0
		constraint.Attachment1 = a1
		constraint.Name = "Ragdoll_" .. part1.Name
		constraint.Parent = constraintfolder
	end

	ragdollJoint(classic.bodyparts.LowerTorso, classic.bodyparts.UpperTorso, "Waist")
	ragdollJoint(classic.bodyparts.UpperTorso, classic.bodyparts.Head, "Neck")

	ragdollJoint(classic.bodyparts.UpperTorso, classic.bodyparts.LeftUpperArm, "LeftShoulder")
	ragdollJoint(classic.bodyparts.UpperTorso, classic.bodyparts.RightUpperArm, "RightShoulder")

	ragdollJoint(classic.bodyparts.LeftUpperArm, classic.bodyparts.LeftLowerArm, "LeftElbow")
	ragdollJoint(classic.bodyparts.RightUpperArm, classic.bodyparts.RightLowerArm, "RightElbow")

	ragdollJoint(classic.bodyparts.LeftLowerArm, classic.bodyparts.LeftHand, "LeftWrist")
	ragdollJoint(classic.bodyparts.RightLowerArm, classic.bodyparts.RightHand, "RightWrist")

	ragdollJoint(classic.bodyparts.LowerTorso, classic.bodyparts.LeftUpperLeg, "LeftHip")
	ragdollJoint(classic.bodyparts.LowerTorso, classic.bodyparts.RightUpperLeg, "RightHip")

	ragdollJoint(classic.bodyparts.LeftUpperLeg, classic.bodyparts.LeftLowerLeg, "LeftKnee")
	ragdollJoint(classic.bodyparts.RightUpperLeg, classic.bodyparts.RightLowerLeg, "RightKnee")

	ragdollJoint(classic.bodyparts.LeftLowerLeg, classic.bodyparts.LeftFoot, "LeftAnkle")
	ragdollJoint(classic.bodyparts.RightLowerLeg, classic.bodyparts.RightFoot, "RightAnkle")

	local function toggleMotors(mode)
		for name, motor in pairs(classic.motors) do
			if name ~= "Root" then
				motor.Enabled = mode
			end
		end
	end

	classic.toggleMotors = toggleMotors
	classic.orgrootmotor = classic.motors.Root

	local altrootmotor = Instance.new("Motor6D")
	altrootmotor.Name = "AltRootMotor"
	altrootmotor.Part0 = classic.bodyparts.HumanoidRootPart
	altrootmotor.Part1 = classic.bodyparts.UpperTorso
	altrootmotor.C0 = CFrame.new(0, (classic.bodyparts.LowerTorso.Size.Y) * 0.7, 0)
	altrootmotor.Enabled = false
	altrootmotor.Parent = classic.bodyparts.UpperTorso
	classic.altrootmotor = altrootmotor

	classic.bodyparts.HumanoidRootPart.CanCollide = true
	classic.bodyparts.HumanoidRootPart.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)

	classic.bodyparts.Head.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)

	pcall(function()
		classic.bodyparts.Head.OriginalSize.Value = Vector3.new(1, 1, 1)
	end)

	local HeadCollision = Instance.new("Part")
	HeadCollision.Name = "HeadCollision"
	HeadCollision.Transparency = 1
	HeadCollision.Shape = Enum.PartType.Cylinder
	HeadCollision.CanCollide = false
	HeadCollision.Parent = classic.bodyparts.Head

	local headsize = classic.bodyparts.Head.Size
	HeadCollision.Size = Vector3.new(headsize.Y, headsize.Z, headsize.Z)

	classic.bodyparts.Head:GetPropertyChangedSignal("Size"):Connect(function()
		local hs = classic.bodyparts.Head.Size
		HeadCollision.Size = Vector3.new(hs.Y, hs.Z, hs.Z)
	end)

	local HeadCollisionWeld = Instance.new("Weld")
	HeadCollisionWeld.Part0 = classic.bodyparts.Head
	HeadCollisionWeld.Part1 = HeadCollision
	HeadCollisionWeld.C0 = HeadCollisionWeld.C0 * CFrame.fromOrientation(0, 0, math.rad(-90))
	HeadCollisionWeld.Parent = HeadCollision

	pcall(function()
		PhysicsService:SetPartCollisionGroup(classic.bodyparts.Head, "noclip")
	end)

	local HeadCollisionAttachment = Instance.new("Attachment")
	HeadCollisionAttachment.Orientation = Vector3.new(0, 0, -90)
	HeadCollisionAttachment.Parent = HeadCollision

	local HeadCollisionConstraint = Instance.new("HingeConstraint")
	HeadCollisionConstraint.Name = "HeadCollision"
	HeadCollisionConstraint.Attachment0 = classic.bodyparts.Head:FindFirstChild("FaceCenterAttachment")
	HeadCollisionConstraint.Attachment1 = HeadCollisionAttachment
	HeadCollisionConstraint.LimitsEnabled = true
	HeadCollisionConstraint.UpperAngle = 0
	HeadCollisionConstraint.LowerAngle = 0
	HeadCollisionConstraint.Parent = constraintfolder

	local function makeAccessoryJoints()
		for _, v in pairs(character:GetChildren()) do
			if v:IsA("Accessory") then
				local handle = v:FindFirstChild("Handle")
				if handle then
					handle.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
					local attachment1 = handle:FindFirstChildOfClass("Attachment")
					if attachment1 then
						local attachment0
						for _, obj in pairs(character:GetChildren()) do
							local att = obj:FindFirstChild(attachment1.Name)
							if att then
								attachment0 = att
								break
							end
						end
						if attachment0 then
							local con = Instance.new("HingeConstraint")
							con.Name = "Accessory_" .. v.Name
							con.Attachment0 = attachment0
							con.Attachment1 = attachment1
							con.LimitsEnabled = true
							con.UpperAngle = 0
							con.LowerAngle = 0
							con.Parent = constraintfolder
						end
					end
				end
			end
		end
	end

	makeAccessoryJoints()

	local collisionfiltertbl = {
		{
			HeadCollision,
			classic.bodyparts.LeftUpperArm,
			classic.bodyparts.LeftUpperLeg,
			classic.bodyparts.LowerTorso,
			classic.bodyparts.RightUpperArm,
			classic.bodyparts.RightUpperLeg,
			classic.bodyparts.UpperTorso,
		},
		{ classic.bodyparts.LeftFoot, classic.bodyparts.LowerTorso, classic.bodyparts.UpperTorso },
		{ classic.bodyparts.LeftLowerArm, classic.bodyparts.LowerTorso, classic.bodyparts.UpperTorso },
		{ classic.bodyparts.LeftLowerLeg, classic.bodyparts.LowerTorso, classic.bodyparts.UpperTorso },
		{
			classic.bodyparts.LeftUpperArm,
			classic.bodyparts.LeftUpperLeg,
			classic.bodyparts.LowerTorso,
			classic.bodyparts.RightUpperArm,
			classic.bodyparts.RightUpperLeg,
			classic.bodyparts.UpperTorso,
		},
		{ classic.bodyparts.LeftUpperLeg, classic.bodyparts.LowerTorso, classic.bodyparts.RightUpperLeg, classic.bodyparts.UpperTorso },
		{ classic.bodyparts.RightFoot, classic.bodyparts.LowerTorso, classic.bodyparts.UpperTorso },
		{ classic.bodyparts.RightHand, classic.bodyparts.UpperTorso },
		{ classic.bodyparts.RightLowerArm, classic.bodyparts.LowerTorso, classic.bodyparts.UpperTorso },
		{ classic.bodyparts.RightLowerLeg, classic.bodyparts.LowerTorso, classic.bodyparts.UpperTorso },
		{
			classic.bodyparts.RightUpperArm,
			classic.bodyparts.LeftUpperLeg,
			classic.bodyparts.LowerTorso,
			classic.bodyparts.LeftUpperArm,
			classic.bodyparts.RightUpperLeg,
			classic.bodyparts.UpperTorso,
		},
		{ classic.bodyparts.RightUpperLeg, classic.bodyparts.LowerTorso, classic.bodyparts.LeftUpperLeg, classic.bodyparts.UpperTorso },
	}

	for i = 1, #collisionfiltertbl do
		for b = 2, #collisionfiltertbl[i] do
			local constraint = Instance.new("NoCollisionConstraint")
			constraint.Name = collisionfiltertbl[i][1].Name .. "<->" .. collisionfiltertbl[i][b].Name
			constraint.Part0 = collisionfiltertbl[i][1]
			constraint.Part1 = collisionfiltertbl[i][b]
			constraint.Parent = collisionfolder
		end
	end
end

local function buildMorphFallback()
	morph.mesh = findMorphMesh(character)
	morph.hrp = character:WaitForChild("HumanoidRootPart")

	if not morph.mesh then
		warn("DrD morph ragdoll fallback: no MeshPart found")
		return
	end

	local rootMotor
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("Motor6D") and (obj.Part0 == morph.hrp or obj.Part1 == morph.mesh or obj.Part0 == morph.mesh) then
			rootMotor = obj
			break
		end
	end

	morph.rootMotor = rootMotor

	local att0 = Instance.new("Attachment")
	att0.Name = "MorphRagdoll_Att0"
	att0.CFrame = rootMotor and rootMotor.C0 or CFrame.new()
	att0.Parent = morph.hrp
	morph.att0 = att0

	local att1 = Instance.new("Attachment")
	att1.Name = "MorphRagdoll_Att1"
	att1.CFrame = rootMotor and rootMotor.C1 or CFrame.new()
	att1.Parent = morph.mesh
	morph.att1 = att1

	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "MorphRootSocket"
	socket.Attachment0 = att0
	socket.Attachment1 = att1
	socket.LimitsEnabled = false
	socket.Parent = constraintfolder
	morph.socket = socket

	morph.mesh.CanCollide = false
	morph.mesh.Massless = false
	morph.hrp.CanCollide = true
end

if rigMode == "ClassicR15" then
	buildClassicRig()
else
	buildMorphFallback()
end

local isragdollnow = false

local function ragdollClassic(mode, velocity)
	if mode == true then
		if isragdollnow then
			if velocity then
				functions_remoteragdollvelocity:InvokeClient(player, velocity)
			end
			return
		end

		isragdollnow = true
		variables_ragdoll.Value = true

		classic.altrootmotor.Enabled = true
		classic.orgrootmotor.Enabled = false
		classic.toggleMotors(false)

		functions_remoteragdoll:InvokeClient(player, true, velocity)

	elseif mode == "dead" then
		-- keep your old clone-on-death block here if you use it
	else
		if not isragdollnow then return end
		isragdollnow = false

		classic.orgrootmotor.Enabled = true
		classic.altrootmotor.Enabled = false
		classic.toggleMotors(true)

		functions_remoteragdoll:InvokeClient(player, false)
	end
end

local function ragdollMorph(mode, velocity)
	if mode == true then
		if isragdollnow then
			if velocity then
				functions_remoteragdollvelocity:InvokeClient(player, velocity)
			end
			return
		end

		isragdollnow = true
		variables_ragdoll.Value = true

		if morph.rootMotor then
			morph.rootMotor.Enabled = false
		end

		morph.socket.Enabled = true
		humanoid.AutoRotate = false
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)

		pcall(function()
			character.Animate.Disabled = true
		end)

		if velocity and morph.hrp then
			morph.hrp.AssemblyLinearVelocity = velocity
		end

		if morph.mesh then
			morph.mesh.CanCollide = false
		end

		functions_remoteragdoll:InvokeClient(player, true, velocity)

	elseif mode == "dead" then
		-- keep your old clone-on-death block here if you use it
	else
		if not isragdollnow then return end
		isragdollnow = false

		if morph.rootMotor then
			morph.rootMotor.Enabled = true
		end

		if morph.socket then
			morph.socket.Enabled = false
		end

		humanoid.AutoRotate = true
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

		pcall(function()
			character.Animate.Disabled = false
		end)

		for _, v in pairs(character:GetDescendants()) do
			if v:IsA("BasePart") then
				v.AssemblyLinearVelocity = Vector3.zero
				v.AssemblyAngularVelocity = Vector3.zero
			end
		end

		if morph.mesh then
			morph.mesh.CanCollide = false
		end

		functions_remoteragdoll:InvokeClient(player, false)
	end
end

local function ragdoll(mode, velocity)
	if rigMode == "ClassicR15" then
		ragdollClassic(mode, velocity)
	else
		ragdollMorph(mode, velocity)
	end
end

humanoid.Died:Connect(function()
	ragdoll(true)
	ragdoll("dead")
	print("YES")
end)

events_variableserver.OnServerEvent:Connect(function(plr, variable, mode)
	if variable == "reset" then
		humanoid.Health = 0
	else
		ragdoll(mode)
		ragdoll("dead")
	end
end)

function functions_ragdoll.OnInvoke(velocity)
	ragdoll(true, velocity)
end

function functions_remoteragdoll.OnServerInvoke(plr)
	ragdoll(true)
end
