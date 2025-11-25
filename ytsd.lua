-- Robust Roblox Client-Side UI Layout Manager (Improved, Defensive)
-- Now includes SeasonPassUI deep scanning and forced scroll-frame attaching.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- CONFIG
local UI_NAMES = { "Gear_Shop", "Seed_Shop", "SeasonPassUI", "PetShop_UI" }
local UI_PADDING = 20
local SCROLL_SPEED = 0.6     
local UI_SCALE = 0.75
local SCROLL_PAUSE_TIME = 1.2

local function debug(...)
	-- print("[UI AutoScroll]", ...)
end

-- --------------- FIND & ARRANGE UIs ----------------
local foundUIs = {}

local function tryAddUI(ui)
	for _, name in ipairs(UI_NAMES) do
		if ui.Name == name then
			if not table.find(foundUIs, ui) then
				table.insert(foundUIs, ui)
				ui.Enabled = true
				if ui:IsA("ScreenGui") then
					ui.ResetOnSpawn = false
					ui.IgnoreGuiInset = false
				end
				debug("Added UI:", ui.Name)
			end
		end
	end
end

for _, name in ipairs(UI_NAMES) do
	local ui = playerGui:FindFirstChild(name)
	if ui then tryAddUI(ui) end
end

playerGui.ChildAdded:Connect(function(child)
	tryAddUI(child)
end)

local cornerPositions = {
	{anchor = Vector2.new(0, 0), position = UDim2.new(0, UI_PADDING, 0, UI_PADDING)},
	{anchor = Vector2.new(1, 0), position = UDim2.new(1, -UI_PADDING, 0, UI_PADDING)},
	{anchor = Vector2.new(0, 1), position = UDim2.new(0, UI_PADDING, 1, -UI_PADDING)},
	{anchor = Vector2.new(1, 1), position = UDim2.new(1, -UI_PADDING, 1, -UI_PADDING)},
}

local function arrangeUIs()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local viewport = cam.ViewportSize
	local uiWidth = math.floor(viewport.X * 0.35)
	local uiHeight = math.floor(viewport.Y * 0.45)

	for idx, ui in ipairs(foundUIs) do
		local corner = cornerPositions[((idx - 1) % #cornerPositions) + 1]
		for _, child in ipairs(ui:GetChildren()) do
			if child:IsA("Frame") or child:IsA("ImageLabel") or child:IsA("ScrollingFrame") then
				child.Visible = true
				child.AnchorPoint = corner.anchor
				child.Position = corner.position
				child.Size = UDim2.new(0, uiWidth, 0, uiHeight)
				local sc = child:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", child)
				sc.Scale = UI_SCALE
			end
		end
	end
end

arrangeUIs()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(arrangeUIs)

-- --------------- SCROLL FRAME MANAGEMENT ----------------
local managedFrames = {}

local function addFrame(sf)
	for _, entry in ipairs(managedFrames) do
		if entry.frame == sf then return end
	end

	local layout = sf:FindFirstChildOfClass("UIListLayout") or sf:FindFirstChildOfClass("UIPageLayout")
	table.insert(managedFrames, {frame = sf, listLayout = layout})

	sf.ScrollingEnabled = true
	sf.ScrollBarThickness = 8

	debug("Added ScrollingFrame:", sf:GetFullName())
end

-- FORCE DETECT ALL SCROLLING FRAMES (SeasonPassUI fix)
local function rescanAll()
	for _, ui in ipairs(foundUIs) do
		for _, desc in ipairs(ui:GetDescendants()) do
			if desc:IsA("ScrollingFrame") then
				addFrame(desc)
			end
		end
	end
end

-- initial scan
rescanAll()

-- rescan every second (SeasonPassUI nested fix)
task.spawn(function()
	while true do
		rescanAll()
		task.wait(1)
	end
end)

-- --------------- MAX SCROLL LOGIC ----------------
local function getContentHeight(entry)
	local f = entry.frame
	if not f then return 0 end

	if entry.listLayout then
		if entry.listLayout.AbsoluteContentSize then
			return entry.listLayout.AbsoluteContentSize.Y
		end
	end

	local offset = f.CanvasSize.Y.Offset or 0
	local scale = f.CanvasSize.Y.Scale or 0
	return offset + (scale * f.AbsoluteSize.Y)
end

local function getMaxScroll(entry)
	local f = entry.frame
	if not f then return 0 end

	if f.AbsoluteSize.Y <= 0 then return 0 end

	local contentHeight = getContentHeight(entry)
	return math.max(0, contentHeight - f.AbsoluteSize.Y)
end

-- --------------- AUTO-SCROLL LOOP ----------------
local scrollDirection = 1
local scrollProgress = 0
local isPaused = false
local pauseTimer = 0

local function progressToY(progress, entry)
	local maxScroll = getMaxScroll(entry)
	if maxScroll <= 0 then return 0 end
	progress = math.clamp(progress, 0, 1)
	return math.floor(progress * maxScroll)
end

RunService.RenderStepped:Connect(function(dt)
	if #managedFrames == 0 then return end

	if isPaused then
		pauseTimer += dt
		if pauseTimer >= SCROLL_PAUSE_TIME then
			isPaused = false
			pauseTimer = 0
			scrollDirection *= -1
		else
			return
		end
	end

	local normalizedSpeed = SCROLL_SPEED * 0.25
	scrollProgress += dt * scrollDirection * normalizedSpeed

	if scrollProgress >= 1 then
		scrollProgress = 1
		isPaused = true
	elseif scrollProgress <= 0 then
		scrollProgress = 0
		isPaused = true
	end

	for _, entry in ipairs(managedFrames) do
		local f = entry.frame
		if f and f.Parent and f.AbsoluteSize.Y > 0 then
			local maxScroll = getMaxScroll(entry)
			if maxScroll > 0 then
				local y = progressToY(scrollProgress, entry)
				f.CanvasPosition = Vector2.new(0, y)
			end
		end
	end
end)

debug("Auto-scroll manager loaded.")
