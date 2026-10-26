-- RocketSwap | Data.lua
-- The ONLY layer that talks to the game's API. No other file calls `C_*`.
--
-- WHAT THIS ADDON DOES, AND WHY IT NEEDS TO EXIST:
--
-- The game already keeps everything that matters. It keeps equipment sets (Frost, Unholy, Blood,
-- PvP) and it keeps talent loadouts (PvP, SBA ST, Deathbringer ST). What it does **not** do is
-- relate the two in a useful way:
--
--   * `C_EquipmentSet.AssignSpecToEquipmentSet` ties **one** set per specialization.
--     A Frost Death Knight with a "Frost" set and a "PvP" set cannot
--     express that -- both are the same spec.
--   * The game remembers **the last** talent loadout per spec. Same problem: "PvP" and
--     "SBA ST" are both Frost.
--
-- So the table `name -> (spec, talents, items)` **has** to live in the addon. It is the thin
-- layer that is missing, and it is all RocketSwap keeps. The rest is read from the game.
--
-- THE ORDER OF APPLYING -- it is not arbitrary:
--
--   1. specialization   -> it is a CAST, it can fail (`SPECIALIZATION_CHANGE_CAST_FAILED`)
--   2. talents          -> asynchronous, confirms on `TRAIT_CONFIG_UPDATED`
--   3. items            -> LAST, on purpose
--
-- Step 3 comes last because, on a spec switch, **the game equips by itself** the set
-- tied to that spec. Equipping before would be overwritten by the game itself.
--
-- A CORRECTION OF A BELIEF OF MINE THAT BECAME A DEFECT. This header said, in writing, that
-- "`UseEquipmentSet` returns no error" -- and further down the listener repeated that "the function itself
-- returns nothing". **Both phrases were false in 12.1.0**, and while they stayed here the
-- next round would redo the same reasoning:
--
--   `C_EquipmentSet.UseEquipmentSet`         -> `setWasEquipped` (bool)
--                                              `EquipmentManagerDocumentation.lua:287-299`
--   `C_SpecializationInfo.SetSpecialization` -> `success` (bool)
--                                              `SpecializationInfoDocumentation.lua:368-380`
--
-- Blizzard branches on both (`Blizzard_ClassSpecializationsFrame.lua:457-465`). We
-- kept only the `pcall`'s `ok`, which answers "did it blow up?" and not "did the game accept?" -- so an
-- immediate refusal became twelve seconds of waiting and then "the game did not confirm in time", with the
-- chain going on to the next step in the wrong state.
--
-- Each step waits for the confirmation event AND looks at the return. Without both the addon says "done"
-- having done nothing, which is worse than having no addon.
local ADDON, ns = ...
local L = ns.L

local Data = {}
ns.Data = Data

-- A DEADLINE PER STEP, and a generous one. The user was explicit: *"não tem problema demorar um pouco"*.
--
-- Twelve seconds for everything was a number of mine, and Blizzard imposes no deadline: its frame
-- holds the "activating" state until the event arrives or the cast fails
-- (`Blizzard_ClassSpecializationsFrame.lua:174-190,209-214`). Switching spec has a cast and a server
-- round trip, and still fires the automatic gear swap tied to that spec -- it is the
-- step most likely to choke, and the one that most often ran out.
--
-- The appearance is the opposite: it was already asked for on the click, before the chain started. If it
-- did not arrive in two seconds, it will not -- waiting twelve only delays the message.
-- The steps the GAME refuses in combat, which therefore wait for the fight to end instead of failing.
-- The appearance stays out: the secure click switches it, before the chain, and its step here
-- only checks -- there is nothing combat prevents.
local COMBAT_SENSITIVE = { spec = true, talent = true, gear = true }

local STEP_TIMEOUT = {
    spec     = 45,
    talent   = 30,
    gear     = 20,
    transmog = 2,
}
local STEP_TIMEOUT_DEFAULT = 20

-- THE SPELL THE MANUAL APPEARANCE SWAP SPENDS, and why it has one.
--
-- Switching a set by hand is not free in Midnight: it consumes
-- `Constants.TransmogOutfitDataConsts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID`, and the game's own UI
-- draws the cooldown over the set's button
-- (`Blizzard_Transmog/Blizzard_TransmogTemplates.lua:191-198`).
--
-- THAT MATTERS HERE BECAUSE IT IS A SILENT REFUSAL: on cooldown the call switches nothing and
-- returns no error -- which is exactly the user's report, twice. And whoever is TESTING
-- falls into it most: switching sets several times in a row keeps the cooldown up.
--
-- The literal number is the constant's value in 12.1.0
-- (`Blizzard_APIDocumentationGenerated/TransmogOutfitConstantsDocumentation.lua:429`). We read from the
-- constant when it exists and fall back on the literal when not -- `Constants` is a client table and
-- may not be loaded in the order we expect.
local TRANSMOG_SPELL_ID = 1247613

local function TransmogSpellID()
    local consts = Constants and Constants.TransmogOutfitDataConsts
    local id = consts and consts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID
    return type(id) == "number" and id or TRANSMOG_SPELL_ID
end

--- What is blocking the appearance swap NOW, or nil when nothing is.
---
--- The three doors come from the native set UI, which checks all three before letting you click
--- (`Blizzard_TransmogTemplates.lua:72-87,191-198`). None of them returns an error when the swap is
--- asked for anyway: the call simply does nothing. Asking BEFORE is what turns
--- "nao troca e nao gera nenhum erro" into a phrase that says the reason.
--- @param outfitID number|nil the target set, to check whether IT is locked
--- @return string|nil
function Data.TransmogBlockedBy(outfitID)
    if not C_TransmogOutfitInfo then return nil end

    -- COOLDOWN -- and here lived the worst defect of this chain, written by me.
    --
    -- The earlier version read `cd.startTime` and `cd.duration`, compared both with zero and even
    -- added one to the other. Both are **SECRET inside mythic+**:
    --
    --   * `C_Spell.GetSpellCooldown` is `SecretWhenCooldownsRestricted`
    --     (`SpellDocumentation.lua:271`), and that predicate holds for combat, encounter, **challenge
    --     mode** and a PvP match -- that is, the whole key, not only the fight;
    --   * in `SpellCooldownInfo`, `isEnabled`, `isActive` and `isOnGCD` are `NeverSecret`;
    --     **`startTime` and `duration` ARE NOT** (`SpellSharedDocumentation.lua:23-30`).
    --
    -- And the `type` guard protected nothing: `type()` on a secret returns the REAL TYPE, so the
    -- two passed and the comparison blew up. The `pcall` above covers the CALL, not the arithmetic
    -- done with what it returned.
    --
    -- THE DAMAGE WAS THE WHOLE REPORT. A Lua error here, with `running` already set and no deadline
    -- armed yet, left the chain stuck forever -- and every following click came back SILENT
    -- in `Data.Apply`. "As vezes nao troca, gera erro", in one line.
    --
    -- `isActive` answers the same question without reading any secret field: *"False if cooldown is
    -- not active (ex: not enabled, or startTime or duration are 0)"* -- the three conditions of
    -- `CooldownFrame_Set` at once. The price is not saying how many seconds are left, and it is worth it:
    -- counting seconds needs the two forbidden fields.
    local getCD = C_Spell and C_Spell.GetSpellCooldown
    local ok, cd = false, nil
    if getCD then ok, cd = pcall(getCD, TransmogSpellID()) end
    if ok and type(cd) == "table" and cd.isActive == true then
        return L["changing appearance is on cooldown."]
    end

    -- A STYLE EVENT: during it the UI disables every set that is not the event's.
    if C_TransmogOutfitInfo.InTransmogEvent then
        local okEv, emEvento = pcall(C_TransmogOutfitInfo.InTransmogEvent)
        if okEv and emEvento then
            return L["a style event is running; appearances are locked."]
        end
    end

    -- A SET LOCKED to a situation: the UI marks it with a padlock.
    if outfitID and C_TransmogOutfitInfo.IsLockedOutfit then
        local okLk, travado = pcall(C_TransmogOutfitInfo.IsLockedOutfit, outfitID)
        if okLk and travado then
            return L["that appearance set is locked."]
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Reading: what the player already has
--------------------------------------------------------------------------------
--- The class's specializations, in the order the game lists them.
---
--- `specIndex` (1..n) is what the switch and set APIs use -- **not** the `specID`.
--- Mixing the two is the classic mistake here: `AssignSpecToEquipmentSet` takes the index.
function Data.GetSpecs()
    local out = {}
    local count = C_SpecializationInfo.GetNumSpecializations
        and C_SpecializationInfo.GetNumSpecializations() or GetNumSpecializations()
    if not count then return out end

    for index = 1, count do
        local id, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(index)
        if id then
            out[#out + 1] = { index = index, id = id, name = name or "?", icon = icon }
        end
    end
    return out
end

function Data.GetCurrentSpecIndex()
    local index = C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
    if index == nil and GetSpecialization then index = GetSpecialization() end
    return index
end

function Data.GetSpecByIndex(index)
    if not index then return nil end
    for _, spec in ipairs(Data.GetSpecs()) do
        if spec.index == index then return spec end
    end
    return nil
end

--- A specialization's talent loadouts.
---
--- The name comes from `C_Traits.GetConfigInfo`, not from `C_ClassTalents` -- the latter only gives
--- the ids. The "Starter Build" does not show here because it is not a saved config.
function Data.GetLoadouts(specID)
    local out = {}
    if not specID or not C_ClassTalents or not C_ClassTalents.GetConfigIDsBySpecID then
        return out
    end

    local ok, ids = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if not ok or type(ids) ~= "table" then return out end

    for _, configID in ipairs(ids) do
        local info = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
        if info and info.name then
            out[#out + 1] = { configID = configID, name = info.name }
        end
    end
    return out
end

function Data.GetActiveLoadoutID(specID)
    if not specID or not C_ClassTalents or not C_ClassTalents.GetLastSelectedSavedConfigID then
        return nil
    end
    local ok, configID = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
    return ok and configID or nil
end

--- Equipment sets, with their icon -- the same one the character sheet shows.
function Data.GetGearSets()
    local out = {}
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetIDs then return out end

    local ok, ids = pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if not ok or type(ids) ~= "table" then return out end

    for _, setID in ipairs(ids) do
        local name, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
        if name then
            out[#out + 1] = { setID = setID, name = name, icon = icon, isEquipped = isEquipped }
        end
    end
    return out
end

--- The appearance (transmog) sets the player has saved.
---
--- `C_TransmogOutfitInfo` is a NEW namespace of Midnight -- it is not the old transmog, tied to the NPC.
--- It is the "outfits" system the game started switching by itself per situation (the enum
--- `TransmogSituationTrigger` has `Location`, `Movement`, `Weather`, `Specialization` and even
--- `EquipmentSet`).
---
--- WE KEEP THE `outfitID`, BUT THE SWAP ASKS FOR THE INDEX. They are different things, and Blizzard's
--- own comment says why: *"playerFacingOutfitIndex is slightly different from outfitID
--- (outfitIDs may have gaps)"*. Keeping the index would rot: deleting an appearance set
--- shifts all the following ones, and the preset would come to wear another outfit.
function Data.GetOutfits()
    local out = {}
    if not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.GetOutfitsInfo then return out end

    local ok, list = pcall(C_TransmogOutfitInfo.GetOutfitsInfo)
    if not ok or type(list) ~= "table" then return out end

    for _, info in ipairs(list) do
        if info.outfitID and not info.isDisabled then
            out[#out + 1] = {
                outfitID = info.outfitID,
                index = info.playerFacingOutfitIndex,
                name = info.name or "?",
                icon = info.icon,
            }
        end
    end
    return out
end

function Data.OutfitName(outfitID)
    if not outfitID then return nil end
    for _, o in ipairs(Data.GetOutfits()) do
        if o.outfitID == outfitID then return o.name, o.icon end
    end
    return nil
end

--- The `playerFacingOutfitIndex` of an appearance set, resolved NOW.
---
--- We keep the `outfitID` and the swap asks for the index, and the two are not the same thing -- Blizzard's
--- own comment says why: *"playerFacingOutfitIndex is slightly different from outfitID
--- (outfitIDs may have gaps)"*. The index shifts when an appearance is deleted, so it is
--- resolved at the time of use and never kept.
function Data.OutfitIndex(outfitID)
    if not outfitID then return nil end
    for _, outfit in ipairs(Data.GetOutfits()) do
        if outfit.outfitID == outfitID then return outfit.index end
    end
    return nil
end

--- The spell the game casts to activate a specialization.
---
--- THERE IS NO CONSTANT FOR IT. I looked: transmog has
--- `EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID` in the generated documentation, the spec switch has no
--- equivalent. What exists is the predicate `IsSpecializationActivateSpell(spellID)`, which the
--- talents window itself uses to recognise its cast
--- (`Blizzard_ClassSpecializationsFrame.lua:187`).
---
--- So the addon **learns the id from the game**: when a cast of the player ends, it asks the
--- predicate whether that was the spec activation, and keeps it. From then on the cooldown can be read.
---
--- Kept in SavedVariables because the id does not change and learning it again every session would mean the
--- first switch of each session still going blind.
local function SpecSpellID()
    return RocketSwapLogDB and RocketSwapLogDB.specSpellID
end

--- Called when a cast of the player ends. Keeps the id if it is the spec activation's.
function Data.NoteSpellCast(spellID)
    -- `type` BEFORE EVERYTHING. `UNIT_SPELLCAST_SUCCEEDED` is `SecretWhenUnitSpellCastRestricted`
    -- (`UnitDocumentation.lua:4702`), so under a restriction the `spellID` comes opaque -- and keeping an
    -- opaque value in SavedVariables is a sure way to an error.
    --
    -- The guard is **defensive**: sabotaging it fails no test, because the game's predicate
    -- returns false for a value that is not the id. It stays because the cost of getting it wrong is a
    -- corrupted settings file, and the cost of getting it right is one line.
    if type(spellID) ~= "number" then return end
    if not IsSpecializationActivateSpell then return end
    if SpecSpellID() then return end                       -- already known

    local ok, ehDeSpec = pcall(IsSpecializationActivateSpell, spellID)
    if ok and ehDeSpec then
        RocketSwapLogDB = RocketSwapLogDB or {}
        RocketSwapLogDB.specSpellID = spellID
        if ns.Log then
            ns.Log.Add("aprendeu", { magiaDeSpec = spellID })
        end
    end
end

--- Can the specialization be switched now?
---
--- It is the SAME question the game's talents window asks to decide whether the "Activate" button stays
--- clickable: `specContentFrame.ActivateButton:SetEnabled(canSpecsBeActivated)`, with
--- `canSpecsBeActivated = C_SpecializationInfo.CanPlayerUseTalentSpecUI()`
--- (`Blizzard_ClassSpecializationsFrame.lua:139,149`).
---
--- Using Blizzard's condition has two advantages over inventing ours: it covers every
--- reason at once (combat, vehicle, a switch under way, whatever else exists), and it **returns
--- the reason as text**, already translated by the client -- `canUse, failureReason`
--- (`SpecializationInfoDocumentation.lua:21-28`).
---
--- Before, the addon found out the refusal **by calling and getting a no**, which is what produced the
--- generic message after the click. Asking first lets the interface answer without trying.
--- @return boolean can, string|nil reason
function Data.CanChangeSpec()
    if not C_SpecializationInfo or not C_SpecializationInfo.CanPlayerUseTalentSpecUI then
        return true      -- a client without the function: there is no asking, so nothing is blocked
    end

    local ok, pode, motivo = pcall(C_SpecializationInfo.CanPlayerUseTalentSpecUI)
    if ok and pode == false then
        return false, (type(motivo) == "string" and motivo ~= "") and motivo or nil
    end

    -- AND THE SPELL'S COOLDOWN, which is the case the user lived and which the question above does NOT cover.
    --
    -- The log proved it: at 02:28:18 the switch worked and at 02:28:26 -- eight seconds later -- the
    -- game returned `false`, with `CanPlayerUseTalentSpecUI` answering **yes** the whole time.
    -- That question is about the interface being usable, not about the switch being available.
    --
    -- `isActive` and not `startTime`/`duration`: the last two become SECRET under a restriction, and
    -- comparing a secret already locked this addon up once.
    local spellID = SpecSpellID()
    local getCD = spellID and C_Spell and C_Spell.GetSpellCooldown
    if getCD then
        local okCD, cd = pcall(getCD, spellID)
        if okCD and type(cd) == "table" and cd.isActive == true then
            -- A THIRD RETURN: "it was the cooldown". Without it the log wrote `pode=false motivo=nil`
            -- exactly like the case "the interface answered no and did not say why" -- two different
            -- causes on the same line, and reading the log could not tell them apart.
            --
            -- And the caller uses it to decide between WAITING and giving up: a cooldown passes.
            return false, nil, "recarga da magia de spec"
        end
    end

    return true
end

function Data.GetActiveOutfitID()
    if not C_TransmogOutfitInfo or not C_TransmogOutfitInfo.GetActiveOutfitID then return nil end
    local ok, id = pcall(C_TransmogOutfitInfo.GetActiveOutfitID)
    return ok and id or nil
end

--- The first set marked as worn. It serves the list's check mark, and **only** that.
---
--- `isEquipped` is per set and independent: the game's window draws a check mark on EVERY set whose
--- `isEquipped` is true (`PaperDollFrame.lua:2396,2414-2418`). Two sets sharing
--- pieces are both marked, and "the first" is an arbitrary answer.
function Data.GetEquippedSetID()
    for _, set in ipairs(Data.GetGearSets()) do
        if set.isEquipped then return set.setID end
    end
    return nil
end

--- The set the player IS using with a piece swapped -- the almost-worn one.
---
--- ⚑ THIS EXISTS BECAUSE OF THE LYING `(nenhum)`. `isEquipped` is all-or-nothing: swapping one single
--- piece of a 14-piece set drops the flag of the 14, and the ready check's summary came to say
--- "Itens: (nenhum)" to whoever had the set almost whole on. The phrase was false at the
--- moment it costs most -- the leader just asked for the check.
---
--- THE MEASURE IS `numEquipped`, the 6th return of `GetEquipmentSetInfo`: how many pieces OF THIS set
--- are on the body now. It is not a deduction of ours, it is the game's bookkeeping -- the same that
--- `Data.GearSetCounts` already lives on.
---
--- TWO REFUSALS, both so as not to invent an answer:
---
---  * **a simple majority or nothing.** With half or fewer of the pieces matching, "you are wearing
---    set X" stops being true: two raid sets share a ring, a cloak and a trinket without
---    anyone having worn either. Below the cut the honest answer is still
---    `(nenhum)`;
---  * **a tie does not answer.** Two sets with the same count are the same ambiguity that
---    `GetEquippedSetID`'s comment describes, and choosing "the first" here would be drawing lots for
---    which name the player reads. A tie returns `nil`.
---
--- The ignored pieces stay out of the count on both sides (`itens` already includes them, and the game counts
--- an ignored one as not worn): the denominator is the set's total, the number the
--- player sees in the equipment window.
--- @return number|nil setID, number|nil worn, number|nil items, string|nil name
function Data.PartialGearSet()
    local melhorID, melhorNome, melhorVestidas, melhorItens
    local empatado = false

    for _, set in ipairs(Data.GetGearSets()) do
        if not set.isEquipped then
            local c = Data.GearSetCounts(set.setID)
            -- `type` and not just `and`: a missing count becomes a comparison with nil, which is a Lua error.
            if c and type(c.vestidas) == "number" and type(c.itens) == "number" and c.itens > 0 then
                if c.vestidas * 2 > c.itens then
                    if melhorVestidas == nil or c.vestidas > melhorVestidas then
                        melhorID, melhorNome = set.setID, set.name
                        melhorVestidas, melhorItens = c.vestidas, c.itens
                        empatado = false
                    elseif c.vestidas == melhorVestidas then
                        empatado = true
                    end
                end
            end
        end
    end

    if empatado then return nil end
    return melhorID, melhorVestidas, melhorItens, melhorNome
end

--- Is **this** set worn?
---
--- It is the right question to confirm the items step, and it is different from the one above: asking
--- "which is worn" and comparing gives the wrong answer when two sets share pieces --
--- the target would be worn and the addon would think not, because the other showed first in the list.
function Data.IsGearSetEquipped(setID)
    if setID == nil then return false end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetInfo then return false end

    -- `isEquipped` is the 4th return (`EquipmentManagerDocumentation.lua:128-149`).
    local ok, _, _, _, isEquipped = pcall(C_EquipmentSet.GetEquipmentSetInfo, setID)
    return ok and isEquipped == true
end

--- THE SET'S BOOKKEEPING, which is what the game knows and we were not asking.
---
--- `GetEquipmentSetInfo` returns NINE values, and the last four are counts:
--- `numItems, numEquipped, numInInventory, numLost, numIgnored`. **`numLost` is "pieces the
--- player does not have at hand now"** -- and it is the only direct answer there is to "why did the swap
--- fail", because `UseEquipmentSet` gives no reason and `EQUIPMENT_SWAP_FINISHED` only brings a boolean.
---
--- ⚑ THIS EXISTS BECAUSE OF THE LOG OF 09/09. At 17:22:02 the game returned
--- `EQUIPMENT_SWAP_FINISHED(false, 1)` for the set "Frost PvE ST" -- and at 00:00:26 of the SAME day
--- the same chain, with the same set and the same order of events, had returned `true`. The
--- log recorded the refusal and nothing else: not the call's return, not the set's state. There
--- was no telling "a piece was missing" from "the game refused for another reason", which is exactly the
--- question the log exists to answer.
--- @return table|nil counts `{ nome, itens, vestidas, naBolsa, perdidas, ignoradas }`
function Data.GearSetCounts(setID)
    if setID == nil then return nil end
    if not C_EquipmentSet or not C_EquipmentSet.GetEquipmentSetInfo then return nil end

    local ok, name, _, _, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored =
        pcall(C_EquipmentSet.GetEquipmentSetInfo, setID)
    if not ok or name == nil then return nil end

    return {
        nome = name,
        vestido = isEquipped == true,
        itens = numItems,
        vestidas = numEquipped,
        naBolsa = numInInventory,
        perdidas = numLost,
        ignoradas = numIgnored,
    }
end

--- The bookkeeping in one line, for the log. `nil` when the game did not answer.
function Data.DescribeGearSet(setID)
    local c = Data.GearSetCounts(setID)
    if not c then return nil end
    return format("itens=%s vestidas=%s naBolsa=%s perdidas=%s ignoradas=%s vestido=%s",
        tostring(c.itens), tostring(c.vestidas), tostring(c.naBolsa),
        tostring(c.perdidas), tostring(c.ignoradas), tostring(c.vestido))
end

--- The equip failure, said with what the game tells -- and only with what it tells.
---
--- With `numLost > 0` the cause is proven: the set asks for a piece the player does not have at hand. Without
--- it, it returns the generic phrase: **inventing a reason here would be worse than having none**.
function Data.GearFailureReason(setID)
    local c = Data.GearSetCounts(setID)
    if c and type(c.perdidas) == "number" and c.perdidas > 0 then
        return format(L["%d item(s) of this set are not available right now."], c.perdidas)
    end
    return L["the gear set could not be equipped."]
end

--- Is the equipment set broken? And can it be fixed now?
---
--- (!) A DEFECT REPORTED ON 22/09. The player swapped a piece and **sold the previous one** without saving the
--- set. The game shows the set's name in RED in the manager; Rocket Swap switched
--- anyway, but the step never closed with the check -- because with a missing piece the game's `isEquipped`
--- never becomes `true`, and "worn" is what confirms the step. His report: *"ele troca, mas não
--- fica marcado como trocado e em uso"*.
---
--- The data was already here since 09/09: `numLost` is read and recorded in the log. Only it was used
--- **after** the failure, to explain it. The right information arriving too late is almost the same as
--- not having it.
---
--- `consertavel` answers the question that makes the fix SAFE. Saving a set writes what
--- you are wearing over it -- so it is only the right thing to do when you **are already
--- wearing the whole set but what went missing**. Outside that, saving would wreck the set
--- swapping it for the outfit of the moment, which is a much worse damage than the original defect.
--- @return table|nil `{ nome, perdidas, consertavel }`, or nil if there is no problem
function Data.GearSetProblem(setID)
    local c = Data.GearSetCounts(setID)
    if not c then return nil end
    if type(c.perdidas) ~= "number" or c.perdidas <= 0 then return nil end

    local vestidas = type(c.vestidas) == "number" and c.vestidas or 0
    local itens = type(c.itens) == "number" and c.itens or 0

    -- WHICH PIECE WENT MISSING, and not only how many. "1 item missing" sends the player hunting; "the
    -- Helm is missing" he already knows what to do. `GetItemLocations` marks with **-1** the slot whose piece is not
    -- available.
    --
    -- ⚠️ The documentation itself warns that `-1` **does not tell** "went missing" from "this slot cannot
    -- be equipped". That is why the names are only collected when `numLost > 0` (then we know there is a
    -- really missing piece) and the list is cut at `numLost`: more names than that would be
    -- inventing, and naming the wrong slot is worse than naming none.
    local slots
    if C_EquipmentSet and C_EquipmentSet.GetItemLocations then
        local okLoc, locais = pcall(C_EquipmentSet.GetItemLocations, setID)
        if okLoc and type(locais) == "table" then
            slots = {}
            for slot, onde in pairs(locais) do
                if onde == -1 and #slots < c.perdidas then
                    slots[#slots + 1] = ns.Gear and ns.Gear.SlotName(slot) or tostring(slot)
                end
            end
            if #slots == 0 then slots = nil end
        end
    end

    return {
        nome = c.nome,
        perdidas = c.perdidas,
        slots = slots,
        consertavel = (itens > 0) and (vestidas + c.perdidas == itens) or false,
    }
end

--- Writes what the player is wearing NOW over the set, fixing the piece that went missing.
---
--- `SaveEquipmentSet` only changes an existing set and runs in an untainted context -- the same
--- class as `UseEquipmentSet`, which this chain already uses successfully. The return goes to the log
--- because that is where one finds out, from outside the game, whether the call took.
function Data.SaveGearSet(setID)
    if not C_EquipmentSet or not C_EquipmentSet.SaveEquipmentSet then return false end
    local ok, err = pcall(C_EquipmentSet.SaveEquipmentSet, setID)
    if ns.Log then
        ns.Log.Call("gear", "SaveEquipmentSet(" .. tostring(setID) .. ")", ok, err)
    end
    if ns.Log then ns.Log.TaintProbe("SaveEquipmentSet") end
    return ok
end

--------------------------------------------------------------------------------
-- (!) IN TRAVEL FORM THE SPECIALIZATION DOES NOT CHANGE (29/09)
--
-- The user's screenshot, a druid in Travel Form: Specialization and Talents with a red cross,
-- Gear and Appearance with a green tick -- *"caso o druida tiver na forma de viagem, ocorre
-- erro ao trocar, precisamos avisar ao usuário e não mudar nada"*. The diary of that character
-- has it twice: `CanChangeSpec` answers yes, `SetSpecialization` answers accepted, and the cast
-- fails at once (SPECIALIZATION_CHANGE_CAST_FAILED, UNIT_SPELLCAST_FAILED of the spell 200749),
-- four times in a row. Nothing the game answers BEFORE the cast says no.
--
-- What the game's own tables say (SpellMisc, SpellShapeshiftForm, 12.1.0): the spell that
-- changes specialization is not allowed while mounted, and the flight forms (27, 29) are forms
-- with a mount type. For the forms of the ground and of the water (3, 4) there is no such
-- proof: they are here because they are the same spell of the druid, Travel Form, which turns
-- into one or another by where the druid is -- and the user's words are "forma de viagem".
-- Cat, Bear and Moonkin are NOT here: nothing says they cut the cast.
--------------------------------------------------------------------------------
local TRAVEL_FORMS = { [3] = true, [4] = true, [27] = true, [29] = true }

---The form the player is in, when it is one that cuts the change of specialization.
---@return string|nil reason -- with the form's name as the game gives it, in its language
function Data.FormBlocksSpec()
    if not GetShapeshiftFormID then return nil end
    local ok, id = pcall(GetShapeshiftFormID)
    if not ok or type(id) ~= "number" then return nil end
    if issecretvalue and issecretvalue(id) then return nil end
    if not TRAVEL_FORMS[id] then return nil end

    local nome
    if GetShapeshiftForm and GetShapeshiftFormInfo and C_Spell and C_Spell.GetSpellName then
        local okI, indice = pcall(GetShapeshiftForm)
        if okI and type(indice) == "number" and indice > 0 then
            local okF, _, _, _, magia = pcall(GetShapeshiftFormInfo, indice)
            if okF and type(magia) == "number" then
                local okN, n = pcall(C_Spell.GetSpellName, magia)
                if okN and type(n) == "string" and n ~= "" then
                    -- (25/10) the form's icon before its name (the user: *"coloque o icone também"*)
                    local okT, tex = pcall(C_Spell.GetSpellTexture, magia)
                    nome = (okT and tex and ("|T%s:14:14:0:0|t "):format(tostring(tex)) or "") .. n
                end
            end
        end
    end
    if nome then
        return format(L["you are in %s: leave the form to change specialization."], nome)
    end
    -- The game's own sentence for it, when the form has no name to give.
    return ERR_NOT_WHILE_SHAPESHIFTED or L["you are shapeshifted: leave the form to change specialization."]
end

--- Why the Load button is dimmed, or `nil` if it can be clicked.
---
--- (!) THE RULE LIVES HERE, and not inside the row's drawing. It lived there once, and the sabotage
--- showed the cost: turning off the line that dimmed the button **failed nothing**, because no
--- test reaches a widget. A rule that decides behaviour cannot live where only the eye sees.
---
--- There are two reasons, and the order matters: a missing piece first, because it holds for any
--- set, and the specialization restriction after, because it only holds for a set that switches
--- spec -- dimming an items-only set because of it would punish the innocent.
--- @return string|nil reason
function Data.LoadBlockedReason(preset)
    if not preset then return nil end

    -- A switch that is running comes first, and is of every preset (`Data.ApplyingReason`).
    local trocando = Data.ApplyingReason()
    if trocando then return trocando end

    -- Then the name: a preset without one is not finished (`Data.HasName`).
    if not Data.HasName(preset) then return L["Give the preset a name first."] end

    local problema = preset.gear and Data.GearSetProblem(preset.gear)
    if problema then
        return format(
            L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
            problema.nome or "?", problema.perdidas)
    end

    if preset.spec ~= nil and preset.spec ~= Data.GetCurrentSpecIndex() then
        local forma = Data.FormBlocksSpec()
        if forma then return forma end
        local pode, motivo = Data.CanChangeSpec()
        if not pode then
            return motivo or L["the game refused to change specialization now; wait a few seconds."]
        end
    end

    return nil
end

--- Which action the row's button should offer: no change, save, or open the manager.
---
--- It lives here, and not in the UI, for two reasons: the decision is about **the game's data**, not pixels;
--- and so the harness can make assertions about it. Its earlier version lived inside the row's
--- drawing, where only a widget test would reach -- and a test that does not run looks passed.
--- @return string|nil `nil` (a normal load), `"save"` or `"manager"`
function Data.GearFixAction(preset)
    local problema = preset and preset.gear and Data.GearSetProblem(preset.gear)
    if not problema then return nil end
    return problema.consertavel and "save" or "manager"
end

--- Opens the game's Equipment Manager, on the right tab.
---
--- Explaining where it is is worse than taking you there: "open the character sheet, click the third tab on
--- the side" is an instruction the player has to carry out, and he is in the middle of something else.
---
--- `ToggleCharacter` **toggles** -- called with the sheet already open, it CLOSES it. Hence the
--- `IsShown` guard.
---
--- The side tab has two paths because not every client exposes both; if none exists, the
--- sheet opens anyway, which is already almost all the way.
function Data.OpenEquipmentManager()
    if InCombatLockdown() then
        ns.Print(L["in combat: will apply when the fight ends."])
        return false
    end

    if CharacterFrame and CharacterFrame.IsShown and not CharacterFrame:IsShown() then
        if ToggleCharacter then pcall(ToggleCharacter, "PaperDollFrame") end
    elseif ToggleCharacter and not CharacterFrame then
        pcall(ToggleCharacter, "PaperDollFrame")
    end

    if PaperDollFrame_SetSidebar then
        pcall(PaperDollFrame_SetSidebar, nil, 3)
    elseif _G and _G.PaperDollSidebarTab3 and _G.PaperDollSidebarTab3.Click then
        pcall(_G.PaperDollSidebarTab3.Click, _G.PaperDollSidebarTab3)
    end
    if ns.Log then ns.Log.TaintProbe("OpenEquipmentManager") end
    return true
end

-- (25/10) THE ROCKET SBA LAB'S BUILDS, FROM THE GAME'S OWN LISTS. RocketLab saves each build as the game's own presets:
-- the talents as a loadout "Rocket SBA Lab: M+ <hero tree>" (or "Raide"/"Raid") and the items as an equipment set
-- "Rocket M+" (or "Rocket Raide", with the spec's number when another spec holds the name), assigned to the
-- specialization. The two of one build share that word, so a RocketSwap preset is made of them here, reading the game's
-- lists only -- never RocketLab's data (the workspace rule: no addon reads another addon; the plan of 25/10, "ponte com o
-- RocketSwap pelos conjuntos nativos (nome padronizado)"). Both languages: the player may have switched the game's.
local ROCKET_TAG = { ["M+"] = "mplus", ["Raid"] = "raid", ["Raide"] = "raid" }

---The pairs found: { { name, spec (index), talent (configID), gear (setID), tag, loadoutName, setName }, ... }.
function Data.RocketPairs()
    local out = {}
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetAssignedSpec) then return out end
    for _, g in ipairs(Data.GetGearSets()) do
        local tag = g.name:match("^Rocket (%S+)$") or g.name:match("^Rocket (%S+) %d+$")
        local content = tag and ROCKET_TAG[tag]
        local ok, specIndex = false, nil
        if content then ok, specIndex = pcall(C_EquipmentSet.GetEquipmentSetAssignedSpec, g.setID) end
        local spec = ok and specIndex and Data.GetSpecByIndex(specIndex)
        if spec then
            for _, l in ipairs(Data.GetLoadouts(spec.id)) do
                local ltag = l.name:match("^Rocket SBA Lab: (%S+) ")
                if ltag and ROCKET_TAG[ltag] == content then
                    out[#out + 1] = { name = spec.name .. " " .. tag, spec = specIndex, talent = l.configID,
                                      gear = g.setID, tag = tag, loadoutName = l.name, setName = g.name }
                    break
                end
            end
        end
    end
    return out
end

--- A loadout's/set's name by id, so the list shows text instead of a number.
function Data.LoadoutName(specID, configID)
    if not configID then return nil end
    for _, l in ipairs(Data.GetLoadouts(specID)) do
        if l.configID == configID then return l.name end
    end
    return nil
end

function Data.GearSetName(setID)
    if not setID then return nil end
    for _, s in ipairs(Data.GetGearSets()) do
        if s.setID == setID then return s.name, s.icon end
    end
    return nil
end

--- Is this set already wholly applied? It serves the list to mark the active one and to not
--- announce a swap when there is nothing to swap.
function Data.IsLoaded(preset)
    if not preset then return false end

    if preset.spec and preset.spec ~= Data.GetCurrentSpecIndex() then return false end

    local spec = Data.GetSpecByIndex(preset.spec or Data.GetCurrentSpecIndex())
    if preset.talent and spec and Data.GetActiveLoadoutID(spec.id) ~= preset.talent then
        return false
    end
    if preset.gear and Data.GetEquippedSetID() ~= preset.gear then return false end
    if preset.transmog and Data.GetActiveOutfitID() ~= preset.transmog then return false end

    return true
end

--------------------------------------------------------------------------------
-- Applying: the chain of steps
--------------------------------------------------------------------------------
local running          -- { preset, steps, at, timer, report, progress, startedAt }

-- THE PICTURE OF THE END OF THE LAST SWAP. `running` is cleared in `Finish` -- and that is exactly where the
-- result matters: which step went in, which was skipped, which failed. Without keeping this, the
-- progress screen would vanish the instant it has something to say.
local lastRun
local listener

local function Report(text, isError)
    if running and running.report then running.report(text, isError) end
end

--- Is the step already satisfied in the world, now?
---
--- ⚑ IT EXISTS FOR ONE THING ONLY: not flagging as failed what worked. When the deadline runs out, the right
--- question is not "did the event arrive?" but "is it applied?" -- and this addon's history shows the
--- two drift apart: on 07/09 02:05:35 `EQUIPMENT_SWAP_FINISHED` arrived with `true` and the state
--- reading still said the set was not worn. The steps' confirmation is still
--- by EVENT exactly for that; this reading only comes in at the end of the deadline, tens of seconds
--- later, when the state has had time to settle.
---
--- The user's request is literal: *"devo conseguir fazer as trocas sem que tenha erros"*. Complaining
--- about something that is applied is the cheapest error to remove.
local function StepSatisfied(name)
    if not running or not running.preset then return false end
    local preset = running.preset

    if name == "spec" then
        return preset.spec ~= nil and Data.GetCurrentSpecIndex() == preset.spec

    elseif name == "talent" then
        if not preset.talent then return false end
        -- A loadout belongs to a spec: without the right spec the comparison means nothing.
        if preset.spec and Data.GetCurrentSpecIndex() ~= preset.spec then return false end
        local spec = Data.GetSpecByIndex(Data.GetCurrentSpecIndex())
        return spec ~= nil and Data.GetActiveLoadoutID(spec.id) == preset.talent

    elseif name == "gear" then
        return preset.gear ~= nil and Data.IsGearSetEquipped(preset.gear)

    elseif name == "transmog" then
        return preset.transmog ~= nil and Data.GetActiveOutfitID() == preset.transmog
    end

    return false
end

local function Finish(ok, message)
    if running and running.timer then running.timer:Cancel() end

    -- Keeps the `report` BEFORE clearing `running`: `Report()` reads from `running`, and clearing
    -- first made the final message -- including the FAILURE one -- never reach the window. The error
    -- only showed in the chat, which is exactly where the person is not looking after clicking
    -- "Carregar". Caught by the harness, not in the game.
    local preset = running and running.preset
    local report = running and running.report
    local failures = running and running.failures

    if running then
        -- A STEP LEFT IN "doing" AT THE END IS A STEP THAT DID NOT CONFIRM. Getting here with
        -- a step under way only happens by giving up or by a deadline running out -- when the game
        -- confirms, `RunNext` has already closed the step as "done" before ending up in this `Finish`.
        for _, key in ipairs(running.steps) do
            if running.progress and running.progress[key] == "doing" then
                running.progress[key] = "failed"
            end
        end
        lastRun = {
            preset = running.preset,
            steps = running.steps,
            progress = running.progress or {},
            startedAt = running.startedAt,
            tries = running.specTries or 0,
        }
    end

    running = nil

    -- Everything ran, but some step failed: the result is neither success nor failure, it is
    -- **partial**, and the message has to say both -- what was applied and what was not.
    if ok and failures and #failures > 0 then
        ok = false
        message = format(L["%s loaded, except: %s"],
            preset and preset.name or "?", table.concat(failures, "; "))
    end

    local text = ok and format(L["%s is ready."], preset and preset.name or "?")
        or (message or L["timed out waiting for the game to confirm."])

    if ns.Log then ns.Log.Finish(ok, text, failures) end

    if report then report(text, not ok) end
    if not ok then ns.Print(text) end

    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local RunNext   -- declared before so the steps can call it
local RerunStep -- idem: o `RunNext` pausa em combate e pede o passo DE NOVO quando a luta acaba

--- Arms the current step's deadline. Without it, a step that never confirms leaves the addon
--- stuck in "loading" forever, saying nothing.
--- The name of the step under way, for the report. The deadline said only "the game did not confirm in time", without
--- saying of what -- and in a chain of four steps that forces the player to guess (or to tell
--- me, which is what happened: "deu a mensagem que o jogo não confirmou o tempo" and I had to
--- ask which step it was).
local STEP_LABEL = {
    spec     = "Specialization",
    talent   = "Talents",
    gear     = "Gear",
    transmog = "Appearance",
}

local function StepName(key)
    local label = STEP_LABEL[key]
    return label and L[label] or (key or "?")
end

local function Arm()
    if running.timer then running.timer:Cancel() end
    -- THE DEADLINE ONLY TAKES A NOTE TOO. For the same reason as `fail` in `RunNext`: if the talents do not
    -- confirm in time, the items and the appearance can still be applied, and bringing everything down
    -- would leave the player with nothing instead of without one part.
    -- THE STEP'S NAME IS CAPTURED NOW, and not read inside the deadline: when it runs out, `running.at`
    -- may already have moved. Reading it in there would name the wrong step -- worse than naming none.
    local passo = running.steps[running.at]
    local qual = StepName(passo)
    local prazo = STEP_TIMEOUT[passo] or STEP_TIMEOUT_DEFAULT

    running.timer = C_Timer.NewTimer(prazo, function()
        if not running then return end

        -- ⚑ BEFORE FLAGGING, IT CHECKS THE STATE. This is the biggest source of "error" the player sees
        -- with nothing having gone wrong: the confirmation event did not arrive (or arrived and was not
        -- ours), but the swap happened. Without this reading the addon announces "the game did not confirm in
        -- time" about a spec that already switched.
        --
        -- And the deadline is the safe place to read state: it is 20 to 45 seconds after the request, not the
        -- instant right after it -- which is what made 0.13.2 lock the chain.
        if StepSatisfied(passo) then
            if running.progress then running.progress[passo] = "done" end
            if ns.Log then
                ns.Log.Add("prazo", { passo = passo, desfecho = "ja estava aplicado" })
            end
            RunNext()
            return
        end

        -- ⚑ AND THE DEADLINE GETS A LINE OF ITS OWN. Before, it only showed in `fim`, inside
        -- `falhas`: in the log, a silence and then the verdict. `insistindo` and `gravou` already have a
        -- line; the deadline is the outcome that most needs one.
        if ns.Log then ns.Log.Add("prazo", { passo = passo, desfecho = "nao confirmou" }) end

        -- THE STEP DID NOT CONFIRM, AND THAT HAS TO BE MARKED **BEFORE** `RunNext`.
        --
        -- Without this line `RunNext` would find the step still in "doing" and promote it to
        -- "done" -- because that is how it closes a step the game confirmed. An expired deadline is
        -- the opposite case, and the result would be a green check on a step the game never confirmed:
        -- the worst lie this screen can tell, because it contradicts the failure message that
        -- comes out right below.
        if running.progress then running.progress[passo] = "failed" end

        running.failures = running.failures or {}
        running.failures[#running.failures + 1] =
            format(L["%s: the game did not confirm in time."], qual)
        RunNext()
    end)
end

--------------------------------------------------------------------------------
-- Declared here and defined below: `Steps.talent` calls it, and a `local` declared AFTER whoever
-- uses it resolves as a nil global in there. It is the trap this project already paid for three times.
local ConfirmTalent

-- How often to insist on the specialization switch, and how many times.
--
-- Four seconds because it was the shortest interval the log showed working (02:42:48
-- refused, 02:42:52 accepted). The ceiling comes from the step's deadline: `Arm()` already cuts at 45 s, so the
-- attempts stop well before the deadline runs out.
local SPEC_RETRY_DELAY = 4

-- THE CEILING IS THE REAL BACKSTOP, and not the step's deadline: `RetrySpec` calls `Arm()` at each
-- attempt, which RE-ARMS the 45 seconds -- so the deadline alone would never run out while there was
-- insisting. Without this number the chain would insist forever, and getting stuck is the
-- lock-up this sequence already produced twice.
--
-- (The harness does not tell the two endings apart: its `RunTimers` fires everything queued at
-- once, so sabotaging the ceiling fails nothing. It stays for the reasoning above, which is the game's.)
local SPEC_RETRY_MAX = 8

-- INSISTING ON THE TALENT LOAD, for the same reason one insists on the spec switch.
--
-- The real log of 07/09 21:1x, the switch to "Frost PvP":
--
--     SetSpecialization(2)            -> true
--     ACTIVE_PLAYER_SPECIALIZATION_CHANGED
--     LoadConfig(66832448)            -> result = 0 (Error), changeError = **nil**
--
-- `Enum.LoadConfigResult.Error` is 0 (`ClassTalentsDocumentation.lua:501`), so the step was
-- right to call it a failure. What was wrong was GIVING UP: `changeError` came `nil`, that is the
-- game refused **without saying why**, the instant after the spec switch -- which is exactly
-- when it has just rewritten the whole talent tree on the server's side.
--
-- And `CanEditTalents` had answered that it could. Again the pattern this project already paid three
-- times for: the predictor says "can" and the call refuses anyway.
--
-- ⚠️ The interval IS NOT MEASURED -- the only number of this file that is not. There is only one
-- occurrence recorded with the full return, so no pattern can be drawn from it. The 4 seconds come from
-- the spec refusal, which is the same family (a server refusal with no stated reason) and the only one
-- this project measured. If the log shows something else, this is the number that changes.
local TALENT_RETRY_DELAY = 4
local TALENT_RETRY_MAX = 5      -- 20 s, abaixo do prazo de 30 s do passo

-- ⚑ COMMITTING TALENTS IS A CAST, AND THE ITEMS DO NOT GO IN WHILE IT RUNS.
--
-- `LoadConfig` with `LoadInProgress` opens a commit, and Blizzard's UI only calls it finished
-- when the cast `COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID` ends
-- (`Blizzard_ClassTalentsFrame.lua:345-350`). The log of 11/09 shows what happens when one
-- equips before that -- the switch "Tank" -> "Frost PvP":
--
--     17:20:02  ACTIVE_PLAYER_SPECIALIZATION_CHANGED
--     17:20:02  LoadConfig(66832448)          -> LoadInProgress
--     17:20:02  TRAIT_CONFIG_UPDATED 59714245        <- the step closed HERE
--     17:20:02  UseEquipmentSet(0)            -> true, true
--     17:20:02  TRAIT_CONFIG_UPDATED 59714244
--     17:20:02  EQUIPMENT_SWAP_FINISHED       -> false   (16 pieces in the bags, 0 missing)
--     17:20:07  TRAIT_CONFIG_UPDATED 59714245        <- the commit really finishing
--
-- THE PAIR OF THE SAME INSTANT IS AN ECHO OF THE SPEC SWITCH, and not an answer to `LoadConfig`: it shows in the
-- seven recorded chains that switched spec before the talents, including the one of 07/09 21:10:59,
-- in which `LoadConfig` failed on the spot and nothing was loaded. And in the log's 24 chains the
-- items were refused in exactly the THREE that opened a commit (09/09 17:22:02 and 17:58:14,
-- 11/09 17:20:02) -- and went in in all the other 21.
--
-- The echo brings the SAME `configID` as the true event (59714245 in both). That is why the id
-- filter of 0.13.0 could not work, and no other id filter will. What tells the
-- two apart is time: the echo fell in the second of `LoadConfig` all seven times, the true one arrived 4 to
-- 7 s later in the three commits.
--
-- So the step closes on the FIRST of two signals:
--   1. the end of the commit cast -- what Blizzard itself uses;
--   2. a `TRAIT_CONFIG_UPDATED` arriving after the echo's window -- the fallback, for when the
--      cast is not seen (an opaque `spellID`, or a client that changes the flow).
--
-- ⚠️ THE WINDOW IS NOT MEASURED PRECISELY: the log records whole seconds. What is known is that the
-- echo fell within the same second seven times in seven, and the true one never before 4 s. 2 sits
-- in the middle. The log now records WHICH signal closed it and in how many seconds (`event = "gravou"`); if
-- "evento" comes with less than 4 s, this is the number that needs a look.
local COMMIT_SPELL_ID = Constants and Constants.TraitConsts
    and Constants.TraitConsts.COMMIT_COMBAT_TRAIT_CONFIG_CHANGES_SPELL_ID or 384255
local COMMIT_ECHO_WINDOW = 2

--- Translates a step's result into the state the window draws.
---
--- ONE PLACE ONLY, and the reason is a real defect: this lived inside `RunNext`, and the
--- INSISTING paths (`RetrySpec`, `RetryTalent`) call `Steps.*` directly, without going through it. The step
--- that gave up after the ceiling stayed marked "doing", and the next call of `RunNext`
--- promoted it to **"done"** -- a green check beside the failure message, the same lie
--- the expired deadline had already produced once.
---
--- "wait" does not show here on purpose: it keeps "doing", which is what it means.
local function NoteOutcome(name, outcome)
    if not running or not running.progress then return end

    -- `"skip"` only becomes "skipped" when the picture from before says it was already right. Without that
    -- check, everything that switched mid-chain was announced as "nothing to change".
    if outcome == "skip" then
        running.progress[name] = (running.already or {})[name] and "skipped" or "done"
    elseif outcome == "fail" or outcome == "abort" then
        running.progress[name] = "failed"
    end
end

local Steps = {}

--- Insists on the loadout load when the game refuses without saying why.
---
--- It mirrors `RetrySpec` on purpose, the token guard included: another apply may have
--- started meanwhile, and the attempt scheduled by this one no longer rules.
local function RetryTalent(preset)
    running.talentTries = (running.talentTries or 0) + 1

    if running.talentTries > TALENT_RETRY_MAX then
        return "fail", L["the game kept refusing to load the talents."]
    end

    Report(L["Waiting for the game to accept the talents..."], false)
    if ns.Log then
        ns.Log.Add("insistindo", { passo = "talent", tentativa = running.talentTries })
    end

    Arm()

    local token = running
    C_Timer.After(TALENT_RETRY_DELAY, function()
        if not running or running ~= token then return end
        if running.steps[running.at] ~= "talent" then return end

        local outcome, message = Steps.talent(preset)
        if ns.Log then ns.Log.Step("talent", outcome or "wait", message) end
        NoteOutcome("talent", outcome)

        if outcome == "skip" then
            RunNext()
        elseif outcome == "abort" then
            Finish(false, message)
        elseif outcome == "fail" then
            running.failures = running.failures or {}
            running.failures[#running.failures + 1] = message
            RunNext()
        end
    end)

    return "wait"
end

--- What the character is casting now, if anything.
---
--- ⛑ IT EXISTS BECAUSE OF A DEFECT OF OURS, found in the log on 21/09. In **10 out of 10** recorded
--- switches touching the specialization, the first `SetSpecialization` was refused and the second,
--- four seconds later, accepted. The cause was not the game being busy on its own: the
--- Load button switches the appearance by **a secure action on the click itself** (`UI.lua`, attribute
--- `"outfit"`), and that **casts** spell 1247613 at the same instant. The game does not let a
--- cast start with another in flight, so the refusal was **caused by us**, always, and cost the
--- player a lost cast bar plus four seconds of nothing.
---
--- The report was *"às vezes ele cast mais de uma vez"*. It was always; the "sometimes" is because a set
--- without an appearance, or without a spec switch, does not go through here.
local function CastInFlight()
    if UnitCastingInfo then
        local name, _, _, _, _, _, _, _, spellID = UnitCastingInfo("player")
        if name then return name, spellID end
    end
    if UnitChannelInfo then
        local name, _, _, _, _, _, _, spellID = UnitChannelInfo("player")
        if name then return name, spellID end
    end
end

-- A short, repeated wait: the appearance cast lasts about a second, so the step
-- usually comes out at the first or second look. The ceiling exists for the case of the player
-- casting something else -- then the normal insisting takes over, as it always did.
local CAST_WAIT_STEP = 0.25
local CAST_WAIT_MAX = 3

--- Waits for the cast in flight to end and only then asks for the spec switch.
---
--- **It DOES NOT use up a `RetrySpec` attempt**: this is not the game refusing, it is us waiting for
--- our own cast to get out of the way. Spending an attempt here would shorten the insisting
--- budget of whoever really needs it.
local function WaitForCast(preset, elapsed)
    elapsed = elapsed or 0
    Arm()

    local token = running
    C_Timer.After(CAST_WAIT_STEP, function()
        if not running or running ~= token then return end
        if running.steps[running.at] ~= "spec" then return end

        if CastInFlight() and elapsed + CAST_WAIT_STEP < CAST_WAIT_MAX then
            WaitForCast(preset, elapsed + CAST_WAIT_STEP)
            return
        end

        local outcome, message = Steps.spec(preset)
        if ns.Log then ns.Log.Step("spec", outcome or "wait", message) end
        NoteOutcome("spec", outcome)

        if outcome == "skip" then
            RunNext()
        elseif outcome == "abort" then
            Finish(false, message)
        elseif outcome == "fail" then
            running.failures = running.failures or {}
            running.failures[#running.failures + 1] = message
            RunNext()
        end
    end)

    return "wait"
end

--- Insists on the specialization switch until the game accepts.
---
--- The refusal is not a player's or the addon's error: it is the game saying "not now". Returning that
--- as a failure forced the player to click again -- which is exactly what this function does for
--- him, and without turning into an error what is only waiting.
local function RetrySpec(preset, wanted)
    running.specTries = (running.specTries or 0) + 1

    if running.specTries > SPEC_RETRY_MAX then
        return "abort", L["the game kept refusing to change specialization."]
    end

    Report(L["Waiting for the game to allow the specialization change..."], false)
    if ns.Log then
        ns.Log.Add("insistindo", { passo = "spec", tentativa = running.specTries })
    end

    -- `Arm()` continua sendo o teto: se o jogo nunca aceitar, o prazo do passo encerra.
    Arm()

    local token = running
    C_Timer.After(SPEC_RETRY_DELAY, function()
        -- Another apply may have started meanwhile; this one no longer rules.
        if not running or running ~= token then return end
        if running.steps[running.at] ~= "spec" then return end

        local outcome, message = Steps.spec(preset)
        if ns.Log then ns.Log.Step("spec", outcome or "wait", message) end
        NoteOutcome("spec", outcome)

        if outcome == "skip" then
            RunNext()
        elseif outcome == "abort" then
            Finish(false, message)
        elseif outcome == "fail" then
            running.failures = running.failures or {}
            running.failures[#running.failures + 1] = message
            RunNext()
        end
    end)

    return "wait"
end

function Steps.spec(preset)
    local wanted = preset.spec
    if not wanted or wanted == Data.GetCurrentSpecIndex() then return "skip" end

    -- IT ASKS BEFORE CALLING, with the condition of the game's own talents window. The reason
    -- comes from it already translated; our phrase only goes in when it sends none.
    local pode, motivo, porque = Data.CanChangeSpec()
    if ns.Log then
        ns.Log.Call("spec", "CanChangeSpec", pode, motivo,
            porque or SpecSpellID() or "magia desconhecida")
    end
    if not pode then
        -- ⚑ A COOLDOWN IS NOT A REASON TO GIVE UP -- IT IS A REASON TO WAIT, and it was the most common cause
        -- of the player getting "the game refused to switch specialization now" right after a
        -- successful switch. The spell's cooldown ends in seconds, and the insisting already exists.
        --
        -- A reason IN TEXT still aborts: there the game said what it was (combat, a mythic area), and
        -- insisting would be repeating a question already answered.
        if porque and not motivo then
            return RetrySpec(preset, wanted)
        end
        return "abort", motivo
            or L["the game refused to change specialization now; wait a few seconds."]
    end

    -- ⛑ DO NOT ASK WITH A CAST IN FLIGHT. See `CastInFlight`: the refusal the addon had been treating
    -- as "the game is busy" was caused by our own appearance swap. Waiting
    -- here is cheaper than insisting later -- and the second cast bar goes away.
    local conjurando, conjurandoID = CastInFlight()
    if conjurando then
        if ns.Log then
            ns.Log.Add("esperando cast", {
                passo = "spec", magia = conjurando, id = conjurandoID or 0,
            })
        end
        Report(L["Switching specialization..."], false)
        return WaitForCast(preset)
    end

    Report(L["Switching specialization..."], false)

    -- `C_SpecializationInfo.SetSpecialization` is the current path; the old global stays as a
    -- fallback. Both take the spec's INDEX, not the id.
    -- THE RETURN MATTERS. `SetSpecialization` returns `success`
    -- (`SpecializationInfoDocumentation.lua:368-380`), and Blizzard itself branches on it
    -- (`Blizzard_ClassSpecializationsFrame.lua:457-465`). Keeping only the `pcall`'s `ok` captured
    -- only "did it blow up?", so an immediate refusal of the game became twelve seconds of
    -- "Carregando..." followed by "the game did not confirm in time" -- and the chain went on to the
    -- talents with the WRONG spec.
    -- SWALLOWS THE RED ERROR OUR OWN CALL IS ABOUT TO CAUSE.
    --
    -- The report: *"quando troco o preset aparece uma mensagem do jogo mesmo 'Você não pode fazer isso
    -- agora', vai confundir o usuário, ele vai achar que não vai trocar nada, mas tá funcionando"*.
    -- He is right: the refusal is transient and the addon already insists by itself, so the game's error
    -- describes a state that stops holding four seconds later.
    --
    -- `SuppressMessagesThisFrame` is Blizzard's own method
    -- (`Blizzard_UIErrorsFrame/Mainline/UIErrorsFrame.lua:182-189`) and it is the right size: it holds for
    -- **one frame** and disarms itself with a `C_Timer.After(0, …)`. It is not
    -- `UnregisterEvent`, which would erase others' errors for an unknown time -- the error swallowed
    -- here is only the one our next line causes.
    --
    -- And no information is lost: the reason is still in the log, and the step still reports what
    -- happened in the window. What leaves the screen is the contradiction -- red saying "you cannot"
    -- while the addon is solving it.
    if UIErrorsFrame and UIErrorsFrame.SuppressMessagesThisFrame then
        pcall(UIErrorsFrame.SuppressMessagesThisFrame, UIErrorsFrame)
    end

    local ok, aceito
    if C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
        ok, aceito = pcall(C_SpecializationInfo.SetSpecialization, wanted)
        if ns.Log then
            ns.Log.Call("spec", "SetSpecialization(" .. tostring(wanted) .. ")", ok, aceito)
        end
    elseif SetSpecialization then
        ok, aceito = pcall(SetSpecialization, wanted)
        if ns.Log then ns.Log.Call("spec", "SetSpecialization global", ok, aceito) end
    elseif ns.Log then
        ns.Log.Call("spec", "nenhuma funcao de troca de spec existe")
    end
    if ns.Log then ns.Log.TaintProbe("SetSpecialization") end
    -- `aceito == false` is THE GAME REFUSING, and the log showed it is common: in four of the nine
    -- recorded switches the game returned `false`, always when the switch came a few seconds after
    -- another. Switching specialization has a cost in the game, and insisting does not help -- waiting does.
    -- A REFUSAL IS TRANSIENT: WAIT AND TRY AGAIN, instead of returning an error to the player.
    --
    -- It was his log that settled this, after I got the forecast wrong THREE times:
    --
    --   02:42:14  SetSpecialization(1) -> true    (success)
    --   02:42:28  SetSpecialization(2) -> false   (refused)
    --   02:42:37  SetSpecialization(2) -> true    (nine seconds later, success)
    --   02:42:48  SetSpecialization(1) -> false   (refused)
    --   02:42:52  SetSpecialization(1) -> true    (four seconds later, success)
    --
    -- **Trying again always works.** And the three things I tried to use to PREDICT the
    -- refusal were refuted by the same file: `CanPlayerUseTalentSpecUI` answered `true` in
    -- all of them; the cooldown of spell 200749 (learnt from the game itself) was inactive; and there is no
    -- fixed time window -- the refused interval ranges from 4 to 14 seconds.
    --
    -- So the addon stops guessing and does what the player would do: waits and clicks again. He
    -- said *"não tem problema demorar um pouco"*, and the step's deadline (45 s) is the ceiling.
    if not ok or aceito == false then
        -- RECORDS WHAT WAS BEING CAST AT THE TIME OF THE REFUSAL. It is the proof, or the refutation, of the cause
        -- diagnosed on 21/09: if the guard above is right, this field comes to be
        -- `nenhum` and the refusal vanishes from the log. If it keeps showing with a spell, the cause is another
        -- and the next log says which -- instead of me guessing again.
        if ns.Log then
            local emVoo, emVooID = CastInFlight()
            ns.Log.Add("recusa", {
                passo = "spec", conjurando = emVoo or "nenhum", id = emVooID or 0,
            })
        end
        return RetrySpec(preset, wanted)
    end

    Arm()
    return "wait"
end

--- The GAME's message, when it gives one.
---
--- The text comes localised and says the concrete cause ("você não pode fazer isso em combate", "não é
--- possível numa área de dificuldade Mítica"…). Our generic phrase only goes in when the game
--- did not explain -- and then it is honest, because indeed nobody knows.
--- The name of the `Enum.LoadConfigResult` value, so the log says `Error` instead of `0`.
local function LoadConfigResultName(result)
    local E = Enum and Enum.LoadConfigResult
    if not E or result == nil then return result end
    for name, value in pairs(E) do
        if value == result then return name .. "(" .. tostring(result) .. ")" end
    end
    return result
end

local function TalentError(changeError)
    if type(changeError) == "string" and changeError ~= "" then
        return format(L["talents: %s"], changeError)
    end
    return L["the talent loadout could not be loaded."]
end

function Steps.talent(preset)
    if not preset.talent then return "skip" end

    -- THE SPEC HAS TO BE THE SET'S BEFORE TOUCHING TALENTS, and this was the defect that made
    -- the swap "do the wrong thing".
    --
    -- A loadout belongs to ONE specialization. This step resolved by the CURRENT spec, so when
    -- the step before failed, ran out of time, or simply had not switched yet, it
    -- took the OLD spec and sent `LoadConfig` with an id that is ANOTHER's -- the game complains, and
    -- rightly.
    --
    -- And the worst came right after: `UpdateLastSelectedSavedConfigID(spec.id, preset.talent)`
    -- recorded the target spec's loadout as "the last selected" of the old spec. That **stays
    -- recorded in the game**, so the damage survives `/reload` and shows again the next time the
    -- player comes back to that spec through the talents window.
    --
    -- Refusing here is what "sequential" means: without the right spec, the talents step has
    -- nothing to do, and pretending it has is how others' state gets corrupted.
    local atual = Data.GetCurrentSpecIndex()
    if preset.spec and atual ~= preset.spec then
        return "fail", L["the specialization did not change, so the talents were left alone."]
    end

    local spec = Data.GetSpecByIndex(atual)
    if spec and Data.GetActiveLoadoutID(spec.id) == preset.talent then return "skip" end

    -- ⚑ DOES THE LOADOUT STILL EXIST? The id stays saved in `RocketSwapDB.presets` and the player can delete
    -- the loadout in the talents window at any time. Without this check the addon called
    -- `LoadConfig` on a dead id and the player heard "the game kept refusing to load the
    -- talents" after five attempts and twenty seconds -- the wrong cause, a useless wait.
    --
    -- It is the same answer the appearance already gave ("that set no longer exists"), and what the native UI
    -- does in the matching case: `ERR_TALENT_FAILED_INVALID_CONFIG`
    -- (`Blizzard_ClassTalentsFrame.lua:1743`).
    --
    -- It only decides when the list exists: a client without the API returns an empty list, and then "not found" does not
    -- prove it was deleted.
    if spec then
        local loadouts = Data.GetLoadouts(spec.id)
        if #loadouts > 0 then
            local existe = false
            for _, l in ipairs(loadouts) do
                if l.configID == preset.talent then existe = true end
            end
            if not existe then
                return "fail", L["that talent loadout no longer exists."]
            end
        end
    end

    Report(L["Loading talents..."], false)

    if not C_ClassTalents or not C_ClassTalents.LoadConfig then
        return "fail", L["the talent loadout could not be loaded."]
    end

    -- IT ASKS FIRST, and uses the game's answer. `CanEditTalents` returns `canEdit, changeError`
    -- and the documentation is explicit: *"Returns true if the player could switch talents if they
    -- staged a proper loadout"*. It is the real reason of the intermittent failure -- combat, the wrong area,
    -- an instance restriction -- and the game already gives it in Portuguese.
    if C_ClassTalents.CanEditTalents then
        local fine, canEdit, why = pcall(C_ClassTalents.CanEditTalents)
        if fine and canEdit == false then
            return "fail", TalentError(why)
        end
    end

    -- THREE returns, not one: `result, changeError, newLearnedNodeIDs`. Capturing only the first
    -- threw away exactly the string that says WHY it failed -- and the addon answered with a
    -- "could not load the talents" that teaches nothing.
    running.commit = nil        -- only a commit opened BY THIS call confirms the step
    local ok, result, changeError = pcall(C_ClassTalents.LoadConfig, preset.talent, true)
    if ns.Log then
        -- THE ENUM'S NAME, NOT ONLY THE NUMBER. Reading `result = 0` in the log cost a trip to the
        -- documentation to find out that 0 is `Error` -- and the log exists to answer on the
        -- spot, not to send one searching.
        ns.Log.Call("talent", "LoadConfig(" .. tostring(preset.talent) .. ")",
            ok, LoadConfigResultName(result), changeError)
    end
    if ns.Log then ns.Log.TaintProbe("LoadConfig") end
    if not ok then return "fail", L["the talent loadout could not be loaded."] end

    -- THE WRITING OF "WHICH LOADOUT HOLDS" LEFT HERE, for two reasons:
    --
    --   1. writing BEFORE the game confirms is how others' state got corrupted (the target spec's
    --      loadout recorded as the old spec's) -- it is the defect of 0.13.1 by its root;
    --   2. and it poisoned the confirmation itself: I came to confirm the step by reading
    --      `GetLastSelectedSavedConfigID`, which is exactly what this line writes. The addon
    --      wrote the answer and then read it as proof. Circular.
    --
    -- Now it runs in `ConfirmTalent`, when the game confirms.

    -- `Ready` IS NOT "already applied", and treating it so was a comfortable lie. `NoChangesNecessary`
    -- says there is nothing to do; `Ready` says the configuration was STAGED and awaits a commit.
    -- Lumping the two into a `skip` made the addon announce "done" with the old talents.
    local E = Enum.LoadConfigResult
    if result == (E and E.NoChangesNecessary) then
        -- IT RECORDS EVEN WITH NO CHANGE, and the real log is what showed this: `LoadConfig` returned
        -- `NoChangesNecessary` in **six of the nine** recorded switches. It makes sense -- the tree's
        -- nodes were already the same.
        --
        -- But 0.13.2 only recorded the loadout on the confirmation by event, and this path does not
        -- wait for any event. Result: the game never learnt which loadout came to
        -- hold, the talents window kept marking the previous one, and `IsLoaded` never came out
        -- true -- so the check mark did not show and the player clicked again. It is the "não chega a
        -- trocar tudo certo", and the cause was mine, from yesterday.
        ConfirmTalent()
        return "skip"
    end
    if result == (E and E.Ready) then
        return "fail", L["the talents were staged but not applied; open the talent window and apply."]
    end
    if result == (E and E.Error) then
        -- WITH A REASON, IT REPORTS; WITHOUT A REASON, IT INSISTS.
        --
        -- The distinction is the heart of the fix. When `changeError` brings a string, the game
        -- said what happened -- combat, the wrong area, an instance restriction -- and insisting would be
        -- repeating a question already answered: it reports with its words.
        --
        -- When it comes `nil`, the game refused and did not explain. That was the log's case, right after the
        -- spec switch. A refusal with no stated reason, in this addon, already proved transient
        -- once (the spec's) -- and insisting is right under both possible readings: if it is passing,
        -- it solves it; if it is permanent, the ceiling returns the same failure as before, only a few
        -- seconds later.
        if type(changeError) == "string" and changeError ~= "" then
            return "fail", TalentError(changeError)
        end
        return RetryTalent(preset)
    end

    -- LoadInProgress: the commit started, and it is a cast (see `COMMIT_ECHO_WINDOW`). The time is what
    -- tells the spec switch's echo from the real confirmation.
    running.commit = { since = GetTime() }
    Arm()
    return "wait"           -- confirms at the end of the commit cast (or on the late TRAIT_CONFIG_UPDATED)
end

-- How many times the items step waits for a cast to end before giving up. The measured case is ONE (the
-- talent commit cast); three leave room for the player to cast something else without
-- leaving the chain hanging on whoever never stops casting.
local GEAR_CAST_WAIT_MAX = 3

function Steps.gear(preset)
    if not preset.gear then return "skip" end
    if Data.GetEquippedSetID() == preset.gear then return "skip" end

    -- ⚑ DOES THE SET STILL EXIST? `GetEquipmentSetInfo` returns nothing for a deleted id
    -- (`MayReturnNothing`), and that is how the character sheet decides to disable the
    -- Equip button (`PaperDollFrame.lua:2450-2468`). Without this the addon asked for the swap, the game did
    -- nothing, and the player got the generic phrase "could not equip the equipment set" -- which
    -- sends one hunting a missing piece where the problem is another.
    if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo
        and not Data.GearSetCounts(preset.gear) then
        return "fail", L["that gear set no longer exists."]
    end

    -- The three guards the game itself uses before equipping a set. The order matters
    -- only for the message: each failure has its own, because `UseEquipmentSet` returns no reason.
    if C_EquipmentSet.EquipmentSetContainsLockedItems
        and C_EquipmentSet.EquipmentSetContainsLockedItems(preset.gear) then
        return "fail", L["some items of this set are locked (in use, or in the mail)."]
    end
    -- ⚑ A CAST UNDER WAY IS NOT A FAILURE, IT IS A WAIT. The log of 11/09 17:46:01, the first switch that
    -- exercised 0.22.0:
    --
    --     17:46:01  UNIT_SPELLCAST_SUCCEEDED 384255   -> the talents step closes (right)
    --     17:46:01  gear step -> fail "você está conjurando algo"
    --
    -- The cast that had just ENDED still counted. The game's cast bar does not even look at
    -- SUCCEEDED: it only calls the cast over on `UNIT_SPELLCAST_STOP`, and that is where its
    -- information stops existing (`CastingBarFrame.lua:459,482-483`). Refusing for that
    -- brought the items down exactly in the swap the addon exists to make. Now the step waits for the
    -- end of the cast -- the player's STOP, FAILED or INTERRUPTED -- and tries again.
    --
    -- The CEILING is for the player who keeps casting one spell after another: without it the wait would
    -- re-arm at each cast and the deadline would never run out.
    local conjurando, _, _, _, _, _, _, _, magia = UnitCastingInfo("player")
    if conjurando then
        running.gearCastWaits = (running.gearCastWaits or 0) + 1
        -- WHAT IS BEING CAST goes to the log. The refusal of 17:46:01 did not say, and it had to be
        -- deduced from the instant that it was the commit cast itself.
        if ns.Log then ns.Log.Call("gear", "UnitCastingInfo", conjurando, magia) end
        if running.gearCastWaits > GEAR_CAST_WAIT_MAX then
            return "fail", L["you are casting something — try again in a second."]
        end
        running.gearWaitsCast = true
        Arm()
        return "wait"       -- o fim do cast chama o passo de novo (`RerunStep`)
    end

    Report(L["Equipping gear..."], false)

    -- THE PICTURE BEFORE THE CALL. After it there is no point: if the swap starts, the counts have already
    -- changed. It is what tells "the set asked for a piece that does not exist" from "the game refused for
    -- another reason" when the event comes back `false`.
    if ns.Log then
        ns.Log.Call("gear", "estado de " .. tostring(preset.gear),
            Data.DescribeGearSet(preset.gear) or "sem resposta")
    end

    -- ⚑ THE SECOND RETURN WAS THROWN AWAY, and this file's header already said not to:
    -- *"Each step waits for the confirmation event AND looks at the return"*. `ok` is the `pcall`'s and
    -- answers "did it blow up?"; what answers "did the game accept?" is `setWasEquipped`
    -- (`EquipmentManagerDocumentation.lua:287-299`). Of the chain's three steps, this was the
    -- only one that did not look -- and so the only one whose refusal did not show in the log.
    local ok, equipou = pcall(C_EquipmentSet.UseEquipmentSet, preset.gear)
    if ns.Log then
        ns.Log.Call("gear", "UseEquipmentSet(" .. tostring(preset.gear) .. ")", ok, equipou)
    end
    if ns.Log then ns.Log.TaintProbe("UseEquipmentSet") end
    if not ok then return "fail", Data.GearFailureReason(preset.gear) end

    -- AN IMMEDIATE REFUSAL IS NOT WAITED FOR. With no swap, `EQUIPMENT_SWAP_FINISHED` does not come -- and the step
    -- would spend the deadline's 20 seconds waiting for an event nobody is going to send, only to say in the
    -- end "the game did not confirm in time". It is the same defect the spec and the talents already
    -- had, fixed in both; here it was still standing.
    if equipou == false then
        return "fail", Data.GearFailureReason(preset.gear)
    end

    Arm()
    return "wait"           -- confirma em EQUIPMENT_SWAP_FINISHED
end

--- The appearance is the chain's LAST -- but whoever switches it already did, back at the start.
---
--- The reason written here before ("equipping items moves the pieces, so the outfit comes after") described
--- a request this addon **no longer makes**. Switching an appearance set is a privilege of
--- secure code: what fires it is the `outfit` action armed on the button, inside the click itself, before
--- `Data.Apply` even exists. The addon here **checks and waits**, it does not ask.
---
--- So what the last position settles is the CHECK: asking "did the outfit go in?" after the
--- items were equipped, and not before. Leaving the old phrase in place was guaranteeing that the
--- next reading would redo the same wrong reasoning.
---
--- This said, in writing, that "this step is the only one with NO confirmation event
--- tied". **It was false**, and the claim cost dearly: on top of it the step came to check with
--- a `C_Timer.After(0.1)` -- a number picked by eye, with nothing guaranteeing the swap holds
--- within it. If the swap takes longer than that, the step flags a failure on a swap that worked.
---
--- The event exists and is `TRANSMOG_DISPLAYED_OUTFIT_CHANGED`
--- (`TransmogOutfitInfoDocumentation.lua:818-821`, `SynchronousEvent = true`), and it is what the
--- transmog window itself listens to in order to redraw (`Blizzard_Transmog.lua:85,184`). What I
--- had looked at was `TRANSMOG_OUTFITS_CHANGED` -- that one does say the LIST changed (create,
--- delete), and not which is active. Two events with a similar name, and I checked only one.
function Steps.transmog(preset)
    if not preset.transmog then return "skip" end
    if Data.GetActiveOutfitID() == preset.transmog then return "skip" end

    -- BY HERE THE SWAP SHOULD ALREADY HAVE HAPPENED, on the click itself. If it did not, there is nothing
    -- this step can do: the two functions that switch a set are PROTECTED.
    --
    -- Getting to this cost three rounds of in-game testing, and the answer was in nothing I
    -- could deduce from the code -- it was in the patch notes:
    --
    --   * an addon's appearance swap goes through a secure button (`type = "outfit"`,
    --     `outfit-index`, `action = "change"`);
    --   * and patch 12.0.5 added **a secure action `"outfit"`** exactly for that --
    --     *"Added a new secure action (`"outfit"`) for changing/clearing transmog outfits"* -- which
    --     is how Blizzard answered the request for addons to be able to switch.
    --
    -- That is: the path does not exist through the API and will not. It exists through **the player's click on a
    -- secure button**, and that is what the "Carregar" button became (`UI.lua`, `BuildRow`).
    --
    -- WHY THE STEP STAYS HERE, if it does not act: because it is the only thing that can say the
    -- appearance was left behind. Without it the set would call itself applied with the wrong outfit.
    -- Before, it CALLED and lied about being able to; now it CHECKS and tells the truth.
    local index = Data.OutfitIndex(preset.transmog)
    if not index then
        return "fail", L["that transmog outfit no longer exists."]
    end

    -- And if any of the known doors is closed, its reason beats the generic one:
    -- the secure click goes through the same ones (the cooldown of spell 1247613, the style event, the
    -- locked set), so they also explain the click that did not take.
    local impedindo = Data.TransmogBlockedBy(preset.transmog)
    if impedindo then return "fail", impedindo end

    -- IF IT CAME FROM THE CLICK, THE SWAP WAS ALREADY ASKED FOR -- and asking is not having arrived.
    --
    -- The secure action runs on the click and the server answers later; this step may run before the
    -- answer, especially when the three steps before have nothing to do and the chain
    -- gets here in the same frame. Checking on the spot and failing would turn a swap that works
    -- into a failure warning -- worse than the original defect, and what the first version of this
    -- check did.
    --
    -- So it waits for the event, with `Arm()`'s deadline behind it, like every other step.
    if running and running.byClick then
        Arm()
        return "wait"
    end

    -- AND IF IT DID NOT COME FROM THE CLICK there is nothing to wait for: nobody asked for anything. It is the case of
    -- `/rs load <name>` and of the minimap, and the phrase has to say so instead of leaving the player
    -- waiting twelve seconds for a confirmation that does not come.
    return "fail", L["the appearance only changes by clicking Load (Blizzard protects the API)."]
end

--- Records in the game which loadout came to hold.
---
--- Only after the game confirms. Without this call the talents window keeps marking the
--- previous one as selected; done too early, it records the wrong association and the damage stays
--- saved in the game, surviving `/reload`.
ConfirmTalent = function()
    if not running or not running.preset.talent then return end
    if not C_ClassTalents or not C_ClassTalents.UpdateLastSelectedSavedConfigID then return end

    local spec = Data.GetSpecByIndex(Data.GetCurrentSpecIndex())
    if not spec then return end

    -- ONLY IF THE SPEC IS THE SET'S -- and this guard is **defensive**, not load-bearing: the talents
    -- step already refuses before getting here, and sabotaging it fails no test. It stays because
    -- this function runs from an EVENT, and an event arrives when it pleases: between the step and the
    -- confirmation the spec may have changed from outside. And what it protects is state that survives
    -- `/reload`, so the cost of getting it wrong is bigger than one more line.
    if running.preset.spec and Data.GetCurrentSpecIndex() ~= running.preset.spec then return end

    pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, spec.id, running.preset.talent)
    if ns.Log then ns.Log.TaintProbe("UpdateLastSelectedSavedConfigID") end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
RunNext = function()
    if not running then return end

    -- THE STEP THAT WAS WAITING HAS JUST BEEN CONFIRMED. Whoever calls `RunNext` from outside is the
    -- event listener, and getting here with the step in "doing" means the game confirmed.
    local anterior = running.steps[running.at]
    if anterior and running.progress and running.progress[anterior] == "doing" then
        running.progress[anterior] = "done"
    end

    running.at = running.at + 1
    local name = running.steps[running.at]

    if not name then
        Finish(true)
        return
    end

    -- `pcall` ON THE STEP, and the reason is the worst defect this chain ever had: a Lua error
    -- inside a step goes up through `RunNext`, and **nothing clears `running`** -- only `Finish`. From
    -- then on every click on Load came back SILENT, because `Data.Apply` refuses while a chain is
    -- under way. A red error once, and the button dead until `/reload`.
    --
    -- With the `pcall`, the error becomes a failure noted like any other: the chain goes on, the
    -- log records the Lua message, and the addon stays alive.
    -- THE STEP STARTED. The window reads this to show which stage the swap is in.
    running.progress = running.progress or {}
    running.progress[name] = "doing"

    -- ⚑ COMBAT IN THE MIDDLE OF THE CHAIN PAUSES, IT DOES NOT FAIL. `Data.Apply` already queues when the click
    -- happens in combat, but nothing re-evaluated after starting: entering combat midway made
    -- the game refuse step by step, and the player ended with a partial result and a row of
    -- error messages -- three of the four describing the SAME cause.
    --
    -- `RunWhenSafe` is the queue that already exists (`Core.lua:33-39`, emptied on `PLAYER_REGEN_ENABLED`),
    -- and the token guards against the case of another chain having started meanwhile.
    --
    -- No `Arm()` on purpose: a paused step has no deadline running. A deadline running out during the
    -- fight would flag a failure of something the addon did not even try.
    -- ⚑ `running.preset[name]` IS NOT REDUNDANT, and the harness caught it on the first round: the
    -- chain ALWAYS has the four steps, and the step the set does not define only passes through here
    -- to return "skip". Without this condition, a spec+items-only set paused on the
    -- TALENTS step -- stopped for the whole fight on a step with no work, and invisible on screen, because
    -- the panel only draws the steps the set defines (`Data.GetProgress`). It is the panel's same
    -- condition, on purpose.
    if COMBAT_SENSITIVE[name] and running.preset[name] and InCombatLockdown() then
        Report(L["in combat: will apply when the fight ends."], false)
        if ns.Log then ns.Log.Add("pausado", { passo = name, motivo = "combate" }) end

        local token = running
        ns.RunWhenSafe(function()
            if not running or running ~= token then return end
            if running.steps[running.at] ~= name then return end
            RerunStep(name)
        end)
        return
    end

    local okStep, outcome, message = pcall(Steps[name], running.preset)
    if not okStep then
        if ns.Log then ns.Log.Step(name, "erro de lua", tostring(outcome)) end
        message = L["an internal error interrupted this step."]
        outcome = "fail"
    elseif ns.Log then
        ns.Log.Step(name, outcome or "wait", message)
    end

    NoteOutcome(name, outcome)

    if outcome == "skip" then
        RunNext()

    -- "abort" IS DIFFERENT FROM "fail", and the difference came from the log: when the spec switch is
    -- refused, **everything after it falls together** -- the talents are another spec's, the equipment set
    -- goes with the spec, and the appearance is already on cooldown from the previous switch. The report
    -- came out with FOUR failures in a row, which the user read as "fica bugado e dando erro".
    --
    -- One cause, one message. Only the spec step uses this, and only when the set asks for a spec:
    -- without it, none of the rest makes sense.
    elseif outcome == "abort" then
        Finish(false, message)

    elseif outcome == "fail" then
        -- `running` may have vanished INSIDE the step: the confirmation events are dispatched
        -- by the game and one of them may have closed the whole chain before we got back here.
        if not running then return end
        -- A STEP THAT FAILS DOES NOT BRING DOWN THE FOLLOWING ONES.
        --
        -- Before, `fail` called `Finish` on the spot, and the chain stopped there. Since the order is
        -- spec -> talents -> items -> appearance, a failure in the talents (which happens for a reason
        -- of the game's -- combat, the wrong area) took with it the ITEMS and the APPEARANCE, which would have
        -- worked. That is how "a aparência não funciona" showed up: it is the last step and
        -- almost never got to run.
        --
        -- Now the failure is noted and the chain goes on. At the end, the report says what failed --
        -- and the player keeps everything that could be applied, instead of nothing.
        running.failures = running.failures or {}
        running.failures[#running.failures + 1] = message
        RunNext()
    end
    -- "wait": o evento correspondente chama RunNext()
end

--- Applies a set. Returns false when it did not even start (combat, or everything already applied).
--- @param report function|nil receives (text, isError) at each step, for the UI to show
--- @param byClick boolean|nil the call came from the click on the secure button, which ALREADY asked for the appearance
--------------------------------------------------------------------------------
-- (!) ALL OR NOTHING: EVERY STEP IS CHECKED BEFORE ANY IS TAKEN (26/09)
--
-- The user: *"temos que mapear os possíveis erros e avisar ao usuário e adicionar algumas
-- seguranças para evitar de dar erro ao trocar e ficar coisa pelo meio do caminho, ou troca tudo
-- ou não troca nada e avisa"* -- and the macro on the bar makes the click fast. The log had it:
-- of 18 swaps, the 4 that went wrong all ended "loaded, except the appearance" (on cooldown twice,
-- not confirmed in time, not by the click) -- spec, talents and gear changed, the outfit did not.
--
-- So before the chain starts, each step the preset needs is asked of the game, and ONE "no"
-- stops everything, with the reason and, where the game lets us read it, the time left:
--   combat                 InCombatLockdown
--   specialization         CanPlayerUseTalentSpecUI + the spec spell's cooldown (`CanChangeSpec`),
--                          and standing still: the change is a cast, and moving cuts it
--   talents                C_ClassTalents.CanEditTalents -- "true if the player could switch
--                          talents if they staged a proper loadout", with the game's reason
--   gear                   a missing piece (`GearSetProblem`), locked items
--   appearance             `TransmogBlockedBy` (cooldown, style event, locked set) -- and it only
--                          changes through a click on the preset's secure button or macro
-- Cooldown SECONDS only where they are not secret: `startTime`/`duration` are secret in combat,
-- encounters, M+ and PvP (`SpellSharedDocumentation.lua`); there the warning has no time.
--------------------------------------------------------------------------------
local function SegundosDeRecarga(spellID)
    local getCD = spellID and C_Spell and C_Spell.GetSpellCooldown
    if not getCD then return nil end
    local ok, cd = pcall(getCD, spellID)
    if not (ok and type(cd) == "table" and cd.isActive == true) then return nil end
    local ini, dur = cd.startTime, cd.duration
    if issecretvalue and (issecretvalue(ini) or issecretvalue(dur)) then return nil end
    if type(ini) ~= "number" or type(dur) ~= "number" or not GetTime then return nil end
    local falta = ini + dur - GetTime()
    return falta > 0 and math.ceil(falta) or nil
end

---"45 s", "1 min 5 s".
function Data.TimeText(s)
    if not s then return nil end
    if s >= 60 then return format(L["%d min %d s"], math.floor(s / 60), s % 60) end
    return format(L["%d s"], s)
end

local function Com(msg, s)
    return s and (msg .. "  " .. format(L["(you can switch in %s)"], Data.TimeText(s))) or msg
end

---(!) THE ADDON RESTRICTION (26/09). The user: *"quando chama arena e entra, mesmo na contagem antes
---de começar a luta, não tem como mais trocar, isso foi mapeado?"* -- half: Alert.lua knew it, the
---pre-flight did not. Midnight closes windows in which addon actions are blocked, and the client's
---API docs define them (`Enum.AddOnRestrictionType`): `PvPMatch` -- "the player is in an active and
---incomplete PvP match" --, `Encounter`, `ChallengeMode`. The same three `Alert.lua` (`CanFix`) asks.
---Whether the arena countdown already counts as "active" is the user's report, not yet a line in
---the log: `Log.Apply` now writes the three states on every attempt, so the next arena answers it.
---@return string|nil kind "PvPMatch" | "Encounter" | "ChallengeMode" when one is active
function Data.AddonRestriction()
    if not (C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum
        and Enum.AddOnRestrictionType and Enum.AddOnRestrictionState) then return nil end
    for _, kind in ipairs({ "PvPMatch", "Encounter", "ChallengeMode" }) do
        local t = Enum.AddOnRestrictionType[kind]
        if t ~= nil then
            local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, t)
            if ok and state == Enum.AddOnRestrictionState.Active then return kind end
        end
    end
    return nil
end

---The three states, for the log ("Inactive", "Activating", "Active", or "?").
function Data.RestrictionStates()
    local out = {}
    if not (C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState and Enum
        and Enum.AddOnRestrictionType and Enum.AddOnRestrictionState) then return out end
    local nomes = {}
    for k, v in pairs(Enum.AddOnRestrictionState) do nomes[v] = k end
    for _, kind in ipairs({ "PvPMatch", "Encounter", "ChallengeMode" }) do
        local t = Enum.AddOnRestrictionType[kind]
        local ok, state = pcall(C_RestrictedActions.GetAddOnRestrictionState, t)
        out[kind] = ok and (nomes[state] or tostring(state)) or "?"
    end
    return out
end

-- (!) THE NAME IS REQUIRED (30/09). The user: *"tem como fazer o preset name ser obrigatorio?
-- talvez deixar os combos desabilitados e só habilita colocando o nome do preset e claro, precisa
-- deixar claro que é obrigatorio"*. Without a name a preset was half a preset everywhere: no
-- macro (Macro.lua refuses), an empty line in the minimap menu, "Loading ..." with nothing after
-- it, and no way to reach it by `/rs load`. The rule lives here, where every way of loading
-- passes; the window draws it (UI.lua).
--
-- A preset saved without a name BEFORE the rule is not deleted: it stays in the list as
-- "Unnamed", and asks for the name before it loads or changes.
---@return boolean
function Data.HasName(preset)
    local name = preset and preset.name
    return type(name) == "string" and name:find("%S") ~= nil
end

local RESTRICAO_TEXTO = {
    PvPMatch = L["in a PvP match -- the countdown included -- the game blocks switches made by addons. Switch before accepting the queue."],
    Encounter = L["during a boss encounter the game blocks switches made by addons."],
    ChallengeMode = L["during a Mythic+ keystone the game blocks switches made by addons."],
}

---Everything that stops this preset from switching NOW, one line per reason; empty = go.
---@param byClick boolean the click on the secure button/macro (the only way the outfit changes)
---@return table list of { step, text, seconds }
function Data.Preflight(preset, byClick)
    local out = {}
    local function Nao(step, text, s) out[#out + 1] = { step = step, text = Com(text, s), seconds = s } end
    if not preset then return out end

    -- The name comes before everything: it is of the preset, not of the moment.
    if not Data.HasName(preset) then
        Nao("name", L["Give the preset a name first."])
        return out
    end

    if InCombatLockdown() then
        Nao("combat", L["in combat: nothing was changed. Switch after the fight."])
        return out
    end

    local restricao = Data.AddonRestriction()
    if restricao then
        Nao("restriction", RESTRICAO_TEXTO[restricao])
        return out
    end

    local specAtual = Data.GetCurrentSpecIndex()
    local trocaSpec = preset.spec ~= nil and preset.spec ~= specAtual
    if trocaSpec then
        local pode, motivo, recarga = Data.CanChangeSpec()
        local forma = Data.FormBlocksSpec()
        if forma then
            Nao("spec", forma)
        elseif not pode then
            if recarga then
                Nao("spec", L["changing specialization is on cooldown."], SegundosDeRecarga(SpecSpellID()))
            else
                Nao("spec", motivo or L["the game refused to change specialization now; wait a few seconds."])
            end
        elseif GetUnitSpeed and (GetUnitSpeed("player") or 0) > 0 then
            Nao("spec", L["stand still: changing specialization is a cast, and moving cuts it."])
        end
    end

    if preset.talent then
        local specAlvo = Data.GetSpecByIndex(preset.spec or specAtual)
        -- DELETED since the preset was saved: its own reason, before anything else.
        if specAlvo then
            local loadouts = Data.GetLoadouts(specAlvo.id)
            if #loadouts > 0 then
                local existe = false
                for _, l in ipairs(loadouts) do if l.configID == preset.talent then existe = true end end
                if not existe then Nao("talent", L["that talent loadout no longer exists."]) end
            end
        end
        local jaTem = not trocaSpec and specAlvo and Data.GetActiveLoadoutID(specAlvo.id) == preset.talent
        if not jaTem and C_ClassTalents and C_ClassTalents.CanEditTalents then
            local ok, pode, erro = pcall(C_ClassTalents.CanEditTalents)
            if ok and pode == false then
                Nao("talent", (type(erro) == "string" and erro ~= "") and erro or L["talents cannot be changed here."])
            end
        end
    end

    if preset.gear and Data.GetEquippedSetID() ~= preset.gear then
        local problema = Data.GearSetProblem(preset.gear)
        if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetInfo and not Data.GearSetCounts(preset.gear) then
            Nao("gear", L["that gear set no longer exists."])
        elseif problema then
            Nao("gear", format(L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
                problema.nome or "?", problema.perdidas))
        elseif C_EquipmentSet and C_EquipmentSet.EquipmentSetContainsLockedItems then
            local ok, travado = pcall(C_EquipmentSet.EquipmentSetContainsLockedItems, preset.gear)
            if ok and travado then Nao("gear", L["some items of the set are locked (a trade, the bank, a repair)."]) end
        end
    end

    if preset.transmog and Data.GetActiveOutfitID() ~= preset.transmog then
        if not Data.OutfitIndex(preset.transmog) then
            Nao("transmog", L["that transmog outfit no longer exists."])
        elseif not byClick then
            Nao("transmog", L["the appearance only changes by clicking the preset (window, or its macro on the bar)."])
        else
            local motivo = Data.TransmogBlockedBy(preset.transmog)
            if motivo then
                local s = (motivo == L["changing appearance is on cooldown."]) and SegundosDeRecarga(TransmogSpellID()) or nil
                Nao("transmog", motivo, s)
            end
        end
    end
    return out
end

---The warning, where the player is looking: the red line in the middle of the screen (the game's
---own error line -- the macro on the bar is clicked with the eyes on the fight), chat, and the
---window's status.
function Data.Warn(preset, blockers, report)
    local nome = preset and preset.name or "?"
    local cab = format(L["%s was NOT loaded — nothing was changed:"], nome)
    local primeiro = blockers[1] and blockers[1].text or ""
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, nome .. ": " .. primeiro, 1, 0.1, 0.1)
    end
    ns.Print(cab)
    for _, b in ipairs(blockers) do print("    - " .. b.text) end
    -- In the window the preset is already selected: the reason alone, the game's own words.
    if report then report(primeiro, true) end
    if ns.Log then
        local passos = {}
        for _, b in ipairs(blockers) do passos[#passos + 1] = b.step end
        ns.Log.Add("recusado", { motivo = "pre-voo", conjunto = nome, passos = table.concat(passos, ","),
            texto = primeiro, segundos = blockers[1] and blockers[1].seconds })
    end
end

function Data.Apply(preset, report, byClick)
    if not preset then return false end

    -- In combat nothing is queued any more: the user asked for "nothing, and a warning".
    if InCombatLockdown() then
        Data.Warn(preset, Data.Preflight(preset, byClick), report)
        return false
    end

    -- REFUSING SILENTLY IS WHAT MADE THE BUTTON LOOK BROKEN. If a chain is still under way,
    -- say so -- and record it, because the interesting case is exactly the chain that got
    -- stuck and never ended.
    if running then
        -- IT SAYS WHICH STEP IT IS WAITING ON. The user's log brought eight seconds of "refused"
        -- in a row, and the message said nothing -- hence *"teve mensagem de ainda tá pendente, mas
        -- não ficou carregando nada"*. Naming the step turns the silence into information: if it
        -- stays stuck on the same one for long, the player himself sees it locked up.
        local passo = StepName(running.steps[running.at])
        if ns.Log then
            ns.Log.Add("recusado", { motivo = "ja ha uma troca em curso", esperando = passo })
        end
        if report then
            report(format(L["still applying %s: waiting for %s."],
                running.preset.name or "?", passo), true)
        end
        return false
    end

    -- (!) A BROKEN EQUIPMENT SET DOES NOT SWITCH -- it warns and says to fix it first.
    --
    -- The report of 22/09: the player swapped a piece and sold the previous one without saving the set. The
    -- game puts the set's name in red; the addon switched anyway, but the step never
    -- closed with the check, because with a missing piece the game's `isEquipped` never becomes `true`.
    --
    -- ⚠️ AND THE MISSING CHECK IS THE LEAST OF THE PROBLEMS. The game does not leave the slot empty: it **keeps
    -- equipped what was already there**. That is, the swap "works" and you leave with the PREVIOUS role's
    -- piece in a set of the new role -- the damage trinket in the tank set -- with nothing
    -- on screen saying so. The user's words: *"na troca ele mantém a atual equipada e pode
    -- estar errado porque o usuário não salvou ainda a certa"*.
    --
    -- A check mark that does not show is confusion; a wrong piece in combat is a loss. That is why the
    -- chain does not even start: the block exists for the player to **confirm and save** the right
    -- set before switching, and then the swap comes out really right.
    local problema = preset.gear and Data.GearSetProblem(preset.gear)
    if problema then
        local msg = format(L["%s is missing %d item(s): the slot keeps what you are wearing, which may be wrong. Save the set first."],
            problema.nome or "?", problema.perdidas)
        if problema.slots then
            msg = msg .. "  (" .. table.concat(problema.slots, ", ") .. ")"
        end
        ns.Print(msg)
        -- THE WAY OUT, in one line. Refusing without saying the way is just a wall.
        if problema.consertavel then
            ns.Print(L["You are already wearing the rest of it — use /rs fix to update the set."])
        else
            ns.Print(L["Open the equipment manager, fix the set and save it, then switch."])
        end
        if report then report(msg, true) end
        if ns.Log then
            ns.Log.Add("recusado", {
                motivo = "conjunto de itens com peca perdida",
                conjunto = problema.nome or "?",
                perdidas = problema.perdidas,
                consertavel = problema.consertavel and "sim" or "nao",
            })
        end
        return false
    end

    -- THE REST OF THE PRE-FLIGHT (the missing piece above keeps its longer message and the way
    -- out). One "no" and nothing starts.
    local impedimentos = Data.Preflight(preset, byClick)
    if ns.Log and ns.Log.Attempt then pcall(ns.Log.Attempt, preset, byClick, impedimentos) end
    if #impedimentos > 0 then
        Data.Warn(preset, impedimentos, report)
        return false
    end

    if Data.IsLoaded(preset) then
        -- A CLICK THAT DID NOTHING IS INFORMATION TOO. Without this line, a click that did not become a
        -- chain stayed invisible in the log -- and "I clicked and nothing happened" is a common report.
        if ns.Log then
            ns.Log.Add("recusado", { motivo = "ja esta carregado", conjunto = preset.name or "?" })
        end
        if report then
            report(format(L["Nothing to change — %s is already loaded."], preset.name or "?"), false)
        end
        return false
    end

    running = {
        preset = preset, steps = { "spec", "talent", "gear", "transmog" }, at = 0,
        report = report, byClick = byClick and true or false,
        progress = {},
        -- WHOEVER STARTS IS WHO MARKS THE TIME. The window may be opened in the middle of the swap, and a
        -- clock zeroed at opening would count a shorter wait than the real one.
        startedAt = GetTime and GetTime() or 0,

        -- WHAT WAS ALREADY RIGHT BEFORE THE CHAIN STARTED.
        --
        -- `Steps.*` returns `"skip"` for three different reasons, and all three reached the screen as the
        -- same phrase -- "nothing to change". In one of them that is a lie, and exactly in the most common:
        --
        --   1. the set does not define the field      -> it is not a step, and does not even become a line (`GetProgress`)
        --   2. it was already right before starting    -> "nothing to change" is true
        --   3. **it became right DURING the chain**    -> it changed, and the screen said it did not
        --
        -- Case 3 is the appearance's: what switches the outfit is the secure click, at the first instant;
        -- when its step finally runs, two or three steps later, the outfit is already right and
        -- `Steps.transmog` returns `"skip"`. The panel then announced **"Aparência -- nada a
        -- mudar"** over the piece that same click had just switched -- the exact opposite of what
        -- this panel exists to say.
        --
        -- The picture taken now tells the two apart: skipped is only "nothing to change" if it was already so
        -- BEFORE. What switched along the way is a completion, and that is how it shows.
        already = {
            spec = preset.spec and Data.GetCurrentSpecIndex() == preset.spec or nil,
            gear = preset.gear and Data.GetEquippedSetID() == preset.gear or nil,
            transmog = preset.transmog and Data.GetActiveOutfitID() == preset.transmog or nil,
            -- The talent depends on the spec, and the spec may switch midway. It can only be stated that it
            -- "was already right" when the chain is not going to touch the specialization.
            talent = preset.talent and (not preset.spec
                or preset.spec == Data.GetCurrentSpecIndex()) and (function()
                    local spec = Data.GetSpecByIndex(Data.GetCurrentSpecIndex())
                    return spec and Data.GetActiveLoadoutID(spec.id) == preset.talent or nil
                end)() or nil,
        },
    }

    -- THE PICTURE FROM BEFORE. It is the line that answers "the swap did not even need to happen" and "it asked
    -- for something that no longer exists" -- two cases that already came up and that the chat did not show.
    if ns.Log then ns.Log.Apply(preset, byClick) end
    if report then report(format(L["Loading %s..."], preset.name or "?"), false) end

    Data.EnsureListener()
    -- The floating panel opens here, and not inside `RunNext`: opening there, a swap in which
    -- all the steps close in the same frame would flash on screen without being read.
    if ns.Progress then ns.Progress.Start() end
    RunNext()
    return true
end

function Data.IsApplying()
    return running ~= nil
end

---(!) ONE SWITCH AT A TIME, AND THE BUTTONS SAY SO (28/09). The user, before the 0.38.0 went
---out: *"quando apertar no botão de carregar, tem que desativar o botão carregar dos outros
---salvos, vai que o jogador sai clicando em todos de uma vez só"*. A second click was already
---refused (`Data.Apply`), with a line in the chat; the buttons went on looking ready. It is the
---rule the user gave twice before: a button that takes the click and then answers "no" is
---worse than a button that is off.
---@return string|nil reason -- what the button's tooltip says while a switch runs
function Data.ApplyingReason()
    if not running then return nil end
    return format(L["Switching to %s. Wait for it to finish."],
        running.preset and running.preset.name or "?")
end

--- The state of each step of the swap, in the order they happen -- the swap under way's, or the picture
--- of the last one that ended.
---
--- It is the minimal API for the window to draw the progress: the list of steps, and a table with the
--- context it needs to write a state line. The window does **not** see `running`,
--- deadlines nor the events' mechanics -- if it did, two parts of the addon would know the same thing,
--- and the second would drift at the first change.
---
--- Possible states, and they are exactly the ones the chain already produces -- none made up:
---
---  `pending`  its turn has not come yet
---  `doing`    under way (includes the step waiting for the game to confirm)
---  `done`     the game confirmed
---  `skipped`  there was nothing to do -- **it is not a failure**, and the screen cannot say it is
---  `failed`   it failed, and the reason already went to the report and to the log
---
--- `info.live` separates the two readings: `true` is a swap happening now, `false` is the picture of the
--- end. The window needs the difference to know when to stop the animation and when to give back the
--- editor -- and reading "it ended" as "it never started" would erase the result right when showing it.
---
--- @return table[]|nil steps list of `{ key, label, state }`
--- @return table|nil info `{ preset, live, startedAt, tries }`
function Data.GetProgress()
    local src = running or lastRun
    if not src then return nil end

    -- OUT WITH WHAT THE SET DOES NOT ASK FOR. An items-only set opened four lines, three of them
    -- saying "nothing to change" -- which makes the swap look bigger than it is and buries the only line
    -- that matters in noise. It is the same rule the list's `Subtitle` already follows: only
    -- what the set defines goes in.
    local out = {}
    for _, key in ipairs(src.steps) do
        if src.preset and src.preset[key] then
            out[#out + 1] = {
                key = key,
                label = StepName(key),
                state = (src.progress and src.progress[key]) or "pending",
            }
        end
    end

    return out, {
        preset = src.preset,
        live = running ~= nil,
        startedAt = src.startedAt or 0,
        -- How many times the specialization step has insisted. **The window does not draw this** --
        -- the user asked to take the counter off the screen, and he is right: it is internal mechanics,
        -- and the player decides nothing with it. It stays here because the log and `/rs log`
        -- read it, and because taking it out of `info` would force the chain to expose `running` for that.
        tries = src.specTries or src.tries or 0,
    }
end

--------------------------------------------------------------------------------
-- Confirmation: the events that close each step
--------------------------------------------------------------------------------
--- The listener only exists while the addon needs it. Registering `TRAIT_CONFIG_UPDATED` and
--- `EQUIPMENT_SWAP_FINISHED` all the time would make the addon wake up on every manual swap of the
--- player, and there is nothing to do in those cases.
-- The cast events the listener hears. All of them only matter from the player and with a chain under way.
local CAST_EVENTS = {
    UNIT_SPELLCAST_SUCCEEDED   = true,
    UNIT_SPELLCAST_STOP        = true,
    UNIT_SPELLCAST_FAILED      = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

--- Runs the step under way again when what made it wait has ended.
---
--- The same outcome `RunNext` gives a step, without moving the index -- and with the same `pcall`,
--- for the same reason: a Lua error in here would leave `running` stuck and the button silent.
RerunStep = function(name)
    local okStep, outcome, message = pcall(Steps[name], running.preset)
    if not okStep then
        if ns.Log then ns.Log.Step(name, "erro de lua", tostring(outcome)) end
        message, outcome = L["an internal error interrupted this step."], "fail"
    elseif ns.Log then
        ns.Log.Step(name, outcome or "wait", message)
    end
    NoteOutcome(name, outcome)

    if outcome == "skip" then
        RunNext()
    elseif outcome == "abort" then
        Finish(false, message)
    elseif outcome == "fail" then
        if not running then return end
        running.failures = running.failures or {}
        running.failures[#running.failures + 1] = message
        RunNext()
    end
end

-- How many times the spec switch cast can be cut before the addon gives up. Three because
-- each cut is an action of the player (walking, being interrupted) and repeating three times is already a sign that
-- he does not want to wait standing still.
local SPEC_CAST_CUT_MAX = 3

--- Was the cast that just failed the specialization switch's?
---
--- `IsSpecializationActivateSpell` is the predicate the talents window itself uses to
--- recognise its cast (`Blizzard_ClassSpecializationsFrame.lua:185-190`). The learnt spell
--- stays as a fallback, for the case of the predicate not existing in this client.
local function IsSpecCast(spellID)
    if issecretvalue and issecretvalue(spellID) then return false end
    if type(spellID) ~= "number" then return false end

    if IsSpecializationActivateSpell then
        local ok, ehDeSpec = pcall(IsSpecializationActivateSpell, spellID)
        if ok then return ehDeSpec and true or false end
    end
    return spellID == SpecSpellID()
end

--- The spec switch cast was cut: try again, instead of waiting the whole deadline.
---
--- ⚑ BLIZZARD FINDS IT OUT THIS WAY, and we did not: the native window listens to
--- `UNIT_SPELLCAST_FAILED/INTERRUPTED` filtering by the spell's predicate
--- (`Blizzard_ClassSpecializationsFrame.lua:69-70,185-190`), because
--- `SPECIALIZATION_CHANGE_CAST_FAILED` **is consumed by no file of the 12.1.0 UI**. Without
--- this, walking during the switch cost the deadline's 45 seconds and ended with "the game did not
--- confirm in time" -- the costliest error of the list, because the player did nothing wrong.
local function SpecCastCut(event)
    running.specCastCuts = (running.specCastCuts or 0) + 1
    if ns.Log then
        ns.Log.Add("cast cortado", {
            passo = "spec", evento = event, vez = running.specCastCuts,
        })
    end

    if running.specCastCuts > SPEC_CAST_CUT_MAX then
        if running.progress then running.progress.spec = "failed" end
        -- (!) THE SPECIALIZATION THAT DOES NOT CHANGE STOPS THE CHAIN (29/09). It used to go on
        -- to the next step, and the diary of the druid in Travel Form has what came of it: the
        -- specialization of one role and the gear of another. It is what `abort` already was
        -- for a refusal of the game; a cast cut until the ceiling is the same thing.
        local motivo = format(L["%s was NOT loaded: the specialization did not change, and nothing after it was touched."],
            running.preset and running.preset.name or "?")
        -- THE OUTCOME GOES TO THE LOG TOO. The event already did; what the step did with it, did not.
        if ns.Log then ns.Log.Step("spec", "abort", motivo) end
        Finish(false, motivo)
        return
    end

    Report(L["Switching specialization..."], false)
    RerunStep("spec")
end

--- Closes the talents step when the commit ends, and says in the log WHICH signal closed it and in
--- how long. It is this record that checks the echo's window against real data.
local function CloseTalentCommit(por, commit)
    if ns.Log then
        ns.Log.Add("gravou", {
            passo = "talent", por = por,
            segundos = commit and format("%.1f", GetTime() - commit.since) or nil,
        })
    end
    running.commit = nil
    ConfirmTalent()
    RunNext()
end

function Data.EnsureListener()
    if listener then return listener end

    listener = CreateFrame("Frame", ADDON .. "ApplyListener")
    listener:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
    listener:RegisterEvent("SPECIALIZATION_CHANGE_CAST_FAILED")
    listener:RegisterEvent("TRAIT_CONFIG_UPDATED")
    listener:RegisterEvent("CONFIG_COMMIT_FAILED")
    listener:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    listener:RegisterEvent("UNIT_SPELLCAST_STOP")
    listener:RegisterEvent("UNIT_SPELLCAST_FAILED")
    listener:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    listener:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
    listener:RegisterEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
    -- THE CHAIN DIES ON `/reload` AND ON LOGOUT, and it died silent: `running` is memory, `Finish`
    -- does not run, and the log ended at the last step without saying it was interrupted. Whoever reads
    -- later cannot tell "it stopped halfway" from "the addon locked up".
    listener:RegisterEvent("PLAYER_LEAVING_WORLD")
    listener:RegisterEvent("PLAYER_LOGOUT")

    listener:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
        -- IT RECORDS BEFORE DECIDING, including the event that arrives with no chain under way. It is what
        -- answers the guess I had no way to test: these events are GLOBAL and fire
        -- when the PLAYER changes things by hand or another addon does. If the log shows an event
        -- closing a step that was not ours, that is it.
        -- BOTH ARGUMENTS. `EQUIPMENT_SWAP_FINISHED` carries `result, setID`, and without the second
        -- there is no knowing whether the event was our set's -- it was exactly the question
        -- left unanswered when reading the log of 02:05.
        local emCurso = running and running.steps[running.at] or nil
        if CAST_EVENTS[event] then
            -- THE CAST ONLY MATTERS WITH A CHAIN UNDER WAY, and only the player's. It fires at every
            -- spell of any unit: recording everything would sweep the 400-line log in minutes
            -- of play. With a chain, it records the `spellID` -- it is what says, at the next real switch, whether
            -- the end of the commit cast arrived and in what order with `TRAIT_CONFIG_UPDATED`.
            if not running or arg1 ~= "player" then return end
            if ns.Log then ns.Log.Event(event, emCurso, true, arg3) end
        elseif ns.Log then
            ns.Log.Event(event, emCurso, running ~= nil, arg1, arg2)
        end

        -- THE INTERRUPTION GETS A LINE, and it is recorded only with a chain under way, not without.
        -- `PLAYER_LOGOUT` is the last instant SavedVariables can be written, so
        -- this line is the file's only chance to say the swap stopped halfway.
        if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then
            if running and ns.Log then
                ns.Log.Add("interrompido", {
                    passo = emCurso or "nenhum", motivo = event,
                    conjunto = running.preset and running.preset.name or "?",
                })
            end
            return
        end

        if not running then return end
        local step = running.steps[running.at]

        -- EVERY BRANCH CHECKS THE STEP UNDER WAY, and this one did not. Any spec switch cast
        -- that failed -- the player's own click in the talents window, another addon --
        -- killed the chain wherever it was. And `Finish` became a note: failing the spec must not
        -- keep the items from going in.
        if event == "SPECIALIZATION_CHANGE_CAST_FAILED" and step == "spec" then
            -- TRY AGAIN INSTEAD OF NOTING A FAILURE. This event's meaning is nowhere
            -- in Blizzard's source (nobody consumes it, and it has no payload), but the
            -- family is the same as this addon's other refusals: transient. `SpecCastCut`'s ceiling
            -- is what decides when to stop insisting.
            SpecCastCut(event)

        elseif event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED" and step == "spec" then
            RunNext()

        elseif event == "TRAIT_CONFIG_UPDATED" and step == "talent" then
            -- IT CHECKS WHOSE EVENT IT IS. It carries `configID`
            -- (`SharedTraitsDocumentation.lua:810-815`) and Blizzard warns in writing that it
            -- arrives more than once per commit -- *"Saving a change to a loadout may lead to
            -- Updated event both for the base spec config id and then the selected loadout config
            -- id"* (`Blizzard_ClassTalentsFrame.lua:407-411`) -- and filters.
            --
            -- We closed on the FIRST, which is the spec's base config's, before the loadout went in.
            -- Result: "X is ready" with the old talents. And the spec switch, which runs
            -- right before, queues these same events -- which is why it happened on every set
            -- that touches spec and talents, the common case.
            -- IT ACCEPTS THE EVENT. And this line is a deliberate WITHDRAWAL, with the reason written:
            --
            -- In 0.13.0 I put in a filter by `configID`, because Blizzard warns that the commit
            -- makes an event "both for the base spec config id **and then** the selected loadout
            -- config id" (`Blizzard_ClassTalentsFrame.lua:407-411`) and I wanted to close only on the right one.
            -- But the source **does not say which of the two closes**, and the filter refused the event that
            -- worked: the step kept waiting until the deadline -- which I had just raised
            -- to thirty seconds. The user felt it as *"apertei duas, três vezes pra
            -- funcionar"* and *"mensagem de ainda tá pendente, mas não ficou carregando nada"*.
            --
            -- Swapping a path that works for a more precise guess is the worst deal
            -- possible. The risk of closing early is the next step starting an instant before; the
            -- risk of the wrong filter is the addon locking up. I go back to what worked, and the log records
            -- the `arg1` of each event -- with a real switch in hand the question can be settled with
            -- data instead of deduction.
            --
            -- ⚑ THE DATA ARRIVED (11/09), AND IT UNDOES HALF THE WITHDRAWAL. The events that closed the
            -- step were the ECHO of the spec switch, with the same id as the true one -- see
            -- `COMMIT_ECHO_WINDOW`. Accepting any of them asked for the items with the commit under way, and
            -- the game refused: three times in three.
            --
            -- The rule is now Blizzard's own -- the event only confirms the commit it opened itself
            -- (`Blizzard_SharedTalentFrame.lua:358`) --, plus the echo's window:
            --   - WITHOUT `running.commit`, the step is INSISTING (`Error` with no reason): the game
            --     refused `LoadConfig`, and the event that arrives is an echo. The log's three chains
            --     that closed this way (15:51:07, 21:59:36, 00:00:26) announced "done" with nothing
            --     proving the talents went in -- and `ConfirmTalent` still marked the loadout
            --     as selected. Now the insisting goes on and asks again;
            --   - WITH `running.commit`, the event only counts after the window.
            local commit = running.commit
            if commit and (GetTime() - commit.since) >= COMMIT_ECHO_WINDOW then
                CloseTalentCommit("evento", commit)
            end

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" and step == "talent" then
            -- THE END OF THE COMMIT CAST, the signal the game's talents window uses
            -- (`Blizzard_ClassTalentsFrame.lua:345-350`). `issecretvalue` BEFORE `==`: this
            -- event's `spellID` comes opaque under a restriction (`UnitDocumentation.lua:4702`), and
            -- comparing an opaque value is an error.
            if running.commit and not (issecretvalue and issecretvalue(arg3))
                and arg3 == COMMIT_SPELL_ID then
                CloseTalentCommit("cast", running.commit)
            end

        elseif event == "CONFIG_COMMIT_FAILED" and step == "talent" then
            -- THE COMMIT FAILED -- and Blizzard closes its commit on the same event
            -- (`Blizzard_SharedTalentFrame.lua:346-349`). Without this branch, the failure would only be
            -- noticed by the step's deadline. It marks "failed" BEFORE `RunNext`, for the same reason
            -- as the deadline in `Arm`: otherwise it promotes the step to "done".
            if running.commit then
                running.commit = nil
                if running.progress then running.progress.talent = "failed" end
                running.failures = running.failures or {}
                running.failures[#running.failures + 1] = L["the talent loadout could not be loaded."]
                -- THE OUTCOME IN THE LOG, and not only the event: it was one of the map's gaps.
                if ns.Log then
                    ns.Log.Step("talent", "fail", L["the talent loadout could not be loaded."])
                end
                RunNext()
            end

        elseif CAST_EVENTS[event] and event ~= "UNIT_SPELLCAST_SUCCEEDED" and step == "spec"
            and IsSpecCast(arg3) then
            -- THE SPEC SWITCH CAST WAS CUT (walking cuts it, and it is the case of `Core.lua:201-202`).
            SpecCastCut(event)

        elseif CAST_EVENTS[event] and event ~= "UNIT_SPELLCAST_SUCCEEDED" and step == "gear" then
            -- THE CAST ENDED, or was cut -- it is now that `UnitCastingInfo` stops answering
            -- (`CastingBarFrame.lua:459,482-483`). SUCCEEDED stays out on purpose: it is the one that
            -- arrives with the cast still counting, and it was exactly it that brought the items down.
            if running.gearWaitsCast then
                running.gearWaitsCast = nil
                RerunStep("gear")
            end

        elseif event == "TRANSMOG_DISPLAYED_OUTFIT_CHANGED" and step == "transmog" then
            -- THE EVENT DOES NOT SAY WHICH set went in -- it has no payload
            -- (`TransmogOutfitInfoDocumentation.lua:818-821`). So it is the signal that
            -- SOMETHING changed, and what answers "did it change to the right one?" is still the reading.
            --
            -- And if it changed to the WRONG one, that is not a failure to repeat: it is the player having switched the
            -- appearance by hand in the middle of applying. The report says what happened and the chain
            -- goes on, as in every step that failed.
            local ativa = Data.GetActiveOutfitID()
            if ativa ~= running.preset.transmog then
                local porque = Data.TransmogBlockedBy(running.preset.transmog)
                -- ⚑ THE THREE THINGS MISSING FROM THE LOG. The event has no payload, and we only
                -- recorded our conclusion: reading later there was no telling "the player
                -- switched the outfit by hand" from "a door of the game was closed".
                if ns.Log then
                    ns.Log.Call("transmog", "divergiu",
                        "ativa=" .. tostring(ativa),
                        "desejada=" .. tostring(running.preset.transmog),
                        porque or "nenhuma porta fechada")
                end
                running.failures = running.failures or {}
                running.failures[#running.failures + 1] =
                    porque or L["the transmog outfit could not be applied."]
            end
            RunNext()

        elseif event == "EQUIPMENT_SWAP_FINISHED" and step == "gear" then
            -- THE EVENT SAYS IT ENDED. It is what one trusts, and this line is the SECOND withdrawal
            -- of the same mistake of mine in this sequence.
            --
            -- 0.13.2 swapped the confirmation for a state reading --
            -- `Data.IsGearSetEquipped(preset.gear)` -- thinking that asking the world was more
            -- honest than trusting the event. The user's log proved the opposite, and
            -- mechanically: at 02:05:35 `EQUIPMENT_SWAP_FINISHED` arrived with `result = true`, that is
            -- **the swap ended successfully**, and the state reading still answered that the
            -- set was not worn. The chain did not move on, and from then on every click of the
            -- player hit "a swap is already under way" -- eight seconds of "refused" in a row
            -- in the log.
            --
            -- THE LESSON IS THE SAME AS THE TALENTS BRANCH'S, two versions ago: the game's state may
            -- lag behind the event, so demanding that it has already switched turns a
            -- confirmation into a trap. The event is the fact; the reading, at most, a detail.
            --
            -- `arg2` still serves to REFUSE what is clearly another set's --
            -- switching spec makes the game equip by itself the set tied to that spec -- but
            -- refusing is all it does. Without `arg2`, we go on.
            if arg2 ~= nil and running.preset.gear ~= nil and arg2 ~= running.preset.gear then
                return      -- it is another set's; ours is still coming
            end

            -- `false` is a NOTE, not the end of the chain: someone else's `false` killed ours and threw
            -- away the failures already noted.
            if arg1 == false then
                -- ⚑ AND HERE ONE ASKS WHY, at the only instant the answer exists.
                --
                -- The log of 09/09 recorded this refusal (17:22:02, set 1) and had no way to
                -- explain it: the same chain, with the same set, had worked at
                -- 00:00:26. Without the set's bookkeeping at the moment of the refusal, the two log
                -- lines cannot be told apart -- and the next round would start guessing again.
                if ns.Log then
                    ns.Log.Call("gear", "recusou; estado de " .. tostring(running.preset.gear),
                        Data.DescribeGearSet(running.preset.gear) or "sem resposta")
                end

                running.failures = running.failures or {}
                running.failures[#running.failures + 1] =
                    Data.GearFailureReason(running.preset.gear)
            end
            RunNext()
        end
    end)

    return listener
end
