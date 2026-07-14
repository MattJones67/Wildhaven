--[[
	BuildController — the sanctuary build mode, designed thumb-first:

	  * 🔨 BUILD toggles the mode; a bottom palette shows Terrain / Habitat /
	    Decor tabs with big item buttons and the live object-cap readout
	  * pick an item -> a translucent GHOST follows your cursor/finger across
	    the plot, snapped to the grid; ⟳ rotates in 45° steps; ✓ places
	    (and stays in ghost mode so tiles chain fast); ✕ cancels
	  * tap one of YOUR placed objects -> Move / Rotate / Delete, and for
	    habitats: "+ Pet" opens a picker of unequipped pets (placing into a
	    matching-biome pen is called out), "− Pet" takes them home
	  * 🏡 Relocate row: move the whole plot to any unlocked biome — that
	    biome's perk then applies to YOU globally

	Everything here just *requests*; SanctuaryService re-validates all of it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)
local SanctuaryBuilder = require(ReplicatedStorage.SanctuaryBuilder)
local Sounds = require(script.Parent.Sounds)

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(40, 45, 55)
local GREEN = Color3.fromRGB(95, 200, 90)
local RED = Color3.fromRGB(200, 100, 90)

local BuildController = {}

-- Server-pushed sanctuary state
local sanctuary = nil -- payload from SanctuaryUpdate/GetSanctuary
local collectionCache = {}
local equippedIds: { [number]: boolean } = {}

-- UI + mode state
local gui: ScreenGui
local buildButton: TextButton
local palette: Frame
local paletteGrid: ScrollingFrame
local capLabel: TextLabel
local ghostButtons: Frame
local selectButtons: Frame
local petPicker: Frame
local petPickerList: ScrollingFrame
local relocateRow: Frame

local buildMode = false
local ghostModel: Model? = nil
local ghostKey: string? = nil
local ghostRotation = 0
local movingUid: number? = nil -- set when the ghost is a MOVE, not a place
local selectedUid: number? = nil
local ghostConnection: RBXScriptConnection? = nil

local mouse = Players.LocalPlayer:GetMouse()

-- ------------------------------------------------------------
-- Small UI helpers
-- ------------------------------------------------------------

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function makeButton(parent: Instance, props: { [string]: any }): TextButton
	local button = Instance.new("TextButton")
	button.Font = FONT
	button.TextScaled = true
	button.AutoButtonColor = false
	button.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(button :: any)[key] = value
	end
	button.Parent = parent
	round(button, 10)
	button.Activated:Connect(function()
		Sounds.buttonPress()
	end)
	return button
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

-- ------------------------------------------------------------
-- Ghost placement
-- ------------------------------------------------------------

local function clearGhost()
	if ghostConnection then
		ghostConnection:Disconnect()
		ghostConnection = nil
	end
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
	ghostKey = nil
	movingUid = nil
	ghostButtons.Visible = false
end

local function snapLocal(value: number): number
	local grid = GameConfig.Sanctuary.GridSnap
	if grid <= 0 then
		return value
	end
	return math.round(value / grid) * grid
end

-- Current ghost position in PLOT-LOCAL coordinates (clamped + snapped)
local function ghostLocalPosition(): (number, number)
	if not sanctuary then
		return 0, 0
	end
	local origin = sanctuary.Origin :: CFrame
	local hit = mouse.Hit and mouse.Hit.Position or origin.Position
	local relative = origin:PointToObjectSpace(hit)
	local half = sanctuary.HalfSize
	return snapLocal(math.clamp(relative.X, -half, half)), snapLocal(math.clamp(relative.Z, -half, half))
end

local function startGhost(key: string, rotation: number, moveUid: number?)
	clearGhost()
	local model = SanctuaryBuilder.createGhost(key)
	if not model or not sanctuary then
		return
	end
	ghostModel = model
	ghostKey = key
	ghostRotation = rotation
	movingUid = moveUid
	model.Parent = workspace
	ghostButtons.Visible = true

	local buildPivot = model:GetPivot()
	ghostConnection = RunService.Heartbeat:Connect(function()
		if not sanctuary then
			return
		end
		local x, z = ghostLocalPosition()
		local origin = sanctuary.Origin :: CFrame
		model:PivotTo(origin * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(ghostRotation), 0) * buildPivot)
	end)
end

local function confirmGhost()
	if not ghostKey then
		return
	end
	local x, z = ghostLocalPosition()
	task.spawn(function()
		local ok, result = pcall(function()
			if movingUid then
				return Remotes.MoveObject:InvokeServer(movingUid, x, z, ghostRotation)
			end
			return Remotes.PlaceObject:InvokeServer(ghostKey, x, z, ghostRotation)
		end)
		if ok and result and result.Success then
			Sounds.equipPop()
			if movingUid then
				clearGhost() -- moves are one-shot; placements chain
			end
		else
			Sounds.errorBuzz()
		end
	end)
end

-- ------------------------------------------------------------
-- Selection (tap your own placed objects)
-- ------------------------------------------------------------

local selectionBox: SelectionBox? = nil

local function clearSelection()
	selectedUid = nil
	selectButtons.Visible = false
	petPicker.Visible = false
	if selectionBox then
		selectionBox:Destroy()
		selectionBox = nil
	end
end

local function selectObject(uid: number, model: Model)
	clearSelection()
	selectedUid = uid
	selectButtons.Visible = true

	selectionBox = Instance.new("SelectionBox")
	selectionBox.Adornee = model
	selectionBox.Color3 = Color3.fromRGB(255, 220, 120)
	selectionBox.LineThickness = 0.06
	selectionBox.Parent = model

	-- Show pet buttons only for habitats
	local object
	for _, candidate in sanctuary.Objects do
		if candidate.Uid == uid then
			object = candidate
			break
		end
	end
	local def = object and GameConfig.SanctuaryObjectByKey[object.Key]
	local isHabitat = def and def.Category == "Habitat";
	(selectButtons:FindFirstChild("AddPet") :: TextButton).Visible = isHabitat == true;
	(selectButtons:FindFirstChild("RemovePet") :: TextButton).Visible = isHabitat == true
end

-- Walk up from a tapped part to "Obj_<uid>" inside MY sanctuary folder
local function objectUidFromPart(part: BasePart?): (number?, Model?)
	if not part then
		return nil, nil
	end
	local sanctuaries = workspace:FindFirstChild("Sanctuaries")
	local mine = sanctuaries and sanctuaries:FindFirstChild(Players.LocalPlayer.Name)
	if not mine then
		return nil, nil
	end
	local node: Instance? = part
	while node and node ~= workspace do
		if node.Parent == mine and node:IsA("Model") then
			local uid = tonumber((node.Name):match("^Obj_(%d+)$"))
			return uid, node :: Model
		end
		node = node.Parent
	end
	return nil, nil
end

local function onTap()
	if not buildMode or ghostKey then
		return
	end
	local uid, model = objectUidFromPart(mouse.Target)
	if uid and model then
		selectObject(uid, model)
	else
		clearSelection()
	end
end

-- ------------------------------------------------------------
-- Pet picker
-- ------------------------------------------------------------

local function placedPetIds(): { [number]: boolean }
	local placed = {}
	if sanctuary then
		for _, entry in sanctuary.PlacedPets do
			placed[entry.PetId] = true
		end
	end
	return placed
end

local function openPetPicker(forUid: number, removing: boolean)
	petPicker.Visible = true
	for _, child in petPickerList:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local placed = placedPetIds()
	local shown = 0
	for _, entry in collectionCache do
		if not entry.Id then
			continue
		end
		local eligible
		if removing then
			-- Only pets placed in THIS pen
			eligible = false
			for _, placedEntry in sanctuary.PlacedPets do
				if placedEntry.PetId == entry.Id and placedEntry.ObjectUid == forUid then
					eligible = true
					break
				end
			end
		else
			eligible = not placed[entry.Id] and not equippedIds[entry.Id]
		end
		if not eligible then
			continue
		end
		shown += 1
		local animal = GameConfig.AnimalByName[entry.Species]
		local rarity = animal and GameConfig.RarityByName[animal.Rarity]
		local tags = {}
		if entry.Mutation ~= "None" then
			table.insert(tags, entry.Mutation)
		end
		if entry.Size and entry.Size ~= "Normal" then
			table.insert(tags, entry.Size)
		end
		local rowButton = makeButton(petPickerList, {
			Size = UDim2.new(1, -8, 0, 44),
			BackgroundColor3 = Color3.fromRGB(55, 62, 75),
			Text = entry.Species .. (#tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or ""),
			TextColor3 = rarity and rarity.Color or Color3.new(1, 1, 1),
			LayoutOrder = shown,
		})
		rowButton.Activated:Connect(function()
			task.spawn(function()
				local ok, result = pcall(function()
					if removing then
						return Remotes.UnplacePet:InvokeServer(entry.Id)
					end
					return Remotes.PlacePet:InvokeServer(entry.Id, forUid)
				end)
				if ok and result and result.Success then
					Sounds.equipPop()
				else
					Sounds.errorBuzz()
				end
				petPicker.Visible = false
			end)
		end)
	end
	if shown == 0 then
		makeButton(petPickerList, {
			Size = UDim2.new(1, -8, 0, 44),
			BackgroundColor3 = Color3.fromRGB(45, 50, 62),
			Text = removing and "No pets in this pen" or "No free pets (unequip some!)",
		})
	end
end

-- ------------------------------------------------------------
-- Palette + mode UI construction
-- ------------------------------------------------------------

local currentCategory = "Terrain"

local function refreshPalette()
	for _, child in paletteGrid:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local order = 0
	for _, def in GameConfig.SanctuaryObjects do
		if def.Category ~= currentCategory then
			continue
		end
		order += 1
		local biome = def.Biome and GameConfig.BiomeByName[def.Biome]
		local itemButton = makeButton(paletteGrid, {
			Size = UDim2.new(0, 108, 0, 52),
			BackgroundColor3 = Color3.fromRGB(55, 62, 75),
			Text = (biome and biome.Emoji .. " " or "") .. def.Title,
			LayoutOrder = order,
		})
		itemButton.Activated:Connect(function()
			clearSelection()
			startGhost(def.Key, 0, nil)
		end)
	end
	if sanctuary then
		capLabel.Text = ("Objects %d/%d · Pets %d/%d"):format(
			#sanctuary.Objects, sanctuary.ObjectCap, #sanctuary.PlacedPets, sanctuary.PetCap)
	end
end

local function refreshRelocateRow()
	for _, child in relocateRow:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	for order, biome in GameConfig.Biomes do
		local here = sanctuary and sanctuary.Biome == biome.Name
		local biomeButton = makeButton(relocateRow, {
			Size = UDim2.new(0, 64, 0, 40),
			BackgroundColor3 = here and GREEN or Color3.fromRGB(55, 62, 75),
			Text = biome.Emoji,
			LayoutOrder = order,
		})
		biomeButton.Activated:Connect(function()
			if here then
				return
			end
			task.spawn(function()
				local ok, result = pcall(function()
					return Remotes.RelocatePlot:InvokeServer(biome.Name)
				end)
				if not (ok and result and result.Success) then
					Sounds.errorBuzz()
				end
			end)
		end)
	end
end

local function setBuildMode(enabled: boolean)
	buildMode = enabled
	palette.Visible = enabled
	buildButton.Text = enabled and "✕ Done" or "🔨 Build"
	buildButton.BackgroundColor3 = enabled and RED or Color3.fromRGB(200, 150, 90)
	if not enabled then
		clearGhost()
		clearSelection()
	else
		refreshPalette()
		refreshRelocateRow()
	end
end

local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "WildhavenBuild"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6

	buildButton = makeButton(gui, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -20),
		Size = UDim2.new(0, 120, 0, 56),
		BackgroundColor3 = Color3.fromRGB(200, 150, 90),
		Text = "🔨 Build",
	})
	buildButton.Activated:Connect(function()
		setBuildMode(not buildMode)
	end)

	-- Bottom palette
	palette = Instance.new("Frame")
	palette.AnchorPoint = Vector2.new(0.5, 1)
	palette.Position = UDim2.new(0.5, 0, 1, -84)
	palette.Size = UDim2.new(0, 560, 0, 168)
	palette.BackgroundColor3 = PANEL_COLOR
	palette.BackgroundTransparency = 0.1
	palette.Visible = false
	palette.Parent = gui
	round(palette, 14)

	capLabel = makeLabel(palette, {
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -24, 0, 22),
		Text = "Objects 0/20",
		TextColor3 = Color3.fromRGB(255, 235, 170),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Category tabs
	local tabs = Instance.new("Frame")
	tabs.Position = UDim2.new(0, 12, 0, 30)
	tabs.Size = UDim2.new(0, 300, 0, 34)
	tabs.BackgroundTransparency = 1
	tabs.Parent = palette
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabs
	for _, category in { "Terrain", "Habitat", "Decor" } do
		local tabButton = makeButton(tabs, {
			Size = UDim2.new(0, 92, 1, 0),
			BackgroundColor3 = Color3.fromRGB(70, 78, 94),
			Text = category,
		})
		tabButton.Activated:Connect(function()
			currentCategory = category
			refreshPalette()
		end)
	end

	-- Item strip (horizontal scroll)
	paletteGrid = Instance.new("ScrollingFrame")
	paletteGrid.Position = UDim2.new(0, 12, 0, 68)
	paletteGrid.Size = UDim2.new(1, -24, 0, 56)
	paletteGrid.BackgroundTransparency = 1
	paletteGrid.BorderSizePixel = 0
	paletteGrid.ScrollBarThickness = 4
	paletteGrid.ScrollingDirection = Enum.ScrollingDirection.X
	paletteGrid.AutomaticCanvasSize = Enum.AutomaticSize.X
	paletteGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	paletteGrid.Parent = palette
	local gridLayout = Instance.new("UIListLayout")
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.Padding = UDim.new(0, 6)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = paletteGrid

	-- Relocate row (biome emojis)
	relocateRow = Instance.new("Frame")
	relocateRow.Position = UDim2.new(0, 12, 1, -40)
	relocateRow.Size = UDim2.new(1, -24, 0, 36)
	relocateRow.BackgroundTransparency = 1
	relocateRow.Parent = palette
	local relocateLayout = Instance.new("UIListLayout")
	relocateLayout.FillDirection = Enum.FillDirection.Horizontal
	relocateLayout.Padding = UDim.new(0, 6)
	relocateLayout.SortOrder = Enum.SortOrder.LayoutOrder
	relocateLayout.Parent = relocateRow
	makeLabel(palette, {
		Position = UDim2.new(0, 12, 1, -62),
		Size = UDim2.new(1, -24, 0, 20),
		Text = "🏡 Move plot (biome perk applies to you):",
		TextColor3 = Color3.fromRGB(190, 200, 215),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	-- Ghost controls (float above the palette)
	ghostButtons = Instance.new("Frame")
	ghostButtons.AnchorPoint = Vector2.new(0.5, 1)
	ghostButtons.Position = UDim2.new(0.5, 0, 1, -260)
	ghostButtons.Size = UDim2.new(0, 260, 0, 56)
	ghostButtons.BackgroundTransparency = 1
	ghostButtons.Visible = false
	ghostButtons.Parent = gui
	local ghostLayout = Instance.new("UIListLayout")
	ghostLayout.FillDirection = Enum.FillDirection.Horizontal
	ghostLayout.Padding = UDim.new(0, 8)
	ghostLayout.Parent = ghostButtons
	local placeButton = makeButton(ghostButtons, { Size = UDim2.new(0, 96, 1, 0), BackgroundColor3 = GREEN, Text = "✓ Place" })
	local rotateButton = makeButton(ghostButtons, { Size = UDim2.new(0, 72, 1, 0), BackgroundColor3 = Color3.fromRGB(90, 140, 200), Text = "⟳" })
	local cancelButton = makeButton(ghostButtons, { Size = UDim2.new(0, 72, 1, 0), BackgroundColor3 = RED, Text = "✕" })
	placeButton.Activated:Connect(confirmGhost)
	rotateButton.Activated:Connect(function()
		ghostRotation = (ghostRotation + 45) % 360
	end)
	cancelButton.Activated:Connect(clearGhost)

	-- Selection controls
	selectButtons = Instance.new("Frame")
	selectButtons.AnchorPoint = Vector2.new(0.5, 1)
	selectButtons.Position = UDim2.new(0.5, 0, 1, -260)
	selectButtons.Size = UDim2.new(0, 420, 0, 52)
	selectButtons.BackgroundTransparency = 1
	selectButtons.Visible = false
	selectButtons.Parent = gui
	local selectLayout = Instance.new("UIListLayout")
	selectLayout.FillDirection = Enum.FillDirection.Horizontal
	selectLayout.Padding = UDim.new(0, 8)
	selectLayout.Parent = selectButtons

	local moveButton = makeButton(selectButtons, { Size = UDim2.new(0, 84, 1, 0), BackgroundColor3 = Color3.fromRGB(90, 140, 200), Text = "Move" })
	local deleteButton = makeButton(selectButtons, { Size = UDim2.new(0, 84, 1, 0), BackgroundColor3 = RED, Text = "🗑 Delete" })
	local addPetButton = makeButton(selectButtons, { Name = "AddPet", Size = UDim2.new(0, 84, 1, 0), BackgroundColor3 = GREEN, Text = "+ Pet" })
	local removePetButton = makeButton(selectButtons, { Name = "RemovePet", Size = UDim2.new(0, 84, 1, 0), BackgroundColor3 = Color3.fromRGB(200, 150, 90), Text = "− Pet" })

	moveButton.Activated:Connect(function()
		if not selectedUid or not sanctuary then
			return
		end
		for _, object in sanctuary.Objects do
			if object.Uid == selectedUid then
				local uid = selectedUid
				clearSelection()
				startGhost(object.Key, object.R, uid)
				return
			end
		end
	end)
	deleteButton.Activated:Connect(function()
		if not selectedUid then
			return
		end
		local uid = selectedUid
		clearSelection()
		task.spawn(function()
			local ok, result = pcall(function()
				return Remotes.DeleteObject:InvokeServer(uid)
			end)
			if ok and result and result.Success then
				Sounds.eggCrack()
			else
				Sounds.errorBuzz()
			end
		end)
	end)
	addPetButton.Activated:Connect(function()
		if selectedUid then
			openPetPicker(selectedUid, false)
		end
	end)
	removePetButton.Activated:Connect(function()
		if selectedUid then
			openPetPicker(selectedUid, true)
		end
	end)

	-- Pet picker panel
	petPicker = Instance.new("Frame")
	petPicker.AnchorPoint = Vector2.new(0.5, 0.5)
	petPicker.Position = UDim2.new(0.5, 0, 0.42, 0)
	petPicker.Size = UDim2.new(0, 320, 0, 300)
	petPicker.BackgroundColor3 = PANEL_COLOR
	petPicker.Visible = false
	petPicker.Parent = gui
	round(petPicker, 14)
	makeLabel(petPicker, {
		Position = UDim2.new(0, 12, 0, 8),
		Size = UDim2.new(1, -24, 0, 30),
		Text = "Choose a pet",
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local closePicker = makeButton(petPicker, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 32, 0, 30),
		BackgroundColor3 = RED,
		Text = "✕",
	})
	closePicker.Activated:Connect(function()
		petPicker.Visible = false
	end)
	petPickerList = Instance.new("ScrollingFrame")
	petPickerList.Position = UDim2.new(0, 8, 0, 44)
	petPickerList.Size = UDim2.new(1, -16, 1, -52)
	petPickerList.BackgroundTransparency = 1
	petPickerList.BorderSizePixel = 0
	petPickerList.ScrollBarThickness = 5
	petPickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	petPickerList.CanvasSize = UDim2.new(0, 0, 0, 0)
	petPickerList.Parent = petPicker
	local pickerLayout = Instance.new("UIListLayout")
	pickerLayout.Padding = UDim.new(0, 6)
	pickerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickerLayout.Parent = petPickerList

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------

function BuildController.setSanctuary(payload)
	sanctuary = payload
	if buildMode then
		refreshPalette()
		refreshRelocateRow()
	end
end

function BuildController.setCollection(collection)
	collectionCache = collection or {}
end

function BuildController.setEquipped(payload)
	equippedIds = {}
	for _, id in payload.Equipped or {} do
		equippedIds[id] = true
	end
end

function BuildController.init()
	buildGui()
	-- Tap-to-select (mouse click and touch both fire Button1Down via Mouse)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			onTap()
		end
	end)
end

return BuildController
