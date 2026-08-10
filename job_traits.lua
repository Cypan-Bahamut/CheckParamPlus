--[[
job_traits.lua - supporting resource for checkparam's //cp full (v2.4 structure)
================================================================================
Returns { traits = {...}, gifts = {...} }.

traits[JOB][stat] = { tiers = {{lv=,val=},...}, main_bonus = <MERITS ONLY>,
                      main_only = true|nil, note = '...' }
  - highest tier at/below the job's level applies; ranked traits from main and sub
    DO NOT stack (the higher tier wins); main_bonus (merits) rides on MAIN only;
    main_only traits never apply from the sub.
gifts[JOB][stat] = flat total from ALL job point gifts (MASTERED-99 assumption:
  2100 JP spent, level 99). Applies to the MAIN job only, and STACKS with traits
  (gift attack + sub-job Attack Bonus trait are different mechanisms).
  MECHANICALLY EXTRACTED from LandSandBoat sql/job_point_gifts.sql - a dataset
  validated row-for-row against FFXIclopedia for MNK and NIN, and against bg-wiki
  for THF (TA +8, DW +5@550) - and cross-checked against 9 independently verified
  totals at generation time (all matched). Non-stat gifts (skill bonuses, pet
  bonuses, recasts, TH, etc.) are excluded.

TOTAL per stat = max(main trait tier, sub trait tier) + main merits + main gifts.
]]

return {
traits = {
    WAR = {
        -- Trait Lv25 = 10% (FFXIclopedia Warrior page). Merits: Double Attack Rate
        -- +1%/level, 5 max (FFXIclopedia). Gifts (+10) now live in the gifts table.
        ['double attack'] = { tiers = { {lv=25, val=10} }, main_bonus = 5,
            note = 'trait+merits verified' },
        -- WAR Attack Bonus I @30 (FFXIclopedia Warrior Support Job page: WAR 30) = +10
        -- (GameFAQs "+10 atk"; matches Accuracy Bonus I=+10 pattern). WAR also has
        -- Attack Bonus II @91 (Warrior page ladder) but its VALUE is unverified -
        -- omitted, so main WAR 91+ understates by the II delta.
        ['attack'] = { tiers = { {lv=30, val=10} },
            note = 'tier I verified; II@91 value unverified, omitted' },
    },
    NIN = {
        ['dual wield'] = { tiers = { {lv=10,val=10},{lv=25,val=15},{lv=45,val=25},{lv=65,val=30},{lv=85,val=35} },
            note = 'FFXIclopedia NIN ladder + SE forum; no merits/gifts' },
        ['subtle blow'] = { tiers = { {lv=15,val=5},{lv=30,val=10},{lv=45,val=15},{lv=60,val=20},{lv=75,val=25},{lv=91,val=27} },
            main_bonus = 5, note = 'ladder verified; merits 5; IV@60 val inferred' },
        -- Tier V value derived: FFXIclopedia Daken page "54% base at 2000 JP" minus
        -- +14 gifts = 40. I-IV values unpublished, omitted. Main-only (support-job
        -- page "(Not Usable)"); sub could never reach 95 regardless.
        ['daken'] = { tiers = { {lv=95, val=40} }, main_only = true,
            note = 'V=40 derived (54 - 14 gifts); I-IV omitted; main-only' },
    },
    MNK = {
        ['subtle blow'] = { tiers = { {lv=5,val=5},{lv=25,val=10},{lv=45,val=15},{lv=65,val=20},{lv=91,val=25} },
            note = 'Monk page ladder; no MNK SB merits' },
        ['martial arts'] = { tiers = { {lv=1,val=80},{lv=16,val=100},{lv=31,val=120},{lv=46,val=140},{lv=61,val=160},{lv=75,val=180},{lv=82,val=200} },
            note = 'delay reduction; 200@99 verified (480->280, bg-wiki H2H + Attack Speed)' },
    },
    THF = {
        ['triple attack'] = { tiers = { {lv=55, val=5} }, main_bonus = 5,
            note = 'trait 5 + merits 5 verified; +8 gifts in gifts table (bg-wiki total-19 claim unresolved, encoding verified components)' },
        ['dual wield'] = { tiers = { {lv=83,val=10},{lv=87,val=15},{lv=98,val=25} },
            note = 'THF page ladder; universal tier values' },
    },
    SAM = {
        ['store tp'] = { tiers = { {lv=10,val=10},{lv=30,val=15},{lv=50,val=20},{lv=70,val=25},{lv=90,val=30} },
            main_bonus = 10, note = 'ladder+values verified; merits +10; II/III inferred' },
    },
    DNC = {
        ['dual wield'] = { tiers = { {lv=20,val=10},{lv=40,val=15},{lv=60,val=25},{lv=80,val=30} },
            note = 'Dancer page ladder; universal tier values' },
        ['subtle blow'] = { tiers = { {lv=25,val=5},{lv=45,val=10},{lv=65,val=15},{lv=86,val=20} },
            note = 'Dancer page ladder; I-III values explicit in How-To: Dancer' },
        -- Accuracy Bonus I @30 = +10, II @60 = +22 total ("additional +12 for a total
        -- of +22" - FFXIclopedia How-To: Dancer; PUP guide corroborates 22 for I+II).
        -- III @80 exists (Dancer page ladder) but its VALUE is unverified - omitted,
        -- so main DNC 80+ understates by the III delta.
        ['accuracy'] = { tiers = { {lv=30, val=10}, {lv=60, val=22} },
            note = 'I/II verified; III@80 value unverified, omitted' },
    },
    DRG = {
        -- Attack Bonus I @10 (FFXIclopedia Dragoon page; Support Job page confirms
        -- granted to subs at DRG 10) = +10 (GameFAQs AB I "+10 atk"). Higher DRG AB
        -- tiers are not sub-reachable (absent from Support Job page through DRG 58)
        -- and their levels/values are unverified - omitted.
        ['attack'] = { tiers = { {lv=10, val=10} },
            note = 'tier I verified (the sub-DRG case); higher tiers unverified, omitted' },
        -- Accuracy Bonus I @30 = +10; II @ DRG 50 (Support Job page, ML sub range)
        -- = 22 total (universal AccB II value, verified via DNC/PUP sources).
        ['accuracy'] = { tiers = { {lv=30, val=10}, {lv=50, val=22} },
            note = 'I verified; II@50 level verified, value = universal AccB II (22)' },
    },
    -- REMAINING TRAIT LADDERS (not yet encoded - verify before adding, never guess):
    -- WHM/BLM/RDM/PLD/DRK/BST/BRD/RNG/SMN/BLU/COR/PUP/SCH/GEO/RUN traits (e.g. PUP
    -- Martial Arts ladder, RDM/BLM Fast Cast, WAR Fencer, SAM Zanshin, PLD Shield
    -- Mastery, RNG Snapshot/Rapid Shot ladders). Their GIFTS are already covered
    -- below. Kunimitsu path augments still omitted (rank 14/30).
},
gifts = {
        BLM = { ['magic accuracy']=42, ['magic attack bonus']=50, ['magic def bonus']=14, ['magic evasion']=42 },
        BLU = { ['accuracy']=36, ['attack']=70, ['def']=70, ['evasion']=36, ['magic accuracy']=36, ['magic attack bonus']=36, ['magic def bonus']=36, ['magic evasion']=36, ['ranged accuracy']=36, ['ranged attack']=70 },
        BRD = { ['accuracy']=21, ['def']=22, ['evasion']=22, ['magic accuracy']=36, ['magic def bonus']=15, ['magic evasion']=36, ['ranged accuracy']=21 },
        BST = { ['accuracy']=36, ['attack']=70, ['def']=85, ['evasion']=36, ['magic accuracy']=36, ['magic evasion']=36, ['ranged accuracy']=36, ['ranged attack']=70 },
        COR = { ['accuracy']=36, ['attack']=36, ['def']=22, ['evasion']=22, ['magic accuracy']=36, ['magic attack bonus']=14, ['magic evasion']=36, ['ranged accuracy']=36, ['ranged attack']=36, ['snapshot']=10 },
        DNC = { ['accuracy']=64, ['attack']=42, ['def']=42, ['dual wield']=5, ['evasion']=64, ['magic accuracy']=36, ['magic evasion']=36, ['ranged accuracy']=64, ['ranged attack']=42, ['subtle blow']=13 },
        DRG = { ['accuracy']=64, ['attack']=70, ['def']=70, ['evasion']=36, ['magic accuracy']=36, ['magic evasion']=36, ['ranged accuracy']=64, ['ranged attack']=70 },
        DRK = { ['accuracy']=22, ['attack']=106, ['def']=28, ['evasion']=22, ['magic accuracy']=42, ['magic evasion']=42, ['ranged accuracy']=22, ['ranged attack']=106, ['weapon skill damage']=8 },
        GEO = { ['magic accuracy']=50, ['magic attack bonus']=42, ['magic def bonus']=28, ['magic evasion']=50 },
        MNK = { ['accuracy']=42, ['attack']=56, ['counter']=10, ['def']=36, ['evasion']=42, ['magic accuracy']=36, ['magic evasion']=36, ['martial arts']=10, ['ranged accuracy']=42, ['ranged attack']=56, ['subtle blow']=10 },
        NIN = { ['accuracy']=56, ['attack']=70, ['daken']=14, ['def']=56, ['evasion']=64, ['magic accuracy']=50, ['magic attack bonus']=28, ['magic evasion']=50, ['ranged accuracy']=56, ['ranged attack']=70, ['weapon skill damage']=5 },
        PLD = { ['accuracy']=28, ['attack']=28, ['cure potency']=50, ['def']=106, ['evasion']=22, ['magic accuracy']=42, ['magic evasion']=42, ['ranged accuracy']=28, ['ranged attack']=28 },
        PUP = { ['accuracy']=50, ['attack']=42, ['evasion']=66, ['magic accuracy']=26, ['magic evasion']=36, ['martial arts']=5, ['ranged accuracy']=50, ['ranged attack']=42 },
        RDM = { ['accuracy']=22, ['fast cast']=8, ['magic accuracy']=70, ['magic attack bonus']=28, ['magic def bonus']=28, ['magic evasion']=56, ['ranged accuracy']=22 },
        RNG = { ['accuracy']=70, ['attack']=70, ['conserve tp']=15, ['def']=22, ['evasion']=14, ['magic accuracy']=36, ['magic evasion']=36, ['ranged accuracy']=70, ['ranged attack']=70 },
        RUN = { ['accuracy']=56, ['attack']=50, ['def']=36, ['evasion']=56, ['magic accuracy']=36, ['magic def bonus']=56, ['magic evasion']=70, ['ranged accuracy']=56, ['ranged attack']=50 },
        SAM = { ['accuracy']=36, ['attack']=70, ['def']=70, ['evasion']=36, ['magic accuracy']=36, ['magic evasion']=36, ['ranged accuracy']=36, ['ranged attack']=70, ['store tp']=8, ['zanshin']=20 },
        SCH = { ['magic accuracy']=42, ['magic attack bonus']=36, ['magic def bonus']=22, ['magic evasion']=42 },
        SMN = { ['def']=22, ['evasion']=22, ['magic def bonus']=22, ['magic evasion']=22 },
        THF = { ['accuracy']=36, ['attack']=50, ['def']=28, ['dual wield']=5, ['evasion']=70, ['magic accuracy']=36, ['magic evasion']=36, ['ranged accuracy']=36, ['ranged attack']=50, ['triple attack']=8 },
        WAR = { ['accuracy']=36, ['attack']=70, ['def']=70, ['double attack']=10, ['evasion']=36, ['magic accuracy']=36, ['magic evasion']=36, ['ranged accuracy']=36, ['ranged attack']=70, ['weapon skill damage']=3 },
        WHM = { ['accuracy']=14, ['cure potency']=23, ['magic accuracy']=50, ['magic attack bonus']=22, ['magic def bonus']=50, ['magic evasion']=50, ['ranged accuracy']=14 },
},
}
