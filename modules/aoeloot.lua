-- AoE Loot
-- Automatically loots all nearby lootable corpses through ClassicAPI's
-- native corpse walker, instead of opening (or clicking through) the loot
-- window for each corpse individually. Ported from ShaguTweaks-ClassicAPI's
-- aoe-loot.lua (itself adapted from AoELoot by Sandrea) at the user's
-- request, kept opt-in (see C.loot.aoeloot below) since it changes how
-- corpse looting behaves.
--
-- Relies entirely on ClassicAPI's C_Loot/C_Container namespaces -- if this
-- build's client doesn't expose them, the module does nothing rather than
-- error (same capability check ShaguTweaks itself uses).
pfUI:RegisterModule("aoeloot", "vanilla:tbc", function ()
  if C.loot.aoeloot ~= "1" then return end

  if type(_G.C_Loot) ~= "table"
    or type(_G.C_Loot.GetNearbyLootableUnits) ~= "function"
    or type(_G.C_Loot.LootAllCorpses) ~= "function"
    or type(_G.C_Loot.IsScanInProgress) ~= "function"
  then return end

  local containerOpenable = type(_G.C_Container) == "table"
    and type(_G.C_Container.IsContainerItemOpenable) == "function"

  -- Small OnUpdate-based delayed-call helper (stand-in for C_Timer.After,
  -- same pattern already used in modules/innervatecall.lua).
  local function After(delay, callback)
    local frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function()
      elapsed = elapsed + arg1
      if elapsed >= delay then
        frame:SetScript("OnUpdate", nil)
        callback()
      end
    end)
  end

  local frame = CreateFrame("Frame", "pfAoELoot")
  local pending = false
  local containerLootDeadline = 0
  local takeoverGeneration = 0
  local TAKEOVER_DELAY = 0.3

  local function CancelTakeover()
    takeoverGeneration = takeoverGeneration + 1
    pending = false
  end

  -- Inventory containers (clams, lockboxes, ...) fire the same LOOT_OPENED
  -- event corpses do. Track container use just BEFORE UseContainerItem runs
  -- so LOOT_OPENED can be told apart from an actual corpse loot below --
  -- matches ShaguTweaks' prepend-mode hook for the same reason.
  if containerOpenable then
    local origUseContainerItem = _G.UseContainerItem
    function _G.UseContainerItem(bag, slot)
      local isOpenable, canOpen = _G.C_Container.IsContainerItemOpenable(bag, slot)
      if isOpenable and canOpen then
        containerLootDeadline = GetTime() + 3
      end
      return origUseContainerItem(bag, slot)
    end
  end

  local function IsMasterLootActive()
    if not GetLootMethod then return false end
    return GetLootMethod() == "master"
  end

  local function CanStartAoELoot()
    if IsMasterLootActive() then return false end
    if _G.C_Loot.IsScanInProgress() then return false end
    return true
  end

  local function HasNearbyLootableCorpse()
    local units = _G.C_Loot.GetNearbyLootableUnits()
    return type(units) == "table" and table.getn(units) > 0
  end

  local function StartAoELoot(generation)
    if generation ~= takeoverGeneration or not pending then return end

    pending = false
    if CanStartAoELoot() then
      _G.C_Loot.LootAllCorpses()
    end
  end

  local function TakeOverLootSession()
    -- AoE Loot owns corpse sessions while enabled. Close the normal client
    -- window immediately so autoloot (pfUI's own C.loot.autopickup included)
    -- can't keep control of the session.
    takeoverGeneration = takeoverGeneration + 1
    local generation = takeoverGeneration
    pending = true
    CloseLoot()

    -- Native autoloot may already have emitted loot packets before
    -- LOOT_OPENED reaches Lua. ClassicAPI's own loot test uses the same
    -- 0.3s settling window between loot operations; after it expires the
    -- native corpse walker becomes the sole owner of all remaining nearby
    -- corpse loot.
    After(TAKEOVER_DELAY, function()
      StartAoELoot(generation)
    end)
  end

  frame:RegisterEvent("LOOT_OPENED")
  frame:SetScript("OnEvent", function()
    if event ~= "LOOT_OPENED" then return end

    -- Inventory containers use the same loot event as corpses. Let the
    -- normal client finish them instead of treating them as an AoE-loot
    -- trigger.
    if containerLootDeadline > 0 then
      local isContainerLoot = GetTime() <= containerLootDeadline
      containerLootDeadline = 0
      if isContainerLoot then
        CancelTakeover()
        return
      end
    end

    -- The master looter must keep the normal window to inspect and assign
    -- loot.
    if IsMasterLootActive() then
      CancelTakeover()
      return
    end

    -- Chests, fishing nodes and other non-corpse sources also emit
    -- LOOT_OPENED. Only take over when ClassicAPI can see at least one
    -- nearby lootable unit.
    if not HasNearbyLootableCorpse() then return end

    -- A queued takeover already owns this interaction. ClassicAPI
    -- suppresses its own LOOT_OPENED/LOOT_CLOSED events while walking
    -- corpses, so no additional session needs to be stacked here.
    if pending then return end

    TakeOverLootSession()
  end)
end)
