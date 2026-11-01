-- Same-instance container upgrades. No tick handler, world scan or script-item edits.
SuQingContainerUpgradeAuto = SuQingContainerUpgradeAuto or {}
local C = SuQingContainerUpgradeAuto
if C.loaded then return C end
C.loaded = true
C.version = "0.1.0-test"
C.modDataKey = "SuQingContainerUpgradeAuto"
require "SuQingContainerUpgradeAuto/Compatibility"
-- The build generates both these sets and native recipe inputs from one audited
-- registry. An unknown type is never admitted just because it is a container.
local compatibility = SuQingContainerUpgradeAutoCompatibility
assert(type(compatibility) == "table" and compatibility.schema == 1,
    "SuQingContainerUpgradeAuto compatibility registry is missing or unsupported")
C.compatibility = compatibility
C.supported = compatibility.supported
C.retired = compatibility.retired
C.tiers = {
    { capacity = 12, weightReduction = 90, cloth = 4, leather = 0, thread = 2, skill = 0 },
    { capacity = 20, weightReduction = 93, cloth = 6, leather = 2, thread = 4, skill = 1 },
    { capacity = 30, weightReduction = 95, cloth = 10, leather = 4, thread = 6, skill = 2 },
    { capacity = 40, weightReduction = 97, cloth = 14, leather = 6, thread = 8, skill = 3 },
    { capacity = 49, weightReduction = 99, cloth = 20, leather = 10, thread = 10, skill = 4 },
}
C.Position = C.Position or { active = {} }
C.Position.characters = C.Position.characters or {}

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

C.profileVersions = { existing_v013 = 1, standard_light = 1, heavy_native_cap = 1,
    position_pair = 1, restricted_webbing = 1, restricted_ammo = 1,
    mod_container = 1, native_capacity = 1, dynamic_capacity = 1,
    hybrid_container = 1, restricted_holster = 1 }

local function profileOf(item)
    return item and C.compatibility.profiles[item:getFullType()]
end

local function preservePhysicalCapacity(item)
    local profile = profileOf(item)
    return profile == "native_capacity" or profile == "dynamic_capacity"
end

-- This accessor deliberately never calls GetState: Dynamic's narrow native
-- capacity wrapper also uses it, so recursion here would break room checks.
function C.GetAppliedStats(item)
    local record = C.GetRecord(item)
    if not C.IsValidRecord(record) then return nil end
    if record.schema == 2 then
        if record.profile ~= profileOf(item) then return nil end
        return record.appliedCapacity, record.appliedWeightReduction
    end
    local tier = C.tiers[record.level]
    return math.max(record.baseCapacity, tier.capacity), math.max(record.baseWeightReduction, tier.weightReduction)
end

function C.ReadCapacity(item)
    if profileOf(item) == "dynamic_capacity" and C.Dynamic then
        local capacity = C.Dynamic.GetEffectiveCapacity(item, nil)
        if capacity ~= nil then return capacity end
    end
    return item:getInventory():getCapacity()
end

function C.GetRestoreCapacity(item, record)
    if profileOf(item) == "dynamic_capacity" and C.Dynamic then
        return C.Dynamic.NativeCapacity(item, record.baseCapacity)
    end
    if preservePhysicalCapacity(item) then return item:getInventory():getCapacity() end
    return record.baseCapacity
end

function C.GetNativeCapacityLimit(item)
    local ok, weight = pcall(function() return item:getActualWeight() end)
    if not ok or type(weight) ~= "number" or weight ~= weight or weight < 0 or weight >= 50 then
        return nil, "invalid_weight"
    end
    local limit = math.floor(50 - weight)
    if limit < 1 then return nil, "capacity_limit" end
    return limit
end

-- One target calculation for eligibility, equivalent tiers, preflight and commit.
-- Audited heavy/mod/hybrid profiles clip nominal capacity; the v0.1.4
-- light/legacy contract stays fixed. Original weight is never changed.
function C.GetTierTarget(item, tierIndex)
    if not integer(tierIndex, 1, #C.tiers) then return nil, "invalid_tier" end
    local profile = item and C.compatibility.profiles[item:getFullType()]
    local profileVersion = profile and C.profileVersions[profile]
    if not profileVersion then return nil, "unsupported_profile" end
    local limit, reason = C.GetNativeCapacityLimit(item)
    if not limit then return nil, reason end
    local tier = C.tiers[tierIndex]
    return {
        capacity = profile == "native_capacity" and C.ReadCapacity(item)
            or ((profile == "heavy_native_cap" or profile == "mod_container" or profile == "hybrid_container")
                and math.min(tier.capacity, limit) or tier.capacity),
        weightReduction = tier.weightReduction, nativeLimit = limit,
        profile = profile, profileVersion = profileVersion,
    }
end

function C.IsSinglePlayer()
    if type(getActivatedMods) == "function" then
        local mods = getActivatedMods()
        if mods and mods:contains("SuQingContainerUpgrade_4221") then return false end
    end
    return not (type(isClient) == "function" and isClient())
        and not (type(isServer) == "function" and isServer())
end

function C.IsSupported(item)
    return item ~= nil and instanceof(item, "InventoryContainer")
        and C.Auto ~= nil and C.Auto.ready and C.Auto.EnsureItem(item, false)
        and C.supported[item:getFullType()] == true and item:getInventory() ~= nil
end

function C.IsManaged(item)
    return item ~= nil and instanceof(item, "InventoryContainer")
        and C.Auto ~= nil and C.Auto.EnsureItem(item, true)
        and (C.supported[item:getFullType()] == true or C.retired[item:getFullType()] == true)
        and item:getInventory() ~= nil
end

function C.GetRecord(item)
    if not C.IsManaged(item) then return nil end
    return item:getModData()[C.modDataKey]
end

function C.IsValidRecord(record)
    if type(record) ~= "table" or not integer(record.baseCapacity, 0, 100000)
        or not integer(record.baseWeightReduction, 0, 100)
        or not integer(record.level, 1, #C.tiers) then return false end
    -- Old records retain their original fixed-target meaning; no eager migration.
    if record.schema == 1 then return true end
    return record.schema == 2 and C.profileVersions[record.profile] == record.profileVersion
        and record.profileVersion == 1
        and integer(record.nativeLimit, 1, 50)
        and integer(record.appliedCapacity, record.baseCapacity, 100000)
        and integer(record.appliedWeightReduction, record.baseWeightReduction, 100)
        and record.appliedWeightReduction >= C.tiers[record.level].weightReduction
        and (record.profile == "heavy_native_cap"
            and record.appliedCapacity >= math.min(C.tiers[record.level].capacity, record.nativeLimit)
            and record.appliedCapacity <= record.nativeLimit
            or record.profile == "native_capacity"
            or (record.profile == "mod_container" or record.profile == "hybrid_container")
                and record.appliedCapacity >= math.min(C.tiers[record.level].capacity, record.nativeLimit)
            or record.profile ~= "heavy_native_cap" and record.profile ~= "mod_container"
                and record.profile ~= "hybrid_container" and record.profile ~= "native_capacity"
                and record.appliedCapacity >= C.tiers[record.level].capacity)
end

function C.GetState(item)
    if not C.IsManaged(item) then return nil end
    local capacity = C.ReadCapacity(item)
    local weightReduction = item:getWeightReduction()
    if not integer(capacity, 0, 100000) or not integer(weightReduction, 0, 100) then return nil end
    local retired = C.retired[item:getFullType()] == true
    local equivalentLevel, targetError = 0, nil
    for index, tier in ipairs(C.tiers) do
        local target, reason
        if not retired then target, reason = C.GetTierTarget(item, index) end
        if not retired and not target then targetError = reason end
        -- Even with bad foreign weight metadata, old records remain readable for
        -- zero-cost restoration. An invalid target only blocks paid upgrades.
        target = target or tier
        if capacity >= target.capacity and weightReduction >= target.weightReduction then equivalentLevel = index end
    end
    local record = C.GetRecord(item)
    local valid = C.IsValidRecord(record)
    local profileMismatch = valid and record.schema == 2
        and record.profile ~= C.compatibility.profiles[item:getFullType()]
    -- A native bag meeting tier I is not a bag which has actually been upgraded.
    -- Keep completed progress separate from current/native equivalent specs.
    local level = valid and record.level or equivalentLevel
    local inconsistent = false
    if valid then
        if record.schema == 1 then
            local tier = C.tiers[record.level]
            inconsistent = capacity < math.max(record.baseCapacity, tier.capacity)
                or weightReduction < math.max(record.baseWeightReduction, tier.weightReduction)
        else
            -- Saved applied values are historical facts. Never recompute them
            -- from today's weight/profile when deciding if an old record broke.
            inconsistent = capacity < record.appliedCapacity or weightReduction < record.appliedWeightReduction
        end
    end
    local reached = math.max(level, equivalentLevel)
    return {
        capacity = capacity, weightReduction = weightReduction, level = level,
        equivalentLevel = equivalentLevel,
        nextLevel = not retired and not targetError and not profileMismatch and reached < #C.tiers and reached + 1 or nil,
        retired = retired,
        targetError = targetError,
        profileMismatch = not not profileMismatch,
        upgraded = valid, recordedLevel = valid and record.level or nil,
        corruptRecord = record ~= nil and not valid,
        inconsistent = inconsistent,
        baseCapacity = valid and record.baseCapacity or nil,
        baseWeightReduction = valid and record.baseWeightReduction or nil,
    }
end

local function checkTarget(item, character, allowInconsistent, allowRetired)
    if not C.IsSinglePlayer() then return false, "multiplayer" end
    if not C.IsSupported(item) and not (allowRetired and C.IsManaged(item)) then return false, "unsupported" end
    if not character or not character.getInventory then return false, "no_character" end
    if item:getContainer() ~= character:getInventory() then return false, "not_carried" end
    if character:isEquipped(item) or character:getPrimaryHandItem() == item
        or character:getSecondaryHandItem() == item then return false, "equipped" end
    if item:getInventory():getItems():size() ~= 0 then return false, "not_empty" end
    -- Hybrid bags have separate physical fluid storage. Never change that
    -- component or its contents; require it empty before any paid/restore action.
    if item.getFluidContainer then
        local fluid = item:getFluidContainer()
        if fluid then
            local amount = fluid:getAmount()
            if type(amount) ~= "number" or amount ~= amount or amount < 0 then return false, "invalid_fluid" end
            if amount > 0 then return false, "fluid_not_empty" end
        end
    end
    local state = C.GetState(item)
    if not state or state.corruptRecord then return false, "invalid_record" end
    if state.profileMismatch and not allowInconsistent then return false, "profile_mismatch" end
    if state.inconsistent and not allowInconsistent then return false, "inconsistent" end
    return true, nil, state
end

function C.CanUpgrade(item, character, tierIndex)
    if not integer(tierIndex, 1, #C.tiers) then return false, "invalid_tier" end
    local ok, reason, state = checkTarget(item, character)
    if not ok then return false, reason end
    local target, targetReason = C.GetTierTarget(item, tierIndex)
    if not target then return false, targetReason end
    if target.profile == "dynamic_capacity" and (not C.Dynamic or not C.Dynamic.IsReady()) then
        return false, "dynamic_not_ready"
    end
    if state.nextLevel ~= tierIndex then return false, "wrong_tier" end
    local tier = C.tiers[tierIndex]
    if tier.skill > 0 and character:getPerkLevel(Perks.Tailoring) < tier.skill then
        return false, "skill"
    end
    local capacity = math.max(state.capacity, target.capacity)
    if target.profile ~= "dynamic_capacity" and target.profile ~= "native_capacity" and capacity > target.nativeLimit
        and (target.profile == "heavy_native_cap" or capacity > state.capacity) then return false, "capacity_limit" end
    return true, nil, state, target
end

function C.CanRestore(item, character)
    -- A valid original-stat record can also repair a later foreign stat reset.
    local ok, reason, state = checkTarget(item, character, true, true)
    if not ok then return false, reason end
    if not state.upgraded then return false, "not_upgraded" end
    return true, nil, state
end

-- Every kept input is inspected. Ambiguity must not select a random bag.
function C.FindTarget(recipeData)
    if not recipeData or not recipeData.getAllKeepInputItems then return nil, "no_recipe_data" end
    local kept = recipeData:getAllKeepInputItems()
    if not kept then return nil, "no_recipe_data" end
    local target
    for index = 0, kept:size() - 1 do
        local item = kept:get(index)
        if C.IsManaged(item) then
            if target ~= nil and target ~= item then return nil, "multiple_targets" end
            target = item
        end
    end
    if not target then return nil, "no_target" end
    return target
end

function C.SetStats(item, capacity, weightReduction)
    local beforeCapacity = item:getInventory():getCapacity()
    local beforeReduction = item:getWeightReduction()
    local keepCapacity = preservePhysicalCapacity(item)
    local changedCapacity = false
    local ok, message = pcall(function()
        -- The native getter clamps raw 60 to50. A nominal no-op setter would
        -- silently destroy that original raw value. These audited policies must
        -- never write capacity, including probes, rollback and restoration.
        if not keepCapacity and capacity ~= beforeCapacity then
            changedCapacity = true
            item:setCapacity(capacity)
        end
        item:setWeightReduction(weightReduction)
        if item:getInventory():getCapacity() ~= (keepCapacity and beforeCapacity or capacity)
            or item:getWeightReduction() ~= weightReduction then
            error("Container setters did not retain the requested values")
        end
    end)
    if not ok then
        -- Keep both fields consistent if a foreign override or setter fails.
        if changedCapacity then pcall(function() item:setCapacity(beforeCapacity) end) end
        pcall(function() item:setWeightReduction(beforeReduction) end)
        return false, tostring(message)
    end
    return true
end

function C.CaptureTarget(item)
    local state = C.GetState(item)
    if not state then return nil end
    return { item = item, capacity = state.capacity, weightReduction = state.weightReduction,
        record = C.GetRecord(item) }
end

function C.RestoreTarget(snapshot)
    if not snapshot then return false end
    local ok, message = C.SetStats(snapshot.item, snapshot.capacity, snapshot.weightReduction)
    if ok then snapshot.item:getModData()[C.modDataKey] = snapshot.record end
    return ok, message
end

-- Check setter compatibility before the native crafting engine can consume cloth
-- or leather. This is synchronous and restores the exact original stats/record.
function C.ProbeChange(item, character, mode)
    local ok, reason, state, target
    if mode == "restore" then ok, reason, state = C.CanRestore(item, character)
    else ok, reason, state, target = C.CanUpgrade(item, character, mode) end
    if not ok then return false, reason end
    local snapshot = C.CaptureTarget(item)
    local capacity, reduction
    if mode == "restore" then
        capacity, reduction = C.GetRestoreCapacity(item, C.GetRecord(item)), state.baseWeightReduction
    else
        capacity = math.max(state.capacity, target.capacity)
        reduction = math.max(state.weightReduction, target.weightReduction)
    end
    local changed, message = C.SetStats(item, capacity, reduction)
    local restored, restoreMessage = C.RestoreTarget(snapshot)
    if not changed or not restored then
        print("[SuQingContainerUpgradeAuto] setter probe rejected: " .. tostring(message or restoreMessage))
        return false, restored and "setter" or "rollback"
    end
    return true, nil, snapshot, capacity, reduction
end

function C.Upgrade(recipeData, character, tierIndex)
    local item, reason = C.FindTarget(recipeData)
    if not item then return false, reason end
    local ok, errorCode, state, target = C.CanUpgrade(item, character, tierIndex)
    if not ok then return false, errorCode end
    local capacity = math.max(state.capacity, target.capacity)
    local reduction = math.max(state.weightReduction, target.weightReduction)
    local record = C.GetRecord(item)
    local newRecord = {
        schema = 2, level = tierIndex, version = C.version, fullType = item:getFullType(),
        profile = target.profile, profileVersion = target.profileVersion,
        nativeLimit = target.nativeLimit,
        appliedCapacity = capacity, appliedWeightReduction = reduction,
        baseCapacity = state.upgraded and record.baseCapacity or state.capacity,
        baseWeightReduction = state.upgraded and record.baseWeightReduction or state.weightReduction,
    }
    if not C.Refund then return false, "refund_unavailable" end
    local copied, copyReason = C.Refund.CopyLedger(record, newRecord)
    if not copied then return false, copyReason end
    local changed, message = C.SetStats(item, capacity, reduction)
    if not changed then return false, message end
    item:getModData()[C.modDataKey] = newRecord
    if item.setDrawDirty then pcall(function() item:setDrawDirty(true) end) end
    return true, item
end

function C.Restore(recipeData, character)
    local item, reason = C.FindTarget(recipeData)
    if not item then return false, reason end
    local ok, errorCode = C.CanRestore(item, character)
    if not ok then return false, errorCode end
    local record = C.GetRecord(item)
    local changed, message = C.SetStats(item, C.GetRestoreCapacity(item, record), record.baseWeightReduction)
    if not changed then return false, message end
    item:getModData()[C.modDataKey] = nil
    if item.setDrawDirty then pcall(function() item:setDrawDirty(true) end) end
    return true, item
end

local function test(item, character, tierIndex)
    if not C.IsSinglePlayer() then return false end
    -- OnTest also receives the needle, cloth, leather and thread inputs.
    if not instanceof(item, "InventoryContainer") then return true end
    if not C.IsManaged(item) then return false end
    return C.CanUpgrade(item, character, tierIndex)
end

function C.Test1(item, character) return test(item, character, 1) end
function C.Test2(item, character) return test(item, character, 2) end
function C.Test3(item, character) return test(item, character, 3) end
function C.Test4(item, character) return test(item, character, 4) end
function C.Test5(item, character) return test(item, character, 5) end
function C.Create1(data, character) return C.Upgrade(data, character, 1) end
function C.Create2(data, character) return C.Upgrade(data, character, 2) end
function C.Create3(data, character) return C.Upgrade(data, character, 3) end
function C.Create4(data, character) return C.Upgrade(data, character, 4) end
function C.Create5(data, character) return C.Upgrade(data, character, 5) end
function C.TestRestore(item, character)
    if not C.IsSinglePlayer() then return false end
    if not instanceof(item, "InventoryContainer") then return true end
    if not C.IsManaged(item) then return false end
    return C.CanRestore(item, character)
end

function C.GetRecipeMode(recipe)
    if not recipe then return nil end
    -- Native getName() is unqualified; another mod can use the same short name.
    -- Restrict the crafting guard to our module; native menus remain untouched.
    local name = recipe.getScriptObjectFullType and recipe:getScriptObjectFullType() or recipe:getName()
    for index = 1, #C.tiers do
        local short = "SuQingAutoUpgrade" .. index
        if name == "SuQingContainerUpgradeAuto." .. short then return index end
    end
    if name == "SuQingContainerUpgradeAuto.SuQingAutoRestore" then return "restore" end
    return nil
end

function C.CanComplete(recipeData, character, mode)
    local target, reason = C.FindTarget(recipeData)
    if not target then return false, reason end
    if mode == "restore" then return C.CanRestore(target, character) end
    return C.CanUpgrade(target, character, mode)
end

require "SuQingContainerUpgradeAuto/Refund"
require "SuQingContainerUpgradeAuto/Auto"
return C
