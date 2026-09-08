-- Item Count tooltip
-- Adds a Bags/Bank/Equipped breakdown to item tooltips. The ClassicAPI
-- edition reads this from C_Item.GetItemCount, which this build's API does
-- not have -- this backport counts bags/bank/equipped itself using stock
-- 1.12 container functions, and uses pfUI's own libtooltip (already part of
-- this addon) instead of the newer GameTooltip:HasItem()/:GetItem().
--
-- Note: bank slots (container -1 and 5-10) only report real data once the
-- bank has been opened at least once this session -- a stock vanilla-client
-- limitation, not something we can work around client-side. Before that,
-- the bank line simply won't show.
--
-- Simplification vs. the ClassicAPI edition: this skips the "is this item
-- unique-equipped" pre-check (no native equivalent without a tooltip scan)
-- -- worst case a unique item shows a slightly redundant total line, it's
-- otherwise harmless.
pfUI:RegisterModule("itemcount", "vanilla:tbc", function ()
  local function CountBags(id)
    local count = 0
    for bag = 0, NUM_BAG_SLOTS do
      for slot = 1, (GetContainerNumSlots(bag) or 0) do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local _, _, linkID = string.find(link, "item:(%d+):")
          if tonumber(linkID) == id then
            local _, itemCount = GetContainerItemInfo(bag, slot)
            count = count + (itemCount or 1)
          end
        end
      end
    end
    return count
  end

  local function CountBank(id)
    local count = 0
    local bankBags = { BANK_CONTAINER }
    for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
      table.insert(bankBags, bag)
    end
    for _, bag in ipairs(bankBags) do
      for slot = 1, (GetContainerNumSlots(bag) or 0) do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local _, _, linkID = string.find(link, "item:(%d+):")
          if tonumber(linkID) == id then
            local _, itemCount = GetContainerItemInfo(bag, slot)
            count = count + (itemCount or 1)
          end
        end
      end
    end
    return count
  end

  local function CountEquipped(id)
    local count = 0
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
      if GetInventoryItemID("player", slot) == id then
        count = count + 1
      end
    end
    return count
  end

  local function AddCounts(frame, id)
    if not id or id == HEARTHSTONE_ITEM_ID then return end

    local bags     = CountBags(id)
    local bank     = CountBank(id)
    local equipped = CountEquipped(id)
    local total    = bags + bank + equipped
    if total < 1 then return end

    frame:AddLine(" ")
    if bags > 0     then frame:AddDoubleLine(T["Bags"] .. ":",     bags,     1, 1, 1, 1, 1, 1) end
    if bank > 0     then frame:AddDoubleLine(T["Bank"] .. ":",     bank,     1, 1, 1, 1, 1, 1) end
    if equipped > 0 then frame:AddDoubleLine(T["Equipped"] .. ":", equipped, 1, 1, 1, 1, 1, 1) end

    local sources = (bags > 0 and 1 or 0) + (bank > 0 and 1 or 0) + (equipped > 0 and 1 or 0)
    if sources > 1 then
      frame:AddDoubleLine(T["Total"] .. ":", total, 1, 1, 1, 1, 1, 1)
    end
    frame:Show()
  end

  pfUI.itemcount = CreateFrame("Frame", "pfItemCountTooltip", GameTooltip)
  pfUI.itemcount:SetScript("OnShow", function()
    local link = libtooltip:GetItemLink()
    if link then
      local id = libtooltip:GetItemID()
      if id then AddCounts(GameTooltip, id) end
    end
  end)

  hooksecurefunc("SetItemRef", function(link)
    local _, _, id = string.find(link or "", "item:(%d+):")
    if id then AddCounts(ItemRefTooltip, tonumber(id)) end
  end)
end)
