-- Friend notes
-- Client-side notes for friends. This server's client doesn't have a native
-- SetFriendNotes function (confirmed: calling it errors as a nil global),
-- so notes are stored entirely on our end, in pfUI_playerDB (an existing
-- per-character SavedVariable), keyed by friend name. Adds an "Edit Note"
-- entry to the friend right-click menu (the "FRIEND" UnitPopup) and shows
-- the note in a tooltip when you hover a friend in the list.
pfUI:RegisterModule("friendnotes", "vanilla:tbc", function ()
  local EDIT_TOKEN = "PFUI_FRIEND_NOTE"
  local DELETE_TOKEN = "PFUI_FRIEND_NOTE_DELETE"

  pfUI_playerDB.friendnotes = pfUI_playerDB.friendnotes or {}

  local function GetNote(name)
    if not name then return "" end
    return pfUI_playerDB.friendnotes[name] or ""
  end

  local function SetNote(name, note)
    if not name then return end
    if note and note ~= "" then
      pfUI_playerDB.friendnotes[name] = note
    else
      pfUI_playerDB.friendnotes[name] = nil
    end
  end

  -- Note editor. Vanilla 1.12's StaticPopup callbacks don't reliably pass
  -- the target name as an argument the way later clients do -- captured it
  -- as a plain upvalue instead, set right before showing the popup, so the
  -- callbacks don't depend on what `this`/the callback's own parameter
  -- actually resolves to.
  local currentNoteTarget = nil
  local currentDialogFrame = nil

  StaticPopupDialogs["PFUI_FRIEND_NOTE_EDIT"] = {
    text = SET_FRIENDNOTE_LABEL or "Note:",
    button1 = SAVE,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 128,
    OnAccept = function()
      if currentDialogFrame then
        local editbox = _G[currentDialogFrame:GetName().."EditBox"]
        SetNote(currentNoteTarget, editbox and editbox:GetText() or "")
        FriendsList_Update()
      end
    end,
    EditBoxOnEnterPressed = function()
      if currentDialogFrame then
        local editbox = _G[currentDialogFrame:GetName().."EditBox"]
        SetNote(currentNoteTarget, editbox and editbox:GetText() or "")
        currentDialogFrame:Hide()
        FriendsList_Update()
      end
    end,
    EditBoxOnEscapePressed = function()
      if currentDialogFrame then currentDialogFrame:Hide() end
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
  }

  local function OpenNoteEditor(name)
    if not name or name == "" then return end
    currentNoteTarget = name
    local dialog = StaticPopup_Show("PFUI_FRIEND_NOTE_EDIT", name)
    if not dialog then return end
    currentDialogFrame = dialog
    local editbox = _G[dialog:GetName().."EditBox"]
    editbox:SetText(GetNote(name))
    editbox:HighlightText()
    editbox:SetFocus()
  end

  -- Add "Edit Note" and "Delete Note" to the friend right-click menu, just
  -- before Cancel.
  UnitPopupButtons[EDIT_TOKEN] = { text = SET_NOTE or "Set Note", dist = 0 }
  UnitPopupButtons[DELETE_TOKEN] = { text = "Delete Note", dist = 0 }
  local friendMenu = UnitPopupMenus["FRIEND"]
  table.insert(friendMenu, table.getn(friendMenu), EDIT_TOKEN)
  table.insert(friendMenu, table.getn(friendMenu), DELETE_TOKEN)

  UnitPopupMenus["PFUI_FRIENDNOTE"] = { EDIT_TOKEN, DELETE_TOKEN, "CANCEL" }
  local function OfflineNoteDropDown_Initialize()
    UnitPopup_ShowMenu(_G[UIDROPDOWNMENU_OPEN_MENU], "PFUI_FRIENDNOTE", nil, FriendsDropDown.name)
  end
  local FriendsFrame_ShowDropdown_orig = FriendsFrame_ShowDropdown
  _G.FriendsFrame_ShowDropdown = function(name, connected)
    if connected then return FriendsFrame_ShowDropdown_orig(name, connected) end
    HideDropDownMenu(1)
    FriendsDropDown.initialize = OfflineNoteDropDown_Initialize
    FriendsDropDown.displayMode = "MENU"
    FriendsDropDown.name = name
    ToggleDropDownMenu(1, nil, FriendsDropDown, "cursor")
  end

  -- Route our entry to the editor and close the menu; delegate the rest. A
  -- bare assignment lands on pfUI.env, so set the global explicitly.
  local UnitPopup_OnClick_orig = UnitPopup_OnClick
  _G.UnitPopup_OnClick = function()
    if this and this.value == EDIT_TOKEN then
      local dropdown = _G[UIDROPDOWNMENU_INIT_MENU]
      local name = dropdown and dropdown.name
      CloseDropDownMenus()
      OpenNoteEditor(name)
      return
    elseif this and this.value == DELETE_TOKEN then
      local dropdown = _G[UIDROPDOWNMENU_INIT_MENU]
      local name = dropdown and dropdown.name
      CloseDropDownMenus()
      if name then
        SetNote(name, "")
        FriendsList_Update()
      end
      return
    end
    return UnitPopup_OnClick_orig()
  end


  -- Small icon next to friends who have a note. Hovering it shows "Click
  -- to edit" plus the note text; clicking it opens the note editor.
  hooksecurefunc("FriendsList_Update", function()
    local off = FauxScrollFrame_GetOffset(FriendsFrameFriendsScrollFrame)
    for i = 1, FRIENDS_TO_DISPLAY do
      local button = _G["FriendsFrameFriendButton"..i]
      if button then
        if not button.pfNoteIcon then
          local iconButton = CreateFrame("Button", nil, button)
          iconButton:SetWidth(14)
          iconButton:SetHeight(14)
          iconButton:SetPoint("RIGHT", button, "RIGHT", -6, 0)

          local tex = iconButton:CreateTexture(nil, "OVERLAY")
          tex:SetAllPoints(iconButton)
          tex:SetTexture("Interface\\Icons\\INV_Misc_Note_01")

          iconButton:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText("Click to edit", 1, 0.82, 0)
            local note = GetNote(this.friendName)
            if note and note ~= "" then
              GameTooltip:AddLine(note, 1, 1, 1, 1)
            end
            GameTooltip:Show()
          end)
          iconButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
          iconButton:SetScript("OnClick", function()
            OpenNoteEditor(this.friendName)
          end)

          button.pfNoteIcon = iconButton
        end

        local name = GetFriendInfo(off + i)
        button.pfNoteIcon.friendName = name
        if name and GetNote(name) ~= "" then
          button.pfNoteIcon:Show()
        else
          button.pfNoteIcon:Hide()
        end
      end
    end
  end)
end)
