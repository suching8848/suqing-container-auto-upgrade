-- Preserve only audited, owned fanny-pack actions. All visual/content copying
-- remains native. Ordinary copyClothingItem/CopyClothing calls have no marker.
require "SuQingContainerUpgradeAuto/Core"
require "TimedActions/ISClothingExtraAction"
local C = SuQingContainerUpgradeAuto
C.Position = C.Position or { active = {} }
local P = C.Position
P.characters = P.characters or {}

local function log(message)
    print("[SuQingContainerUpgradeAuto] position " .. tostring(message))
end

local function items(container)
    local result, list = {}, container:getItems()
    for index = 0, list:size() - 1 do result[#result + 1] = list:get(index) end
    return result
end

local function has(container, item)
    return container ~= nil and container:getItems():contains(item)
end

function P.IsOwnedAction(action)
    if not C.IsSinglePlayer() or not action or not C.IsSupported(action.item) then return false end
    local sourceType = action.item:getFullType()
    local paired = C.compatibility.positionPairs[sourceType]
    return paired ~= nil and (action.extra == sourceType or action.extra == paired)
        and C.GetRecord(action.item) ~= nil
end

function P.Capture(action)
    local source, character = action.item, action.character
    local state = C.GetState(source)
    if not state or not state.upgraded or state.corruptRecord or state.inconsistent or state.profileMismatch then
        return nil, "invalid_source_record"
    end
    local inventory = character and character:getInventory()
    if source:getContainer() ~= inventory or not has(inventory, source) then return nil, "not_carried" end
    local sourceSlot = source:canBeEquipped()
    local snapshot = C.CaptureTarget(source)
    local recordFields = {}
    for key, value in pairs(snapshot.record) do recordFields[key] = value end
    return { action = action, source = source, destinationType = action.extra, character = character,
        inventory = inventory, sourceSlot = sourceSlot, sourceWorn = character:getWornItem(sourceSlot),
        primary = character:getPrimaryHandItem(), secondary = character:getSecondaryHandItem(),
        snapshot = snapshot, recordFields = recordFields, contents = items(source:getInventory()) }
end

local recordKeys = { "schema", "level", "version", "baseCapacity", "baseWeightReduction",
    "profile", "profileVersion", "nativeLimit", "appliedCapacity", "appliedWeightReduction",
    "paidLedgerVersion", "paidCloth", "paidLeather", "paidThreadUses" }

-- An occupied destination is an ordinary refusal, not an exception. Check it
-- before native complete removes hands/worn items or creates/moves anything.
-- Capture is also used by unequipped size conversions, so keep this check in
-- the owned wear-action path only.
function P.CheckDestination(transaction)
    local destinationSlot
    if transaction.destinationType == transaction.source:getFullType() then
        destinationSlot = transaction.sourceSlot
    else
        -- Only the eight audited front/back fanny-pack types reach this path.
        -- Their script BodyLocation matches the instance's canBeEquipped slot.
        -- Script Item has getBodyLocation; it has no getCanBeEquipped method.
        local manager = type(getScriptManager) == "function" and getScriptManager()
        local script = manager and manager:getItem(transaction.destinationType)
        destinationSlot = script and script:getBodyLocation()
    end
    if destinationSlot == nil or destinationSlot == "" then
        return false, "destination_slot_unavailable"
    end
    local occupant = transaction.character:getWornItem(destinationSlot)
    if occupant ~= nil and occupant ~= transaction.source then
        return false, "destination_occupied"
    end
    -- Do not publish rollback slot state before native code has even created
    -- our target. An unrelated occupant arriving before that point belongs to
    -- another action and must not be unworn by recovery of this transaction.
    transaction.expectedDestinationSlot = destinationSlot
    return true
end

function P.VerifyTarget(transaction, target)
    if target ~= transaction.target or not C.IsSupported(target)
        or target:getFullType() ~= transaction.destinationType then error("unexpected_target") end
    local state = C.GetState(target)
    if not state or not state.upgraded or state.corruptRecord or state.inconsistent or state.profileMismatch
        or state.capacity ~= transaction.snapshot.capacity
        or state.weightReduction ~= transaction.snapshot.weightReduction then error("target_stats") end
    local record = C.GetRecord(target)
    for _, key in ipairs(recordKeys) do
        if record[key] ~= transaction.recordFields[key] then error("target_record:" .. key) end
    end
end

function P.Prepare(transaction, target)
    if not C.IsSupported(target) or target == transaction.source
        or target:getFullType() ~= transaction.destinationType
        or target:getContainer() ~= nil or target:getInventory():getItems():size() ~= 0 then
        error("unsafe_new_target")
    end
    -- Until freshness is proven this could be somebody else's carried item;
    -- it must never become a rollback target or have its contents moved.
    transaction.target = target
    local character = transaction.character
    local destinationSlot = target:canBeEquipped()
    if transaction.expectedDestinationSlot ~= nil and transaction.expectedDestinationSlot ~= destinationSlot then
        error("destination_slot_changed")
    end
    transaction.destinationSlot = destinationSlot
    if transaction.destinationSlot == transaction.sourceSlot then
        transaction.destinationWorn = transaction.sourceWorn
    else
        transaction.destinationWorn = character:getWornItem(transaction.destinationSlot)
    end
    -- Native setWornItem may drop a displaced occupied-slot item into the world
    -- when inventory space is tight. Keep this action narrow: require an empty
    -- destination (or the source itself for same-orientation wear).
    if transaction.destinationWorn ~= nil and transaction.destinationWorn ~= transaction.source then
        error("destination_occupied")
    end
    local limit, reason = C.GetNativeCapacityLimit(target)
    if not limit or transaction.snapshot.capacity > limit then error(reason or "capacity_limit") end
    local ok, message = C.SetStats(target, transaction.snapshot.capacity, transaction.snapshot.weightReduction)
    if not ok then error("setter:" .. tostring(message)) end
end

function P.Rollback(transaction)
    local allOK = true
    local function recover(label, fn)
        local ok, result = pcall(fn)
        if not ok or result == false then
            allOK = false
            log("recovery failed " .. label .. ": " .. tostring(result))
        end
    end
    local source, target = transaction.source, transaction.target
    local sourceInner = source:getInventory()
    local function restoreChild(child)
        local current = child:getContainer()
        if current ~= sourceInner and has(current, child) then
            pcall(function() current:Remove(child) end)
            if has(current, child) then error("content_still_in_previous_container") end
        end
        if not has(sourceInner, child) then pcall(function() sourceInner:AddItem(child) end) end
        if not has(sourceInner, child) then
            -- If recovery AddItem also fails, put this exact child back into a
            -- tracked container. Do not leave it between Remove and Add, then
            -- mistake an empty target for safe-to-discard recovery.
            local candidates = {}
            if current and current ~= sourceInner then candidates[#candidates + 1] = current end
            if target and target ~= source and instanceof(target, "InventoryContainer") then
                candidates[#candidates + 1] = target:getInventory()
            end
            candidates[#candidates + 1] = transaction.inventory
            local stored = false
            for _, destination in ipairs(candidates) do
                local ok, present = pcall(function()
                    if not has(destination, child) then pcall(function() destination:AddItem(child) end) end
                    return has(destination, child)
                end)
                if ok and present then stored = true; break end
            end
            error("content_recovery_failed; safelyStored=" .. tostring(stored))
        end
    end
    -- Keep the actual child references. Native takeItemsFrom can Remove a child
    -- and then fail to Add it, leaving it in neither container.
    for _, child in ipairs(transaction.contents) do
        recover("content", function() restoreChild(child) end)
    end
    if target and target ~= source and instanceof(target, "InventoryContainer") then
        recover("remaining_contents", function()
            for _, child in ipairs(items(target:getInventory())) do restoreChild(child) end
        end)
    end
    recover("source_inventory", function()
        local current = source:getContainer()
        if current ~= transaction.inventory and has(current, source) then
            pcall(function() current:Remove(source) end)
            if has(current, source) then error("source_still_in_previous_container") end
        end
        if not has(transaction.inventory, source) then transaction.inventory:AddItem(source) end
        if not has(transaction.inventory, source) then error("source_missing") end
    end)
    recover("source_record", function()
        local record = transaction.snapshot.record
        for key in pairs(record) do record[key] = nil end
        for key, value in pairs(transaction.recordFields) do record[key] = value end
        source:getModData()[C.modDataKey] = record
    end)
    recover("source_stats", function() return C.RestoreTarget(transaction.snapshot) end)
    if target and target ~= source then
        recover("new_target", function()
            -- Never discard a target still holding unrecovered data.
            if instanceof(target, "InventoryContainer") and target:getInventory():getItems():size() ~= 0 then
                if target:getContainer() == nil then transaction.inventory:AddItem(target) end
                error("target_still_has_contents")
            end
            local current = target:getContainer()
            if has(current, target) then current:Remove(target) end
            if has(current, target) then error("target_still_carried") end
        end)
    end
    if transaction.destinationSlot and transaction.destinationSlot ~= transaction.sourceSlot then
        recover("destination_slot", function()
            transaction.character:setWornItem(transaction.destinationSlot, transaction.destinationWorn, false)
        end)
    end
    recover("source_slot", function()
        transaction.character:setWornItem(transaction.sourceSlot, transaction.sourceWorn, false)
    end)
    recover("primary_hand", function() transaction.character:setPrimaryHandItem(transaction.primary) end)
    recover("secondary_hand", function() transaction.character:setSecondaryHandItem(transaction.secondary) end)
    if type(syncVisuals) == "function" then
        recover("visual_sync", function() syncVisuals(transaction.character) end)
    end
    -- Do this after source restoration and all native recovery callbacks. Even
    -- a foreign shallow copy of ModData cannot reintroduce duplicate credit.
    local targetCreditRevoked = true
    if target and target ~= source then
        local revoked, result = pcall(function() return C.Refund.DropLedger(target) end)
        targetCreditRevoked = revoked and result == true
        if not targetCreditRevoked then
            allOK = false
            log("recovery failed target_payment_credit: " .. tostring(result))
        end
    end
    if not targetCreditRevoked then
        -- RestoreTarget above reinstates the original record. Revoke its paid
        -- credit LAST if we could not revoke the fresh target's copy; neither a
        -- retained target nor a source recovery may create two refund claims.
        recover("source_payment_credit", function() return C.Refund.DropLedger(source) end)
    end
    return allOK
end

local function refresh(transaction, item)
    if type(C.RefreshInventory) == "function" then pcall(C.RefreshInventory, transaction.character, item) end
end

function P.Install()
    if P.installed or not C.IsSinglePlayer() or not ISClothingExtraAction then return end
    local originalCreate = ISClothingExtraAction.createItemNew
    local originalComplete = ISClothingExtraAction.complete
    if type(originalCreate) ~= "function" or type(originalComplete) ~= "function" then return end
    ISClothingExtraAction.createItemNew = function(self, source, target, ...)
        local transaction = P.active[self]
        if not transaction or source ~= transaction.source then
            return originalCreate(self, source, target, ...)
        end
        -- Before native copying can move any contents, validate the exact fresh
        -- target and probe its setters. Exceptions are caught by our complete.
        P.Prepare(transaction, target)
        local result = originalCreate(self, source, target, ...)
        P.VerifyTarget(transaction, result)
        return result
    end
    ISClothingExtraAction.complete = function(self, ...)
        if self.suQingPositionFinished or P.active[self] then return false end
        if not P.IsOwnedAction(self) then return originalComplete(self, ...) end
        if P.characters[self.character] then
            log("stopped nested owned conversion")
            return false
        end
        self.suQingPositionFinished = true
        local captured, transaction, reason = pcall(P.Capture, self)
        if not captured or not transaction then
            log("stopped before conversion: " .. tostring(captured and reason or transaction))
            return false
        end
        local checked, destinationOK, destinationReason = pcall(P.CheckDestination, transaction)
        if not checked or not destinationOK then
            log("stopped before conversion: " .. tostring(checked and destinationReason or destinationOK))
            return false
        end
        P.active[self] = transaction
        P.characters[transaction.character] = transaction
        local ok, result = pcall(originalComplete, self, ...)
        if ok and result == true then
            ok, result = pcall(function()
                local target = transaction.target
                P.VerifyTarget(transaction, target)
                if not has(transaction.inventory, target) or has(transaction.inventory, transaction.source) then
                    error("inventory_verification")
                end
                for _, child in ipairs(transaction.contents) do
                    if not has(target:getInventory(), child) then error("contents_verification") end
                end
                if transaction.character:getWornItem(transaction.destinationSlot) ~= target then
                    error("worn_verification")
                end
                return true
            end)
        else
            ok = false
        end
        P.active[self] = nil
        if not ok then
            local recovered, restored = pcall(P.Rollback, transaction)
            restored = recovered and restored == true
            log("aborted " .. tostring(result) .. "; inventoryRestored=" .. tostring(restored))
            -- External sync/events already observed by other mods cannot be
            -- retracted. Recovery covers our known inventory/equipment state.
            refresh(transaction, transaction.source)
            P.characters[transaction.character] = nil
            return false
        end
        refresh(transaction, transaction.target)
        P.characters[transaction.character] = nil
        return true
    end
    P.installed = true
    log("native-action preservation ready; exact vanilla pairs only")
end

Events.OnGameStart.Add(P.Install)
