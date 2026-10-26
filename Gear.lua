-- RocketSwap | Gear.lua
-- Finds out, piece by piece, whether what you are wearing is PvP or PvE.
--
-- NO API ANSWERS THAT. Not `C_Item`, not `C_PaperDollInfo`, not `C_PvP`. The only per-piece
-- signal is a TOOLTIP LINE, whose text comes from the global `PVP_ITEM_LEVEL_TOOLTIP`:
--
--   enUS  "Equip: Increases item level to a minimum of %d in Arenas, Battlegrounds, and War Mode."
--   ptBR  "Equipar: aumenta o nível do item para um mínimo de %d em Arenas, Campos de Batalha
--          e no Modo de Guerra."
--
-- Four decisions, each against a mistake easy to make here:
--
--   1. READ BY SLOT, NOT BY LINK. `C_TooltipInfo.GetInventoryItem("player", slot)` instead of
--      `GetHyperlink(link)`. Every getter of `C_TooltipInfo` has
--      `SecretArguments = "AllowedWhenUntainted"`: passing a SECRET link from addon code
--      **raises an error**, it does not return nil. And an item link is not categorically
--      non-secret in 12.x. The
--      contexts where that would bite are exactly arena, encounter and M+, which is where this
--      feature works.
--
--   2. A PATTERN WITHOUT ANCHORS. Built as `"^" .. pat .. "$"`, the pattern
--      **does not match** when the line comes wrapped in a
--      colour code (`|cffffffff...|r`). Reproduced in LuaJIT: with anchors it misses, without
--      anchors it matches in both cases.
--
--   3. DO NOT FILTER BY `line.type`. The enum `TooltipDataLineType` has 50 values and **none is
--      PvP's**.
--
--   4. THREE STATES, NOT TWO. `true` (it is PvP), `false` (it is not), `nil` (**I do not know**). In
--      Korean the string carries a grammar directive (`%d|1으로;로;`) that no derived pattern
--      matches -- there "I did not find the line" does NOT mean "it is not a PvP piece". An addon
--      that mixes the two shouts over 16 slots at once.
local ADDON, ns = ...

local Gear = {}
ns.Gear = Gear

-- The slots that count. `INVSLOT_FIRST_EQUIPPED..LAST` is 1..19 and includes the shirt (4) and the
-- tabard (19), which have no stats nor a PvP version -- warning about them would be warning about a
-- piece that does not exist. Blizzard exposes no table of the 16 useful ones; this one is ours.
local SLOTS = {
    1,  2,  3,      -- head, neck, shoulders
    5,  6,  7,  8,  -- chest, waist, legs, feet
    9,  10, 11, 12, -- wrists, hands, ring 1, ring 2
    13, 14,         -- berloque 1, berloque 2
    15,             -- costas
    16, 17,         -- main hand, off hand
}

Gear.SLOTS = SLOTS

--------------------------------------------------------------------------------
--- Builds the pattern from the global, without anchors.
---
--- Escapes the magic characters, turns `%d` into `%d+` and `%s` into `.+`, and turns the **grammar
--- directive** (`|1form1;form2;`) into a wildcard.
---
--- ⚑ THE COMMENT AND THE CODE CONTRADICTED EACH OTHER HERE, and the comment was the right one: it said
--- "the directive becomes a wildcard" and the code **removed** it.
---
--- THE REACH, MEASURED -- and it is smaller than it looks at first, so the number is worth recording
--- instead of the impression. Removing only breaks when the directive is in the **middle** of the
--- string; when it is at the end, the match is not anchored and the prefix is enough:
---
---     global                      remove    wildcard
---     directive at the END        matches   matches
---     directive in the MIDDLE     NO match  matches
---
--- The known Korean form (`PvP 장비 레벨 %d|1으로;로;`) has the directive at the end -- that is, the
--- defect was **not** breaking the Korean client today. What was wrong was the rule: the
--- directive is not literal text, and erasing it only worked by an accident of position.
local function BuildPattern(text)
    if type(text) ~= "string" or text == "" then return nil end

    -- The directive becomes a wildcard: what comes after the number changes WITH the number, so one
    -- of the forms cannot be fixed nor both erased.
    local clean = text:gsub("|%d+[^;]*;[^;]*;", "\1")

    local pattern = clean:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    pattern = pattern:gsub("%%%%d", "%%d+")
    pattern = pattern:gsub("%%%%s", ".+")
    pattern = pattern:gsub("\1", ".-")
    return pattern
end

local pvpPattern

local function Pattern()
    if pvpPattern == nil then
        pvpPattern = BuildPattern(PVP_ITEM_LEVEL_TOOLTIP) or false
    end
    return pvpPattern or nil
end

--- The pattern, so the dump of `/rs gear <slot>` can say WHICH line matches.
---
--- `Debug` in the name because production does not use it: `IsPvPItem` decides. It is the same rule
--- that already governs this project's other hooks -- code that outlives its only consumer becomes
--- a trap for the next reading.
function Gear.DebugPattern()
    return Pattern()
end

--- Forgets the pattern and its self-test.
---
--- It exists so the test can swap the game's global and check the behaviour in another language:
--- the pattern is memorised at the first reading, so without this the second language would never
--- be built. In the game nothing calls this -- the global does not change mid-session.
function Gear.__ResetPattern()
    pvpPattern = nil
    Gear.__patternWorksReset()
end

--------------------------------------------------------------------------------
-- A cache by link. Reading a tooltip is too expensive to run at every event.
--
-- The trap here: keeping `{nil, nil}` when the tooltip comes back empty and then doing
-- `if cached then return cached[1], cached[2] end` -- the table is truthy, so the false negative is kept forever.
-- Here, an unknown result **does not go into the cache**.
local cache = {}

-- Items whose loading was already asked for. Without this list, each sweep (and there are several:
-- entering a zone, a ready check, a gear swap) would ask again for the same item.
local pendingLoads = {}

function Gear.ClearCache()
    cache = {}
end

--- Forgets the requests under way too. Only the harness uses it: in the game, a pending request that
--- survives a gear swap is exactly what avoids asking twice.
function Gear.__ResetPending()
    pendingLoads = {}
end

--- Is the detection alive in this client?
---
--- `Pattern()` comes from a game global (`PVP_ITEM_LEVEL_TOOLTIP`). If it does not exist or yields
--- no pattern, EVERY piece comes back `nil` and the addon stays quiet on both sides -- no error, no
--- log, nothing to hold on to. Asking this is the first thing a diagnosis does.
function Gear.PatternReady()
    return Pattern() ~= nil
end

--- Does the pattern MATCH the line it was made to find?
---
--- ⚑ THIS IS THE SIGNAL THAT WAS MISSING, and it is what lets the `LooksReliable` gate be removed
--- without turning the addon into a shouter.
---
--- The problem it tried to solve is real and lopsided. A `true` is only born from
--- `text:match(pattern)`; no way of failing to read can make up a `true` -- only a
--- `false`. So:
---
---  * in PvE, "all wrong" = 16 genuine matches. It is never ambiguous.
---  * in PvP, "all wrong" = no match -- which is **exactly** what the failure produces.
---
--- That is why the gate only bit on one side, and bit exactly the common case: whoever enters an
--- arena coming from PvE is wearing all PvE gear.
---
--- The way out is to ask not the gear, but **the pattern itself**: build a synthetic line from the
--- same global it came from and see whether it finds it. If it does, the detection is proven and
--- "all wrong" is a reading, not a failure. If it does not, the pattern is broken in this client and
--- silence is still the right answer.
---
--- It does not depend on the player owning a single PvP piece -- the hole of any heuristic based
--- on what he is wearing.
local patternWorks

function Gear.__patternWorksReset()
    patternWorks = nil
end

function Gear.PatternWorks()
    if patternWorks ~= nil then return patternWorks end

    local pattern = Pattern()
    if not pattern then
        patternWorks = false
        return false
    end

    -- THE SYNTHETIC LINE comes from the same global, with a number in place of `%d`. It is the same
    -- text the game writes in the tooltip, built by `format` instead of read from an item.
    local ok, linha = pcall(format, PVP_ITEM_LEVEL_TOOLTIP, 684)
    if not ok or type(linha) ~= "string" then
        patternWorks = false
        return false
    end

    -- The grammar directive does not go through `format`: the client resolves it when drawing.
    -- Here it becomes the raw text, and the pattern's wildcard is exactly what crosses it.
    patternWorks = linha:match(pattern) ~= nil
    return patternWorks
end

--------------------------------------------------------------------------------
--- Did the tooltip come with the item's data, or is it only the "I am fetching" placeholder?
---
--- ⚑ THIS FUNCTION IS THE CAUSE OF THE DEFECT OF 13/09, AND THE PROOF CAME FROM THE DUMP OF `/rs gear 5`:
---
---     slot 5 (Torso): link: [Peitoral do Necrocavaleiro Pernicioso]
---     padrão montado: sim | padrão se prova: sim
---     leitura atual: false
---     1 linha(s):
---       1  tipo=41  Recuperando informações do item
---
--- The client returns ONE line, a placeholder, while it fetches the data from the server. The guard
--- there was (`#data.lines == 0`) does not catch it: there **is** a line. None matches the pattern, so
--- the piece became `false` -- and went into the cache. A PvP piece marked PvE, for good.
---
--- And the link of slot 3 came out `[]`, with no name: the same symptom from the other side.
---
--- ⚑ AND WAITING DOES NOT SOLVE IT: the client only fetches an item's data when someone asks.
--- The addon never asked -- which is why it survived the character switch, where the cache starts empty.
---
--- The detection uses the game's own global (`RETRIEVING_ITEM_INFO`), not the enum's number 41:
--- an enum number changes between patches, the global is the same the client writes in the line.
local function TooltipNotReady(data)
    if #data.lines == 0 then return true end

    local recado = RETRIEVING_ITEM_INFO
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not issecretvalue(text) then
            if type(recado) == "string" and recado ~= "" and text == recado then
                return true
            end
        end
    end
    return false
end

--- Asks the client for the data of that slot's item, and tells whoever cares when it arrives.
---
--- `ContinueOnItemLoad` is the game's own way (the `Item` mixin).
--- `RequestLoadItemDataByID` stays as a fallback for a client without the mixin.
---
--- ⚑ THE CACHE IS CLEARED ON THE WAY BACK. Without it, the piece would keep answering with the value read
--- while the tooltip was a placeholder -- and the request would have been for nothing.
function Gear.RequestLoad(slot)
    local id = GetInventoryItemID and GetInventoryItemID("player", slot)
    if type(id) ~= "number" then return false end

    if pendingLoads[id] then return true end     -- already asked; do not ask again at every sweep
    pendingLoads[id] = true

    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, id)
    end

    if Item and Item.CreateFromItemID then
        local ok, obj = pcall(Item.CreateFromItemID, Item, id)
        if ok and obj and obj.ContinueOnItemLoad then
            pcall(obj.ContinueOnItemLoad, obj, function()
                Gear.ClearCache()
                -- Whoever wants to react subscribes. `Gear` does not know the equipment warning: if it
                -- called `ns.Alert` directly, the reading layer would start depending on the screen's.
                if type(Gear.onItemLoaded) == "function" then
                    pcall(Gear.onItemLoaded, id)
                end
                -- (!) THE REQUEST IS ONLY OVER AFTER WHOEVER WAITED HAS RUN (28/09). With the
                -- item already in the client's cache the game calls this back AT ONCE, inside
                -- `ContinueOnItemLoad` -- and the tooltip can still be the "retrieving" note. The
                -- one who waited read the slot again, the slot asked again, the game called back
                -- again: `C stack overflow`, 22 times in the error log on 25/09, stack
                -- RequestLoad > IsPvPItem > Wrong > Alert.Check > RequestLoad. Cleared here, the
                -- reading made from inside the callback finds the request still open and stops.
                pendingLoads[id] = nil
            end)
            return true
        end
    end

    pendingLoads[id] = nil
    return false
end

--- Is this piece PvP?
--- @return boolean|nil  true = it is, false = it is not, nil = could not tell
function Gear.IsPvPItem(slot)
    local link = GetInventoryItemLink("player", slot)
    if link == nil or issecretvalue(link) then return nil end

    local hit = cache[link]
    if hit ~= nil then return hit end

    local pattern = Pattern()
    if not pattern then return nil end

    if not C_TooltipInfo or not C_TooltipInfo.GetInventoryItem then return nil end

    -- By SLOT, and inside pcall: see decision 1 at the top of the file.
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end

    -- ⚑ THE DATA HAS NOT ARRIVED YET: "I do not know", and it **does not go into the cache**. This is where a
    -- PvP piece became PvE for good (13/09). And it asks for the load, because the client does not fetch
    -- by itself -- without the request, the reading would be wrong again at the next sweep, and the next.
    if TooltipNotReady(data) then
        Gear.RequestLoad(slot)
        return nil
    end

    local found = false
    for _, line in ipairs(data.lines) do
        -- `leftText` pode vir nil: sem esta guarda haveria um erro latente.
        local text = line.leftText
        if text ~= nil and not issecretvalue(text) and type(text) == "string" then
            if text:match(pattern) then
                found = true
                break
            end
        end
    end

    cache[link] = found
    return found
end

--------------------------------------------------------------------------------
--- Sweeps the gear and returns what is out of place.
---
--- @param wantPvP boolean true = we are in PvP (a piece without the line is an error);
---                       false = we are in PvE (a piece with the line is an error)
--- @param ignored table|nil slots the user told to keep quiet
--- @return table errors  list of { slot = n, link = "..." }
--- @return number read  how many slots gave an answer (neither nil nor empty)
--- @return number worn how many slots have a piece
function Gear.Wrong(wantPvP, ignored)
    local wrong, read, worn = {}, 0, 0

    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link ~= nil and not issecretvalue(link) then
            worn = worn + 1

            local isPvP = Gear.IsPvPItem(slot)
            if isPvP ~= nil then
                read = read + 1
                -- Unknown never counts as wrong: it is the difference between a reminder and
                -- an addon that shouts when the reading fails.
                if isPvP ~= wantPvP and not (ignored and ignored[slot]) then
                    wrong[#wrong + 1] = { slot = slot, link = link }
                end
            end
        end
    end

    return wrong, read, worn
end

--- Is the reading reliable in this sweep?
---
--- ⚑ THIS GATE SILENCED THE MOST COMMON PvP CASE. The user's report, 08/09/2026: *"o de pve no
--- pvp, ainda não vi funcionar, quando dou fila em BG, arena, ele não avisa nada sobre meus
--- itens"*.
---
--- The old rule was `#wrong < read`: if ALL the slots read came out wrong, it assumed a detection
--- failure. Measured sweeping from 0 to 16 PvP pieces, it silences **exactly one** of the 17
--- configurations on each side -- and on the PvP side that one is `n = 0`, all PvE gear,
--- which is precisely whoever enters an arena coming from PvE. It was not a noise filter: it was a
--- cut right on the common case.
---
--- The ambiguity it tried to solve is real, but it only exists on one side (see
--- `Gear.PatternWorks`, which explains why). And it goes away without asking the gear:
--- **the pattern tests itself**. If it finds the line it was made to find, "all wrong" is a
--- good reading; if it does not, silence is still right.
---
--- What is NOT covered, and worth recording instead of pretending: a tooltip **not loaded** also
--- gives `false` in every slot, and a partial tooltip has lines (just not the PvP one), so it passes
--- the `#data.lines == 0` guard and counts as a reading. The mitigation is the one already there --
--- an unknown result does not go into the cache -- plus the check repeating at several
--- events. A window at login is still possible.
function Gear.LooksReliable(wrong, read)
    if read < 3 then return false end
    if #wrong < read then return true end

    -- ALL WRONG: it is only a real reading if the detection proves it can find the line.
    return Gear.PatternWorks()
end

--------------------------------------------------------------------------------
--- A readable name of a slot, so the warning says WHERE the problem is.
---
--- `_G` is asked because the slot globals (`INVTYPE_*` will not do; the right ones are the
--- `..._SLOT`) vary in name per piece, and a name that does not exist becomes the slot's number instead
--- of breaking.
local SLOT_GLOBAL = {
    [1] = "HEADSLOT",     [2] = "NECKSLOT",      [3] = "SHOULDERSLOT",
    [5] = "CHESTSLOT",    [6] = "WAISTSLOT",     [7] = "LEGSSLOT",
    [8] = "FEETSLOT",     [9] = "WRISTSLOT",     [10] = "HANDSSLOT",
    [11] = "FINGER0SLOT", [12] = "FINGER1SLOT",  [13] = "TRINKET0SLOT",
    [14] = "TRINKET1SLOT",[15] = "BACKSLOT",     [16] = "MAINHANDSLOT",
    [17] = "SECONDARYHANDSLOT",
}

function Gear.SlotName(slot)
    local key = SLOT_GLOBAL[slot]
    local name = key and _G and _G[key]
    if type(name) == "string" and name ~= "" then return name end
    return tostring(slot)
end
