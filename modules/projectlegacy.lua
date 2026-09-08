-- A module to update pfUI to match the Project Legacy server (enUS only)
-- Based on the pfUI Vanilla Plus module research by @Heroclastus09, @hawaiisa,
-- @cgoodwin117, with Project Legacy additions by @TerraBaddie.

pfUI:RegisterModule("projectlegacy", function()
  do -- add Project Legacy debuffs to dynamic debuffs
    pfUI_locale["enUS"]["dyndebuffs"]["Crusader's Inquest"] = "Crusader's Inquest"
  end

  do -- adjust Project Legacy spell durations
    pfUI_locale["enUS"]["debuffs"]['Crusader\'s Inquest'] = {[0] = 10.0,}
  end

  do -- refresh Crusader's Inquest whenever Crusader Strike successfully lands
    local libdebuff = pfUI.api.libdebuff

    if libdebuff then
      local refresh = CreateFrame("Frame")
      refresh:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")

      refresh:SetScript("OnEvent", function()
        if event ~= "CHAT_MSG_SPELL_SELF_DAMAGE" or not arg1 then return end

        local spell, unit = pfUI.api.cmatch(arg1, SPELLLOGSELFOTHER)

        if spell ~= "Crusader Strike" then
          spell, unit = pfUI.api.cmatch(arg1, SPELLLOGCRITSELFOTHER)
        end

        if spell == "Crusader Strike" and unit then
          local level = 0

          if UnitName("target") == unit then
            level = UnitLevel("target") or 0
          end

          -- AddEffect replaces the stored start time with GetTime(), which
          -- restarts the displayed pfUI timer at the full 10 second duration.
          libdebuff:AddEffect(unit, level, "Crusader's Inquest", 10.0, "player")
        end
      end)
    end
  end
end)
