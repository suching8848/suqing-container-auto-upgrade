-- RaccoonCity owns its native sandbox capacities. Never change its physical
-- item-container capacity or the Workshop wrapper. This final narrow layer
-- observes valid owned applied values and otherwise delegates the whole chain.
require "SuQingContainerUpgradeAuto/Core"
local C = SuQingContainerUpgradeAuto
C.Dynamic = C.Dynamic or {}
local D = C.Dynamic

D.types = {
    ["Base.ResidentEvilBackPack"] = { option = "ResidentEvilBackpackCapacity", default = 49 },
    ["Base.ResidentEvilSuspenders"] = { option = "ResidentEvilSuspendersCapacity", default = 10 },
}

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == value
        and value >= minimum and value <= maximum and value == math.floor(value)
end

function D.IsDynamic(item)
    return item ~= nil and instanceof(item, "InventoryContainer")
        and D.types[item:getFullType()] ~= nil
end

-- Read the original mod's business baseline, never the native getter which
-- clamps an inventory container to50. Missing SandboxVars use original defaults.
function D.NativeCapacity(item, fallback)
    local policy = D.IsDynamic(item) and D.types[item:getFullType()]
    if not policy then return fallback end
    local value = SandboxVars and SandboxVars[policy.option]
    if not integer(value, 1, 1000) then value = policy.default end
    return value
end

function D.GetEffectiveCapacity(item, character)
    if not C.IsSinglePlayer() or not D.IsDynamic(item) or not C.IsSupported(item)
        or type(C.GetAppliedStats) ~= "function" then return nil end
    local ok, applied = pcall(C.GetAppliedStats, item)
    local owned = ok and integer(applied, 1, 100000)
    local capacity = D.NativeCapacity(item)
    if owned then capacity = math.max(capacity, applied) end
    -- These are the same ceil rules and trait precedence as RaccoonCity's
    -- BackpackCapacityOverride.lua. Do not multiply an already adjusted value.
    if character then
        if character:hasTrait(CharacterTrait.ORGANIZED) then
            return math.ceil(capacity * 1.3), owned
        elseif character:hasTrait(CharacterTrait.DISORGANIZED) then
            return math.ceil(capacity * 0.7), owned
        end
    end
    return capacity, owned
end

function D.Wrap(original)
    return function(container, character, ...)
        local item = container:getContainingItem()
        if item and D.IsDynamic(item) then
            local capacity, owned = D.GetEffectiveCapacity(item, character)
            if owned and capacity ~= nil then return capacity end
        end
        return original(container, character, ...)
    end
end

function D.IsReady()
    return D.installedFunction ~= nil and C.IsSinglePlayer()
end

function D.Install()
    if not C.IsSinglePlayer() or not __classmetatables or not ItemContainer then return false end
    local meta = __classmetatables[ItemContainer.class]
    local index = meta and meta.__index
    local original = index and index.getEffectiveCapacity
    if not original then return false end
    if original == D.installedFunction then return true end
    local wrapper = D.Wrap(original)
    index.getEffectiveCapacity = wrapper
    D.installedFunction = wrapper
    return true
end

-- loadModAfter=RaccoonCityB42 is required so its original event installs first.
-- Reinstallation is idempotent for our current layer, but can follow a freshly
-- installed native layer at a later native startup event without polling.
Events.OnGameStart.Add(D.Install)
Events.OnServerStarted.Add(D.Install)
return D
