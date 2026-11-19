-- The talents Maxroll's WoW Forever levelling guides highlight for each class, one list per build the guide shows.
-- This is only a list of talent names (game terms) with a link to the guides: it is not their guide and has no order.
-- Source and credit: https://maxroll.gg/wow-forever/class-guides
-- The addon works out which build suits me from where my talent points are, and which tree each talent is in from the game.
local ADDON, ns = ...
local addon = ns.addon

local BASE = "https://maxroll.gg/wow-forever/class-guides/"

addon.TalentGuide = {
    source = "Maxroll's WoW Forever levelling guides",
    WARRIOR = { url = BASE .. "warrior-leveling-guide", blocks = {
        { "Improved Tactical Mastery", "Anger Management", "Sweeping Strikes", "Bloodthrill" },
        { "Death Wish", "Gore Drinker" },
    } },
    MAGE = { url = BASE .. "mage-leveling-guide", blocks = {
        { "Elemental Precision", "Ice Lance", "Ice Block", "Cold Snap", "Ice Barrier" },
        { "Improved Fireball", "Pyroblast", "Blast Wave", "Combustion" },
        { "Improved Channeling", "Missile Barrage", "Arcane Blast", "Arcane Wrath", "Presence of Mind", "Arcane Power" },
    } },
    DRUID = { url = BASE .. "druid-leveling-guide", blocks = {
        { "Moonkin Form", "Insect Swarm", "Eclipse" },
        { "Swiftmend", "Bloom", "Nature's Swiftness", "Wild Growth" },
        { "Feral Swiftness", "Feral Charge", "Shifting Power" },
    } },
    HUNTER = { url = BASE .. "hunter-leveling-guide", blocks = {
        { "Deadly Aspects", "Improved Revive Pet", "Summon Hawk", "Rapid Killing", "Improved Mend Pet", "Endurance Training", "Spirit Bond" },
        { "Strider Kick", "Expose Prey", "Resourcefulness", "Lacerating Strikes" },
    } },
    PALADIN = { url = BASE .. "paladin-leveling-guide", blocks = {
        { "Champion of the Light", "Repentance", "Unsealed Wrath" },
        { "Templar's Bulwark", "Swift Judgement" },
        { "Divine Favor", "Light's Vigil", "Oath of Light" },
    } },
    PRIEST = { url = BASE .. "priest-leveling-guide", blocks = {
        { "Wand Specialization", "Spirit Tap", "Holy Precision", "Inner Focus", "Meditation", "Mental Agility", "Penance", "Renewed Hope", "Divine Aegis" },
        { "Spirit Tap", "Shadow Focus", "Devouring Contagion", "Silence", "Shadow Weaving", "Darkness", "Shadowform", "Dark Inspiration",
          "Inner Focus", "Meditation", "Mental Agility", "Vampiric Embrace" },
        { "Wand Specialization", "Holy Precision", "Inner Focus", "Meditation", "Mental Agility", "Penance", "Power in Light", "Divine Fury" },
    } },
    ROGUE = { url = BASE .. "rogue-leveling-guide", blocks = {
        { "Puncturing Wounds", "Riposte", "Blade Flurry", "Adrenaline Rush", "Cold Blood" },
    } },
    SHAMAN = { url = BASE .. "shaman-leveling-guide", blocks = {
        { "Mental Dexterity", "Stormstrike", "Improved Stormstrike", "Mental Quickness" },
        { "Elemental Alacrity", "Elemental Focus", "Lightning Overload", "Lava Burst", "Lightning Mastery" },
    } },
    WARLOCK = { url = BASE .. "warlock-leveling-guide", blocks = {
        { "Improved Corruption", "Improved Drains", "Soul Siphon", "Pandemic", "Malevolence", "Shadow Mastery", "Fel Concentration", "Nightfall", "Siphon Life" },
        { "Shadowburn", "Conflagrate", "Shadow and Flame", "Improved Drains", "Bane of Havoc" },
        { "Demonic Sacrifice", "Demonic Pact", "Demonic Brand", "Fel Domination", "Soul Link" },
    } },
}

-- reached the end of the file without an error (used by /lazy check)
do local ns2 = select(2, ...); if ns2 and ns2.addon then ns2.addon.loaded = ns2.addon.loaded or {}; ns2.addon.loaded["TalentGuide.lua"] = true end end