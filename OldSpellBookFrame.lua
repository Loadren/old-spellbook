local addonName, OldSpellBook = ...

MAX_SKILLLINE_TABS = 8
SPELLS_PER_PAGE = 12
SPELLBOOK_PAGENUMBERS = {}

-- This ensures the table is globally accessible
_G[addonName] = OldSpellBook

-- Global declarations for keybinds
BINDING_HEADER_OLD_SPELLBOOK = "Old Spellbook"
BINDING_NAME_OLD_SPELLBOOK_SHOW_SPELLBOOK = "Show Spellbook"

OldSpellBook.SpellTable = {}

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
    if event == "ADDON_LOADED" and addOnName == addonName then

    elseif event ~= "ADDON_LOADED" then
        HandlePopulatePlayerSpellsWithCooldown()
    end
end)

-- Function to populate the player's spell table and sort spells by type and name
function PopulatePlayerSpells()
    -- Clear the table before populating
    table.wipe(OldSpellBook.SpellTable)

    -- Iterate through all skill lines
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)

        -- Separate tables for active and passive spells
        local activeSpells = {}
        local passiveSpells = {}

        local offset, numSlots = skillLineInfo.itemIndexOffset, skillLineInfo.numSpellBookItems

        -- Iterate over each spell in the skill line
        for j = offset + 1, offset + numSlots do
            -- Get the spell name and info
            local name = C_SpellBook.GetSpellBookItemName(j, Enum.SpellBookSpellBank.Player)
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(j, Enum.SpellBookSpellBank.Player)
            local _, flyoutID = C_SpellBook.GetSpellBookItemType(j, Enum.SpellBookSpellBank.Player)

            -- Only store the spell if it has a valid action ID (i.e., it's not empty)
            if name and spellInfo and spellInfo.actionID then
                local spellData = {
                    spellID = flyoutID or spellInfo.spellID or spellInfo.actionID, -- Because sometimes it's on actionID
                    name = name,
                    isPassive = spellInfo.isPassive,
                    isOffSpec = spellInfo.isOffSpec,
                    icon = spellInfo.iconID,
                    spellType = spellInfo.itemType
                }

                -- Add spells to either active or passive sections
                if spellInfo.isPassive then
                    table.insert(passiveSpells, spellData)
                else
                    table.insert(activeSpells, spellData)
                end
            end
        end

        -- Sort active and passive spells alphabetically by name
        OldSpellBook.Utils.SortSpellsByName(activeSpells)
        OldSpellBook.Utils.SortSpellsByName(passiveSpells)

        -- Merge activeSpells and passiveSpells back into a single table, active first
        OldSpellBook.SpellTable[i] = {}
        for _, spell in ipairs(activeSpells) do
            table.insert(OldSpellBook.SpellTable[i], spell)
        end
        for _, spell in ipairs(passiveSpells) do
            table.insert(OldSpellBook.SpellTable[i], spell)
        end
    end
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
    if (not C_SpellBook.HasPetSpells() and bookType == BOOKTYPE_PET) then
        return;
    end

    local isShown = OldSpellBookFrame:IsShown();
    if (isShown and (OldSpellBookFrame.bookType ~= bookType)) then
        OldSpellBookFrame.suppressCloseSound = true;
    end

    HideUIPanel(OldSpellBookFrame);
    if ((not isShown or (OldSpellBookFrame.bookType ~= bookType))) then
        OldSpellBookFrame.bookType = bookType;
        ShowUIPanel(OldSpellBookFrame);
    end
    OldSpellBookFrame_UpdatePages();

    OldSpellBookFrame.suppressCloseSound = nil;
end

function OldSpellBookFrame_OnLoad(self)
    self:RegisterEvent("SPELLS_CHANGED")
    self:RegisterEvent("LEARNED_SPELL_IN_TAB")

    OldSpellBookFrame.bookType = BOOKTYPE_SPELL

    -- Initialize page numbers for spellbook and pet
    for i = 1, MAX_SKILLLINE_TABS do
        SPELLBOOK_PAGENUMBERS[i] = 1
    end

    if not BOOKTYPE_PET then
        BOOKTYPE_PET = "pet"
    end

    -- Ensure BOOKTYPE_PET is initialized as well
    if not SPELLBOOK_PAGENUMBERS[BOOKTYPE_PET] then
        SPELLBOOK_PAGENUMBERS[BOOKTYPE_PET] = 1
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
        if (OldSpellBookFrame.bookType == BOOKTYPE_PET) then
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

        if i <= numSkillLineTabs and OldSpellBookFrame.bookType == BOOKTYPE_SPELL then
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if not skillLineInfo then
                skillLineTab:Hide()
                return
            end
            if skillLineInfo.iconID then
                skillLineTab:SetNormalTexture(skillLineInfo.iconID)
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

    -- Update the spellbook title and call functions for handling pet or spellbook
    if OldSpellBookFrame.bookType == BOOKTYPE_SPELL then
        OldSpellBookTitleText:SetText(SPELLBOOK)
        OldSpellBookFrame_ShowSpells()
        OldSpellBookFrame_UpdatePages()
    elseif OldSpellBookFrame.bookType == BOOKTYPE_PET then
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
    -- OldSpellBook_UpdateSpellPage()
end

function OldSpellBookFrame_SetTabType(tabButton, bookType, token)
    if (bookType == BOOKTYPE_SPELL) then
        tabButton.bookType = BOOKTYPE_SPELL;
        tabButton:SetText(SPELLBOOK);
        tabButton:SetFrameLevel(OldSpellBookFrame:GetFrameLevel() + 1);
        tabButton.binding = "TOGGLESPELLBOOK";
    elseif (bookType == BOOKTYPE_PET) then
        tabButton.bookType = BOOKTYPE_PET;
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
    if (OldSpellBookFrame.bookType == BOOKTYPE_SPELL) then
        PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
    elseif (OldSpellBookFrame.bookType == BOOKTYPE_PET) then
        PlaySound(SOUNDKIT.IG_ABILITY_OPEN);
    else
        PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
    end
end

function OldSpellBookFrame_PlayCloseSound()
    if (not OldSpellBookFrame.suppressCloseSound) then
        if (OldSpellBookFrame.bookType == BOOKTYPE_SPELL) then
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
        if (OldSpellBookFrame.bookType == BOOKTYPE_PET) then
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
    local currentPage = SPELLBOOK_PAGENUMBERS[selectedSkillLine] or 1
    local spellIndex = (currentPage - 1) * SPELLS_PER_PAGE + self:GetID()

    local spellTableForCategory = OldSpellBook.SpellTable[selectedSkillLine]
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
    local currentPage = SPELLBOOK_PAGENUMBERS[selectedSkillLine] or 1
    local spellIndex = (currentPage - 1) * SPELLS_PER_PAGE + self:GetID()

    local spellTableForCategory = OldSpellBook.SpellTable[selectedSkillLine]
    if not spellTableForCategory or not spellTableForCategory[spellIndex] then
        return
    end

    local spellData = spellTableForCategory[spellIndex]
    local spellID = spellData.spellID

    -- Ensure the icon texture is valid and visible before allowing the drag
    local iconTexture = _G[self:GetName() .. "IconTexture"]
    if not iconTexture or not iconTexture:IsShown() then
        return
    end

    -- Uncheck the button and initiate the drag for the spell
    C_Spell.PickupSpell(spellID, OldSpellBookFrame.bookType)
end

function OldSpellButton_UpdateSelection(self)
    local selectedSkillLine = OldSpellBookFrame.selectedSkillLine
    local currentPage = SPELLBOOK_PAGENUMBERS[selectedSkillLine] or 1
    local spellIndex = (currentPage - 1) * SPELLS_PER_PAGE + self:GetID()

    local spellTableForCategory = OldSpellBook.SpellTable[selectedSkillLine]
    if not spellTableForCategory or not spellTableForCategory[spellIndex] then
        self:SetChecked(false)
        return
    end
end

function OldSpellButton_UpdateButton(self)
    local selectedSkillLine = OldSpellBookFrame.selectedSkillLine
    local currentPage = SPELLBOOK_PAGENUMBERS[selectedSkillLine] or 1
    local spellIndex = (currentPage - 1) * SPELLS_PER_PAGE + self:GetID()

    local spellTableForCategory = OldSpellBook.SpellTable[selectedSkillLine]
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
    iconTexture:SetDesaturated(false)
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
        -- Flyout spell handling
        self:SetAttribute("type", "flyout")
        self:SetAttribute("flyout", spellID)

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
        self:SetAttribute("flyoutDirection", "RIGHT") -- You can change the direction as needed

    else
        -- Regular spell handling
        self:SetAttribute("type", "spell")
        self:SetAttribute("spell", spellID)

        -- Hide the flyout arrow if it exists
        if flyoutArrow then
            flyoutArrow:Hide()
        end

        -- Set the sub-spell string for passive or regular spells
        subSpellString:SetText(spellData.isPassive and "Passive" or "")
        subSpellString:Show()

        -- Set desaturation for unlearned or off-spec spells
        if spellData.isOffSpec or spellData.spellType == Enum.SpellBookItemType.FutureSpell then
            iconTexture:SetDesaturated(true)
        else
            iconTexture:SetDesaturated(false)
        end
    end

    -- Ensure the selection state is updated
    OldSpellButton_UpdateSelection(self)

    -- Finally, show the button
    self:Show()
end


function OldSpellBook_GetCurrentPage()
    local currentPage, maxPages
    local numPetSpells = C_SpellBook.HasPetSpells()

    if OldSpellBookFrame.bookType == BOOKTYPE_PET then
        -- Handle the pet spellbook page number and total pages
        currentPage = SPELLBOOK_PAGENUMBERS[BOOKTYPE_PET] or 1
        maxPages = ceil(numPetSpells / SPELLS_PER_PAGE)
    else
        -- Handle the regular spellbook's skill line page number and total pages
        currentPage = SPELLBOOK_PAGENUMBERS[OldSpellBookFrame.selectedSkillLine] or 1
        local spellTableForCategory = OldSpellBook.SpellTable[OldSpellBookFrame.selectedSkillLine]

        if spellTableForCategory then
            local totalSpells = #spellTableForCategory
            maxPages = ceil(totalSpells / SPELLS_PER_PAGE)
        else
            maxPages = 1 -- Fallback in case the spell table for the skill line is missing
        end
    end

    return currentPage, maxPages
end

function OldSpellBookPrevPageButton_OnClick()
    local pageNum = OldSpellBook_GetCurrentPage() - 1;
    if (OldSpellBookFrame.bookType == BOOKTYPE_SPELL) then
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
        SPELLBOOK_PAGENUMBERS[OldSpellBookFrame.selectedSkillLine] = pageNum;
    else
        OldSpellBookTitleText:SetText(OldSpellBookFrame.petTitle);
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
        SPELLBOOK_PAGENUMBERS[BOOKTYPE_PET] = pageNum;
    end
    OldSpellBook_UpdatePageArrows();
    OldSpellBookPageText:SetFormattedText(PAGE_NUMBER, pageNum);

    -- Update the spell buttons on the current page
    OldSpellBookFrame_ShowSpells();
end

function OldSpellBookNextPageButton_OnClick()
    local pageNum = OldSpellBook_GetCurrentPage() + 1;
    if (OldSpellBookFrame.bookType == BOOKTYPE_SPELL) then
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
        SPELLBOOK_PAGENUMBERS[OldSpellBookFrame.selectedSkillLine] = pageNum;
    else
        OldSpellBookTitleText:SetText(OldSpellBookFrame.petTitle);
        PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
        SPELLBOOK_PAGENUMBERS[BOOKTYPE_PET] = pageNum;
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

    if OldSpellBookFrame.bookType == BOOKTYPE_PET then
        -- Handle the pet spellbook page number and total pages
        currentPage = PET_PAGENUMBER or 1
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

