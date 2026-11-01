-- Exact audited 2DimensionWardrobe resizing recipes only.  Unowned items and
-- every other recipe retain the full existing performRecipe chain.
if isServer() then return end
require "SuQingContainerUpgradeAuto/Core"
require "Entity/TimedActions/ISHandcraftAction"
require "TimedActions/ISClothingExtraAction"

local C = SuQingContainerUpgradeAuto
C.Variant = C.Variant or {}
local V = C.Variant

-- Generated from the single audited compatibility registry.  Recipe identities
-- use ASCII decimal code units because source Unicode literals are not reliable
-- in this game's Kahlua compiler.
V.specs = C.compatibility.variantRecipes or {}

local function log(message)
    print("[SuQingContainerUpgradeAuto] variant " .. tostring(message))
end

local function has(container, item)
    return container ~= nil and container:getItems():contains(item)
end

local function compact(line)
    local compacted = string.gsub(tostring(line), "%s", "")
    return (string.gsub(compacted, ",", ""))
end

function V.GetSpec(recipe)
    if not recipe or not recipe.getScriptObjectFullType then return nil end
    local identity = recipe:getScriptObjectFullType()
    if type(identity) ~= "string" then return nil end
    -- This game Kahlua compiler damages non-ASCII source literals.  Native
    -- Java recipe identities remain Unicode; StringLib.byte returns code units.
    for _, spec in ipairs(V.specs) do
        local points, matches = spec.recipeCodepoints, true
        if #identity == #points then
            for index = 1, #points do
                if string.byte(identity, index) ~= points[index] then matches = false; break end
            end
            if matches then return spec end
        end
    end
    return nil
end

-- A future Workshop change must not silently turn this adapter into protection
-- for a multi-input/material recipe, different output or native CopyClothing.
function V.ValidateRecipe(recipe, spec)
    local inputs, outputs = recipe:getInputs(), recipe:getOutputs()
    if inputs:size() ~= 1 or outputs:size() ~= 1 then error("recipe_shape_changed") end
    local input, output = inputs:get(0), outputs:get(0)
    if compact(input:getOriginalLine()) ~= "item1[" .. spec.from .. "]"
        or compact(output:getOriginalLine()) ~= "item1" .. spec.target
        or input:getAmount() ~= 1 or input:isKeep() or output:getAmount() ~= 1 then
        error("recipe_definition_changed")
    end
end

-- Identify ownership without intercepting unenhanced originals.  Validation of
-- the unique input and its state happens before native input consumption.
function V.FindOwnedSource(action, spec)
    if not action.logic then return nil end
    local data = action.logic:getRecipeData()
    if not data then return nil end
    local inputs = data:getAllInputItems()
    for index = 0, inputs:size() - 1 do
        local item = inputs:get(index)
        if item and item:getFullType() == spec.from and C.GetRecord(item) ~= nil then return item end
    end
    return nil
end

local function attachCompletionRefresh(action)
    if action.suQingVariantRefreshAttached then return end
    local original = action.onCompleteFunc
    action.onCompleteFunc = function(panel)
        if original then original(panel) end
        if type(C.RefreshCraftingPanel) == "function" then C.RefreshCraftingPanel(panel) end
    end
    action.suQingVariantRefreshAttached = true
end

local function refresh(transaction, item)
    if type(C.RefreshInventory) == "function" then
        pcall(C.RefreshInventory, transaction.character, item)
    end
end

function V.Capture(action, spec, source)
    V.ValidateRecipe(action.craftRecipe, spec)
    if not C.IsSinglePlayer() then error("multiplayer") end
    local data = action.logic:getRecipeData()
    local inputs = data:getAllInputItems()
    if inputs:size() ~= 1 or inputs:get(0) ~= source or source:getFullType() ~= spec.from then
        error("inputs_changed")
    end
    local character = action.character
    if character:isEquipped(source) or character:getPrimaryHandItem() == source
        or character:getSecondaryHandItem() == source then error("remove_equipment_first") end
    local transaction, reason = C.Position.Capture({
        item = source, extra = spec.target, character = character,
    })
    if not transaction then error(reason or "invalid_source") end
    transaction.sourceUses = source:getUses()
    transaction.data = data
    transaction.recipe = action.craftRecipe
    return transaction
end

function V.Prepare(transaction, target)
    if not C.IsSupported(target) or target == transaction.source
        or target:getFullType() ~= transaction.destinationType
        or target:getContainer() ~= nil or target:getWorldItem() ~= nil
        or target:getInventory():getItems():size() ~= 0 then error("unsafe_new_target") end
    -- Never register an existing foreign item as a recovery target.
    transaction.target = target
    local limit, reason = C.GetNativeCapacityLimit(target)
    if not limit or transaction.snapshot.capacity > limit then error(reason or "capacity_limit") end
    local ok, message = C.SetStats(target, transaction.snapshot.capacity, transaction.snapshot.weightReduction)
    if not ok then error("setter:" .. tostring(message)) end
end

local function verifyContents(transaction)
    local target = transaction.target
    local sourceInner, targetInner = transaction.source:getInventory(), target:getInventory()
    if sourceInner:getItems():size() ~= 0
        or targetInner:getItems():size() ~= #transaction.contents then error("contents_count") end
    for _, child in ipairs(transaction.contents) do
        if not has(targetInner, child) or child:getContainer() ~= targetInner then error("contents_verification") end
    end
end

function V.Verify(transaction)
    C.Position.VerifyTarget(transaction, transaction.target)
    if not has(transaction.inventory, transaction.target)
        or transaction.target:getContainer() ~= transaction.inventory
        or has(transaction.inventory, transaction.source) then error("inventory_verification") end
    verifyContents(transaction)
    if transaction.character:getWornItem(transaction.sourceSlot) ~= transaction.sourceWorn
        or transaction.character:getPrimaryHandItem() ~= transaction.primary
        or transaction.character:getSecondaryHandItem() ~= transaction.secondary then error("equipment_changed") end
end

function V.Execute(action, transaction)
    -- Native start has already validated selection.  Do not re-test reservations
    -- while this action is craftStarted; performCurrentRecipe consumes once.
    if not action.logic:performCurrentRecipe() then error("native_perform_failed") end
    local outputs = ArrayList.new()
    action.logic:getCreatedOutputItems(outputs)
    if outputs:size() ~= 1 then error("unexpected_output_count") end
    local target = outputs:get(0)
    V.Prepare(transaction, target)
    -- This class-style call has no Position action marker and retains the
    -- original copy chain.  Native copying preserves visuals/name/ModData and
    -- moves the original children; it does not copy our storage stats.
    if ISClothingExtraAction:createItemNew(transaction.source, target) ~= target then
        error("copy_result")
    end
    C.Position.VerifyTarget(transaction, target)
    verifyContents(transaction)
    if not has(transaction.inventory, target) then transaction.inventory:AddItem(target) end
    if not has(transaction.inventory, target) then error("output_not_added") end

    transaction.data:luaCallOnCreate(action.character)
    transaction.data:processDestroyAndUsedItems(action.character)
    -- Preserve the native single-output consumed-type history after OnCreate.
    local used = transaction.data:getAllConsumedItems()
    if used:size() ~= 1 or used:get(0) ~= transaction.source then error("consumed_inputs_changed") end
    local modData = target:getModData()
    local sourceType = transaction.source:getFullType()
    if modData[sourceType] == nil then modData[sourceType] = 0 end
    modData[sourceType] = modData[sourceType] + 1

    -- Native addOrDropItem would create a world item when overloaded.  This
    -- guarded branch aborts safely instead, so recovery never loses a dropped
    -- replacement.  Unowned resizing retains native add/drop behavior.
    if transaction.inventory:getCapacityWeight() > transaction.inventory:getEffectiveCapacity(action.character) then
        error("inventory_full")
    end
    V.Verify(transaction)
    if type(sendAddItemToContainer) == "function" then sendAddItemToContainer(transaction.inventory, target) end
end

function V.Rollback(transaction)
    -- Restore uses independently even if a later recovery component fails.
    local usesOK = pcall(function()
        transaction.source:setUses(transaction.sourceUses)
        if transaction.source:getUses() ~= transaction.sourceUses then error("source_uses") end
    end)
    local recovered, restored = pcall(C.Position.Rollback, transaction)
    return usesOK and recovered and restored == true
end

function V.Perform(action, spec, source)
    if action.suQingVariantFinished then return end
    action.suQingVariantFinished = true
    attachCompletionRefresh(action)
    local P = C.Position
    if not P or type(P.Capture) ~= "function" or type(P.Rollback) ~= "function"
        or type(P.VerifyTarget) ~= "function" or not P.characters then
        return log("stopped before conversion: preservation_unavailable")
    end
    if P.characters[action.character] then return log("stopped nested owned conversion") end
    P.characters[action.character] = action
    local transaction
    local ok, message = pcall(function()
        transaction = V.Capture(action, spec, source)
        P.characters[action.character] = transaction
        V.Execute(action, transaction)
    end)
    if not ok then
        local restored = true
        if transaction then
            local recovered, result = pcall(V.Rollback, transaction)
            restored = recovered and result == true
            refresh(transaction, transaction.source)
        end
        log("aborted " .. tostring(message) .. "; inventoryRestored=" .. tostring(restored))
    else
        refresh(transaction, transaction.target)
        log("preserved " .. spec.from .. " -> " .. spec.target)
    end
    P.characters[action.character] = nil
end

function V.Install()
    if V.installed or not C.IsSinglePlayer() or not ISHandcraftAction
        or type(ISHandcraftAction.performRecipe) ~= "function" then return end
    local original = ISHandcraftAction.performRecipe
    ISHandcraftAction.performRecipe = function(self, ...)
        local spec = V.GetSpec(self.craftRecipe)
        if not spec then return original(self, ...) end
        local inspected, source = pcall(V.FindOwnedSource, self, spec)
        if not inspected then return log("stopped before conversion: input_inspection_failed: " .. tostring(source)) end
        if not source then return original(self, ...) end
        -- No native mutation precedes this protected function.  An unexpected
        -- preflight error stops this owned action and reports no assumed repair.
        local ok, message = pcall(V.Perform, self, spec, source)
        if not ok then log("action exception; recovery not assumed: " .. tostring(message)) end
    end
    V.installed = true
    log("exact owned resize protection ready; eight audited recipes")
end

Events.OnGameStart.Add(V.Install)
