-- FINAL DEFENSIVE AUTO-SCROLL
-- Put in StarterPlayerScripts (LocalScript)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- CONFIG
local UI_NAMES = { "Gear_Shop", "Seed_Shop", "PetShop_UI" }
local UI_PADDING = 20
local SCROLL_SPEED = 0.12      -- lower = slower
local UI_SCALE = 0.75
local SCROLL_PAUSE_TIME = 1.2
local RESCAN_INTERVAL = 1

-- ---------- find & arrange UIs ----------
local foundUIs = {}

local function safePcall(fn)
	local ok, _ = pcall(fn)
	return ok
end

local function tryAddUI(ui)
	safePcall(function()
		for _, name in ipairs(UI_NAMES) do
			if ui and ui.Name == name then
				if not table.find(foundUIs, ui) then
					table.insert(foundUIs, ui)
					ui.Enabled = true
					if ui:IsA("ScreenGui") then
						ui.ResetOnSpawn = false
						ui.IgnoreGuiInset = false
					end
				end
			end
		end
	end)
end

-- initial find
safePcall(function()
	for _, name in ipairs(UI_NAMES) do
		local ui = playerGui:FindFirstChild(name)
		if ui then tryAddUI(ui) end
	end
end)

playerGui.ChildAdded:Connect(function(child)
	safePcall(function() tryAddUI(child) end)
end)

local cornerPositions = {
	{anchor = Vector2.new(0,0), position = UDim2.new(0, UI_PADDING, 0, UI_PADDING)},
	{anchor = Vector2.new(1,0), position = UDim2.new(1, -UI_PADDING, 0, UI_PADDING)},
	{anchor = Vector2.new(0,1), position = UDim2.new(0, UI_PADDING, 1, -UI_PADDING)},
	{anchor = Vector2.new(1,1), position = UDim2.new(1, -UI_PADDING, 1, -UI_PADDING)},
}

local function arrangeUIs()
	safePcall(function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local view = cam.ViewportSize
		local baseW = math.floor(view.X * 0.35)
		local baseH = math.floor(view.Y * 0.45)

		for idx, ui in ipairs(foundUIs) do
			local corner = cornerPositions[((idx-1) % #cornerPositions) + 1]
			local uiW = math.floor(baseW)
			local uiH = math.floor(baseH)

			for _, child in ipairs(ui:GetChildren()) do
				if child:IsA("Frame") or child:IsA("ImageLabel") or child:IsA("ScrollingFrame") then
					safePcall(function()
						child.Visible = true
						child.AnchorPoint = corner.anchor
						child.Position = corner.position
						child.Size = UDim2.new(0, uiW, 0, uiH)

						local sc = child:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", child)
						sc.Scale = UI_SCALE
					end)
				end
			end
		end
	end)
end

-- initial arrange
arrangeUIs()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		safePcall(arrangeUIs)
	end)
end

-- ---------- scrolling frames management ----------
local managed = {}

local function findLayout(sf)
	return sf:FindFirstChildOfClass("UIListLayout")
		or sf:FindFirstChildOfClass("UIGridLayout")
		or sf:FindFirstChildOfClass("UIPageLayout")
end

local function findManagedEntry(frame)
	for _, e in ipairs(managed) do
		if e.frame == frame then return e end
	end
	return nil
end

local function hookLayoutToFrame(sf, entry, layoutObj, contentFrame)
	entry.layout = layoutObj
	entry.contentFrame = contentFrame

	local function updateCanvasFromLayout()
		safePcall(function()
			if not entry or not entry.frame or not entry.frame.Parent then return end
			local acs = layoutObj.AbsoluteContentSize
			if acs and (acs.Y > 0 or acs.X > 0) then
				if layoutObj:IsA("UIGridLayout") then
					entry.frame.CanvasSize = UDim2.new(0, acs.X, 0, acs.Y)
				else
					entry.frame.CanvasSize = UDim2.new(0, 0, 0, acs.Y)
				end
			end
		end)
	end

	layoutObj:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasFromLayout)
	task.defer(updateCanvasFromLayout)
end

local function addManaged(sf)
	safePcall(function()
		if findManagedEntry(sf) then return end

		local layout = findLayout(sf)
		local entry = { frame = sf, layout = layout, contentFrame = nil, currentY = (sf.CanvasPosition and sf.CanvasPosition.Y) or 0 }
		table.insert(managed, entry)

		sf.ScrollingEnabled = true
		sf.ScrollBarThickness = 8

		if layout then
			hookLayoutToFrame(sf, entry, layout, nil)
		end

		local content = sf:FindFirstChild("Content")
		if content and content:IsA("Frame") then
			local innerLayout = content:FindFirstChildOfClass("UIListLayout") or content:FindFirstChildOfClass("UIGridLayout") or content:FindFirstChildOfClass("UIPageLayout")
			if innerLayout then
				hookLayoutToFrame(sf, entry, innerLayout, content)
			end
		end
	end)
end

-- ---------- initial + periodic scan ----------
local function rescanAll()
	safePcall(function()
		for _, ui in ipairs(foundUIs) do
			for _, desc in ipairs(ui:GetDescendants()) do
				if desc:IsA("ScrollingFrame") then
					addManaged(desc)
				end
			end
		end
	end)
end

rescanAll()
task.spawn(function()
	while true do
		rescanAll()
		task.wait(RESCAN_INTERVAL)
	end
end)

-- ---------- smooth auto-scroll loop ----------
local direction = 1
local progress = 0
local paused = false
local pauseTimer = 0

local function progressToY(p, entry)
	local max = entry.frame and entry.frame.AbsoluteCanvasSize.Y - entry.frame.AbsoluteSize.Y or 0
	return math.clamp(p, 0, 1) * math.max(0, max)
end

RunService.RenderStepped:Connect(function(dt)
	if #managed == 0 then return end

	if paused then
		pauseTimer = pauseTimer + dt
		if pauseTimer >= SCROLL_PAUSE_TIME then
			paused = false
			pauseTimer = 0
			direction = -direction
		else
			return
		end
	end

	progress = progress + (dt * direction * SCROLL_SPEED)
	if progress >= 1 then
		progress = 1
		paused = true
	elseif progress <= 0 then
		progress = 0
		paused = true
	end

	for _, entry in ipairs(managed) do
		local f = entry.frame
		if not f or not f.Parent then goto cont end
		if f.AbsoluteSize and f.AbsoluteSize.Y > 0 then
			local maxScroll = math.max(0, f.AbsoluteCanvasSize.Y - f.AbsoluteSize.Y)
			if maxScroll > 0 then
				local target = progressToY(progress, entry)
				entry.currentY = entry.currentY or 0
				local alpha = math.clamp(10 * dt, 0, 1)
				entry.currentY = entry.currentY + (target - entry.currentY) * alpha
				pcall(function()
					f.CanvasPosition = Vector2.new(0, math.floor(entry.currentY + 0.5))
				end)
			end
		end
		::cont::
	end
end)
