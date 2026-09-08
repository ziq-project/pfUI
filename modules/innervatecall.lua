-- Innervate Callout Module
-- Announces Innervate casts via raid/party/battleground chat.
-- Uses Nampower's AURA_CAST_ON_SELF/AURA_CAST_ON_OTHER events directly -
-- zero polling, pure event-driven. This is the one piece of the backport
-- that depends on Nampower itself (not on ClassicAPI, which this build
-- doesn't have) firing those two events; if nothing ever announces after
-- an Innervate cast, that's the signal this Nampower build doesn't send
-- them and we'd need a different detection path.
pfUI:RegisterModule("innervatecall", "vanilla:tbc", function ()
  -- Requires Nampower for AURA_CAST events
  if not GetNampowerVersion then return end

  -- Only load for druids
  local _, playerClass = UnitClass("player")
  if playerClass ~= "DRUID" then return end

  local INNERVATE_SPELLID = 29166
  local _, playerGUID = UnitExists("player")

  -- GUID -> unit token resolution for the target, without a native
  -- UnitTokenFromGUID: walk the tokens a GUID could plausibly be bound to.
  local CANDIDATE_TOKENS = { "player", "target", "focus", "pet" }
  for i = 1, 4 do
    table.insert(CANDIDATE_TOKENS, "party"..i)
    table.insert(CANDIDATE_TOKENS, "partypet"..i)
  end
  for i = 1, 40 do
    table.insert(CANDIDATE_TOKENS, "raid"..i)
    table.insert(CANDIDATE_TOKENS, "raidpet"..i)
  end

  local function ResolveTargetName(targetGuid)
    if not targetGuid then return nil end
    for i = 1, table.getn(CANDIDATE_TOKENS) do
      local token = CANDIDATE_TOKENS[i]
      local exists, guid = UnitExists(token)
      if exists and guid == targetGuid then
        return UnitName(token)
      end
    end
    return nil
  end

  -- Determine chat channel based on group context
  local function GetAnnounceChannel()
    local _, instanceType = IsInInstance()
    if instanceType == "pvp" then
      return "BATTLEGROUND"
    end

    if GetNumRaidMembers() > 0 then
      return "RAID"
    end

    if GetNumPartyMembers() > 0 then
      return "PARTY"
    end

    return nil
  end

  -- Small OnUpdate-based delayed-call helper (stand-in for C_Timer.After).
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

  -- Innervate has a single rank, so its spellbook slot can be resolved
  -- once by (English) name via pfUI's own libspell and reused.
  local function GetInnervateCooldownRemaining()
    local index, bookType = libspell.GetSpellIndex("Innervate")
    if not index then return nil end
    local start, duration = GetSpellCooldown(index, bookType)
    if start and duration and duration > 0 then
      local remaining = start + duration - GetTime()
      if remaining > 0 then return remaining end
    end
    return nil
  end

  -- Event frame - registers AURA_CAST directly (bypasses libdebuff hooks,
  -- which are gated behind checks meant for debuffs, not friendly buffs).
  local frame = CreateFrame("Frame")
  -- AURA_CAST_ON_SELF fires when a buff lands ON the player
  -- AURA_CAST_ON_OTHER fires when a buff lands on someone else
  -- Both needed: self-innervate = ON_SELF, innervate on others = ON_OTHER
  frame:RegisterEvent("AURA_CAST_ON_SELF")
  frame:RegisterEvent("AURA_CAST_ON_OTHER")
  frame:SetScript("OnEvent", function()
    -- AURA_CAST args: arg1=spellId, arg2=casterGuid, arg3=targetGuid
    local spellId    = arg1
    local casterGuid = arg2
    local targetGuid = arg3

    if spellId ~= INNERVATE_SPELLID then return end

    -- Only announce our own casts
    if not casterGuid or casterGuid ~= playerGUID then return end

    -- Resolve target name from GUID
    local targetName = ResolveTargetName(targetGuid) or "Unknown"

    -- Determine channel
    local channel = GetAnnounceChannel()
    if not channel then return end -- solo, no announcement

    SendChatMessage(">> Innervate casted on " .. targetName .. " <<", channel)

    -- Schedule "ready" announcement when the cooldown expires.
    local cdRemaining = GetInnervateCooldownRemaining() or 360
    After(cdRemaining, function()
      local ch = GetAnnounceChannel()
      if ch then
        SendChatMessage(">> Innervate is ready <<", ch)
      end
    end)
  end)
end)
