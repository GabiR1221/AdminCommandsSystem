-- Place this Script in ServerScriptService.
-- See SHOP_SETUP.md for the required Explorer layout and attributes.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local CONFIG = {
	CurrencyName = "Coins",
	CurrencyFolderName = "CurrencyData", -- Not named leaderstats, so Roblox does not show it on the leaderboard.
	StartingCurrency = 0,
	SaveCurrency = false, -- Enable only after publishing and enabling Studio API access.
	DataStoreName = "ToolShopCurrency_v1",
	ShopFolderName = "ToolShopButtons",
	PickupFolderName = "CurrencyPickups",
	ToolFolderName = "ShopTools",
	DefaultPrice = 10,
	DefaultReward = 1,
	DefaultRespawnSeconds = 30,
	RejectDuplicateTools = true,
	InteractionTolerance = 3,
}

local store = CONFIG.SaveCurrency and DataStoreService:GetDataStore(CONFIG.DataStoreName) or nil
local pickupBusy = {}
local purchaseBusy = {}
local boundShopParts = {}
local boundPickupParts = {}

local function getCurrency(player)
	local currencyFolder = player:FindFirstChild(CONFIG.CurrencyFolderName)
	return currencyFolder and currencyFolder:FindFirstChild(CONFIG.CurrencyName)
end

local function characterNearPart(player, part, maxDistance)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and (root.Position - part.Position).Magnitude <= maxDistance
end

local function ownsTool(player, toolName)
	local backpack = player:FindFirstChildOfClass("Backpack")
	return (backpack and backpack:FindFirstChild(toolName) ~= nil)
		or (player.Character and player.Character:FindFirstChild(toolName) ~= nil)
end

local function bindShopPart(part)
	if not part:IsA("BasePart") then return end
	if boundShopParts[part] then return end
	local detector = part:FindFirstChildOfClass("ClickDetector")
	if not detector then
		warn("ToolShop: " .. part:GetFullName() .. " needs a ClickDetector")
		return
	end
	boundShopParts[part] = true

	detector.MouseClick:Connect(function(player)
		if purchaseBusy[player] then return end
		purchaseBusy[player] = true

		local maxDistance = math.max(0, detector.MaxActivationDistance) + CONFIG.InteractionTolerance
		local toolName = part:GetAttribute("ToolName")
		local price = math.max(0, math.floor(tonumber(part:GetAttribute("Price")) or CONFIG.DefaultPrice))
		local toolsFolder = ServerStorage:FindFirstChild(CONFIG.ToolFolderName)
		local template = type(toolName) == "string" and toolsFolder and toolsFolder:FindFirstChild(toolName)
		local currency = getCurrency(player)
		local backpack = player:FindFirstChildOfClass("Backpack")

		if characterNearPart(player, part, maxDistance)
			and template and template:IsA("Tool") and currency and backpack
			and currency.Value >= price
			and (not CONFIG.RejectDuplicateTools or not ownsTool(player, toolName)) then
			-- Charge and grant together on the server; clients never choose prices or tools.
			currency.Value -= price
			local tool = template:Clone()
			tool.Parent = backpack
		end

		purchaseBusy[player] = nil
	end)
end

local function bindPickup(part)
	if not part:IsA("BasePart") then return end
	if boundPickupParts[part] then return end
	boundPickupParts[part] = true
	local originalTransparency = part.Transparency
	local originalCanCollide = part.CanCollide
	local originalCanTouch = part.CanTouch

	part.Touched:Connect(function(hit)
		if pickupBusy[part] then return end
		local character = hit and hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local currency = player and getCurrency(player)
		if not player or not humanoid or humanoid.Health <= 0 or not currency then return end

		pickupBusy[part] = true
		local reward = math.max(0, math.floor(tonumber(part:GetAttribute("Reward")) or CONFIG.DefaultReward))
		local respawnTime = math.max(0.1, tonumber(part:GetAttribute("RespawnTime")) or CONFIG.DefaultRespawnSeconds)
		currency.Value += reward
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false

		task.delay(respawnTime, function()
			if part.Parent then
				part.Transparency = originalTransparency
				part.CanCollide = originalCanCollide
				part.CanTouch = originalCanTouch
			end
			pickupBusy[part] = nil
		end)
	end)
end

local function onPlayerAdded(player)
	local initialValue = CONFIG.StartingCurrency
	if store then
		local success, saved = pcall(store.GetAsync, store, tostring(player.UserId))
		if success and type(saved) == "number" then
			initialValue = math.max(0, math.floor(saved))
		elseif not success then
			warn("ToolShop: could not load currency for " .. player.Name)
		end
	end
	if player.Parent ~= Players then return end

	local currencyFolder = player:FindFirstChild(CONFIG.CurrencyFolderName)
	if not currencyFolder then
		currencyFolder = Instance.new("Folder")
		currencyFolder.Name = CONFIG.CurrencyFolderName
		currencyFolder.Parent = player
	end
	local currency = currencyFolder:FindFirstChild(CONFIG.CurrencyName)
	if not currency then
		currency = Instance.new("IntValue")
		currency.Name = CONFIG.CurrencyName
		currency.Value = initialValue
		currency.Parent = currencyFolder
	end
end

local function savePlayer(player)
	if not store then return end
	local currency = getCurrency(player)
	if not currency then return end
	local success = pcall(store.UpdateAsync, store, tostring(player.UserId), function()
		return math.max(0, math.floor(currency.Value))
	end)
	if not success then warn("ToolShop: could not save currency for " .. player.Name) end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	savePlayer(player)
	purchaseBusy[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, player) end

local shopFolder = Workspace:WaitForChild(CONFIG.ShopFolderName)
local pickupFolder = Workspace:WaitForChild(CONFIG.PickupFolderName)
for _, descendant in ipairs(shopFolder:GetDescendants()) do bindShopPart(descendant) end
for _, descendant in ipairs(pickupFolder:GetDescendants()) do bindPickup(descendant) end
shopFolder.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ClickDetector") and descendant.Parent then
		bindShopPart(descendant.Parent)
	else
		bindShopPart(descendant)
	end
end)
pickupFolder.DescendantAdded:Connect(bindPickup)

game:BindToClose(function()
	if not store then return end
	for _, player in ipairs(Players:GetPlayers()) do task.spawn(savePlayer, player) end
	task.wait(2)
end)
