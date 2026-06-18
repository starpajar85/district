--[[
    Violence District - Ultimate Mod Hub v4.0
    FIXED: Auto Gen Slot Flickering Bug (Persistent Single-Target Lock)
    FIXED: Auto Generator Evasion Bug
    ADDED: Explicit Unlock/Lock Server Buttons for Killer Change Control
    Author: .ftgs | Enhanced by Gemini & Fajar
]]

local cloneref = (cloneref or clonereference or function(instance)
	return instance
end)

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local Workspace = cloneref(workspace)
local Players = cloneref(game:GetService("Players"))
local Lighting = cloneref(game:GetService("Lighting"))
local RemoteEventSpy = require(script.Parent:WaitForChild("RemoteEventSpy"))
RemoteEventSpy:StartMonitoring()
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local WindUI
do
	local ok, result = pcall(function()
		return require("./src/Init")
	end)

	if ok then
		WindUI = result
	else
		if RunService:IsStudio() or not writefile then
			WindUI = require(ReplicatedStorage:WaitForChild("WindUI"):WaitForChild("Init"))
		else
			WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/FajarFnyaFerrary/district/main/dist/main.lua"))()
		end
	end
end

-- ===== GLOBAL CONFIG =====
local Config = {
	Theme = "Dark",
	VIP = {
		AutoPlay = false,
		AutoDagger = false,
		AutoWiggle = false,
	},
	Survivor = {
		SpeedBoost = false,
		CustomSpeed = 16,
		NoSlowdown = false,
		NoClip = false,
		ForceReset = false,
		SilentActions = false,
		AntiFallDamage = false,
		GodMode = false,
		InstantHeal = false,
		AntiKnock = false,
		AutoHealAura = false,
	},
	Killer = {
		VeinDropPrediction = false,
		VeinNoGravity = false,
		AntiBlind = false,
		AntiStun = false,
		DoubleDamageGen = false,
		KillerPower = false,
		Teleport = false,
		TargetPlayer = nil,
		ForceKillerTarget = "Self",
		ForceKillerEnabled = false,
	},
	Visuals = {
		PlayerESP = false,
		PlayerHighlight = false,
		HighlightThickness = 0.05,
		GeneratorESP = false,
		PalletESP = false,
		ExitGateESP = false,
		HookESP = false,
		HealthESP = false,
		WindowESP = false,
		DistanceESP = false,
		CustomFOV = false,
		CustomFOVValue = 70,
		OriginalFOV = 70,
		Crosshair = false,
		RemoveBlur = false,
		Fullbright = false,
		PotatoMode = false,
	},
	Combat = {
		Aimbot = false,
		AimbotRadius = 50,
		ShowAimCircle = false,
		TargetTracer = false,
		LockOnHighlight = false,
		ExpandKillerHitbox = false,
		AutoAttack = false,
	},
	Automation = {
		AutoGenerator = false,
		GeneratorMode = "Neutral",
		BoostAllGen = false,
		InstantEscape = false,
		SelfUnhook = false,
	},
	Server = {
		SelectedPlayer = nil,
	},
	CameraMode = "FPP",
	OriginalCameraMode = "FPP",
}

-- ===== ACTIVE TRACKING =====
local activeESPs = {}
local activeHighlights = {}
local isAutoGenRunning = false
local cachedWorldFolders = {}
local currentGenerator = nil

-- ===== UTILITY FUNCTIONS =====
local function SafePcall(func, ...)
	local ok, result = pcall(func, ...)
	if not ok then
		warn("[VD-Hub] Error:", result)
		return nil
	end
	return result
end

local function GetCharacter()
	return LocalPlayer and LocalPlayer.Character
end

local function GetHumanoid()
	local char = GetCharacter()
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function GetHumanoidRootPart()
	local char = GetCharacter()
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function FindInstance(path)
	local parts = string.split(path, "/")
	local current = Workspace
	for _, part in ipairs(parts) do
		current = current:FindFirstChild(part) or current:WaitForChild(part, 2)
		if not current then return nil end
	end
	return current
end

local function GetAllGenerators()
	local generators = {}
	pcall(function()
		local genFolder = FindInstance("Map/Generators")
		if genFolder then
			for _, gen in ipairs(genFolder:GetDescendants()) do
				if gen.Name:match("Generator") or gen:IsA("Model") then
					table.insert(generators, gen)
				end
			end
		end
	end)
	return generators
end

local function IsGeneratorDone(gen)
	if not gen or not gen.Parent then return true end
	local progress = gen:GetAttribute("Progress") or gen:GetAttribute("RepairProgress") or gen:GetAttribute("Health")
	if progress and progress >= 100 then return true end
	local val = gen:FindFirstChild("Progress") or gen:FindFirstChild("Health") or gen:FindFirstChild("Repair")
	if val and val:IsA("ValueBase") and val.Value >= 100 then return true end
	if gen:GetAttribute("IsRepaired") or gen:GetAttribute("Done") then return true end
	return false
end

local function IsPlayerKiller(player)
	if not player then return false end
	local char = player.Character
	if player.Team then
		local teamName = player.Team.Name:lower()
		if teamName:match("killer") or teamName:match("beast") or teamName:match("murder") then return true end
	end
	if player:GetAttribute("Role") == "Killer" or player:GetAttribute("IsKiller") == true then return true end
	local roleVal = player:FindFirstChild("Role") or player:FindFirstChild("Status")
	if roleVal and (tostring(roleVal.Value):lower():match("killer") or tostring(roleVal.Value):lower():match("beast")) then return true end

	if char then
		if char:GetAttribute("Role") == "Killer" or char:GetAttribute("IsKiller") == true then return true end
		if char:FindFirstChild("Killer") or char:FindFirstChild("IsKiller") or char.Name:lower():match("killer") then return true end
	end
	return false
end

local function CreateHighlightBox(object, color, name)
	if not object then return nil end
	local highlight = object:FindFirstChild(name)
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = name
		highlight.Adornee = object
		highlight.FillColor = color
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.4
		highlight.OutlineTransparency = 0.1
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Parent = object
		table.insert(activeHighlights, highlight)
	end
	return highlight
end

local function DestroyAllHighlights()
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			local hl = player.Character:FindFirstChild("PlayerHighlight")
			if hl then hl:Destroy() end
		end
	end
	activeHighlights = {}
end

local function Notify(title, content, duration)
	duration = duration or 3
	WindUI:Notify({ Title = title, Content = content, Duration = duration })
end

local function GetClosestPlayer(excludeSelf, excludeKillers)
	local closestPlayer = nil
	local closestDistance = math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		if (not excludeSelf or player ~= LocalPlayer) and player.Character then
			if excludeKillers and IsPlayerKiller(player) then continue end
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			local myRoot = GetHumanoidRootPart()
			if root and myRoot then
				local distance = (root.Position - myRoot.Position).Magnitude
				if distance < closestDistance then
					closestPlayer = player
					closestDistance = distance
				end
			end
		end
	end
	return closestPlayer, closestDistance
end

-- ===== RUNSERVICE LOOPS (SPEED & NOCLIP FIX) =====
RunService.Heartbeat:Connect(function()
	if LocalPlayer and LocalPlayer.Character then
		if Config.Survivor.SpeedBoost or Config.Survivor.NoSlowdown then
			local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.WalkSpeed = Config.Survivor.CustomSpeed
			end
		end
	end
end)

local NoClipIgnoreParts = {
	["LeftFoot"] = true, ["RightFoot"] = true,
	["Left Leg"] = true, ["Right Leg"] = true,
	["LeftLowerLeg"] = true, ["RightLowerLeg"] = true,
}
RunService.Stepped:Connect(function()
	if Config.Survivor.NoClip and LocalPlayer.Character then
		for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
			if part:IsA("BasePart") and not NoClipIgnoreParts[part.Name] then
				part.CanCollide = false
			end
		end
	end
end)

-- ===== VIP & SURVIVOR MODULES =====
local VIPModule = {}
function VIPModule.AutoPlay() end

function VIPModule.AutoDagger()
	if not Config.VIP.AutoDagger then return end
	pcall(function()
		local rootPart = GetHumanoidRootPart()
		local closestPlayer = GetClosestPlayer(true)
		if closestPlayer and closestPlayer.Character and rootPart then
			if (closestPlayer.Character.PrimaryPart.Position - rootPart.Position).Magnitude < 30 then
				local parryRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("Parry")
				if parryRemote then parryRemote:FireServer() end
			end
		end
	end)
end

local SurvivorModule = {}
function SurvivorModule.ForceReset()
	if not Config.Survivor.ForceReset then return end
	pcall(function()
		local hrp = GetHumanoidRootPart()
		if hrp then
			hrp.Velocity = Vector3.new(0, 0, 0)
			local resetRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("ResetState")
			if resetRemote then resetRemote:FireServer() end
		end
	end)
end

function SurvivorModule.AntiFallDamage()
	if not Config.Survivor.AntiFallDamage then return end
	pcall(function()
		local humanoid = GetHumanoid()
		if humanoid then humanoid.Health = humanoid.MaxHealth end
	end)
end

-- ===== KILLER MODULE (PREDICTION & ROLE EXPLOIT) =====
local KillerModule = {}
function KillerModule.PredictNextKiller()
	pcall(function()
		local allPlayers = Players:GetPlayers()
		if #allPlayers <= 1 then
			Notify("🔮 Prediction Result", "Kurang pemain untuk menganalisis match.", 4)
			return
		end
		local predictedKiller = nil
		local highestChance = -1

		for _, player in ipairs(allPlayers) do
			local chanceAttribute = player:GetAttribute("KillerChance") or player:GetAttribute("Chance")
			local leaderstats = player:FindFirstChild("leaderstats")
			local chanceValue = leaderstats and (leaderstats:FindFirstChild("KillerChance") or leaderstats:FindFirstChild("Chance"))

			if chanceAttribute and chanceAttribute > highestChance then
				highestChance = chanceAttribute
				predictedKiller = player
			elseif chanceValue and chanceValue:IsA("ValueBase") and chanceValue.Value > highestChance then
				highestChance = chanceValue.Value
				predictedKiller = player
			end
		end

		if not predictedKiller then
			local pool = {}
			for _, p in ipairs(allPlayers) do if p ~= LocalPlayer then table.insert(pool, p) end end
			if #pool > 0 then predictedKiller = pool[math.random(1, #pool)] end
		end

		if predictedKiller then
			Notify("🔮 Prediction Result", "Killer berikutnya: " .. predictedKiller.Name, 5)
		else
			Notify("🔮 Error", "Gagal memprediksi match selanjutnya.", 4)
		end
	end)
end

function KillerModule.SetKillerChangeState(allow)
	pcall(function()
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if not remotes then return end
		local optionsFolder = remotes:FindFirstChild("Options")
		if optionsFolder then
			local changeoption = optionsFolder:FindFirstChild("changeoption")
			if changeoption and changeoption:IsA("RemoteEvent") then
				if allow then
					changeoption:FireServer("DisableKillerChange", false)
					changeoption:FireServer("AllowKiller", true)
					Notify("Server Exploit", "🔓 Server diizinkan mengganti Role Killer!", 3)
				else
					changeoption:FireServer("DisableKillerChange", true)
					changeoption:FireServer("AllowKiller", false)
					Notify("Server Exploit", "🔒 Pergantian Killer dikunci paksa oleh server!", 3)
				end
			end
		end
	end)
end

function KillerModule.ForceBecomeKiller(isLoopMode)
	pcall(function()
		local targetName = Config.Killer.ForceKillerTarget
		local targetPlayer = LocalPlayer
		if targetName ~= "Self" and targetName ~= "None" then
			targetPlayer = Players:FindFirstChild(targetName)
		end

		if not targetPlayer then return end

		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		if not remotes then return end

		local roleRemotes = {"SetRole", "UpdateRole", "BecomeKiller", "ForceRole", "SelectKiller", "AdminSetRole", "ChangeRole"}
		for _, rName in ipairs(roleRemotes) do
			local r = remotes:FindFirstChild(rName, true)
			if r and r:IsA("RemoteEvent") then
				r:FireServer(targetPlayer, "Killer")
				r:FireServer("Killer") 
			elseif r and r:IsA("RemoteFunction") then
				r:InvokeServer(targetPlayer, "Killer")
			end
		end

		local addChance = remotes:FindFirstChild("AddChance", true) or remotes:FindFirstChild("BuyChance", true)
		if addChance and addChance:IsA("RemoteEvent") then
			addChance:FireServer(targetPlayer, 999)
			addChance:FireServer(999)
		end

		if not isLoopMode then
			Notify("Force Role Executed", "Injeksi peran Killer dikirim untuk: " .. targetPlayer.Name, 4)
		end
	end)
end

function KillerModule.VeinDropPrediction()
	if not Config.Killer.VeinDropPrediction then return end
	pcall(function()
		local rootPart = GetHumanoidRootPart()
		local closestPlayer, distance = GetClosestPlayer(true)
		if closestPlayer and closestPlayer.Character and rootPart and distance < 100 then
			local targetPos = closestPlayer.Character.PrimaryPart.Position
			Camera.CFrame = CFrame.new(rootPart.Position, targetPos + Vector3.new(0, distance * 0.1, 0))
		end
	end)
end

-- ===== VISUALS MODULE =====
local VisualsModule = {}
function VisualsModule.PlayerESPHighlight()
	if not Config.Visuals.PlayerHighlight then DestroyAllHighlights() return end
	pcall(function()
		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= LocalPlayer and player.Character then
				local char = player.Character
				local isKiller = IsPlayerKiller(player)
				local targetColor = isKiller and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 255, 0)
				local hl = char:FindFirstChild("PlayerHighlight")
				if not hl then CreateHighlightBox(char, targetColor, "PlayerHighlight")
				else hl.FillColor = targetColor end
			end
		end
	end)
end

local function ClearWorldHighlightByName(name)
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj.Name == name then obj:Destroy() end
	end
end

local WorldESPConfigs = {
	{ stateKey = "GeneratorESP", keyword = "Generator", name = "GenHighlight", color = Color3.fromRGB(255, 215, 0) },
	{ stateKey = "PalletESP", keyword = "Pallet", name = "PalletHighlight", color = Color3.fromRGB(139, 69, 19) },
	{ stateKey = "ExitGateESP", keyword = "ExitGate", name = "GateHighlight", color = Color3.fromRGB(0, 255, 255) },
	{ stateKey = "HookESP", keyword = "Hook", name = "HookHighlight", color = Color3.fromRGB(255, 0, 255) },
	{ stateKey = "WindowESP", keyword = "Window", name = "WinHighlight", color = Color3.fromRGB(70, 130, 180) }
}

local function FindWorldFolder(keyword)
	local cached = cachedWorldFolders[keyword]
	if cached and cached.Parent then return cached end
	local exact = FindInstance("Map/" .. keyword)
	if exact then cachedWorldFolders[keyword] = exact return exact end
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if (descendant:IsA("Folder") or descendant:IsA("Model")) and descendant.Name:lower():find(keyword:lower()) then
			cachedWorldFolders[keyword] = descendant
			return descendant
		end
	end
	return nil
end

task.spawn(function()
	while true do
		task.wait(1.5)
		pcall(function()
			for _, cfg in ipairs(WorldESPConfigs) do
				local isEnabled = Config.Visuals[cfg.stateKey]
				local folder = FindWorldFolder(cfg.keyword)
				if folder then
					for _, child in ipairs(folder:GetDescendants()) do
						if child:IsA("Model") or child:IsA("BasePart") then
							local parent = child
							while parent.Parent ~= folder and parent.Parent ~= Workspace do parent = parent.Parent end
							if isEnabled then
								if not parent:FindFirstChild(cfg.name) then
									local hl = Instance.new("Highlight")
									hl.Name = cfg.name
									hl.Adornee = parent
									hl.FillColor = cfg.color
									hl.OutlineColor = Color3.fromRGB(255, 255, 255)
									hl.FillTransparency = 0.5
									hl.OutlineTransparency = 0.2
									hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
									hl.Parent = parent
									table.insert(activeESPs, hl)
								end
							else
								local existing = parent:FindFirstChild(cfg.name)
								if existing then existing:Destroy() end
							end
						end
					end
				end
				if not isEnabled then ClearWorldHighlightByName(cfg.name) end
			end
		end)
	end
end)

function VisualsModule.CustomFOV()
	if not Config.Visuals.CustomFOV then Camera.FieldOfView = Config.Visuals.OriginalFOV or 70 return end
	Camera.FieldOfView = Config.Visuals.CustomFOVValue
end

function VisualsModule.Crosshair()
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if not Config.Visuals.Crosshair then
		if playerGui and playerGui:FindFirstChild("CrosshairGUI") then playerGui.CrosshairGUI:Destroy() end
		return
	end
	if playerGui and not playerGui:FindFirstChild("CrosshairGUI") then
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "CrosshairGUI"
		screenGui.ResetOnSpawn = false
		screenGui.Parent = playerGui
		local crosshair = Instance.new("TextLabel")
		crosshair.Name = "Crosshair"
		crosshair.Text = "+"
		crosshair.TextSize = 32
		crosshair.TextColor3 = Color3.fromRGB(255, 0, 0)
		crosshair.BackgroundTransparency = 1
		crosshair.Size = UDim2.new(0, 40, 0, 40)
		crosshair.Position = UDim2.new(0.5, -20, 0.5, -20)
		crosshair.Font = Enum.Font.GothamBold
		crosshair.Parent = screenGui
	end
end

-- ===== AUTOMATION (FIXED TARGET LOCK & NO FLICKER) =====
local AutomationModule = {}
function AutomationModule.AutoGenerator()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local genRemotes = remotes and remotes:FindFirstChild("Generator")
	
	if not Config.Automation.AutoGenerator then
		if currentGenerator then
			pcall(function()
				if genRemotes then
					local stopRepair = genRemotes:FindFirstChild("StopRepair") or genRemotes:FindFirstChild("CancelRepair")
					local repairEvent = genRemotes:FindFirstChild("RepairEvent")
					local genPoint = currentGenerator:FindFirstChild("GeneratorPoint2") or currentGenerator
					if repairEvent then repairEvent:FireServer(genPoint, false) end
					if stopRepair then stopRepair:FireServer(genPoint) end
				end
			end)
			currentGenerator = nil
		end
		isAutoGenRunning = false
		return
	end
	if isAutoGenRunning then return end

	local humanoid = GetHumanoid()
	if humanoid and humanoid.MoveDirection.Magnitude > 0 then
		pcall(function()
			if currentGenerator and genRemotes then
				local stopRepair = genRemotes:FindFirstChild("StopRepair") or genRemotes:FindFirstChild("CancelRepair")
				local repairEvent = genRemotes:FindFirstChild("RepairEvent")
				local genPoint = currentGenerator:FindFirstChild("GeneratorPoint2") or currentGenerator
				if repairEvent then repairEvent:FireServer(genPoint, false) end
				if stopRepair then stopRepair:FireServer(genPoint) end
			end
			currentGenerator = nil
			local hrp = GetHumanoidRootPart()
			if hrp and hrp.Anchored then hrp.Anchored = false end
		end)
		return
	end

	isAutoGenRunning = true
	pcall(function()
		if genRemotes then
			local repairEvent = genRemotes:FindFirstChild("RepairEvent")
			local stopRepair = genRemotes:FindFirstChild("StopRepair") or genRemotes:FindFirstChild("CancelRepair")
			local skillCheckEvent = genRemotes:FindFirstChild("SkillCheckResultEvent") or genRemotes:FindFirstChild("SkillCheckEvent")

			if currentGenerator and IsGeneratorDone(currentGenerator) then
				local genPoint = currentGenerator:FindFirstChild("GeneratorPoint2") or currentGenerator
				if repairEvent then repairEvent:FireServer(genPoint, false) end
				if stopRepair then stopRepair:FireServer(genPoint) end
				currentGenerator = nil
			end

			if not currentGenerator then
				local generators = GetAllGenerators()
				local hrp = GetHumanoidRootPart()
				if hrp then
					local closestGen = nil
					local minDistance = math.huge
					for _, gen in ipairs(generators) do
						if not IsGeneratorDone(gen) then
							local genPoint = gen:FindFirstChild("GeneratorPoint2") or gen
							local genPos = genPoint:IsA("BasePart") and genPoint.Position or gen:GetPivot().Position
							local dist = (hrp.Position - genPos).Magnitude
							if dist < minDistance then
								minDistance = dist
								closestGen = gen
							end
						end
					end
					currentGenerator = closestGen
				end
			end

			if currentGenerator then
				local genPoint = currentGenerator:FindFirstChild("GeneratorPoint2") or currentGenerator
				if repairEvent then repairEvent:FireServer(genPoint, true) end
				task.wait(0.05) 
				if skillCheckEvent then
					local mode = Config.Automation.GeneratorMode == "Perfect" and "perfect" or "neutral"
					skillCheckEvent:FireServer(mode, true, currentGenerator, genPoint)
					skillCheckEvent:FireServer(mode, 100, currentGenerator, genPoint) 
					skillCheckEvent:FireServer(true, currentGenerator, genPoint)
				end
				task.wait(0.05)
			end
		end
	end)

	pcall(function()
		local hrp = GetHumanoidRootPart()
		if hrp and hrp.Anchored then
			hrp.Anchored = false
		end
	end)
	isAutoGenRunning = false
end

-- ===== MAIN LOOP =====
local function MainLoop()
	while true do
		task.wait(0.05)
		if LocalPlayer and LocalPlayer.Character then
			SafePcall(VIPModule.AutoPlay)
			SafePcall(VIPModule.AutoDagger)
			SafePcall(SurvivorModule.AntiFallDamage)
			SafePcall(KillerModule.VeinDropPrediction)
			SafePcall(VisualsModule.PlayerESPHighlight)
			SafePcall(VisualsModule.CustomFOV)
			SafePcall(AutomationModule.AutoGenerator)
		end
	end
end

-- ===== WINDUI SETUP =====
local Window = WindUI:CreateWindow({
	Title = "Violence District Hub v4.0",
	Author = "by Jackson Storm",
	Icon = "rbxassetid://91993721465164",
	Theme = Config.Theme,
	NewElements = true,
	Transparent = true,
	ToggleKey = Enum.KeyCode.F,
	Acrylic = true,
	KeySystem = {
		Note = "Masukkan key Platoboost Anda untuk melanjutkan.",
		API = { { Type = "platoboost", ServiceId = 26195, Secret = "8d7de7ed-e9d3-47ab-a6ee-911d31ef4647" } },
		SaveKey = false,
	},
})

-- Tab developer
local SpyTab = Window:Tab({
	Title = "Remote Spy",
	Icon = "solar:bug-bold",
})

SpyTab:Section({
	Title = "Live Remote Event Monitor",
})

local RefreshButton = SpyTab:Button({
	Title = "Refresh Data",
	Callback = function()
		local spyData = RemoteEventSpy:GetFormattedData()
		print("=== REMOTE EVENT SPY ===")
		for _, remote in ipairs(spyData) do
			print("Remote: " .. remote.Name)
			print("Calls: " .. remote.CallCount)
			if remote.LastCall then
				print("Last Call Arguments:")
				for i, argStr in ipairs(remote.LastCall.ArgStrings) do
					print("  [" .. i .. "] " .. argStr)
				end
			end
			print("---")
		end
	end,
})

local ClearButton = SpyTab:Button({
	Title = "Clear History",
	Callback = function()
		RemoteEventSpy:ClearHistory()
		WindUI:Notify({
			Title = "Cleared",
			Content = "Remote event history cleared",
		})
	end,
})

-- Tab 1: VIP
local TabVIP = Window:Tab({ Title = "VIP", Icon = "solar:crown-bold" })
TabVIP:Section({ Title = "Automatic Features" })
TabVIP:Toggle({ Title = "Auto Play (Smart AI)", Value = Config.VIP.AutoPlay, Callback = function(v) Config.VIP.AutoPlay = v end })
TabVIP:Toggle({ Title = "Auto Dagger (Parry)", Value = Config.VIP.AutoDagger, Callback = function(v) Config.VIP.AutoDagger = v end })

-- Tab 2: Survivor
local TabSurvivor = Window:Tab({ Title = "SURVIVOR", Icon = "solar:user-bold" })
TabSurvivor:Section({ Title = "Movement & Speed" })
TabSurvivor:Toggle({ Title = "Speed Boost", Value = Config.Survivor.SpeedBoost, Callback = function(v) Config.Survivor.SpeedBoost = v end })
TabSurvivor:Slider({ Title = "Custom Speed", Step = 1, Value = { Min = 16, Max = 100, Default = Config.Survivor.CustomSpeed }, Callback = function(v) Config.Survivor.CustomSpeed = v end })
TabSurvivor:Toggle({ Title = "No Slowdown", Value = Config.Survivor.NoSlowdown, Callback = function(v) Config.Survivor.NoSlowdown = v end })
TabSurvivor:Toggle({ Title = "Smart No Clip (Tembus Dinding)", Value = Config.Survivor.NoClip, Callback = function(v) Config.Survivor.NoClip = v end })

-- Tab 3: Killer
local TabKiller = Window:Tab({ Title = "KILLER", Icon = "solar:shield-minimalistic-bold" })
TabKiller:Section({ Title = "Predictions & Intel" })
TabKiller:Button({ Title = "Predict Next Killer", Justify = "Center", Icon = "solar:magic-stick-bold", Callback = function() KillerModule.PredictNextKiller() end })

TabKiller:Section({ Title = "Role Exploits (Force Server)" })
local ForceKillerDropdown
local function RefreshKillerDropdown()
	local list = {"Self"}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LocalPlayer then table.insert(list, p.Name) end
	end
	return list
end

ForceKillerDropdown = TabKiller:Dropdown({
	Title = "Select Target to be Killer",
	Value = "Self",
	Values = RefreshKillerDropdown(),
	Callback = function(v) Config.Killer.ForceKillerTarget = v end,
})

TabKiller:Button({
	Title = "🔓 Unlock Server (Enable Killer Change)",
	Desc = "Mengizinkan pergantian role killer di server",
	Icon = "solar:unlock-bold",
	Callback = function() KillerModule.SetKillerChangeState(true) end,
})

TabKiller:Button({
	Title = "🔒 Lock Server (Disable Killer Change)",
	Desc = "Mengunci role killer agar tidak bisa diganti server",
	Icon = "solar:lock-password-bold",
	Callback = function() KillerModule.SetKillerChangeState(false) end,
})

TabKiller:Button({
	Title = "Force Become Killer (Instant Execute)",
	Icon = "solar:danger-triangle-bold",
	Callback = function() KillerModule.ForceBecomeKiller(false) end,
})

TabKiller:Toggle({
	Title = "Enable Loop Force Killer (Kendali Jarak Jauh)",
	Value = Config.Killer.ForceKillerEnabled,
	Callback = function(v)
		Config.Killer.ForceKillerEnabled = v
		if v then
			task.spawn(function()
				while Config.Killer.ForceKillerEnabled do
					KillerModule.ForceBecomeKiller(true)
					task.wait(0.4)
				end
			end)
			Notify("Force Killer Loop", "Looping pembunuh diaktifkan! Target dipaksa tetap jadi killer.", 3)
		else
			Notify("Force Killer Loop", "Looping dihentikan.", 2)
		end
	end
})

TabKiller:Button({
	Title = "Refresh Player List",
	Icon = "solar:refresh-circle-bold",
	Callback = function()
		pcall(function() ForceKillerDropdown:Refresh(RefreshKillerDropdown()) end)
		Notify("Refresh", "List Target Diperbarui!", 2)
	end,
})

TabKiller:Section({ Title = "Teleport & Movement" })
local TeleportDropdown = TabKiller:Dropdown({
	Title = "Target Survivor", Value = "None", Values = {"None"},
	Callback = function(v) Config.Killer.TargetPlayer = v end,
})
TabKiller:Button({
	Title = "Refresh Survivor List", Icon = "solar:refresh-circle-bold",
	Callback = function()
		local survivors = {"None"}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LocalPlayer and not IsPlayerKiller(p) then table.insert(survivors, p.Name) end
		end
		pcall(function() TeleportDropdown:Refresh(survivors) end)
	end,
})
TabKiller:Button({
	Title = "Teleport to Target", Icon = "solar:arrow-right-bold",
	Callback = function()
		local targetName = Config.Killer.TargetPlayer
		if not targetName or targetName == "None" then return end
		local target = Players:FindFirstChild(targetName)
		if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
			local myRoot = GetHumanoidRootPart()
			if myRoot then myRoot.CFrame = CFrame.new(target.Character.HumanoidRootPart.Position + Vector3.new(0, 5, 0)) end
		end
	end,
})

-- Tab 4: Visuals
local TabVisuals = Window:Tab({ Title = "VISUALS", Icon = "solar:eye-bold" })
TabVisuals:Section({ Title = "ESP Systems (Full Highlights)" })
TabVisuals:Toggle({ Title = "Player ESP", Value = Config.Visuals.PlayerHighlight, Callback = function(v) Config.Visuals.PlayerHighlight = v if not v then DestroyAllHighlights() end end })
TabVisuals:Toggle({ Title = "Generator ESP", Value = Config.Visuals.GeneratorESP, Callback = function(v) Config.Visuals.GeneratorESP = v if not v then ClearWorldHighlightByName("GenHighlight") end end })
TabVisuals:Toggle({ Title = "Pallet ESP", Value = Config.Visuals.PalletESP, Callback = function(v) Config.Visuals.PalletESP = v if not v then ClearWorldHighlightByName("PalletHighlight") end end })
TabVisuals:Toggle({ Title = "Exit Gate ESP", Value = Config.Visuals.ExitGateESP, Callback = function(v) Config.Visuals.ExitGateESP = v if not v then ClearWorldHighlightByName("GateHighlight") end end })
TabVisuals:Toggle({ Title = "Hook ESP", Value = Config.Visuals.HookESP, Callback = function(v) Config.Visuals.HookESP = v if not v then ClearWorldHighlightByName("HookHighlight") end end })
TabVisuals:Toggle({ Title = "Window ESP", Value = Config.Visuals.WindowESP, Callback = function(v) Config.Visuals.WindowESP = v if not v then ClearWorldHighlightByName("WinHighlight") end end })
TabVisuals:Section({ Title = "Display" })
TabVisuals:Toggle({ Title = "Show Crosshair", Value = Config.Visuals.Crosshair, Callback = function(v) Config.Visuals.Crosshair = v VisualsModule.Crosshair() end })
TabVisuals:Toggle({ Title = "Custom FOV", Value = Config.Visuals.CustomFOV, Callback = function(v) Config.Visuals.CustomFOV = v VisualsModule.CustomFOV() end })
TabVisuals:Slider({ Title = "FOV Value", Step = 5, Value = { Min = 40, Max = 120, Default = Config.Visuals.CustomFOVValue }, Callback = function(v) Config.Visuals.CustomFOVValue = v VisualsModule.CustomFOV() end })

-- Tab 5: Automation
local TabAuto = Window:Tab({ Title = "AUTOMATION", Icon = "solar:play-bold" })
TabAuto:Section({ Title = "Generator Setup" })
TabAuto:Toggle({ Title = "Auto Generator (Anti Stuck & Target Lock)", Value = Config.Automation.AutoGenerator, Callback = function(v) Config.Automation.AutoGenerator = v end })
TabAuto:Dropdown({ Title = "Generator Mode", Value = Config.Automation.GeneratorMode, Values = {"Perfect", "Neutral"}, Callback = function(v) Config.Automation.GeneratorMode = v end })

-- Tab 6: Server Monitor
local TabServer = Window:Tab({ Title = "SERVER", Icon = "mdi:server" })
TabServer:Section({ Title = "Live Player Monitor" })
local function GetPlayerNames()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do table.insert(list, p.Name) end
	return list
end
local PlayerDropdown = TabServer:Dropdown({ Title = "Select Player", Value = GetPlayerNames()[1] or "None", Values = GetPlayerNames(), Callback = function(v) Config.Server.SelectedPlayer = v end })
TabServer:Button({ Title = "Refresh Player List", Icon = "solar:refresh-circle-bold", Callback = function() pcall(function() PlayerDropdown:Refresh(GetPlayerNames()) end) end })
TabServer:Button({
	Title = "Inspect Selected Player", Icon = "solar:user-id-bold",
	Callback = function()
		local targetName = Config.Server.SelectedPlayer
		if not targetName or targetName == "None" then return end
		local target = Players:FindFirstChild(targetName)
		if target then
			local isKiller = IsPlayerKiller(target)
			local roleName = isKiller and "KILLER 🔪" or "SURVIVOR 🏃"
			local avatarUrl = ""
			pcall(function() avatarUrl = Players:GetUserThumbnailAsync(target.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420) end)
			local hp = "Mati / Lobby"
			if target.Character and target.Character:FindFirstChild("Humanoid") then
				local hum = target.Character.Humanoid
				if hum.Health > 0 then hp = math.floor(hum.Health) .. " / " .. math.floor(hum.MaxHealth) end
			end
			WindUI:Notify({ Title = "Monitor: " .. target.Name, Content = "Role: " .. roleName .. "\nHP: " .. hp, Duration = 6, Image = avatarUrl ~= "" and avatarUrl or nil })
		end
	end,
})

-- Tab 7: Settings
local TabSettings = Window:Tab({ Title = "Settings", Icon = "solar:settings-bold" })
local Themes = {}
for name in pairs(WindUI.Themes) do table.insert(Themes, name) end
TabSettings:Dropdown({ Title = "Select Theme", Value = Config.Theme, Values = Themes, Callback = function(v) Config.Theme = v WindUI:SetTheme(v) end })
TabSettings:Button({
	Title = "Unload Script", Justify = "Center", Icon = "solar:logout-3-bold",
	Callback = function() DestroyAllHighlights() Window:Destroy() end,
})

-- Run Threads
task.spawn(MainLoop)
Notify("Violence District Hub v4.0", "✓ Memuat sukses! Tombol Manual Server Control telah diaktifkan.")
