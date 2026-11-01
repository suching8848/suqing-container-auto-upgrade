local C, A = SuQingContainerUpgradeAuto, SuQingContainerUpgradeAuto.Auto
local case, eq, ok = Review.case, Review.eq, Review.ok
case("independent ID namespace and payment key",function()
    eq(C.modDataKey,"SuQingContainerUpgradeAuto");eq(SuQingContainerUpgrade,nil)
end)
case("new independent Chemical rig automatically accepted",function()
    local p,b=AutoBag("CodexCBRT.SST02_ChestRig",12,90)
    ok(C.IsSupported(b));eq(C.GetState(b).nextLevel,2)
    ok(C.Upgrade(AutoData(b),p,2));eq(b.inner.capacity,20);eq(b.wr,93)
    eq(C.GetRecord(b).fullType,b:getFullType());eq(b.md.SuQingContainerUpgrade,nil)
end)
case("future mod ID needs no whitelist entry",function()
    local p,b=AutoBag("NeverSeenBefore.NewBag",7,35)
    eq(A.known[b:getFullType()],nil);ok(C.IsSupported(b));eq(C.compatibility.profiles[b:getFullType()],"mod_container")
end)
for _,spec in ipairs({
    {"nonwearable",function(b)b.slot=nil end},
    {"empty slot",function(b)b.slot="" end},
    {"missing script",function(b)AutoScripts[b:getFullType()]=nil end},
    {"obsolete script",function(b)AutoScripts[b:getFullType()].obsolete=true end},
    {"hidden script",function(b)AutoScripts[b:getFullType()].hidden=true end},
    {"native conversion",function(b)AutoScripts[b:getFullType()].extra=List({"OtherBag"})end},
    {"conversion submenu",function(b)b.submenu="Resize"end},
    {"on create callback",function(b)b.createCallback="Foreign.onCreate"end},
    {"dynamic effective capacity",function(b)function b.inner:getEffectiveCapacity()return 80 end end},
    {"dynamic item capacity",function(b)function b:getCapacity()return 80 end end},
    {"raw high capacity",function(b)b.inner.capacity=60 end},
    {"at physical safety limit",function(b)b.inner.capacity=49 end},
    {"invalid reduction",function(b)b.wr=101 end},
    {"noninteger capacity",function(b)b.inner.capacity=12.5 end},
    {"invalid weight",function(b)b.weight=50 end},
    {"negative weight",function(b)b.weight=-1 end},
    {"API exception",function(b)function b:canBeEquipped()error("foreign API failure")end end},
    {"old paid record",function(b)b.md.SuQingContainerUpgrade={level=1}end},
})do
    case("reject "..spec[1],function()
        local p,b=AutoBag("Probe."..string.gsub(spec[1]," ","_"),10,50)
        spec[2](b);eq(C.IsSupported(b),false);eq(C.Test1(b,p),false)
        eq(b.capacityWrites,0);eq(b.reductionWrites,0)
    end)
end
for _,id in ipairs({"Base.MaoMaoBackpack","Base.Bag_cat_1","Base.Bag_cat_5","Base.MikuBackPack","LB.Bag_LegendaryBackpack"})do
    case("preserve exact exclusion "..id,function()local p,b=AutoBag(id,10,50);eq(C.IsSupported(b),false)end)
end
case("all five tiers and original restore",function()
    local p,b=AutoBag("Future.FiveTier",10,50)
    for i=1,5 do ok(C.Upgrade(AutoData(b),p,i));eq(b.inner.capacity,C.tiers[i].capacity);eq(b.wr,C.tiers[i].weightReduction)end
    eq(C.CanUpgrade(b,p,5),false);ok(C.Restore(AutoData(b),p));eq(b.inner.capacity,10);eq(b.wr,50)
    eq(b.md[C.modDataKey],nil);eq(C.CanRestore(b,p),false)
end)
case("heavy standard clips capacity and keeps self weight",function()
    local p,b=AutoBag("Future.Heavy",10,50,3.2)
    for i=1,5 do ok(C.Upgrade(AutoData(b),p,i))end
    eq(b.inner.capacity,46);eq(b.weight,3.2);ok(C.Restore(AutoData(b),p));eq(b.inner.capacity,10)
end)
case("filters tags visual fluid and foreign data retain identity",function()
    local p,b=AutoBag("Future.Filtered",10,100)
    local filter=function()return false end;b.inner.acceptItem=filter;b.inner.maxItemSize=1.3
    local fluid,visual,foreign=b.fluid,b.visual,b.md.foreign
    ok(C.Upgrade(AutoData(b),p,1));eq(b.wr,100);eq(b.fluid,fluid);eq(b.visual,visual)
    eq(b.inner.acceptItem,filter);eq(b.inner.maxItemSize,1.3);eq(b.md.foreign,foreign)
end)
for _,spec in ipairs({
    {"contents",function(p,b)b.inner:AddItem(Material("Base.Rock"))end},
    {"liquid",function(p,b)b.fluid.amount=.01 end},
    {"worn",function(p,b)p.worn[b]=true end},
    {"hand",function(p,b)p.primary=b end},
    {"not carried",function(p,b)p.inventory:Remove(b)end},
    {"skill",function(p,b)p.skill=0 end},
})do
    case("paid precondition "..spec[1],function()
        local p,b=AutoBag("Future.Precondition",12,90);spec[2](p,b)
        eq(C.CanUpgrade(b,p,2),false);eq(b.md[C.modDataKey],nil)
    end)
end
case("native material input remains accepted but rejected containers fail OnTest",function()
    local p,b=AutoBag("Future.Box",10,50);b.slot=nil
    eq(C.Test1(Material("Base.Needle"),p),true);eq(C.Test1(b,p),false)
end)
case("old enabled version disables new actions",function()
    local p,b=AutoBag();Activated:add("SuQingContainerUpgrade_4221")
    eq(C.IsSinglePlayer(),false);eq(C.IsSupported(b),false);eq(C.CanUpgrade(b,p,1),false)
    Activated:remove("SuQingContainerUpgrade_4221")
end)
case("multiplayer refuses automatic operations",function()
    local p,b=AutoBag();MPClient=true;eq(C.CanUpgrade(b,p,1),false);MPClient=false
end)
case("restore after source becomes conversion",function()
    local p,b=AutoBag("Future.LaterSpecial",10,50);ok(C.Upgrade(AutoData(b),p,1))
    AutoScripts[b:getFullType()].extra=List({"NewVariant"})
    eq(C.CanUpgrade(b,p,2),false);ok(C.CanRestore(b,p));ok(C.Restore(AutoData(b),p));eq(b.inner.capacity,10)
end)
case("corrupt auto record cannot be restored or charged",function()
    local p,b=AutoBag("Future.Corrupt",10,50);ok(C.Upgrade(AutoData(b),p,1));b.md[C.modDataKey].level=99
    eq(C.CanUpgrade(b,p,2),false);eq(C.CanRestore(b,p),false)
end)
case("setter probe failure retains source and does not create record",function()
    local p,b=AutoBag("Future.Setter",10,50);b.failReductionOnce=true
    eq(C.ProbeChange(b,p,1),false);eq(b.inner.capacity,10);eq(b.wr,50);eq(b.md[C.modDataKey],nil)
end)
case("real crafting guard records payment once",function()
    local p,b=AutoBag("Future.Paid",10,50);local action,f=PaidAction(p,b,1)
    C.PerformUpgradeAction(action,1);local r=C.GetRecord(b)
    eq(f.logic.calls,1);eq(f.data.processed,1);eq(r.paidCloth,4);eq(r.paidThreadUses,2)
    C.PerformUpgradeAction(action,1);eq(f.logic.calls,1);eq(f.thread.uses,18)
end)
case("material processing failure restores original material objects and target",function()
    local p,b=AutoBag("Future.Rollback",10,50);local action,f=PaidAction(p,b,1,{throwProcess=true})
    C.PerformUpgradeAction(action,1);eq(b.inner.capacity,10);eq(b.wr,50);eq(C.GetRecord(b),nil);eq(f.thread.uses,20)
    for _,x in ipairs(f.consumed)do ok(p.inventory:getItems():contains(x))end
end)
case("insufficient materials do not upgrade",function()
    local p,b=AutoBag("Future.Poor",10,50);local action,f=PaidAction(p,b,1,{insufficient=true})
    C.PerformUpgradeAction(action,1);eq(b.inner.capacity,10);eq(C.GetRecord(b),nil);eq(f.thread.uses,20)
end)
case("free craft does not mint refund ledger",function()
    local p,b=AutoBag("Future.Free",10,50);local action,f=PaidAction(p,b,1,{free=true})
    C.PerformUpgradeAction(action,1);eq(C.Refund.ReadLedger(C.GetRecord(b)).cloth,0)
end)
case("paid restore returns half once",function()
    local p,b=AutoBag("Future.Refund",10,50);local action,f=PaidAction(p,b,1);C.PerformUpgradeAction(action,1)
    local before=p.inventory:getItems():size();local restore=PaidAction(p,b,"restore")
    local withTools=p.inventory:getItems():size();C.PerformUpgradeAction(restore,"restore")
    eq(p.inventory:getItems():size(),withTools+3);eq(b.inner.capacity,10);eq(C.GetRecord(b),nil)
    local count=p.inventory:getItems():size();C.PerformUpgradeAction(restore,"restore");eq(p.inventory:getItems():size(),count)
end)
case("foreign native recipes pass through",function()
    eq(ISHandcraftAction.performRecipe({craftRecipe=Recipe("Foreign.Other")},"unchanged"),"unchanged")
end)
case("definition-only discovery updates both native input lists",function()
    A.ready=false;ok(A.Install());ok(A.ready)
    local input=AutoRecipes["SuQingContainerUpgradeAuto.SuQingAutoUpgrade1"]:getInputs():get(0)
    ok(input:getItems():contains("CodexCBRT.SST02_ChestRig"))
    ok(input:getPossibleInputItems():contains(AutoScripts["CodexCBRT.SST02_ChestRig"]))
    eq(input:getItems():contains("Base.MaoMaoBackpack"),false)
    eq(input:getItems():contains("Base.Bag_cat_5"),false)
    ok(AutoRecipes["SuQingContainerUpgradeAuto.SuQingAutoRestore"]:getInputs():get(0):getItems():contains("Base.Bag_cat_5"))
    local count=input:getItems():size();ok(A.Install());eq(input:getItems():size(),count)
end)
case("recipe cache failure rolls back all candidate lists and stays disabled",function()
    A.ready=false
    local input=AutoRecipes["SuQingContainerUpgradeAuto.SuQingAutoUpgrade2"]:getInputs():get(0)
    local cache=input.cache;local original=cache.add;local failed=false
    function cache:add(v)if not failed then failed=true;error("cache failure")end;return original(self,v)end
    local first=AutoRecipes["SuQingContainerUpgradeAuto.SuQingAutoUpgrade1"]:getInputs():get(0)
    local before=first.ids:size();AutoScript("Future.AddedDefinition")
    eq(A.Install(),false);eq(A.ready,false);eq(first.ids:size(),before)
    cache.add=original;ok(A.Install())
end)
case("missing recipe refuses discovery before mutating lists",function()
    A.ready=false;local key="SuQingContainerUpgradeAuto.SuQingAutoRestore";local recipe=AutoRecipes[key];AutoRecipes[key]=nil
    eq(A.Install(),false);eq(A.ready,false);AutoRecipes[key]=recipe;ok(A.Install())
end)
return Review.finish()
