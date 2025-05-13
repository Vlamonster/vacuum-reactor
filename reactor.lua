local transposer = component.proxy(component.list("transposer")())
local redstone = component.proxy(component.list("redstone")())

DOWN, UP, BACK, FRONT, RIGHT, LEFT  = 0, 1, 2, 3, 4, 5
local REDSTONE_CONTROL_SIDE = DOWN
local MAX_DAMAGE = 75
local COOLANT, FUEL = true, false
local ON, PULSE, OFF = 15, 14, 0

local COOLANT_SLOTS = {
  0*9+0, 0*9+4, 0*9+7,
  1*9+2, 1*9+7,
  2*9+0, 2*9+5,
  3*9+3, 3*9+8,
  4*9+1, 4*9+6,
  5*9+1, 5*9+4, 5*9+8
}

local COOLANTS = {
  "[10k|30k|60k] Coolant Cell",
  "[60k|180k|360k] He Coolant Cell",
  "[60k|180k|360k] NaK Coolant Cell",
  "[180k|360k|540k|1080k] Sp Coolant Cell"
}

local FUELS = {
  "[|Dual |Quad ]Fuel Rod (Thorium)",
  "[|Dual |Quad ]Fuel Rod (Uranium)",
  "[|Dual |Quad ]Fuel Rod (Mox)",
  "[|Dual |Quad ]Fuel Rod (Tiberium)",
  "[|Dual |Quad ]Fuel Rod (High Density Uranium)",
  "[|Dual |Quad ]Fuel Rod (High Density Plutonium)",
  "[|Dual |Quad ]Fuel Rod (Excited Uranium)",
  "[|Dual |Quad ]Fuel Rod (Excited Plutonium)",
  "[|Dual |Quad ]Fuel Rod (Naquadah)",
  "\"The Core\" Cell"
}

--- Convert list to lookup table
---@param list table
---@return table
local function toMap(list)
  local result = {}
  for _, value in ipairs(list) do
    if type(value) == "string" and value:find("%[") then
      local prefix, options, suffix = value:match("^(.-)%[(.-)%](.-)$")
      for option in options:gmatch("[^|]+") do
        result[prefix .. option .. suffix] = true
      end
    else
      result[value] = true
    end
  end
  return result
end

COOLANT_SLOTS, COOLANTS, FUELS = toMap(COOLANT_SLOTS), toMap(COOLANTS), toMap(FUELS)

-- Detect system, reactor and IC side
local systemSide, reactorSide, icSide
for s = 0, 5 do
  local n = transposer.getInventoryName(s)
  if n == "tile.appliedenergistics2.BlockInterface" then systemSide = s end
  if n == "blockReactorChamber" then reactorSide = s
  elseif redstone.getComparatorInput(s) > 0 then icSide = s end
end

-- Round-robin indices for coolant import and item export
local nextImport, nextExport = 0, 0

---Import item from system to reactor
---@param index integer reactor slot index (0-based)
---@param type boolean true = coolant, false = fuel
---@return boolean success
local function import(index, type)
  nextImport = (nextImport + 1) % 3
  return transposer.transferItem(systemSide, reactorSide, 1, type and nextImport + 1 or 4, index + 1)
end

---Export item from reactor to system
---@param index integer reactor slot index (0-based)
local function export(index)
  nextExport = (nextExport + 1) % 4
  transposer.transferItem(reactorSide, systemSide, 1, index + 1, nextExport + 5)
end

local prevState

---Set redstone state (only if changed)
---@param state integer redstone level to set
local function setRedstoneState(state)
  if state ~= prevState then
    prevState = state
    redstone.setOutput(icSide, state)
  end
end

-- Main loop
local coolantMissing, reactorItems, slept, item
while true do
  coolantMissing = 0
  reactorItems = transposer.getAllStacks(reactorSide).getAll()
  slept = false
  for index = 0, 5 * 9 + 8 do
    item = reactorItems[index]
    if not item or not next(item) or not item.label then
      if COOLANT_SLOTS[index] then
        setRedstoneState(OFF)
        coolantMissing = coolantMissing + 1 - import(index, COOLANT)
      else
        import(index, FUEL)
      end
    elseif COOLANT_SLOTS[index] then
      if COOLANTS[item.label] then
        if item.damage > MAX_DAMAGE then
          setRedstoneState(OFF)
          if not slept then
            for _ = 1, 6 do transposer.getInventoryName(0) end
            slept = true
          end
          export(index)
          coolantMissing = coolantMissing + 1 - import(index, COOLANT)
        end
      else
        setRedstoneState(OFF)
        export(index)
        coolantMissing = coolantMissing + 1 - import(index, COOLANT)
      end
    elseif not FUELS[item.label] then
      export(index)
      import(index, FUEL)
    end
  end
  if coolantMissing == 0 and redstone.getInput(REDSTONE_CONTROL_SIDE) > 0 then
    setRedstoneState(PULSE)
    setRedstoneState(ON)
  end
end
