-- RocketSwap | Dialog.lua
-- The addon's own notice box: a text and a button, or a text and a link to copy.
--
-- (!) WHY THE ADDON DOES NOT USE THE GAME'S `StaticPopup_Show` (05/10/2026).
--
-- Reported by a player, and recorded by the game on the development machine too:
-- "[ADDON_ACTION_FORBIDDEN] AddOn 'RocketSwap' tried to call the protected function
-- 'IsUserOAuthed()'", with not one line of this addon in the stack -- the whole of it is the
-- game's guild control window answering an event.
--
-- The game keeps ONE list of the dialogs on screen (`shownDialogFrames`, StaticPopup.lua), and
-- a dialog opened by an addon goes into it by the addon's hand. From then on, whoever walks
-- that list is marked by the addon -- the client says so itself, in the comment above
-- `StaticPopup_CollapseTable` -- and the game walks it all the time (`StaticPopup_Hide`,
-- `StaticPopup_Visible`, `StaticPopup_FindVisible`). The guild control window calls
-- `StaticPopup_Hide` and, right after, `C_Discord.IsUserOAuthed()`, which is protected: with a
-- box of ours on screen, the game refuses its own call and blames this addon.
--
-- Measured, not guessed: the game recorded the error at 19:46:24, and the diary of the same
-- session has this addon's box shown at 19:46:19 and hidden at 19:46:28.
--
-- So the box is a frame of OURS, which never enters that list. (18/11/2026) It became the family's question box,
-- `Style.Ask` in Style.lua (the same file in every Rocket addon: every addon's questions and "copy this link" boxes moved
-- to it); this file keeps the Swap's names (Show / Hide / IsShown) over it. The harness has the guard: no file of the
-- addon may call `StaticPopup_Show` (and tools/identidade.py refuses it in every addon).
local ADDON, ns = ...
local L = ns.L

local Dialog = {}
ns.Dialog = Dialog

---Shows the box.
---@param key string what this box is ("summary", "report"): `Hide(key)` closes only it
---@param text string what it says
---@param opts table|nil `url`: a link to put in the box, selected, ready to copy; `button`: the button's text
---@return boolean shown false when the game gave no frame: the caller says it some other way
function Dialog.Show(key, text, opts)
    opts = opts or {}
    local url = type(opts.url) == "string" and opts.url or nil
    return ns.Style.Ask(key, {
        text = text,
        url = url,
        copied = url and L["Link copied — paste it in your browser."] or nil,
        buttons = opts.button and { { text = opts.button } } or nil,
    })
end

---Closes the box, when it is the one named (or whatever is shown, with no name).
function Dialog.Hide(key)
    return ns.Style.AskHide(key)
end

---Is the box named on screen? (With no name: is any?)
function Dialog.IsShown(key)
    return ns.Style.AskShown(key)
end

-- For the harness.
function Dialog.__frame() return ns.Style.AskFrame() end
function Dialog.__current() return ns.Style.AskKey() end
