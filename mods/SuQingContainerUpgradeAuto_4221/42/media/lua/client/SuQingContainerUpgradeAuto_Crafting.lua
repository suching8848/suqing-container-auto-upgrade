if isServer() then return end
require "SuQingContainerUpgradeAuto/Core"
require "Entity/TimedActions/ISHandcraftAction"

local C = SuQingContainerUpgradeAuto

function C.RefreshInventory(character, item)
    local ok, message = pcall(function()
        if item and item.setDrawDirty then item:setDrawDirty(true) end
        local playerNum = character:getPlayerNum()
        if CodexInventoryTransferPerformance and CodexInventoryTransferPerformance.flush then
            CodexInventoryTransferPerformance.flush(playerNum)
        end
        if ISInventoryPage and ISInventoryPage.dirtyUI then ISInventoryPage.dirtyUI() end
        for _, getter in ipairs({ getPlayerInventory, getPlayerLoot }) do
            local page = getter and getter(playerNum)
            if page and page.inventoryPane then page.inventoryPane:refreshContainer() end
        end
    end)
    if not ok then print("[SuQingContainerUpgradeAuto] inventory refresh: " .. tostring(message)) end
end

-- A same-instance stat change need not change the engine's inventory-object set.
-- Rebuild the owning crafting UI once, AFTER its normal completion callback has
-- stopped/dequeued this action. Do not add a tick handler or change other recipes.
function C.RefreshCraftingPanel(panel)
    if not panel or not panel.logic or not ArrayList then return end
    local ok, message = pcall(function()
        local logic = panel.logic
        if not logic.getContainers or not logic.setContainers then return end
        local containers = ArrayList.new()
        containers:addAll(logic:getContainers())
        logic:setContainers(ArrayList.new())
        logic:setContainers(containers)
        if logic.autoPopulateInputs then logic:autoPopulateInputs() end
        if logic.sortRecipeList then logic:sortRecipeList() end
        local handcraft = panel.HandCraftPanel
        local info = handcraft and handcraft.recipeInfoPanel
        if info and info.onRecipeChanged then info:onRecipeChanged() end
    end)
    if not ok then print("[SuQingContainerUpgradeAuto] crafting refresh: " .. tostring(message)) end
end

local function attachCompletionRefresh(action)
    if action.suQingRefreshAttached then return end
    local original = action.onCompleteFunc
    action.onCompleteFunc = function(panel)
        if original then original(panel) end
        C.RefreshCraftingPanel(panel)
    end
    action.suQingRefreshAttached = true
end

function C.CaptureInputs(data)
    local inputs = data:getAllInputItems()
    local result, seen = {}, {}
    for index = 0, inputs:size() - 1 do
        local item = inputs:get(index)
        if not seen[item] then
            seen[item] = true
            local container = item:getContainer()
            if not container or not container:getItems():contains(item) then
                return nil, "inputs_changed"
            end
            local snapshot = { item = item, container = container, fullType = item:getFullType() }
            if instanceof(item, "DrainableComboItem") then
                snapshot.uses = item:getCurrentUsesFloat()
            end
            if snapshot.fullType == "Base.Thread" then
                if not item.getCurrentUses then return nil, "thread_api" end
                snapshot.threadUnits = item:getCurrentUses()
            end
            result[#result + 1] = snapshot
        end
    end
    return result
end

-- Native performCurrentRecipe already removes mode:destroy cloth/leather.
-- Keep the actual instances and drainable amounts so a later failure can undo
-- those inventory changes, instead of creating replacement materials/IDs.
function C.RestoreInputs(snapshots)
    local allOK = true
    for _, snapshot in ipairs(snapshots or {}) do
        local ok, message = pcall(function()
            local item, destination = snapshot.item, snapshot.container
            local current = item:getContainer()
            if current and current ~= destination and current:getItems():contains(item) then
                current:Remove(item)
            end
            if snapshot.uses ~= nil then item:setCurrentUsesFloat(snapshot.uses) end
            if not destination:getItems():contains(item) then destination:AddItem(item) end
            if not destination:getItems():contains(item) then error("Input instance was not restored") end
        end)
        if not ok then
            allOK = false
            print("[SuQingContainerUpgradeAuto] input rollback failed: " .. tostring(message))
        end
    end
    return allOK
end

local function logFailure(reason)
    print("[SuQingContainerUpgradeAuto] craft stopped: " .. tostring(reason))
end

local function performLocked(action, mode)
    if not action.logic then return logFailure("no_recipe_data") end
    local refund = C.Refund
    if not refund then return logFailure("refund_unavailable") end
    local data = action.logic:getRecipeData()
    local target, targetReason = C.FindTarget(data)
    if not target then return logFailure(targetReason) end
    local ledger, ledgerReason = refund.ReadLedger(C.GetRecord(target))
    if not ledger then return logFailure(ledgerReason) end
    local ready, reason, targetSnapshot, expectedCapacity, expectedReduction = C.ProbeChange(target, action.character, mode)
    if not ready then return logFailure(reason) end
    local inputs, inputReason = C.CaptureInputs(data)
    if not inputs then return logFailure(inputReason) end
    local refundPlan
    if mode == "restore" then
        local staged, plan, stageReason = pcall(refund.StageRefund, targetSnapshot.record, action.character)
        if not staged or not plan then return logFailure(staged and stageReason or plan) end
        refundPlan = plan
    end

    local stoppedReason
    local ok, message = pcall(function()
        -- DO NOT call canPerformCurrentRecipe here. At this point craftStarted
        -- is true and test-only checks count this action's keep+ItemCount target
        -- as reserved by itself. Native start already tests the selection; the
        -- real perform below validates/consumes current inputs without that test.
        if not action.logic:performCurrentRecipe() then
            stoppedReason = "ingredients"
            return
        end
        local changed, changedItem
        if mode == "restore" then changed, changedItem = C.Restore(data, action.character)
        else changed, changedItem = C.Upgrade(data, action.character, mode) end
        if not changed or changedItem ~= target then
            stoppedReason = changed and "inputs_changed" or changedItem
            return
        end
        data:processDestroyAndUsedItems(action.character)
        local state = C.GetState(target)
        if not state or state.capacity ~= expectedCapacity or state.weightReduction ~= expectedReduction
            or (mode == "restore" and C.GetRecord(target) ~= nil)
            or (mode ~= "restore" and (not state.upgraded or state.recordedLevel ~= mode or state.inconsistent)) then
            stoppedReason = "verification"
            return
        end
        if mode == "restore" then
            -- Restore has already cleared the refundable record. Keep the actor
            -- lock until every new output and the final refresh are complete.
            refund.InsertRefund(refundPlan)
        else
            local recorded, paymentReason = refund.CommitPayment(target, inputs, mode)
            if not recorded then stoppedReason = paymentReason end
        end
    end)
    if not ok or stoppedReason then
        -- A target rollback error must not prevent the independent material
        -- rollback from running. Unknown recovery is reported as such.
        local revokedOK, revoked = pcall(refund.RevokeRefund, refundPlan)
        local canRestoreCredit = revokedOK and revoked == true
        local targetOK, restoredTarget
        if canRestoreCredit then
            targetOK, restoredTarget = pcall(C.RestoreTarget, targetSnapshot)
        else
            -- Never restore a redeemable ledger while any newly granted refund
            -- may remain. This rare foreign-API failure is deliberately closed:
            -- base stats/cleared record remain, and uncertainty is reported.
            targetOK, restoredTarget = pcall(function()
                target:getModData()[C.modDataKey] = nil
                return C.SetStats(target, expectedCapacity, expectedReduction)
            end)
        end
        local inputsOK, restoredInputs = pcall(C.RestoreInputs, inputs)
        restoredTarget = targetOK and restoredTarget == true
        restoredInputs = inputsOK and restoredInputs == true
        print("[SuQingContainerUpgradeAuto] aborted " .. tostring(stoppedReason or message)
            .. " targetRestored=" .. tostring(restoredTarget) .. " inputsRestored=" .. tostring(restoredInputs)
            .. " refundRevoked=" .. tostring(canRestoreCredit) .. " ledgerConsumed=" .. tostring(not canRestoreCredit))
        C.RefreshInventory(action.character, target)
        return logFailure((canRestoreCredit and restoredTarget and restoredInputs) and (stoppedReason or "exception") or "rollback")
    end
    C.RefreshInventory(action.character, target)
    if mode == "restore" then
        print("[SuQingContainerUpgradeAuto] restored " .. target:getFullType()
            .. " capacity=" .. expectedCapacity .. " reduction=" .. expectedReduction
            .. " refundCloth=" .. refundPlan.cloth .. " refundLeather=" .. refundPlan.leather
            .. " refundThreadUses=" .. refundPlan.threadUses)
    else
        print("[SuQingContainerUpgradeAuto] upgraded " .. target:getFullType() .. " tier=" .. mode
            .. " capacity=" .. expectedCapacity .. " reduction=" .. expectedReduction)
    end
end

function C.PerformUpgradeAction(action, mode)
    if action.suQingFinished then return end
    action.suQingFinished = true -- Timed-action replay must never charge twice.
    attachCompletionRefresh(action)
    if not C.IsSinglePlayer() then return logFailure("multiplayer") end
    local locks = C.Position and C.Position.characters
    if not locks or not action.character then return logFailure("no_character") end
    if locks[action.character] then return logFailure("nested_owned_action") end
    locks[action.character] = action
    local ok, message = pcall(performLocked, action, mode)
    -- Shared with Position and Variant, including callback-triggered reentry.
    if locks[action.character] == action then locks[action.character] = nil end
    if not ok then
        print("[SuQingContainerUpgradeAuto] action exception; recovery not assumed: " .. tostring(message))
        logFailure("exception")
    end
end

function C.InstallCraftGuard()
    if C.craftGuardInstalled or not ISHandcraftAction or not ISHandcraftAction.performRecipe then return end
    local original = ISHandcraftAction.performRecipe
    ISHandcraftAction.performRecipe = function(self, ...)
        local mode = C.GetRecipeMode(self.craftRecipe)
        if mode == nil then return original(self, ...) end
        local ok, message = pcall(C.PerformUpgradeAction, self, mode)
        if not ok then
            print("[SuQingContainerUpgradeAuto] action exception; recovery not assumed: " .. tostring(message))
            logFailure("exception")
        end
    end
    C.craftGuardInstalled = true
    print("[SuQingContainerUpgradeAuto] " .. C.version .. " ready; native queue reservation fix; same-instance upgrades")
end

Events.OnGameStart.Add(C.InstallCraftGuard)
