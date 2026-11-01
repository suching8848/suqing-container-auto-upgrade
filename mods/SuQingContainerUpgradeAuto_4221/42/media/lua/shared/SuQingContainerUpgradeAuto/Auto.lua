-- Discovery is definition-only. No sample items, tag edits, tick or world scan.
require "SuQingContainerUpgradeAuto/AutoPolicy"
SuQingContainerUpgradeAuto = SuQingContainerUpgradeAuto or {}
local C = SuQingContainerUpgradeAuto
C.Auto = C.Auto or {}
local A = C.Auto
if A.loaded then return A end
A.loaded = true
A.ready = false
A.excluded = SuQingContainerUpgradeAutoPolicy
A.lastReason = {}

local function initKnown()
    if A.known then return end
    A.known = {}
    for fullType in pairs(C.supported) do A.known[fullType] = true end
end

local function integer(value, low, high)
    return type(value) == "number" and value == value and value == math.floor(value)
        and value >= low and value <= high
end

local function slotPresent(value)
    if value == nil then return false end
    local name = tostring(value)
    return name ~= "" and name ~= "null" and name ~= "None" and name ~= "base:none"
end

local function ownRecord(item)
    local record = item:getModData()[C.modDataKey]
    if type(record) == "table" and record.fullType == item:getFullType()
        and record.schema == 2 and C.IsValidRecord(record) then return record end
end

local function classify(item, restoring)
    initKnown()
    if not C.IsSinglePlayer() or not item or not instanceof(item, "InventoryContainer")
        or not item:getInventory() then return false, "not_container_or_disabled" end
    local fullType = item:getFullType()
    if item:getModData().SuQingContainerUpgrade ~= nil then return false, "old_version_record" end
    local record = ownRecord(item)
    -- A paid automatic record remains restorable after a source becomes special.
    if restoring and record and not A.known[fullType] then
        if record.profile ~= "mod_container" then return false, "unknown_auto_profile" end
        C.supported[fullType], C.compatibility.profiles[fullType] = true, record.profile
        return true
    end
    if A.known[fullType] or (restoring and C.retired[fullType]) then return true end
    if A.excluded[fullType] then return false, "exact_exclusion" end
    if not item.canBeEquipped or not slotPresent(item:canBeEquipped()) then
        return false, "not_wearable"
    end
    local manager = type(getScriptManager) == "function" and getScriptManager()
    local script = manager and manager:getItem(fullType)
    if not script or script:getObsolete() or script:isHidden() then return false, "script_unavailable" end
    local extra = script:getClothingItemExtra()
    if extra and extra:size() > 0 then return false, "conversion_needs_adapter" end
    if item.getClothingExtraSubmenu and item:getClothingExtraSubmenu() ~= nil
        and item:getClothingExtraSubmenu() ~= "" then return false, "conversion_needs_adapter" end
    if item.getLuaCreate and item:getLuaCreate() ~= nil and item:getLuaCreate() ~= "" then
        return false, "creation_callback_needs_adapter"
    end
    local inner = item:getInventory()
    local capacity, effective = inner:getCapacity(), inner:getEffectiveCapacity(nil)
    local weight, reduction = item:getActualWeight(), item:getWeightReduction()
    if not integer(capacity, 1, 50) or not integer(reduction, 0, 100)
        or type(weight) ~= "number" or weight ~= weight or weight < 0 or weight >= 50 then
        return false, "invalid_stats"
    end
    if effective ~= capacity or item:getCapacity() ~= capacity then return false, "dynamic_capacity_needs_adapter" end
    local limit = math.floor(50 - weight)
    if capacity > limit or (not record and capacity >= limit) then return false, "high_capacity_needs_adapter" end
    -- All automatic additions use the existing bounded mod_container policy.
    C.supported[fullType], C.compatibility.profiles[fullType] = true, "mod_container"
    return true
end

function A.EnsureItem(item, restoring)
    local ok, allowed, reason = pcall(classify, item, restoring)
    if item and item.getFullType then
        A.lastReason[item:getFullType()] = ok and reason or "classification_api_error"
    end
    return ok and allowed == true
end

local function copyList(list)
    local result = {}
    for i = 0, list:size() - 1 do result[#result + 1] = list:get(i) end
    return result
end

local function replaceList(list, values)
    list:clear()
    for _, value in ipairs(values) do list:add(value) end
end

function A.Install()
    initKnown()
    if A.ready then return true end
    if not C.IsSinglePlayer() then return false end
    local manager = type(getScriptManager) == "function" and getScriptManager()
    if not manager or not ItemType or not ItemType.CONTAINER then return false end
    local candidates, scripts = {}, {}
    local all = manager:getAllItems()
    for i = 0, all:size() - 1 do
        local script = all:get(i)
        local fullType = script:getFullName()
        if fullType and not script:getObsolete() and not script:isHidden()
            and (A.known[fullType] or C.retired[fullType] or script:isItemType(ItemType.CONTAINER)) then
            scripts[fullType] = script
            if not A.excluded[fullType] or C.retired[fullType] then candidates[#candidates + 1] = fullType end
        end
    end
    table.sort(candidates)
    local stages = {}
    for i = 1, 6 do
        local name = i == 6 and "SuQingAutoRestore" or ("SuQingAutoUpgrade" .. i)
        local recipe = manager:getCraftRecipe("SuQingContainerUpgradeAuto." .. name)
        if not recipe then return false end
        local input = recipe:getInputs():get(0)
        if not input or not input:isKeep() or not input:isItemCount() then return false end
        local ids, cache = input:getItems(), input:getPossibleInputItems()
        if not ids or not cache then return false end
        local nextIds, nextScripts = {}, {}
        for _, fullType in ipairs(candidates) do
            if i == 6 or not C.retired[fullType] then
                nextIds[#nextIds + 1], nextScripts[#nextScripts + 1] = fullType, scripts[fullType]
            end
        end
        stages[#stages + 1] = { ids = ids, cache = cache, oldIds = copyList(ids), oldCache = copyList(cache),
            nextIds = nextIds, nextScripts = nextScripts }
    end
    local ok, message = pcall(function()
        for _, stage in ipairs(stages) do
            replaceList(stage.ids, stage.nextIds)
            replaceList(stage.cache, stage.nextScripts)
        end
    end)
    if not ok then
        for _, stage in ipairs(stages) do
            pcall(replaceList, stage.ids, stage.oldIds)
            pcall(replaceList, stage.cache, stage.oldCache)
        end
        print("[SuQingContainerUpgradeAuto] recipe discovery failed: " .. tostring(message))
        return false
    end
    A.ready, A.candidateCount = true, #candidates
    print("[SuQingContainerUpgradeAuto] automatic recipe candidates=" .. #candidates .. "; instance validation required")
    return true
end

Events.OnGameStart.Add(function()
    local ok, message = pcall(A.Install)
    if not ok then print("[SuQingContainerUpgradeAuto] discovery unavailable: " .. tostring(message)) end
end)
return A
