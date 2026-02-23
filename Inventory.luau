local InventoryController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local InventoryEvent = ReplicatedStorage.Events.InventoryEvent
local InventoryRF = ReplicatedStorage.Events.InventoryRF

local ScriptsFolder = script.Parent.Parent

local Inventory = require(ScriptsFolder.State.InventoryState)
local Observer = require(ScriptsFolder.ObserverModule)
local System = require(ScriptsFolder.SystemModule)
local Keybinds = require(ScriptsFolder.KeybindsModule)
local Utils = require(ScriptsFolder.UtilitiesModule)
local Cooldown = require(ScriptsFolder.CooldownModule)
local Configuration = require(ScriptsFolder.ConfigurationModule)
local Consumable = require(ScriptsFolder.ConsumableModule)
local ExamineController = require(ScriptsFolder.Controllers.ExamineController)
local House = require(ScriptsFolder.HouseModule)
local Repair = require(ScriptsFolder.RepairModule)
local Crafting = require(ScriptsFolder.CraftingModule)

local EQUIP_COOLDOWN = Configuration.CONFIG_TABLE.EQUIP_COOLDOWN

local InventoryObserver = Observer.new("Inventory")

function InventoryController.initialize()
	local success, inventoryData, cashData, equippedData = pcall(function()
		return InventoryRF:InvokeServer("Inventory")
	end)
	if success then
		for _, category in pairs(inventoryData) do
			for _, itemData in pairs(category) do
				Inventory.addItem(itemData)
			end
		end
		Inventory.updateCash(cashData)
		for i = 1, 7 do
			Inventory.updateEquipped(i, equippedData[i])
		end
	end
end

function InventoryController.selectItem(itemButton, itemData)
	local selectedItem = Inventory.getSelectedItem()
	if selectedItem == itemButton then
		ContextActionService:UnbindAction("InventoryRadial")
		Inventory.removeSelectedItem()
	else
		Inventory.addSelectedItem(itemButton, itemData)
		local bind = Keybinds.getKeybind("RadialMenuButton")
		if bind and bind[1] then
			Utils.addContextBind("InventoryRadial", "gui", bind[1].Key)
		end
	end
end

function InventoryController.selectEquipmentButton(equipmentButton)
	local itemToIndex = Inventory.itemToIndex[equipmentButton.Name] 
	if itemToIndex then
		local equippedItem = Inventory.getEquippedSlot(itemToIndex)
		if equippedItem ~= -1 then
			local itemData = Inventory.getItem(equippedItem)
			InventoryController.selectItem(equipmentButton, itemData)
		end
	end
end

function InventoryController.removeRCSelect()
	Inventory.removeSelectedRCItem()
	ContextActionService:UnbindAction("CloseInventoryRadial")
end

function InventoryController.RCSelectItem(itemButton, item)
	Inventory.addRCSelectedItem(itemButton, item)
	Utils.addModalBind("InventoryMenu", "gui", Enum.UserInputType.MouseButton1)
end

local function sendEvent(typeEvent, eventData, cooldownType, cooldownTime, cooldownDisplay)
	local success, result, secondaryData = pcall(function()
		return InventoryRF:InvokeServer(typeEvent, table.unpack(eventData))
	end)
	if success and result then
		if cooldownType then
			Cooldown.applyCooldown(cooldownType, cooldownTime, cooldownDisplay)
		end
		return true
	end
	return false, secondaryData
end

function InventoryController.equipArmor(itemData)
	if Cooldown.isOnCooldown("Armor") then
		System.showMessage("You must wait " .. string.format("%.1f", Cooldown.getCooldownTimeLeft("Armor")) .. " seconds before equipping armor again!")
		return 
	end
	local armorIndex = Inventory.itemToIndex[itemData.armorType]
	if armorIndex then
		if Inventory.getEquippedSlot(armorIndex) == itemData.UUID then
			if sendEvent("UnequipArmor", {itemData.UUID}, "Armor", EQUIP_COOLDOWN, "Armor") then
				Inventory.updateEquipped(armorIndex, -1)
			end
		else
			if sendEvent("EquipArmor", {itemData.UUID}, "Armor", EQUIP_COOLDOWN, "Armor") then
				Inventory.updateEquipped(armorIndex, itemData.UUID)
			end
		end
	end
end

function InventoryController.equipWeapon(itemData)
	if Cooldown.isOnCooldown("Weapon") then
		System.showMessage("You must wait " .. string.format("%.1f", Cooldown.getCooldownTimeLeft("Weapon")) .. " seconds before equipping a weapon again!")
		return 
	end
	if Inventory.getWeapon() == itemData then
		if sendEvent("UnequipWeapon", {itemData.UUID}, "Weapon", EQUIP_COOLDOWN, "Weapon") then
			Inventory.updateEquipped(1, -1)
		end
	else
		if sendEvent("EquipWeapon", {itemData.UUID}, "Weapon", EQUIP_COOLDOWN, "Weapon") then
			Inventory.updateEquipped(1, itemData.UUID)
		end
	end
end

function InventoryController.useConsumable(itemData)
	if Cooldown.isOnCooldown(itemData.item) then
		System.showMessage("You are already under the effects of this enhancer!")
		return
	end
	if not Consumable.checkFullness(itemData) then
		return
	end
	if sendEvent("Consumable", {itemData.UUID}, itemData.item, itemData.duration) then
		Consumable.applyConsumable(itemData)
		System.showMessage("You are now under the effects of " .. itemData.item .. "!")
	end
end

function InventoryController.useTool(itemData)
	if itemData.item == "Crafting Tool" then
		Crafting.startCrafting(itemData.UUID)
	elseif itemData.item == "Repair Tool" then
		Repair.startRepair(itemData.UUID)
	end
end

function InventoryController.useSpecial(itemData)
	if itemData.specialType == "House" then
		House.plotHouse(itemData.UUID)
	end
end

local MedicalHandler = {
	Stim = function(itemData) 
		require(ScriptsFolder.Skills.MedicinalHeal).useSkill(itemData) 
	end,
	Blanket = function(itemData) 
		require(ScriptsFolder.Skills.ApplyBlanket).useSkill(itemData) 
	end,
	Antidote = function(itemData) 
		require(ScriptsFolder.Skills.ApplyAntidote).useSkill(itemData) 
	end,
	WoundPack = function(itemData) 
		require(ScriptsFolder.TendWound).useSkill(itemData) 
	end,
	EnhancePack = function(itemData)
		require(ScriptsFolder.ApplyEnhancement).useSkill(itemData)
	end,
}

function InventoryController.useMedical(itemData)
	local handler = MedicalHandler[itemData.medicineType]
	if handler then
		handler(itemData)
	end
end


local useHandler = {
	Consumable = InventoryController.useConsumable,
	Tool =InventoryController.useTool,
	Armor = InventoryController.equipArmor,
	Weapon = InventoryController.equipWeapon,
	Powerup = InventoryController.startPowerupDrag,
	Medical = InventoryController.useMedical,
	Special = InventoryController.useSpecial
}

function InventoryController.useItem(unbindEvent)
	local itemButton = Inventory.getRCSelectedItem() or Inventory.getSelectedItem()
	if unbindEvent then
		InventoryController.removeRCSelect()
	end
	local itemData = Inventory.getItem(itemButton.Name)
	local handler = useHandler[itemData.itemType]
	if handler then
		handler(itemData)
	end
end

function InventoryController.ExamineItem()
	local itemButton = Inventory.getRCSelectedItem() or Inventory.getSelectedItem()
	InventoryController.removeRCSelect()
	if itemButton then
		local itemData = Inventory.getItem(itemButton.Name)
		ExamineController.examineItem(itemData)
	end
end

function InventoryController.dropItem(unbindEvent)
	local itemButton = Inventory.getRCSelectedItem() or Inventory.getSelectedItem()
	if unbindEvent then
		InventoryController.removeRCSelect()
	end
	if not House.checkHousing() then
		System.showMessage("You are unable to drop items outside of your own housing structure!")
		return
	end
	local itemData = Inventory.getItem(itemButton.Name)
	if not House.checkBoundsAndItems() or not itemData then
		return
	end
	local eventSucces, eventResult = sendEvent("DropItem", {itemData.UUID, itemData.itemType})
	if eventSucces then
		System.showMessage("You have dropped " .. itemData.itemName .. "!")
	else
		if eventResult == "Error" then
			System.showMessage("There was an error in dropping your item, please try again!")
		else
			System.showMessage("Your house has reached the maximum item limit!")
		end
	end
end

local function destroyItem(itemData)
	if sendEvent("DestroyItem", {itemData.UUID, itemData.itemType}) then
		System.showMessage("You have destroyed " .. itemData.itemName .. "!")
	end
end

function InventoryController.promptDestroy(unbindEvent)
	local itemButton = Inventory.getRCSelectedItem() or Inventory.getSelectedItem()
	if unbindEvent then
		InventoryController.removeRCSelect()
	end
	local itemData = Inventory.getItem(itemButton.Name)
	if itemData then 
		Utils.createGenericQuestion("Delete Item", "Are you sure you want to destroy this item?", function() destroyItem(itemData) end)
	end
end

function InventoryController.startAnimations()

end

function InventoryController.toggleOpen()
	Inventory.Events:Fire("ToggleOpen")
end

function InventoryController.setOpenBinds(isOpen)
	if isOpen then
		local selectedItem = Inventory.getSelectedItem()
		if selectedItem then
			local bind = Keybinds.getKeybind("RadialMenuButton")
			if bind and bind[1] then
				Utils.addContextBind("InventoryRadial", "gui", bind[1].Key)
			end
		end
	else
		ContextActionService:UnbindAction("InventoryRadial")
	end
end

local eventHandler = {
	AddItem = function(itemData)
		Inventory.addItem(itemData)
		InventoryObserver:Fire("AddItem", itemData)
	end,

	RemoveItem = function(itemType, itemUUID)
		Inventory.removeItem(itemType, itemUUID)
		InventoryObserver:Fire("RemoveItem", itemUUID, itemType)
	end,

	ItemBreak = function(itemType, itemUUID)
		Inventory.removeItem(itemType, itemUUID)
		System.showMessageAndChat("System: the item has been destroyed due to insufficient condition!")
	end,

	UpdateCash = function(cash)
		Inventory.updateCash(cash)
		InventoryObserver:Fire("UpdateCash", cash)
	end,

	UpdateQuantity = function(itemType, itemUUID, quantity)
		Inventory.updateQuantity(itemType, itemUUID, quantity)

	end,
}

InventoryEvent.OnClientEvent:Connect(function(event, ...) 
	local handler = eventHandler[event]
	if handler then
		handler(table.unpack({...}))
	end
end)



return InventoryController



local InventoryGUI = {}

local ScriptsFolder = script.Parent.Parent

local Inventory = require(ScriptsFolder.State.InventoryState)
local InventoryController = require(ScriptsFolder.Controllers.InventoryController)
local GUIList = require(ScriptsFolder.GUIListModule)
local Configuration = require(ScriptsFolder.ConfigurationModule)
local Utils = require(ScriptsFolder.UtilitiesModule)
local RotationModule = require(ScriptsFolder.RotationModule)
local ItemModule = require(ScriptsFolder.ItemModule)
local DragDropModule = require(ScriptsFolder.DragDropModule)

local InventoryGUI = GUIList.getGUI("Inventory")
local InventoryFrame = InventoryGUI.Inventory
local EquipmentFrame = InventoryFrame.Equipment
local ItemScrollFrame = InventoryFrame.ItemsScroll
local InfoFrame = InventoryFrame.Info.ScrollingFrame
local ButtonsFrame = InventoryFrame.Buttons
local SampleButton = ItemScrollFrame.Sample
local RoomBar = InventoryFrame.RoomBar.TotalRoomBar
local RoomLabel = InventoryFrame.RoomNumber
local CashLabel = InventoryFrame.Cash
local RightClickFrame = InventoryGUI.RightclickFrame

local CONFIG = Configuration.CONFIG_TABLE

local EquippedButtons = {}
local ItemButtonReference = {}

local itemTypeDisplay = {
	Weapon = function(itemData, frame)
		Utils.createDisplayLabel(frame, "Condition", string.format("Condition: %d/%d", math.round(itemData.condition), itemData.conditionMax))
		Utils.createDisplayLabel(frame, "Damage", string.format("Damage: %.2f", itemData.damage))
		Utils.createDisplayLabel(frame, "ActionCost", string.format("Action Cost: %.2f", itemData.actionCost))
		Utils.createDisplayLabel(frame, "IdealRange", string.format("Ideal Range: %d", itemData.idealRange))
		Utils.createDisplayLabel(frame, "AccuracyModifier", string.format("Accuracy Mod: %d", itemData.idealRangeMod))
		if itemData.power then 
			Utils.createDisplayLabel(frame, "ToolPower", string.format("Power: %.2f", itemData.power))
		end
		if itemData.Powerup then
			Utils.createDisplayLabel(frame, "", "")
			Utils.createDisplayLabel(frame, "PowerupTitle", "[Powerup]")
			if itemData.Powerup.damage then 
				Utils.createDisplayLabel(frame, "PowerupDamage", string.format("Damage: +%.2f", itemData.Powerup.damage))
				frame.Damage.Text = string.format("Damage: %.2f", itemData.damage + itemData.Powerup.damage)
			end
			if itemData.Powerup.action then
				Utils.createDisplayLabel(frame, "PowerupAction", string.format("Action: -%.2f", itemData.Powerup.action))
				frame.ActionCost.Text = string.format("Action Cost: %.2f", itemData.actionCost - itemData.Powerup.action)
			end
			if itemData.Powerup.accuracy then
				Utils.createDisplayLabel(frame, "PowerupAccuracy", string.format("Accuracy: +%d", itemData.Powerup.accuracy))
				frame.AccuracyModifier.Text = string.format("Accuracy Mod: %d", itemData.idealRangeMod + itemData.Powerup.accuracy)
			end
			Utils.createDisplayLabel(frame, "PowerupUses", string.format("Uses: %d", itemData.Powerup.Uses))
		end
		if itemData["dot"] then
			Utils.createDisplayLabel(frame, "", "")
			Utils.createDisplayLabel(frame, "DOTTitle", "[DOT]")
			Utils.createDisplayLabel(frame, "DOTType", string.format("Type: %s", itemData.dotType))
			Utils.createDisplayLabel(frame, "DOTStrength", string.format("Strength: %d", itemData.dotStrength))
			Utils.createDisplayLabel(frame, "DOTPotency", string.format("Potency: %d", itemData.dotPotency)); frame.DOTPotency.Text = frame.DOTPotency.Text .. "%"
			Utils.createDisplayLabel(frame, "DOTDuration", string.format("Duration: %d", itemData.dotDuration))
			Utils.createDisplayLabel(frame, "DOTUses", string.format("Uses: %d", itemData.dotUses))
		end
	end,

	Consumable = function(itemData, frame)
		Utils.createDisplayLabel(frame, "Attribute", string.format("Attribute: %s", itemData.bonusType))
		if itemData.bonus then
			Utils.createDisplayLabel(frame, "Bonus", string.format("%s: +%d", itemData.bonusType, itemData.bonus))
		else
			Utils.createDisplayLabel(frame, "Bonus", string.format("%s: +%d%%", itemData.bonusType, itemData.effectiveness))	
			Utils.createDisplayLabel(frame, "Fullness", string.format("Fullness: %.2f", itemData.fullness))
		end
		Utils.createDisplayLabel(frame, "Duration", string.format("Duration: %d", itemData.duration))
		Utils.createDisplayLabel(frame, "Quantity", string.format("Quantity: %d", itemData.quantity))
	end,

	Armor = function(itemData, frame)
		Utils.createDisplayLabel(frame, "Condition", string.format("Condition: %d/%d", math.round(itemData.condition), itemData.conditionMax))
		Utils.createDisplayLabel(frame, "ArmorPiece", string.format("Armor Piece: %s", itemData.armorType))
		Utils.createDisplayLabel(frame, "Defense", string.format("Defense: %.2f", itemData.defense))
		Utils.createDisplayLabel(frame, "Evasion", string.format("Evasion: %.2f", itemData.evasion))
	end,

	Medical = function(itemData, frame)
		Utils.createDisplayLabel(frame, "MedicineType", string.format("Type: %s", itemData.medicineType))
		if itemData.efficacy then
			Utils.createDisplayLabel(frame, "Efficacy", string.format("Efficacy: %.2f", itemData.efficacy))
		else
			Utils.createDisplayLabel(frame, "Power", string.format("Power: %.2f", itemData.power))
		end
		Utils.createDisplayLabel(frame, "Quantity", string.format("Quantity: %d", itemData.quantity))
	end,

	Tool = function(itemData, frame)
		if itemData.condition then
			Utils.createDisplayLabel(frame, "Condition", string.format("Condition: %d/%d", math.round(itemData.condition), itemData.conditionMax))
		end
		Utils.createDisplayLabel(frame, "Effectiveness", string.format("Effectiveness: %d", itemData.effectiveness))
	end,

	Resource = function(itemData, frame)
		Utils.createDisplayLabel(frame, "ResourceType", string.format("Resource Type: %s", itemData.resourceType))
		Utils.createDisplayLabel(frame, "Power", string.format("Power: %d", itemData.power))
		Utils.createDisplayLabel(frame, "Durability", string.format("Durability: %d", itemData.durability))
		Utils.createDisplayLabel(frame, "Quality", string.format("Quality: %d", itemData.quality))
		Utils.createDisplayLabel(frame, "Quantity", string.format("Quantity: %d", itemData.quantity))
	end,

	Special = function(itemData, frame)
		Utils.createDisplayLabel(frame, "Type", string.format("Type: %s", itemData.specialType))
		Utils.createDisplayLabel(frame, "Description", string.format("Description: %s", itemData.description))
		Utils.createDisplayLabel(frame, "Tradeable", string.format("Tradeable: %s", itemData.trade and "true" or "false"))
	end,

	Powerup = function(itemData, frame)
		Utils.createDisplayLabel(frame, "Quantity", string.format("Quantity: %d", itemData.quantity))
		if itemData.damage then
			Utils.createDisplayLabel(frame, "Damage", string.format("Damage: +%.2f", itemData.damage))
		end
		if itemData.action then
			Utils.createDisplayLabel(frame, "ActionCost", string.format("ActionCost: -%.2f", itemData.action))
		end
		if itemData.accuracy then
			Utils.createDisplayLabel(frame, "Accuracy", string.format("Accuracy: +%.2f", itemData.accuracy))
		end
	end,

	Component = function(itemData, frame)
		Utils.createDisplayLabel(frame, "Quantity", string.format("Quantity: +%d", itemData.quantity))
		for typeBonus, bonus in itemData.modifiers do
			Utils.createDisplayLabel(frame, typeBonus, typeBonus..": " .. bonus)
		end
	end,
}

local function createItemLabels(itemData, frame)
	Utils.createDisplayLabel(frame, "itemName", itemData.itemName)
	local reinforcement = itemData.reinforcement
	if reinforcement and reinforcement > 0 then
		Utils.createDisplayLabel(frame, "item", string.format("Item: %s", itemData.item))
		frame.item.Text = frame.item.Text .. '<font color="#FFFF00"> +' .. reinforcement .. " " .. '</font>'
	else
		Utils.createDisplayLabel(frame, "item", string.format("Item: %s", itemData.item))
	end
	if itemData.Creator then
		Utils.createDisplayLabel(frame, "itemCreator", string.format("Creator: %s", itemData.Creator))
	end
	if itemData.mythical then
		frame.itemName.Text = frame.itemName.Text .. " <font color=\"#FF0000\">[Mythical]</font>"
	elseif itemData.epic then
		frame.itemName.Text = frame.itemName.Text .. " <font color=\"#7F4E9E\">[Epic]</font>"
	end
	local displayFunc = itemTypeDisplay[itemData.itemType]
	if displayFunc then
		displayFunc(itemData, frame)
	end
end

local function displayValues(itemData, frame, resetPosition)
	Utils.clearFrame(frame, "TextLabel")
	if resetPosition then
		frame.CanvasPosition = Vector2.new(0, 0)
	end
	createItemLabels(itemData, frame)
end

local function beginRotation()
	for _, button in ipairs(ItemScrollFrame:GetChildren()) do
		if button:IsA("ImageButton") and button.Name ~= "Sample" then
			RotationModule.rotateItemIcon(button, "INVENTORY_MODEL", InventoryFrame)
		end
	end
end

local function redisplayValues(itemData)
	local selectedItem = Inventory.getSelectedItem()
	if selectedItem and selectedItem.Name == itemData.UUID then
		displayValues(itemData, InfoFrame, false)
	end
end

local function setCapacityBar(total)
	local BarSize = math.clamp(total / CONFIG.INVENTORY_LIMIT, 0, 1)
	RoomBar.Size = UDim2.new(BarSize, 0, 1, 0)
	RoomLabel.Text = "Capacity: " .. total .. "/" .. CONFIG.INVENTORY_LIMIT
end

local function checkWeapon(item)
	if item.itemType == "Weapon" and item["Powerup"] then
		RightClickFrame.Powerup.Text = "Remove"
		RightClickFrame.Powerup.Visible = true
	else
		RightClickFrame.Powerup.Visible = false
	end
end

local function createRightClickMenu(itemButton, itemData)
	local absPos = itemButton.AbsolutePosition
	local absSize = itemButton.AbsoluteSize
	local center = Vector2.new(absPos.X + absSize.X/2, absPos.Y + absSize.Y/2)
	local handler = CONFIG.USE_TEXT[itemData.itemType]
	if handler then
		RightClickFrame.Use.Text = handler(itemData, Inventory.getEquipped())
		checkWeapon(itemData)
		RightClickFrame.Visible = true
		RightClickFrame.Position = UDim2.new(0, center.X, 0, center.Y)
	end
end

local function setButtonRadial()
	local selectedItem = Inventory.getSelectedItem()
	if selectedItem then
		createRightClickMenu(selectedItem, Inventory.getItem(selectedItem.Name))
	end
end

local function createItemButton(itemData)
	local itemButton = SampleButton:Clone()
	itemButton.ItemName.Text = itemData.itemName
	if itemData.itemType == "Weapon" and (itemData["dot"] or itemData["Powerup"]) then
		itemButton.ItemName.TextColor3 = CONFIG.STATE_COLOR
	end
	itemButton.Name = itemData.UUID
	itemButton.Visible = true
	Utils.displayQuantity(itemData, itemButton)
	Utils.setItemImage(itemData, itemButton)
	Utils.setColoredItemText(itemData, itemButton)
	itemButton.Parent = ItemScrollFrame
	RotationModule.rotateItemIcon(itemButton, "INVENTORY_MODEL", InventoryFrame)
	ItemButtonReference[itemData.UUID] = itemButton
	DragDropModule.setButton(itemButton, itemData, InventoryController.selectItem, "Item")
	itemButton.MouseButton2Click:Connect(function()
		InventoryController.RCSelectItem(itemButton, itemData)
	end)
	return itemButton
end

local function toggleInventory()
	InventoryFrame.Visible = not InventoryFrame.Visible
	local isOpen = InventoryFrame.Visible
	if isOpen then
		beginRotation()
	else
		RightClickFrame.Visible = false
	end
	InventoryController.setOpenBinds(isOpen)
end

local function addItem(item, total)
	setCapacityBar(total)
	createItemButton(item)
end

local function removeItem(itemUUID, total)
	setCapacityBar(total)
	local itemButton = ItemButtonReference[itemUUID]
	if itemButton then
		itemButton:Destroy()
		ItemButtonReference[itemUUID] = nil
	end
end

local function updateCash(cash)
	CashLabel.Text = "Cash: " .. cash
end

local function updateEquipped(equipmentIndex, itemUUID, currentEquipped) -- equipped still rotates when inventoryframe is off its fine though
	if currentEquipped ~= -1 then
		local itemButton = EquippedButtons[currentEquipped]
		if itemButton then
			itemButton.Equipped.Enabled = false
		end
		if itemUUID == -1 then
			local button = EquipmentFrame:FindFirstChild(Inventory.EquipmentIndex[equipmentIndex])
			if button then
				button.Image = ""
			end
		end
	end
	if itemUUID ~= -1 then 
		local itemButton = ItemScrollFrame:FindFirstChild(itemUUID)
		if itemButton then
			itemButton.Equipped.Enabled = true
			EquippedButtons[itemUUID] = itemButton
		end
		local item = Inventory.getItem(itemUUID)
		if item then
			local button = EquipmentFrame:FindFirstChild(Inventory.EquipmentIndex[equipmentIndex])
			if button then
				Utils.setItemImage(item, button)
				Utils.setColoredItemText(item, button)
				local imageID = button.Image
				RotationModule.rotateItemIcon(button, "HOTBAR_MODEL", button, imageID)
			end
		end
	end
end

local function updateQuantity(itemUUID, itemData, quantity)
	local button = ItemButtonReference[itemUUID] 
	if button then
		Utils.displayQuantity(itemData, button)
	end
	redisplayValues(itemData)
end

local function deselectItem(previousButton)
	if previousButton then
		previousButton.BackgroundColor3 = CONFIG.INVENTORY_NORMAL_COLOR
		InfoFrame.Visible = false
		ButtonsFrame.Visible = false
	end
end

local function selectItem(itemData, itemButton, previousButton)
	if previousButton then
		previousButton.BackgroundColor3 = CONFIG.INVENTORY_NORMAL_COLOR
	end
	itemButton.BackgroundColor3 = CONFIG.INVENTORY_SELECTED_COLOR
	InfoFrame.Visible = true	
	ButtonsFrame.Visible = true
	displayValues(itemData, InfoFrame)
	local text = CONFIG.USE_TEXT[itemData.itemType]
	if text then
		ButtonsFrame.Equip.Text = text(itemData, Inventory.getEquipped())
		return
	end
end

local function examineItem(itemData, frame, houseExamine)
	Utils.clearFrame(frame, "TextLabel")
	frame.CanvasPosition = Vector2.new(0, 0)
	createItemLabels(itemData, frame)
	if houseExamine then
		Utils.createDisplayLabel(frame, "ItemOwner", string.format("Item Owner : %s", itemData.ItemOwner))
	end
end

for _, EquipmentButton in ipairs(EquipmentFrame:GetChildren()) do
	if EquipmentButton:IsA("ImageButton") then
		EquipmentButton.Activated:Connect(function()
			InventoryController.selectEquipmentButton(EquipmentButton)
		end)
	end
end

local function checkModalBind(input)
	if not Utils.checkModalButton("InventoryMenu", RightClickFrame, "TextButton", input) then
		RightClickFrame.Visible = false
		InventoryController.removeRCSelect()
	end
end

InventoryFrame.Exit.Activated:Connect(function()
	RightClickFrame.Visible = false
	InventoryFrame.Visible = false
	InventoryController.setOpenBinds(false)
end)

ButtonsFrame.Equip.Activated:Connect(function()
	InventoryController.useItem(false)
end)

ButtonsFrame.Drop.Activated:Connect(function()
	InventoryController.dropItem(false)
end)

ButtonsFrame.Break.Activated:Connect(function()
	InventoryController.promptDestroy(false)
end)

--ButtonsFrame.Repair.Activated:Connect(function()
--	repairItem()
--end)

RightClickFrame.Use.Activated:Connect(function()
	RightClickFrame.Visible = false
	InventoryController.useItem(true)
end)

RightClickFrame.Examine.Activated:Connect(function()
	RightClickFrame.Visible = false
	InventoryController.ExamineItem()
end)

RightClickFrame.Drop.Activated:Connect(function()
	RightClickFrame.Visible = false
	InventoryController.dropItem(true)
end)

RightClickFrame.Delete.Activated:Connect(function()
	RightClickFrame.Visible = false
	InventoryController.promptDestroy(true)
end)

Inventory.Events:Connect("ToggleOpen", toggleInventory)
Inventory.Events:Connect("AddItem", addItem)
Inventory.Events:Connect("UpdateCash", updateCash)
Inventory.Events:Connect("UpdateEquipped", updateEquipped)
Inventory.Events:Connect("RemoveItem", removeItem)
Inventory.Events:Connect("UpdateQuantity", updateQuantity)
Inventory.Events:Connect("RemoveSelectedItem", deselectItem)
Inventory.Events:Connect("AddSelectedItem", selectItem)
Inventory.Events:Connect("AddRCSelectedItem", createRightClickMenu)
Inventory.Events:Connect("Examine", examineItem)
Inventory.Events:Connect("SetButtonRadial", setButtonRadial)
Inventory.Events:Connect("CloseRadialMenu", checkModalBind)

return InventoryGUI



local Inventory = {}

local Signal = require(script.Parent.Parent.SignalModule)

local Events = Signal.new()

local Data = {
	Inventory = {
		Armor = {}, 
		Weapon = {},
		Medical = {},
		Consumable = {},
		Tool = {},
		Resource = {}, 
		Powerup = {},
		Component = {}, 
		Special = {}
	},
	UUIDInventory = {},
	Cash = 0,
	Total = 0,
	EquippedItems = {},
	SelectedItem = nil,
	RCSelectedItem = nil, 
}

local EQUIPMENT_INDEX = {
	[1] = "Weapon",
	[2] = "Helmet",
	[3] = "Chest",
	[4] = "LArm",
	[5] = "RArm",
	[6] = "Legs",
	[7] = "Feet"
}

local ITEM_TO_INDEX = {
	Weapon = 1,
	Helmet = 2,
	Chest = 3,
	LArm = 4,
	RArm = 5,
	Legs = 6,
	Feet = 7
}

function Inventory.addItem(item)
	if Data.Inventory[item.itemType] then
		Data.Inventory[item.itemType][item.UUID] = item
		Data.UUIDInventory[item.UUID] = item
		Data.Total += 1
		Events:Fire("AddItem", item, Data.Total)
	end
end

function Inventory.addSelectedItem(itemButton, itemData)
	local previousButton = Inventory.getSelectedItem()
	Data.SelectedItem = itemButton
	Events:Fire("AddSelectedItem", itemData, itemButton, previousButton)
end

function Inventory.addRCSelectedItem(itemButton, itemData)
	Data.RCSelectedItem = itemButton
	Events:Fire("AddRCSelectedItem", itemButton, itemData)
end

function Inventory.removeItem(itemType, itemUUID)
	local item = Inventory.getItem(itemUUID)
	if Data.Inventory[itemType] and item then
		Data.Inventory[itemType][itemUUID] = nil
		Data.UUIDInventory[itemUUID] = nil
		Data.Total -= 1
		Events:Fire("RemoveItem", itemUUID, Data.Total)
		local itemIndex = ITEM_TO_INDEX[item.itemType] or ITEM_TO_INDEX[item.armorType]
		if itemIndex then
			Inventory.updateEquipped(itemIndex, itemUUID)
		end
		local selectedItem = Inventory.getSelectedItem()
		if selectedItem and selectedItem.Name == itemUUID then
			Inventory.removeSelectedItem()
		end
	end
end

function Inventory.removeSelectedItem()
	local previousButton = Inventory.getSelectedItem()
	Data.SelectedItem = nil
	Events:Fire("RemoveSelectedItem", previousButton)
end

function Inventory.removeSelectedRCItem()
	Data.RCSelectedItem = nil
end

function Inventory.updateCash(cash)
	Data.Cash = cash
	Events:Fire("UpdateCash", cash)
end

function Inventory.updateQuantity(itemType, itemUUID, quantity)
	local item = Inventory.getItem(itemUUID)
	if Data.Inventory[itemType] and item then
		Data.Inventory[itemType][itemUUID].quantity = quantity
		Data.UUIDInventory[itemUUID].quantity = quantity
		Events:Fire("UpdateQuantity", itemUUID, item, quantity)
	end
end

function Inventory.updateEquipped(index, itemUUID)
	local currentEquipped = Data.EquippedItems[index]
	Data.EquippedItems[index] = itemUUID
	Events:Fire("UpdateEquipped", index, itemUUID, currentEquipped)
end

function Inventory.getItem(itemUUID)
	return Data.UUIDInventory[itemUUID]
end

function Inventory.getEquipped()
	return Data.EquippedItems
end

function Inventory.getWeapon()
	return Data.UUIDInventory[Data.EquippedItems[1]]
end

function Inventory.getSelectedItem()
	return Data.SelectedItem
end

function Inventory.getRCSelectedItem()
	return Data.RCSelectedItem
end

function Inventory.getEquippedSlot(index)
	return Data.EquippedItems[index]
end

function Inventory.validateCash(cash)
	local cash = tonumber(cash)
	if not cash or cash ~= cash or cash == math.huge or cash == -math.huge or cash < 0 then
		return false
	end
	return cash
end


Inventory.Events = Events
Inventory.EquipmentIndex = EQUIPMENT_INDEX
Inventory.itemToIndex = ITEM_TO_INDEX

return Inventory

