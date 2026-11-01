local C = SuQingContainerUpgradeAuto
local A = C.Auto
local oldList = List
function List(values)
    local value = oldList(values)
    function value:clear() self.values = {} end
    return value
end
ItemType = {CONTAINER = "container"}
AutoScripts, AutoRecipes = {}, {}
Activated = List({"SuQingContainerUpgradeAuto_4221"})
function getActivatedMods() return Activated end
function AutoScript(fullType)
    local s = {fullType = fullType, extra = List(), itemType = "container"}
    function s:getFullName() return self.fullType end
    function s:getObsolete() return self.obsolete or false end
    function s:isHidden() return self.hidden or false end
    function s:isItemType(t) return self.itemType == t end
    function s:getClothingItemExtra() return self.extra end
    AutoScripts[fullType] = s
    return s
end
AutoManager = {}
function AutoManager:getItem(id) return AutoScripts[id] end
function AutoManager:getAllItems()
    local r = List()
    for _, s in pairs(AutoScripts) do r:add(s) end
    return r
end
function AutoManager:getCraftRecipe(id) return AutoRecipes[id] end
function getScriptManager() return AutoManager end
for i = 1, 6 do
    local name = i == 6 and "SuQingAutoRestore" or ("SuQingAutoUpgrade" .. i)
    local input = {ids = List({"Base.Bag_Schoolbag"}), cache = List()}
    function input:isKeep() return true end
    function input:isItemCount() return true end
    function input:getItems() return self.ids end
    function input:getPossibleInputItems() return self.cache end
    AutoRecipes["SuQingContainerUpgradeAuto." .. name] = {getInputs = function() return List({input}) end}
end
AutoScript("Base.Bag_Schoolbag")
AutoScript("Base.Bag_cat_5")
AutoScript("Base.MaoMaoBackpack")
AutoScript("CodexCBRT.SST02_ChestRig")
AutoScript("FutureMod.StandardBag")
function AutoBag(fullType, cap, wr, weight)
    local p = Character()
    local b = Bag(p, fullType or "FutureMod.StandardBag", cap or 10)
    b.md.SuQingContainerUpgrade = nil
    b.wr, b.weight, b.slot = wr or 50, weight or 1, "base:back"
    function b:canBeEquipped() return self.slot end
    function b:setCapacity(v)
        self.capacityWrites = self.capacityWrites + 1
        if self.failCapacity then error("capacity setter failed") end
        self.inner.capacity = v
    end
    function b:setWeightReduction(v)
        self.reductionWrites = self.reductionWrites + 1
        if self.failReductionOnce then self.failReductionOnce = nil; error("reduction setter failed") end
        self.wr = v
    end
    function b:getLuaCreate() return self.createCallback end
    function b:getClothingExtraSubmenu() return self.submenu end
    AutoScript(b:getFullType())
    return p, b
end
function AutoData(b)
    return {getAllKeepInputItems = function() return List({b}) end}
end
function PaidAction(p, b, tier, options)
    options = options or {}
    local cost = type(tier) == "number" and C.tiers[tier] or {cloth=0, leather=0, thread=0}
    local needle, thread = Material("Base.Needle"), Material("Base.Thread", 20)
    p.inventory:AddItem(needle); p.inventory:AddItem(thread)
    local all, consumed = List({b, needle, thread}), {}
    for i=1,cost.cloth do local x=Material("Base.RippedSheets");p.inventory:AddItem(x);all:add(x);consumed[#consumed+1]=x end
    for i=1,cost.leather do local x=Material("Base.LeatherStrips");p.inventory:AddItem(x);all:add(x);consumed[#consumed+1]=x end
    local data = {processed=0}
    function data:getAllKeepInputItems() return List({b,needle}) end
    function data:getAllInputItems() return all end
    function data:processDestroyAndUsedItems()
        self.processed=self.processed+1
        if not options.free then thread.uses=thread.uses-cost.thread end
        if options.throwProcess then error("processor failure after payment") end
    end
    local logic={calls=0}
    function logic:getRecipeData() return data end
    function logic:performCurrentRecipe()
        self.calls=self.calls+1
        if options.insufficient then return false end
        if not options.free then for _,x in ipairs(consumed)do p.inventory:Remove(x)end end
        return true
    end
    local name=tier=="restore" and "SuQingAutoRestore" or ("SuQingAutoUpgrade"..tier)
    local action={character=p,logic=logic,craftRecipe=Recipe("SuQingContainerUpgradeAuto."..name)}
    return action, {data=data,logic=logic,thread=thread,consumed=consumed}
end
A.ready=true
C.InstallCraftGuard()
