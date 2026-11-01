-- Correct RaccoonCity's existing footer only. Native item stats, native tooltip
-- rows and ISToolTipInv.render remain untouched.
require "ISUI/ISToolTipInv"
require "SuQingContainerUpgradeAuto/Dynamic"

local C = SuQingContainerUpgradeAuto
local D = C.Dynamic
C.DynamicTooltip = C.DynamicTooltip or {}
local T = C.DynamicTooltip

local function pack(...)
    return { n = select("#", ...), ... }
end

local function prepare(self)
    local tooltip = self.tooltip
    local character = tooltip:getCharacter()
    local capacity = D.GetEffectiveCapacity(self.item, character)
    if type(capacity) ~= "number" or capacity ~= capacity or capacity < 1 then return nil end
    return {
        text = getText("Tooltip_SuQing_ActualCapacity", tostring(capacity)),
        font = tooltip:getFont(),
        height = tooltip:getHeight(),
    }
end

function T.Wrap(original)
    return function(self, ...)
        -- RaccoonCity only injects its footer for contained items. Its temporary
        -- instance methods identify that in-progress render, so a direct call to
        -- the continuation cannot acquire an extra line.
        if type(self) ~= "table" or not self.item or not D.IsDynamic(self.item)
            or not self.item:getContainer() or not ISToolTipInv then
            return original(self, ...)
        end
        local previousBorder = rawget(self, "drawRectBorder")
        local previousHeight = rawget(self, "setHeight")
        local classBorder = ISToolTipInv.drawRectBorder
        local classHeight = ISToolTipInv.setHeight
        if not previousBorder or not previousHeight or previousBorder == classBorder
            or previousHeight == classHeight or not classBorder or not classHeight then
            return original(self, ...)
        end

        -- Metadata/translation failures retain RaccoonCity's original line. The
        -- original render still runs exactly once, including other mod wrappers.
        local ready, footer = pcall(prepare, self)
        if ready and footer then
            self.drawRectBorder = function(panel, ...)
                panel.tooltip:DrawText(footer.font, footer.text, 5, footer.height, 1, 0, 0, 1)
                return classBorder(panel, ...)
            end
        end
        local result = pack(pcall(original, self, ...))
        if result[1] then
            -- Let the surrounding RaccoonCity render perform its normal restore.
            self.drawRectBorder = previousBorder
        else
            -- Its unprotected render cannot reach its own finally-equivalent on
            -- an error. Restore the same class methods it normally restores.
            self.drawRectBorder = classBorder
            self.setHeight = classHeight
        end
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
end

function T.Install()
    if T.installedContinuation then
        return BackpackCapacity_Render == T.installedContinuation
    end
    if not C.IsSinglePlayer() or type(BackpackCapacity_Render) ~= "function"
        or not ISToolTipInv or not D or type(D.GetEffectiveCapacity) ~= "function" then
        return false
    end
    local wrapper = T.Wrap(BackpackCapacity_Render)
    BackpackCapacity_Render = wrapper
    T.installedContinuation = wrapper
    return true
end

Events.OnGameStart.Add(T.Install)
return T
