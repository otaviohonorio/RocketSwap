-- luacheck --config .luacheckrc .
std = "lua51"
max_line_length = 120

-- Ignora: variável não usada com _, campo global do addon.
ignore = {
    "212/self",   -- argumento self não usado em handlers
    "212/frame",
}

-- Globais que o WoW define. Acrescente conforme usar novas APIs.
read_globals = {
    "CreateFrame", "UIParent", "GameTooltip", "InCombatLockdown", "IsInInstance",
    "UnitName", "UnitClass", "UnitGUID", "UnitExists", "UnitIsUnit", "UnitAffectingCombat",
    "UnitHealth", "UnitHealthMax", "UnitHealthPercent", "UnitPower", "UnitPowerMax",
    "GetTime", "wipe", "hooksecurefunc", "issecretvalue", "hasanysecretvalues",
    "scrubsecretvalues", "securecallfunction", "SlashCmdList", "print", "format",
    "strsplit", "strjoin", "tContains", "CopyTable", "Mixin", "CreateColor",
    "C_Timer", "C_Spell", "C_Item", "C_AddOns", "C_Secrets", "C_CurveUtil",
    "C_DurationUtil", "C_RestrictedActions", "C_UnitAuras", "C_ChatInfo",
    -- O que este addon usa de fato:
    "C_EquipmentSet", "C_TransmogOutfitInfo", "C_ClassTalents", "C_Traits", "C_SpecializationInfo", "Enum",
    "GetSpecialization", "GetNumSpecializations", "SetSpecialization", "UnitCastingInfo",
    "GetLocale", "GetCursorPosition", "Minimap", "UISpecialFrames", "tinsert", "table",
    "math", "ipairs", "pairs", "type", "pcall", "tostring", "tonumber", "unpack",
    "GameTooltip_Hide", "Settings", "C_TooltipInfo", "C_EventUtils", "UIErrorsFrame",
    "RaidWarningUtil", "GetInventoryItemLink", "GetMaxBattlefieldID", "GetBattlefieldStatus",
    "PVP_ITEM_LEVEL_TOOLTIP", "NORMAL_FONT_COLOR", "_G", "GetFileIDFromPath",
    "Settings", "EventRegistry", "LibStub",
}

globals = {
    "SLASH_ROCKETSWAP1",
    "SLASH_ROCKETSWAP2",
    "RocketSwapDB",
}
