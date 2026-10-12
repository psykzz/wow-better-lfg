# Better LFG filters for WoW Forever

![Better LFG logo](logo.png)

**Less scrolling, better groups.** Native-first role, class, and level filters
that fit naturally into WoW Forever's familiar LFG interface.

Better LFG extends the existing **Groups** and **Players** results instead of
replacing Blizzard's finder UI. It adds filters to the native options menu,
reuses Forever's Retail-style level-range widget, and preserves the existing
**Show All Level Ranges** option.

## Filters

The filters are available from the Groups list's options cog.

**Group requires**

- **Needs Tank**, **Needs Healer**, and **Needs Damage** keep groups with an
  open slot for each checked role.
- **No \<class\> already in group** hides groups that already have a player of
  your class.
- **Has Tank** and **Has Healer** require a current member with that role.
- **Group fit** requires enough open slots for your current group's members
  and their assigned roles. When solo, any selected LFG role can fit.

**Player requires**

- **Has Tank**, **Has Healer**, and **Has DPS** keep players advertising any
  selected role. With none selected, no role filtering is applied.
- The **Player level** range uses the Retail-style level-range widget. The
  minimum and maximum are inclusive, and the default 1-60 range covers the
  in-game level range. Saved values outside this range are clamped on load.
- **Player class** checkboxes keep any selected class. With none selected, no
  class filtering is applied. Role, class, and level requirements combine.

Group fit is disabled with a red reason if your current group has 4 or more
members, at least 2 tanks, or at least 2 healers. Filter choices are saved per
character. When upgrading, the previous **My role open** setting maps to a
role-specific **Needs** option if one role was selected. Blizzard's **Show All
Level Ranges** setting remains in the menu. Group filters only evaluate
multi-member group listings; player filters only evaluate solo player listings.

## Install

1. Place the `BetterLFGFilters` folder in `Interface\AddOns`.
2. Reload the game UI with `/reload`.
3. Open Group Finder, select **Groups**, and open the options cog to change
   the role filters.

The addon targets WoW Forever interface `16001`. It uses the client's native
`C_LFGList.GetSearchResultMemberCounts` role and remaining-slot data.

## Releases

Push an annotated version tag to package the addon, create a GitHub release, and
upload it to CurseForge project `1738917`:

```powershell
git tag -a 0.5.0 -m "0.5.0"
git push origin 0.5.0
```

The release workflow uses the repository secret `CURSEFORGE_API_TOKEN` for
CurseForge uploads. GitHub's automatically provided `GITHUB_TOKEN` is used to
create the GitHub release.
