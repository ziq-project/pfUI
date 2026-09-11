-- New Item highlight
-- Glows bag slots holding an item the client considers "new" (looted since
-- the last time it was acknowledged), backed by ClassicAPI's C_NewItems.
-- Ported from brues-code/pfUI (upstream), 2026-09-11. Adapted to this fork:
-- upstream used EventRegistry:RegisterFrameEventAndCallback (a plain
-- CreateFrame+RegisterEvent+OnEvent does the same thing without depending on
-- that convenience wrapper) and pfUI.events:RegisterCallback("bag:closed",
-- ...) (an internal pub/sub bus this fork doesn't have -- replaced with a
-- direct OnHide hook on the single combined bag window, pfUI.bag.right).
pfUI:RegisterModule("newitem", function ()
  if not pfUI.bag then return end
  if C.appearance.bags.newitem ~= "1" then return end
  if type(C_NewItems) ~= "table" then return end

  pfUI.newitem = {}

  local r, g, b, a = pfUI.api.GetStringColor(C.appearance.bags.newitem_color)

  function pfUI.newitem:UpdateSlot(bag, slot)
    if bag < 0 or bag > 4 then return end
    if not pfUI.bags[bag] then return end
    if not pfUI.bags[bag].slots[slot] then return end

    local frame = pfUI.bags[bag].slots[slot].frame

    if frame.hasItem and C_NewItems.IsNewItem(bag, slot) then
      if not frame.newitem then
        local glow = frame:CreateTexture(nil, "OVERLAY")
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(r, g, b, a)
        glow:SetPoint("CENTER", frame, "CENTER")
        glow:Hide()
        glow.RefreshSize = function(g)
          local w = g:GetParent():GetWidth()
          if w > 0 then g:SetSize(w * 1.8, w * 1.8) end
        end
        frame.newitem = glow

        frame:HookScript("OnEnter", function()
          C_NewItems.RemoveNewItem(bag, slot)
        end)
      end
      frame.newitem:RefreshSize()
      frame.newitem:Show()
    elseif frame.newitem and frame.newitem:IsShown() then
      frame.newitem:Hide()
    end
  end

  -- The new-item set can change without any slot's contents changing (an item
  -- acknowledged, pruned when it leaves the bags, or ClearAll) -- re-evaluate
  -- every decorated slot when that happens.
  function pfUI.newitem:RefreshAll()
    for bag in pairs(pfUI.bags) do
      local slots = pfUI.bags[bag] and pfUI.bags[bag].slots
      if slots then
        for slot in pairs(slots) do
          pfUI.newitem:UpdateSlot(bag, slot)
        end
      end
    end
  end

  -- per-slot: pfUI re-runs UpdateSlot whenever a slot's contents change.
  hooksecurefunc(pfUI.bag, "UpdateSlot", function(self, bag, slot)
    pfUI.newitem:UpdateSlot(bag, slot)
  end)

  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("BAG_NEW_ITEMS_UPDATED")
  watcher:SetScript("OnEvent", function()
    pfUI.newitem:RefreshAll()
  end)

  -- Forget the new-item set once the player closes the (single, combined)
  -- bag window -- matches upstream's "bag:closed" behavior without needing
  -- its internal event bus.
  pfUI.bag.right:HookScript("OnHide", function()
    C_NewItems.ClearAll()
  end)
end)
