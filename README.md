# CheckParamPlus

Upgraded version of checkparam by from20020516 & Kigen, modified by Cypan (Bahamut).
Install to `Windower/addons/CheckParamPlus/` and load with `//lua load checkparamplus`.
The `//cp` and `//checkparam` commands are unchanged.

# checkparam (original addon)
![40696007-caf91c3c-63fe-11e8-9837-516f9e1f2b0e](https://user-images.githubusercontent.com/26649687/40877257-96ccef12-66b8-11e8-97a4-797789375a00.jpg)
## English
- `/check` OR `/c` (in-game command)
  - Whenever you `/check` any player, displays the total of property of that players current equipments.(defined in `settings.xml`)

## Modifications by Cypan (Bahamut)

Additional addon commands:

- `//cp` — self-check of equipped gear properties (original behavior).
- `//cp full` — same self-check, but also adds job traits (main + sub) and main-job
  merit/job point gift bonuses from `job_traits.lua` to the tally. Ranked traits from
  main/sub do not stack (higher tier wins); main-job gifts and merits do stack with a
  sub trait. Traits flagged main-only (e.g. NIN Daken) are never credited to the sub job.
- `//cp delta` — compares the two most recent `//cp` or `//cp full` snapshots and shows
  what changed.
- `//cp augtest [<slot>]` — native augment resolver test output.

The augment reader also processes every pet-stat segment of multi-stat augments
(the original code only read the first, silently dropping the rest).

## Support

First and foremost: Please support the original author if this is an addon modification. 
If you enjoy the addon and you'd like to buy me a coffee, it's appreciated but never expected:

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-cypan-FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/cypan)

Bug reports and pull requests are worth more than donations, so open an issue if something's broken please.
