local addonName, OldSpellBook = ...

MAX_SKILLLINE_TABS = 8
SPELLS_PER_PAGE = 12
SPELLBOOK_PAGENUMBERS = {}

-- This ensures the table is globally accessible
_G[addonName] = OldSpellBook

SpellBookUnitType = {
    [0] = "Player",
    [1] = "Pet",
    Player = 0,
    Pet = 1
}

-- Global declarations for keybinds
BINDING_HEADER_OLD_SPELLBOOK = "Old Spellbook"
BINDING_NAME_OLD_SPELLBOOK_SHOW_SPELLBOOK = "Show Spellbook"

local ceil = math.ceil
local strlen = string.len
local tinsert = table.insert
local tremove = table.remove

-- Variables for managing cooldown and pending calls
local isOnCooldown = false
local callWhenCooldownEnds = false

-- Frame to handle events
local f = CreateFrame("Frame")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("LEARNED_SPELL_IN_TAB")
f:RegisterEvent("ADDON_LOADED")

-- OnEvent handler for spellbook updates and event handling
f:SetScript("OnEvent", function(self, event, addOnName)
    -- Handle PopulatePlayerSpells with cooldown logic
    if event ~= "ADDON_LOADED" then
        HandlePopulatePlayerSpellsWithCooldown()
    end
end)

-- Function to populate the player's spell table and sort spells by type and name
function PopulatePlayerSpells()
    -- Clear the table before populating
    if OldSpellBook.SpellTable then
        table.wipe(OldSpellBook.SpellTable)
    end

    OldSpellBook.SpellTable = {
        Player = {},
        Pet = {}
    }

    -- Iterate through all skill lines
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)

        -- Combined table for both active and passive spells
        local combinedSpells = {}

        local offset, numSlots = skillLineInfo.itemIndexOffset, skillLineInfo.numSpellBookItems

        -- Iterate over each spell in the skill line
        for j = offset + 1, offset + numSlots do
            -- Get the spell name and info
            local name = C_SpellBook.GetSpellBookItemName(j, Enum.SpellBookSpellBank.Player)
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(j, Enum.SpellBookSpellBank.Player)
            local _, flyoutID = C_SpellBook.GetSpellBookItemType(j, Enum.SpellBookSpellBank.Player)
            local flyoutInfo = {};
            if spellInfo.itemType == Enum.SpellBookItemType.Flyout then
                flyoutInfo.name, flyoutInfo.description, flyoutInfo.numSlots, flyoutInfo.isKnown = GetFlyoutInfo(
                    flyoutID)
            end

            -- Only store the spell if it has a valid action ID (i.e., it's not empty)
            if name and spellInfo and spellInfo.actionID then
                local spellID = flyoutID or spellInfo.spellID or spellInfo.actionID -- Because sometimes it's on actionID

                local isKnown = IsSpellKnownOrOverridesKnown(spellID, false) or flyoutInfo.isKnown

                local spellData = {
                    newSpellBookIndex = j,
                    spellID = spellID,
                    name = name,
                    isPassive = spellInfo.isPassive,
                    isKnown = (not spellInfo.isOffSpec) and isKnown,
                    isOffSpec = spellInfo.isOffSpec,
                    icon = spellInfo.iconID,
                    spellType = spellInfo.itemType
                }

                -- Add to the combined spell table (both active and passive)
                table.insert(combinedSpells, spellData)
            end
        end

        -- Sort the combined spells by known status, active/passive status, and name
        OldSpellBook.Utils.SortSpellsByKnownActivePassiveAndName(combinedSpells)

        -- Store the sorted spells in the Player's spell table
        OldSpellBook.SpellTable["Player"][i] = combinedSpells
    end

    -- Pet Spells
    if (not C_SpellBook.HasPetSpells()) then
        return
    end

    -- Combined table for both active and passive pet spells
    local combinedSpells = {}

    local numSpells, petToken = C_SpellBook.HasPetSpells() -- nil if pet does not have spellbook, 'petToken' will usually be "PET"
    for i = 1, numSpells do
        local petSpellName, petSubType = C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Pet)
        local spellInfo = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Pet)
        local _, petActionID = C_SpellBook.GetSpellBookItemType(i, Enum.SpellBookSpellBank.Pet)

        -- Get Autocast State  for Pet Spells with Bit 1073741824
        local autoCastState = bit.band(petActionID, 1073741824) == 1073741824

        -- Only store the spell if it has a valid action ID (i.e., it's not empty)
        if petSpellName and spellInfo and spellInfo.actionID then
            local spellID = petActionID or spellInfo.spellID or spellInfo.actionID -- Because sometimes it's on actionID

            -- Perform a bitwise AND operation with the mask 0xFFFFFF (16,777,215 in decimal) if spell is known
            spellID = bit.band(spellID, 0xFFFFFF)

            local spellData = {
                newSpellBookIndex = i,
                spellID = spellID,
                name = petSpellName,
                isPassive = spellInfo.isPassive,
                isKnown = true,
                isOffSpec = spellInfo.isOffSpec,
                icon = spellInfo.iconID,
                spellType = spellInfo.itemType,
                autoCastState = autoCastState
            }

            -- Add to the combined spell table (both active and passive)
            table.insert(combinedSpells, spellData)
        end
    end

    -- Sort the combined pet spells by known status, active/passive status, and name
    OldSpellBook.Utils.SortSpellsByKnownActivePassiveAndName(combinedSpells)

    -- Store the sorted pet spells in the Pet's spell table
    OldSpellBook.SpellTable["Pet"][1] = combinedSpells
end

-- Helper function to handle PopulatePlayerSpells with cooldown
function HandlePopulatePlayerSpellsWithCooldown()
    if isOnCooldown then
        -- If the function is on cooldown, set a flag to call it after cooldown
        callWhenCooldownEnds = true
    else
        -- Call PopulatePlayerSpells and start the cooldown timer
        PopulatePlayerSpells()
        isOnCooldown = true

        -- Start a 5-second cooldown timer
        C_Timer.After(5, function()
            isOnCooldown = false
            -- Check if a call was requested during the cooldown
            if callWhenCooldownEnds then
                callWhenCooldownEnds = false
                PopulatePlayerSpells()
            end
        end)
    end
end

function OldSpellBook:ToggleOldSpellBook(bookType, forceOpen, forceClose)
    if (not C_SpellBook.HasPetSpells() and bookType == Enum.SpellBookSpellBank.Pet) then
        return;
    end

    local isShown = OldSpellBookFrame:IsShown();
    if (isShown and (OldSpellBookFrame.bookType ~= bookType)) then
        OldSpellBookFrame.suppressCloseSound = true;
    end

    HideUIPanel(OldSpellBookFrame);
    if ((not isShown or (OldSpellBookFrame.bookType ~= bookType))) then
        OldSpellBookFrame.bookType = bookType;
        OldSpellBookFrame.selectedSkillLine = 1;
        ShowUIPanel(OldSpellBookFrame);
    end
    OldSpellBookFrame_UpdatePages();

    OldSpellBookFrame.suppressCloseSound = nil;
end

function OldSpellBookFrame_OnLoad(self)
    self:RegisterEvent("SPELLS_CHANGED")
    self:RegisterEvent("LEARNED_SPELL_IN_TAB")

    OldSpellBookFrame.bookType = Enum.SpellBookSpellBank.Player

    -- Initialize page numbers for spellbook
    for i = 1, MAX_SKILLLINE_TABS do
        SPELLBOOK_PAGENUMBERS[i] = 1
    end

    -- Initialize page numbers for pet spellbook
    SPELLBOOK_PAGENUMBERS[SpellBookUnitType[Enum.SpellBookSpellBank.Pet]] = 1

    -- Ensure Enum.SpellBookSpellBank.Pet is initialized as well
    if not SPELLBOOK_PAGENUMBERS[Enum.SpellBookSpellBank.Pet] then
        SPELLBOOK_PAGENUMBERS[Enum.SpellBookSpellBank.Pet] = 1
    end

    -- Set to the first tab by default
    OldSpellBookSkillLineTab_OnClick(nil, 1)

    tinsert(UISpecialFrames, self:GetName())

end

function OldSpellBookFrame_OnEvent(self, event, ...)
    if (event == "SPELLS_CHANGED") then
        if (OldSpellBookFrame:IsVisible()) then
            OldSpellBookFrame_Update();
        end
    elseif (event == "LEARNED_SPELL_IN_TAB") then
        local arg1 = ...;
        local flashFrame = _G["OldSpellBookSkillLineTab" .. arg1 .. "Flash"];
        if (OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet) then
            return;
        end
    end
end

function OldSpellBookFrame_OnShow(self)
    OldSpellBookFrame_Update(1);

    OldSpellBookFrame_PlayOpenSound();
end

function OldSpellBookFrame_Update(showing)
    -- Hide all tabs initially
    OldSpellBookFrameTabButton1:Hide()
    OldSpellBookFrameTabButton2:Hide()
    OldSpellBookFrameTabButton3:Hide()

    -- Show the correct tab based on current book type (SPELL or PET)
    if showing then
        OldSpellBookSkillLineTab_OnClick(nil, OldSpellBookFrame.selectedSkillLine)
        OldSpellBookFrame_ShowSpells() -- This will call the updated function to refresh spells
    end

    -- Set up the tabs for skill lines or pet abilities
    local numSkillLineTabs = C_SpellBook.GetNumSpellBookSkillLines()
    for i = 1, MAX_SKILLLINE_TABS do
        local skillLineTab = _G["OldSpellBookSkillLineTab" .. i]

        if i <= numSkillLineTabs and OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Player then
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if not skillLineInfo then
                skillLineTab:Hide()
                return
            end
            if skillLineInfo.iconID then
                skillLineTab:SetNormalTexture(skillLineInfo.iconID)

                -- if offspec, desaturate the icon and spellbook tab
                if skillLineInfo.offSpecID then
                    skillLineTab:GetNormalTexture():SetDesaturated(true)
                else
                    skillLineTab:GetNormalTexture():SetDesaturated(false)
                end
            end
            skillLineTab.tooltip = skillLineInfo.name
            skillLineTab:Show()

            if OldSpellBookFrame.selectedSkillLine == i then
                skillLineTab:SetChecked(true)
            else
                skillLineTab:SetChecked(false)
            end
        else
            skillLineTab:Hide()
        end
    end

    -- Setup tabs
    local hasPetSpells, petToken = C_SpellBook.HasPetSpells();
    OldSpellBookFrame.petTitle = nil;
    if (hasPetSpells) then
        OldSpellBookFrame_SetTabType(OldSpellBookFrameTabButton1, Enum.SpellBookSpellBank.Player);
        OldSpellBookFrame_SetTabType(OldSpellBookFrameTabButton2, Enum.SpellBookSpellBank.Pet, petToken);
    else
        OldSpellBookFrame_SetTabType(OldSpellBookFrameTabButton1, Enum.SpellBookSpellBank.Player);

        if (OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet) then
            -- if has no pet spells but trying to show the pet spellbook close the window;
            HideUIPanel(OldSpellBookFrame);
            OldSpellBookFrame.bookType = Enum.SpellBookSpellBank.Player;
        end
    end

    -- Update the spellbook title and call functions for handling pet or spellbook
    if OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Player then
        OldSpellBookTitleText:SetText(SPELLBOOK)
        OldSpellBookFrame_ShowSpells()
        OldSpellBookFrame_UpdatePages()
    elseif OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet then
        OldSpellBookTitleText:SetText(OldSpellBookFrame.petTitle)
        OldSpellBookFrame_ShowSpells()
        OldSpellBookFrame_UpdatePages()
    end
end

function OldSpellBookFrame_HideSpells()
    for i = 1, SPELLS_PER_PAGE do
        _G["OldSpellButton" .. i]:Hide();
    end

    for i = 1, MAX_SKILLLINE_TABS do
        _G["OldSpellBookSkillLineTab" .. i]:Hide();
    end

    OldSpellBookPrevPageButton:Hide();
    OldSpellBookNextPageButton:Hide();
    OldSpellBookPageText:Hide();
end

function OldSpellBookFrame_ShowSpells()
    for i = 1, SPELLS_PER_PAGE do
        _G["OldSpellButton" .. i]:Hide();
        _G["OldSpellButton" .. i]:Show();
    end

    OldSpellBookPrevPageButton:Show();
    OldSpellBookNextPageButton:Show();
    OldSpellBookPageText:Show();
end

function OldSpellBookFrame_UpdatePages()
    local currentPage, maxPages = OldSpellBook_GetCurrentPage()

    if maxPages == 0 then
        return
    end

    if currentPage > maxPages then
        SPELLBOOK_PAGENUMBERS[OldSpellBookFrame.selectedSkillLine] = maxPages
        currentPage = maxPages
    end

    -- Update next/previous button status
    if currentPage == 1 then
        OldSpellBookPrevPageButton:Disable()
    else
        OldSpellBookPrevPageButton:Enable()
    end

    if currentPage == maxPages then
        OldSpellBookNextPageButton:Disable()
    else
        OldSpellBookNextPageButton:Enable()
    end

    -- Update the page number display
    OldSpellBookPageText:SetFormattedText(PAGE_NUMBER, currentPage)
end

function OldSpellBookFrameTabButton_OnClick(self)
    -- suppress the hiding sound so we don't play a hide and show sound simultaneously
    OldSpellBookFrame.suppressCloseSound = true;
    OldSpellBook:ToggleOldSpellBook(self.bookType, true);
    OldSpellBookFrame.suppressCloseSound = false;
end

function OldSpellBookFrame_SetTabType(tabButton, bookType, token)
    if (bookType == Enum.SpellBookSpellBank.Player) then
        tabButton.bookType = Enum.SpellBookSpellBank.Player;
        tabButton:SetText(SPELLBOOK);
        tabButton:SetFrameLevel(OldSpellBookFrame:GetFrameLevel() + 1);
        tabButton.binding = "TOGGLESPELLBOOK";
    elseif (bookType == Enum.SpellBookSpellBank.Pet) then
        tabButton.bookType = Enum.SpellBookSpellBank.Pet;
        tabButton:SetText(_G["PET_TYPE_" .. token]);
        tabButton:SetFrameLevel(OldSpellBookFrame:GetFrameLevel() + 1);
        tabButton.binding = "TOGGLEPETBOOK";
        OldSpellBookFrame.petTitle = _G["PET_TYPE_" .. token];
    else
        tabButton.bookType = INSCRIPTION;
        tabButton:SetText(GLYPHS);
        tabButton:SetFrameLevel(OldSpellBookFrame:GetFrameLevel() + 2);
        tabButton.binding = "TOGGLEINSCRIPTION";
    end
    if (OldSpellBookFrame.bookType == bookType) then
        tabButton:Disable();
    else
        tabButton:Enable();
    end
    tabButton:Show();
end

function OldSpellBookFrame_PlayOpenSound()
    if (OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Player) then
        PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
    elseif (OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet) then
        PlaySound(SOUNDKIT.IG_ABILITY_OPEN);
    else
        PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
    end
end

function OldSpellBookFrame_PlayCloseSound()
    if (not OldSpellBookFrame.suppressCloseSound) then
        if (OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Player) then
            PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE);
        else
            PlaySound(SOUNDKIT.IG_ABILITY_CLOSE);
        end
    end
end

function OldSpellBookFrame_OnHide(self)
    OldSpellBookFrame_PlayCloseSound();
    for i = 1, MAX_SKILLLINE_TABS do
        _G["OldSpellBookSkillLineTab" .. i .. "Flash"]:Hide();
    end
end

function OldSpellButton_OnLoad(self)
    self:RegisterForDrag("LeftButton");
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
end

function OldSpellButton_OnEvent(self, event, ...)
    if (event == "SPELLS_CHANGED" or event == "SPELL_UPDATE_COOLDOWN" or event == "UPDATE_SHAPESHIFT_FORM") then
        -- Listen for shapeshift changes to update the attack icons
        OldSpellButton_UpdateButton(self);
    elseif (event == "CURRENT_SPELL_CAST_CHANGED") then
        -- OldSpellButton_UpdateSelection(self);
    elseif (event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE") then
        -- OldSpellButton_UpdateSelection(self);
    elseif (event == "PET_BAR_UPDATE") then
        if (OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet) then
            OldSpellButton_UpdateButton(self);
        end
    end
end

function OldSpellButton_OnShow(self)
    self:RegisterEvent("SPELLS_CHANGED");
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN");
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM");
    self:RegisterEvent("CURRENT_SPELL_CAST_CHANGED");
    self:RegisterEvent("TRADE_SKILL_SHOW");
    self:RegisterEvent("TRADE_SKILL_CLOSE");
    self:RegisterEvent("PET_BAR_UPDATE");

    OldSpellButton_UpdateButton(self);
end

function OldSpellButton_OnHide(self)
    self:UnregisterEvent("SPELLS_CHANGED");
    self:UnregisterEvent("SPELL_UPDATE_COOLDOWN");
    self:UnregisterEvent("UPDATE_SHAPESHIFT_FORM");
    self:UnregisterEvent("CURRENT_SPELL_CAST_CHANGED");
    self:UnregisterEvent("TRADE_SKILL_SHOW");
    self:UnregisterEvent("TRADE_SKILL_CLOSE");
    self:UnregisterEvent("PET_BAR_UPDATE");
end

function OldSpellButton_OnEnter(self)
    local selectedSkillLine = OldSpellBookFrame.selectedSkillLine

    -- Getting Pet Page Number if we're on booktype Pet
    local truePageIndex = 1
    if OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet then
        truePageIndex = "Pet"
    else
        truePageIndex = selectedSkillLine
    end

    local currentPage = SPELLBOOK_PAGENUMBERS[truePageIndex] or 1
    local spellIndex = (currentPage - 1) * SPELLS_PER_PAGE + self:GetID()

    local spellTableForCategory =
        OldSpellBook.SpellTable[SpellBookUnitType[OldSpellBookFrame.bookType]][selectedSkillLine]
    if not spellTableForCategory or not spellTableForCategory[spellIndex] then
        return
    end

    local spellData = spellTableForCategory[spellIndex]
    if not spellData or not spellData.spellID then
        return
    end

    -- Show the spell tooltip
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(spellData.spellID) -- Use the correct spellID
    GameTooltip:Show()

    self.UpdateTooltip = OldSpellButton_OnEnter
end

function OldSpellButton_OnDrag(self)
    local selectedSkillLine = OldSpellBookFrame.selectedSkillLine

    -- Getting Pet Page Number if we're on booktype Pet
    local truePageIndex = 1
    if OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet then
        truePageIndex = "Pet"
    else
        truePageIndex = selectedSkillLine
    end

    local currentPage = SPELLBOOK_PAGENUMBERS[truePageIndex] or 1
    local spellIndex = (currentPage - 1) * SPELLS_PER_PAGE + self:GetID()

    -- spellIndex in this case is the index of the spell in TWW spellbook
    local trueSpellIndex = 0
    for i = 1, selectedSkillLine - 1 do
        trueSpellIndex = trueSpellIndex + #OldSpellBook.SpellTable[SpellBookUnitType[OldSpellBookFrame.bookType]][i]
    end
    trueSpellIndex = trueSpellIndex + spellIndex

    local spellTableForCategory =
        OldSpellBook.SpellTable[SpellBookUnitType[OldSpellBookFrame.bookType]][selectedSkillLine]
    if not spellTableForCategory or not spellTableForCategory[spellIndex] then
        return
    end

    local spellData = spellTableForCategory[spellIndex]

    -- Ensure the icon texture is valid and visible before allowing the drag
    local iconTexture = _G[self:GetName() .. "IconTexture"]
    if not iconTexture or not iconTexture:IsShown() then
        return
    end

    -- Uncheck the button and initiate the drag for the spell
    C_SpellBook.PickupSpellBookItem(spellData.newSpellBookIndex, OldSpellBookFrame.bookType)
end

function OldSpellButton_UpdateSelection(self)
    local selectedSkillLine = OldSpellBookFrame.selectedSkillLine

    -- Getting Pet Page Number if we're on booktype Pet
    local truePageIndex = 1
    if OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet then
        truePageIndex = "Pet"
    else
        truePageIndex = selectedSkillLine
    end

    local currentPage = SPELLBOOK_PAGENUMBERS[truePageIndex] or 1
    local spellIndex = (currentPage - 1) * SPELLS_PER_PAGE + self:GetID()

    local spellTableForCategory =
        OldSpellBook.SpellTable[SpellBookUnitType[OldSpellBookFrame.bookType]][selectedSkillLine]
    if not spellTableForCategory or not spellTableForCategory[spellIndex] then
        self:SetChecked(false)
        return
    end
end

function OldSpellButton_UpdateButton(self)
    local selectedSkillLine = OldSpellBookFrame.selectedSkillLine

    -- Getting Pet Page Number if we're on booktype Pet
    local truePageIndex = 1
    if OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet then
        truePageIndex = "Pet"
    else
        truePageIndex = selectedSkillLine
    end

    local currentPage = SPELLBOOK_PAGENUMBERS[truePageIndex] or 1
    local spellIndex = (currentPage - 1) * SPELLS_PER_PAGE + self:GetID()

    local spellTableForCategory =
        OldSpellBook.SpellTable[SpellBookUnitType[OldSpellBookFrame.bookType]][selectedSkillLine]
    if not spellTableForCategory or not spellTableForCategory[spellIndex] then
        self:Hide()
        return
    end

    local spellData = spellTableForCategory[spellIndex]
    local spellID = spellData.spellID

    -- Get common UI elements
    local name = self:GetName()
    local iconTexture = _G[name .. "IconTexture"]
    local spellString = _G[name .. "SpellName"]
    local subSpellString = _G[name .. "SubSpellName"]
    local cooldown = _G[name .. "Cooldown"]
    local flyoutArrow = _G[self:GetName() .. "FlyoutArrow"]

    -- Set the spell icon texture
    iconTexture:SetTexture(spellData.icon)
    iconTexture:Show()

    -- Set the spell name
    spellString:SetText(spellData.name)
    spellString:Show()

    -- Handle cooldown
    local cooldownInfo = C_Spell.GetSpellCooldown(spellID)
    if cooldownInfo then
        CooldownFrame_Set(cooldown, cooldownInfo.startTime, cooldownInfo.duration, cooldownInfo.isEnabled)
    end

    -- Flyout-specific handling
    if spellData.spellType == Enum.SpellBookItemType.Flyout then
        -- Show flyout arrow
        if flyoutArrow then
            flyoutArrow:Show()
        end

        -- Set sub-spell string to indicate it's a Flyout spell
        subSpellString:SetText("Flyout")
        subSpellString:Show()

        -- Securely handle the flyout toggle
        self:SetAttribute("type", "flyout")
        self:SetAttribute("flyout", spellID)
        self:SetAttribute("spell", spellID)
        self:SetAttribute("flyoutDirection", "RIGHT") -- You can change the direction as needed
        self.isActionBar = false

    else
        -- Regular spell handling
        self:SetAttribute("type1", "spell")
        self:SetAttribute("spell", spellID)

        -- Hide the flyout arrow if it exists
        if flyoutArrow then
            flyoutArrow:Hide()
        end

        -- Set the sub-spell string for passive or regular spells
        subSpellString:SetText(spellData.isPassive and "Passive" or "")
        subSpellString:Show()

    end

    -- Set desaturation for unlearned or off-spec spells
    if spellData.isOffSpec or spellData.spellType == Enum.SpellBookItemType.FutureSpell or not spellData.isKnown then
        iconTexture:SetDesaturated(true)
        spellString:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
        subSpellString:SetTextColor(VERY_DARK_GRAY_COLOR.r, VERY_DARK_GRAY_COLOR.g, VERY_DARK_GRAY_COLOR.b)
    else
        iconTexture:SetDesaturated(false)
        spellString:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
        subSpellString:SetTextColor(PARCHMENT_MATERIAL_TEXT_COLOR.r, PARCHMENT_MATERIAL_TEXT_COLOR.g,
            PARCHMENT_MATERIAL_TEXT_COLOR.b)
    end

    -- Handle autocast for pet spells
    if OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet and spellData.isKnown then
        local autocastEnabled = spellData.autoCastState or false
        print(spellData.autoCastState)

        if autocastEnabled then
            local shine = _G[self:GetName() .. "CustomShine"]
            shine:Show()
            print(shine)
            -- Optional: Add animation or rotation if needed, you can use UIObject:SetRotation()
            shine:SetRotation(GetTime() * 2) -- For example, rotate it slowly over time
        else
            local shine = _G[self:GetName() .. "CustomShine"]
            shine:Hide()
        end
    else
        -- Hide autocast textures if not a pet spell or if it's unknown
        local shine = _G[self:GetName() .. "CustomShine"]
        shine:Hide()
    end

    -- Ensure the selection state is updated
    OldSpellButton_UpdateSelection(self)

    -- Finally, show the button
    self:Show()
end

function OldSpellBookPrevPageButton_OnClick()

    local pageNum = OldSpellBook_GetCurrentPage() - 1;
    if (OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Player) then
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
        SPELLBOOK_PAGENUMBERS[OldSpellBookFrame.selectedSkillLine] = pageNum;
    else
        OldSpellBookTitleText:SetText(OldSpellBookFrame.petTitle);
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
        SPELLBOOK_PAGENUMBERS[SpellBookUnitType[Enum.SpellBookSpellBank.Pet]] = pageNum;
    end
    OldSpellBook_UpdatePageArrows();
    OldSpellBookPageText:SetFormattedText(PAGE_NUMBER, pageNum);

    -- Update the spell buttons on the current page
    OldSpellBookFrame_ShowSpells();
end

function OldSpellBookNextPageButton_OnClick()

    local pageNum = OldSpellBook_GetCurrentPage() + 1;
    if (OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Player) then
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
        SPELLBOOK_PAGENUMBERS[OldSpellBookFrame.selectedSkillLine] = pageNum;
    else
        OldSpellBookTitleText:SetText(OldSpellBookFrame.petTitle);
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
        SPELLBOOK_PAGENUMBERS[SpellBookUnitType[Enum.SpellBookSpellBank.Pet]] = pageNum;
    end
    OldSpellBook_UpdatePageArrows();
    OldSpellBookPageText:SetFormattedText(PAGE_NUMBER, pageNum);

    -- Update the spell buttons on the current page
    OldSpellBookFrame_ShowSpells();
end

function OldSpellBookSkillLineTab_OnClick(self, id)
    if not id then
        id = self:GetID()
    end

    -- Ensure the selected skill line has a page number
    if not SPELLBOOK_PAGENUMBERS[id] then
        SPELLBOOK_PAGENUMBERS[id] = 1
    end

    if OldSpellBookFrame.selectedSkillLine ~= id then
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN)
    end

    OldSpellBookFrame.selectedSkillLine = id
    local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(id)
    if (skillLineInfo == nil) then
        return
    end
    OldSpellBookFrame.selectedSkillLineOffset = skillLineInfo.itemIndexOffset
    OldSpellBookFrame.selectedSkillLineNumSpells = skillLineInfo.numSpellBookItems
    OldSpellBook_UpdatePageArrows()
    OldSpellBookFrame_Update()
    OldSpellBookPageText:SetFormattedText(PAGE_NUMBER, OldSpellBook_GetCurrentPage())

    if (skillLineInfo.offSpecID) then
        _G["OldSpellBookFrameTopLeft"]:SetDesaturated(true)
        _G["OldSpellBookFrameTopRight"]:SetDesaturated(true)
        _G["OldSpellBookFrameBotLeft"]:SetDesaturated(true)
        _G["OldSpellBookFrameBotRight"]:SetDesaturated(true)
    else
        _G["OldSpellBookFrameTopLeft"]:SetDesaturated(false)
        _G["OldSpellBookFrameTopRight"]:SetDesaturated(false)
        _G["OldSpellBookFrameBotLeft"]:SetDesaturated(false)
        _G["OldSpellBookFrameBotRight"]:SetDesaturated(false)
    end
    if self then
        local tabFlash = _G[self:GetName() .. "Flash"]
        if tabFlash then
            tabFlash:Hide()
        end
    end
end

function OldSpellBook_UpdatePageArrows()
    local currentPage, maxPages = OldSpellBook_GetCurrentPage();

    if (currentPage == 1) then
        OldSpellBookPrevPageButton:Disable();
    else
        OldSpellBookPrevPageButton:Enable();
    end
    if (currentPage == maxPages) then
        OldSpellBookNextPageButton:Disable();
    else
        OldSpellBookNextPageButton:Enable();
    end
end

function OldSpellBook_GetCurrentPage()
    local currentPage, maxPages
    local numPetSpells = C_SpellBook.HasPetSpells()

    if OldSpellBookFrame.bookType == Enum.SpellBookSpellBank.Pet then
        -- Handle the pet spellbook page number and total pages
        currentPage = SPELLBOOK_PAGENUMBERS[SpellBookUnitType[Enum.SpellBookSpellBank.Pet]] or 1
        maxPages = ceil(numPetSpells / SPELLS_PER_PAGE)
    else
        -- Handle the regular spellbook's skill line page number and total pages
        currentPage = SPELLBOOK_PAGENUMBERS[OldSpellBookFrame.selectedSkillLine] or 1
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(OldSpellBookFrame.selectedSkillLine)

        if skillLineInfo then
            local numSpells = skillLineInfo.numSpellBookItems
            maxPages = ceil(numSpells / SPELLS_PER_PAGE)
        else
            maxPages = 1 -- Fallback in case the skill line info is missing
        end
    end

    return currentPage, maxPages
end

