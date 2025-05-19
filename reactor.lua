local t = component.proxy(component.list("transposer")())
local r = component.proxy(component.list("redstone")())

DOWN, UP, BACK, FRONT, RIGHT, LEFT  = 0, 1, 2, 3, 4, 5
local REDSTONE_CONTROL_SIDE = DOWN
local MAX_DMG = 0.75
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
      for option in options:gmatch("([^|]*)") do
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
local sysSide, reactorSide, icSide
for s = 0, 5 do
  local n = t.getInventoryName(s)
  if n == "tile.appliedenergistics2.BlockInterface" then sysSide = s end
  if n == "blockReactorChamber" then reactorSide = s
  elseif r.getComparatorInput(s) > 0 then icSide = s end
end

-- Round-robin indices for coolant import and item export
local nextImport, nextExport = 0, 0

---Import item from system to reactor
---@param index integer reactor slot index (0-based)
---@param type boolean true = coolant, false = fuel
---@return boolean success
local function import(index, type)
  nextImport = (nextImport + 1) % 3
  return t.transferItem(sysSide, reactorSide, 1, type and nextImport + 1 or 4, index + 1)
end

---Export item from reactor to system
---@param index integer reactor slot index (0-based)
local function export(index)
  nextExport = (nextExport + 1) % 4
  t.transferItem(reactorSide, sysSide, 1, index + 1, nextExport + 5)
end

local prevState

---Set redstone state (only if changed)
---@param state integer redstone level to set
local function setState(state)
  if state ~= prevState then
    prevState = state
    r.setOutput(icSide, state)
  end
end

-- Main loop
local nextTick = 0
local cMissing, reactorItems, slept, item, tick
while true do
  t.getInventoryName(0)
  tick = os.time() * 1000 / 60 / 60
  if tick >= nextTick or math.abs(tick - nextTick) > 40 then
    nextTick = tick - (tick % 20) + 24
    cMissing = 0
    reactorItems = t.getAllStacks(reactorSide).getAll()
    slept = false
    for i = 0, 5 * 9 + 8 do
      item = reactorItems[i]
      if not item or not next(item) or not item.label then
        if COOLANT_SLOTS[i] then
          setState(OFF)
          cMissing = cMissing + 1 - import(i, COOLANT)
        else
          import(i, FUEL)
        end
      elseif COOLANT_SLOTS[i] then
        if COOLANTS[item.label] then
          if item.damage / item.maxDamage > MAX_DMG then
            setState(OFF)
            if not slept then
              for _ = 1, 6 do t.getInventoryName(0) end
              slept = true
            end
            export(i)
            cMissing = cMissing + 1 - import(i, COOLANT)
          end
        else
          setState(OFF)
          export(i)
          cMissing = cMissing + 1 - import(i, COOLANT)
        end
      elseif not FUELS[item.label] then
        export(i)
        import(i, FUEL)
      end
    end
    if cMissing == 0 and r.getInput(REDSTONE_CONTROL_SIDE) > 0 then
      setState(PULSE)
      setState(ON)
    end
  end
end
