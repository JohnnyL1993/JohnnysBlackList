# Johnny's Blacklist

A World of Warcraft 3.3.5a addon for the Warmane private server.

Blacklist players with unit-popup/slash commands, whisper auto-ignore, and sighting warnings across target/mouseover/group/guild/who.

## Requirements

No other addons required. Johnny's Raid Comp shows blacklist flags on raid members when both are installed.

## Install

1. Go to [Releases](https://github.com/JohnnyL1993/JohnnysBlackList/releases) and download **`JohnnysBlackList-vX.Y.zip`** from the latest release.
   Don't use GitHub's green **Code → Download ZIP** button or the "Source code" zips. Those unpack as `JohnnysBlackList-main` or `JohnnysBlackList-1.0`, and WoW won't load an addon whose folder name doesn't match.
2. Extract it into `World of Warcraft\Interface\AddOns\`. You should end up with `Interface\AddOns\JohnnysBlackList\JohnnysBlackList.toc`.
3. Restart WoW, or log out to the character screen, and make sure the addon is enabled.

## Updating

Download the latest release zip, delete the old `JohnnysBlackList` folder, and extract the new one in its place.

## Slash commands

| Command | What it does |
| --- | --- |
| `/bl or /blacklist` | Blacklist your current target |
| `/bl <name> [reason]` | Blacklist a player by name, with an optional reason |
| `/removebl <name>` | Remove a player from the blacklist |

## Other Johnny's addons

- [Johnny's Raid Comp](https://github.com/JohnnyL1993/JohnnysRaidComp)
- [Johnny's Warmane Addon Hub](https://github.com/JohnnyL1993/JohnnysAddonHub)
- [Johnny's Currency Tracker](https://github.com/JohnnyL1993/JohnnysCurrencyBar)
- [Johnny's Gear Advisor](https://github.com/JohnnyL1993/JohnnysGearAdvisor)
- [Johnny's Professions](https://github.com/JohnnyL1993/JohnnysProfessions)
- [Johnny's Messenger](https://github.com/JohnnyL1993/JohnnysMessenger)
- [Johnny's Raid Browser](https://github.com/JohnnyL1993/JohnnysRaidBrowser)
- [Johnny's Raid Roll](https://github.com/JohnnyL1993/JohnnysRaidRoll)

## Releasing (maintainer notes)

1. Bump `## Version:` in the `.toc`.
2. Commit, then `git tag vX.Y` and `git push && git push --tags`.
3. The **Release** GitHub Action builds the zip and attaches it to the release.
