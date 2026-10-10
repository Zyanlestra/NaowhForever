# Consumable Bar

Your consumables on a bar you can click: potions, elixirs, flasks, scrolls, food, bandages,
weapon stones and oils, healthstones, explosives and engineering devices. Each icon shows how many
you carry, greys out with NONE in red when you run out (or hides, with Hide When Out), and has its
cooldown and its key. Edit Items, the bar's own window, adds items (+, by ID or name, or dragged
from the bags), puts them in order, and opens each one's settings beside it. Off by default
(`consumableBar` in `Core/Features.lua`): while it is off nothing is built or listened to.

A module addon of its own, built on the item bar in `Shared/` (`Shared/UI/ItemBar.lua`, with
`Shared/UI/Anchor.lua` and `Shared/Game/ActionKeys.lua`) that QoL's Food & Drink Bar uses too. Its
settings live in the QoL store (`Core/Settings.lua`, `consumableBar*`). While this addon is
loaded and the bar is on, the Food & Drink Bar's card sits on this page.

## Layout

```
NaowhForever_ConsumableBar/
  NaowhForever_ConsumableBar.toc  its metadata, and one file line: ConsumableBar.xml
  ConsumableBar.xml   every file, in load order
  ConsumableBar.lua   the module table (ns.ConsumableBar, CB): entries, their settings, change listeners
  Constants.lua       the numbers several files share (CB.C)
  Data/
    Categories.lua    the kinds of consumable: by the game's subclass, Trade Goods, weapon items by ID (CB.Data)
  Items.lua           the item rules: what is a consumable, the list, typed items, Scan Bags, Clear
  Keys.lua            the key that uses each entry: its own button's binding, or an action button holding it
  Used.lua            Hide After Use: the item's cooldown, buff or weapon enchant, and when to look again
  View/
    Cell.lua          one icon as the bar, Edit Items and the settings preview draw it
  UI/
    Ask.lua           Ask to Add New Consumables: the popup and what it asks about
    Bar.lua           the bar on screen: secure buttons, layout, place, visibility, events
    Editor.lua        Edit Items, and an item's settings beside it (the page Consumable Bar/Item)
    SettingsPage.lua  its settings page: Edit Items, the bar, adding items, its anchor, the window
  README.md           this file
```

## Why

- The icons are secure item buttons: their layout, place, items, mouse input and visibility only
  change out of combat. A change made in a fight sets `pending` and applies when it ends.
- Each item has its own named button, `NaowhForeverConsumableBarItem<id>`, made the first time it is
  on the bar and kept: WoW never frees a frame, and a key bound to it follows the item wherever it
  sits. Taken off the bar, its button is pointed at nothing, so that key does nothing.
- Hide in Combat and Hide After Use work through state drivers set before a fight: a fight shows
  an item hidden after use again, so it is there when it is needed. A driver is registered only
  when its rule changes, since registering one evaluates it and visibility is checked on every
  global cooldown.
- Hide After Use reads auras and weapon enchants out of combat only, and never a secret value: a
  value handed back secret keeps what was shown. Food's use spell is the eating; what it leaves is
  Well Fed, read from Shared's lists (`ns.FOOD_SPELLS`, `ns.WELL_FED`), so it works with Aura Buffs
  off.
- A cooldown counts only when it started with the item's own cast, seen as `UNIT_SPELLCAST_SUCCEEDED`
  (within `CAST_SLOP`, 1 s): potions share one cooldown, and drinking a healing potion must not hide
  a mana potion. A cooldown from before a reload is not seen, so the item shows until its next use.
- A cooldown of `GCD` (1.5 s) or less is the global cooldown, not the item's own.
- A setting is applied as far as it reaches: the bar's look (fonts, offsets, background, an item's
  own text) restyles the icons, what the bar does not show (window opacity, filters, declined items,
  tooltips) applies nothing, and the rest lays the bar out again. A drag writes the anchor only
  when it changes, since every write reaches the listeners.
- Ask to Add learns what the bags hold on the first bag update, not at login, when they may not
  be filled yet. What waits to be asked about is checked again when it is shown: declined, filtered
  out, no longer in the bags or on the bar already, it is skipped.
- After Hide After Use hides an item, the bar looks again when its cooldown or effect should end,
  `WAKE_LEAD` (0.1 s) after. Only the soonest look is scheduled; a later one just looks again.
- An icon hidden by Hide When Out takes no clicks, so it does not catch ones meant for what is
  under it. Mouse input on a secure button changes only out of combat: one that runs out in a fight
  fades at once and stops taking clicks when the fight ends.
- Counts, keys, the grey icon, NONE and cooldowns are plain text and textures, and update in combat.
- NONE follows the icon's size, not the count's font: as large as fits between the edges.
- Each icon carries its own piece of the background, reaching halfway into the spacing toward each
  neighbour and `BG_PAD` (3 px) past an outer edge, so a hidden icon takes its piece with it.
- Keys are read a frame after a bar changes (`C_Timer.After(0)`): Blizzard redraws its own key text
  on the same events, and a burst of them is read once.
- Edit Items keeps the bar at its real size: it scrolls sideways when the bar is wider than the
  window, and an item out of stock while Hide When Out is on stays in it as a `GHOST` (35 %).
- An item's settings are a settings page of their own (`Consumable Bar/Item`) whose store reads and
  writes that item's entry in `consumableBarItemFlags`, so its rows, dots and Reset work as any
  page's do. Saved tables are copied before every change, so the shared defaults are never written.
- An item given its own text before the Custom Text switch existed keeps showing it.
- The bar starts at `HOME_Y` (-260), under the Food & Drink Bar's spot (-210), so the two never sit
  on top of each other.
- Anchoring is the shared one (`Shared/UI/Anchor.lua`): unit frames there, and the HUD Editor's own
  Anchor for another Naowh Forever element (Anchor to an Element). Another addon's frame could move
  in combat, and the bar's secure buttons on it would block that.

## Checking

`lua Tools/regression/test-consumable-bar.lua` loads the feature switches, the shared item bar,
anchor and action keys, then these files in the XML's order, against stubs.
