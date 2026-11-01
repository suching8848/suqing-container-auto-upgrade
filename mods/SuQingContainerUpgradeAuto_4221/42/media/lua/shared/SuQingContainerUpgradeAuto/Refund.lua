-- Actual-payment accounting only. No preview writes, global registry or scan.
SuQingContainerUpgradeAuto = SuQingContainerUpgradeAuto or {}
local C = SuQingContainerUpgradeAuto
C.Refund = C.Refund or {}
local R = C.Refund
if R.loaded then return R end
R.loaded = true
R.ledgerKeys = { "paidLedgerVersion", "paidCloth", "paidLeather", "paidThreadUses" }

local function integer(value, high)
    return type(value) == "number" and value == math.floor(value) and value >= 0 and value <= high
end

local function limits()
    local result = { cloth = 0, leather = 0, threadUses = 0 }
    for _, tier in ipairs(C.tiers) do
        result.cloth = result.cloth + tier.cloth
        result.leather = result.leather + tier.leather
        result.threadUses = result.threadUses + tier.thread
    end
    return result
end

function R.ReadLedger(record)
    if record ~= nil and type(record) ~= "table" then return nil, "invalid_payment_ledger" end
    local present = false
    for _, key in ipairs(R.ledgerKeys) do if record and record[key] ~= nil then present = true end end
    if not present then return { present = false, cloth = 0, leather = 0, threadUses = 0 } end
    local maximum = limits()
    if record.paidLedgerVersion ~= 1 or not integer(record.paidCloth, maximum.cloth)
        or not integer(record.paidLeather, maximum.leather)
        or not integer(record.paidThreadUses, maximum.threadUses) then
        return nil, "invalid_payment_ledger"
    end
    return { present = true, cloth = record.paidCloth, leather = record.paidLeather,
        threadUses = record.paidThreadUses }
end

function R.CopyLedger(record, destination)
    local ledger, reason = R.ReadLedger(record)
    if not ledger then return false, reason end
    if ledger.present then
        destination.paidLedgerVersion = 1
        destination.paidCloth = ledger.cloth
        destination.paidLeather = ledger.leather
        destination.paidThreadUses = ledger.threadUses
    end
    return true
end

-- A failed native conversion may retain its fresh target to protect unrecovered
-- contents. It must not retain a second copy of the source's payment entitlement.
-- Clone the own record: native copyModData may have shared its table with source.
function R.DropLedger(item)
    local md = item:getModData()
    local record = md[C.modDataKey]
    if record == nil then return true end
    if type(record) ~= "table" then return false end
    local present = false
    for _, key in ipairs(R.ledgerKeys) do if record[key] ~= nil then present = true end end
    if not present then return true end
    local updated = {}
    for key, value in pairs(record) do updated[key] = value end
    for _, key in ipairs(R.ledgerKeys) do updated[key] = nil end
    md[C.modDataKey] = updated
    local observed = item:getModData()[C.modDataKey]
    if type(observed) ~= "table" then return false end
    for _, key in ipairs(R.ledgerKeys) do if observed[key] ~= nil then return false end end
    return true
end

local function contains(container, item)
    return container ~= nil and container:getItems():contains(item)
end

-- Called after native destruction/draining. Count original instances and actual
-- integer Thread uses, not recipe amounts, spool count, or the 0..1 fill ratio.
function R.MeasurePayment(snapshots, tierIndex)
    local tier = C.tiers[tierIndex]
    if not tier then return nil, "payment_tier" end
    local paid = { cloth = 0, leather = 0, threadUses = 0 }
    for _, snapshot in ipairs(snapshots) do
        local item, fullType = snapshot.item, snapshot.fullType
        if item:getFullType() ~= fullType then return nil, "payment_input_changed" end
        if item.getWorldItem and item:getWorldItem() ~= nil then return nil, "payment_input_in_world" end
        local current = item:getContainer()
        if current ~= nil and current ~= snapshot.container then return nil, "payment_input_moved" end
        local present = contains(snapshot.container, item)
        if fullType == "Base.RippedSheets" or fullType == "Base.LeatherStrips" then
            if not present then
                local key = fullType == "Base.RippedSheets" and "cloth" or "leather"
                paid[key] = paid[key] + 1
            end
        elseif fullType == "Base.Thread" then
            local now = item:getCurrentUses()
            if not integer(snapshot.threadUnits, 100000) or not integer(now, snapshot.threadUnits)
                or (now > 0 and not present) then return nil, "payment_thread_changed" end
            paid.threadUses = paid.threadUses + snapshot.threadUnits - now
        elseif not present then
            return nil, "payment_kept_input_changed"
        end
    end
    -- BuildCheat/free crafting must not mint a refundable payment. Partial or
    -- unexpected payment cannot be trusted; the caller rolls it back instead.
    if paid.cloth == 0 and paid.leather == 0 and paid.threadUses == 0 then return paid end
    if paid.cloth ~= tier.cloth or paid.leather ~= tier.leather or paid.threadUses ~= tier.thread then
        return nil, "payment_cost_mismatch"
    end
    return paid
end

function R.CommitPayment(item, snapshots, tierIndex)
    local paid, reason = R.MeasurePayment(snapshots, tierIndex)
    if not paid then return false, reason end
    local record = C.GetRecord(item)
    if not C.IsValidRecord(record) then return false, "payment_record_changed" end
    local ledger, ledgerReason = R.ReadLedger(record)
    if not ledger then return false, ledgerReason end
    if paid.cloth == 0 and paid.leather == 0 and paid.threadUses == 0 then return true end
    local maximum = limits()
    local cloth, leather, thread = ledger.cloth + paid.cloth, ledger.leather + paid.leather,
        ledger.threadUses + paid.threadUses
    if not integer(cloth, maximum.cloth) or not integer(leather, maximum.leather)
        or not integer(thread, maximum.threadUses) then return false, "payment_limit" end
    -- Never mutate a previous snapshot's record in place. Known rollback paths
    -- restore that exact original table, with its original payment entitlement.
    local updated = {}
    for key, value in pairs(record) do updated[key] = value end
    updated.paidLedgerVersion = 1
    updated.paidCloth, updated.paidLeather, updated.paidThreadUses = cloth, leather, thread
    item:getModData()[C.modDataKey] = updated
    return C.GetRecord(item) == updated, "payment_commit"
end

local function fresh(item, fullType)
    return item ~= nil and item:getFullType() == fullType and item:getContainer() == nil
        and (not item.getWorldItem or item:getWorldItem() == nil)
end

function R.StageRefund(record, character)
    local ledger, reason = R.ReadLedger(record)
    if not ledger then return nil, reason end
    local plan = { inventory = character:getInventory(), entries = {}, started = false,
        cloth = math.floor(ledger.cloth / 2), leather = math.floor(ledger.leather / 2),
        threadUses = math.floor(ledger.threadUses / 2) }
    local seen = {}
    local function create(fullType, uses)
        local item = instanceItem(fullType)
        if not fresh(item, fullType) or seen[item] then error("refund_factory_not_fresh") end
        seen[item] = true
        if uses then
            local delta = item:getUseDelta()
            if type(delta) ~= "number" or delta ~= delta or delta <= 0 or delta > 1 then error("refund_thread_delta") end
            item:setCurrentUsesFloat(uses * delta)
            if item:getCurrentUses() ~= uses then error("refund_thread_amount") end
        end
        plan.entries[#plan.entries + 1] = { item = item, fullType = fullType, uses = uses }
        return item
    end
    for index = 1, plan.cloth do create("Base.RippedSheets") end
    for index = 1, plan.leather do create("Base.LeatherStrips") end
    local remaining = plan.threadUses
    while remaining > 0 do
        -- Use the created native spool's own UseDelta, including any legitimate
        -- script update; never grant an unconfigured full spool to inventory.
        local item = instanceItem("Base.Thread")
        if not fresh(item, "Base.Thread") or seen[item] then error("refund_factory_not_fresh") end
        seen[item] = true
        local delta = item:getUseDelta()
        if type(delta) ~= "number" or delta ~= delta or delta <= 0 or delta > 1 then error("refund_thread_delta") end
        local units = math.min(remaining, math.floor(1 / delta + 0.00001))
        if units < 1 then error("refund_thread_delta") end
        item:setCurrentUsesFloat(units * delta)
        if item:getCurrentUses() ~= units then error("refund_thread_amount") end
        plan.entries[#plan.entries + 1] = { item = item, fullType = "Base.Thread", uses = units }
        remaining = remaining - units
    end
    return plan
end

function R.InsertRefund(plan)
    plan.started = true
    for _, entry in ipairs(plan.entries) do
        local item = entry.item
        if not fresh(item, entry.fullType) then error("refund_output_changed") end
        entry.attempted = true
        if plan.inventory:AddItem(item) ~= item or not contains(plan.inventory, item)
            or item:getContainer() ~= plan.inventory then error("refund_output_not_added") end
    end
    for _, entry in ipairs(plan.entries) do
        if not contains(plan.inventory, entry.item) or entry.item:getContainer() ~= plan.inventory
            or entry.item:getFullType() ~= entry.fullType
            or (entry.uses and entry.item:getCurrentUses() ~= entry.uses) then error("refund_verification") end
    end
    return true
end

-- Remove only our freshly staged output instances. An Add/Remove callback may
-- throw after doing its work, so judge cleanup by observed presence, not pcall.
function R.RevokeRefund(plan)
    if not plan or not plan.started then return true end
    local allOK = true
    for _, entry in ipairs(plan.entries) do
        local item = entry.item
        local inspected, wasPresent, intact = pcall(function()
            return contains(item:getContainer(), item) or contains(plan.inventory, item),
                item:getFullType() == entry.fullType and (not entry.uses or item:getCurrentUses() == entry.uses)
        end)
        -- Absence after an attempted Add is ambiguous: it might have failed
        -- before insertion, or an OnAdded callback may already have consumed
        -- the output. Likewise drained Thread has already provided a benefit.
        -- Remove anything we can, but do not reissue that payment entitlement.
        if not inspected or not intact or (entry.attempted and not wasPresent) then allOK = false end
        pcall(function()
            local current = item:getContainer()
            if contains(current, item) then current:Remove(item) end
            if contains(plan.inventory, item) then plan.inventory:Remove(item) end
        end)
        local checked, absent = pcall(function()
            return not contains(item:getContainer(), item) and not contains(plan.inventory, item)
                and (not item.getWorldItem or item:getWorldItem() == nil)
                and item:getFullType() == entry.fullType
                and (not entry.uses or item:getCurrentUses() == entry.uses)
        end)
        if not checked or not absent then allOK = false end
    end
    return allOK
end

return R
