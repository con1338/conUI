# Using conUI with other addons

conUI recognizes supported addons and offers a choice for the jobs they share with conUI. It can step back for a whole module or for a supported individual feature. This is not a guarantee for every addon or combination; check who handles each job on the Other addons page.

## What steps back

- **A whole module.** Some addons own the same frames as a conUI module, so only one of them can run. Bags stays off while Bagnon, AdiBags or Baganator is loaded, Nameplates while Plater is loaded, and Action Bars while Bartender4 or Dominos is loaded.
- **Only the parts both do.** With addons that do many small things, conUI steps back only where they overlap. With Leatrix Plus, each shared feature (junk selling, repairs, faster loot, declining duels and invites, and a few more) steps back only while Leatrix Plus has the same feature switched on; the rest of conUI's Quality of Life features keep running. With TradeSkillMaster, conUI's Open All and address book in the mail step back, and the mail look stays. With ElvUI, each conUI module steps back only while ElvUI's own part for it is on: turn off ElvUI's bags and conUI's Bags runs.
- **Bars that move the same buttons.** The Micro Menu and the experience and reputation bars step back while a bar addon (Bartender4, Dominos, ElvUI) places the same buttons or bars.

An addon that loads later (load on demand) is noticed when it loads. Out of combat, conUI steps back and offers a reload so the change is complete.

## Picking who handles each job

Type `/eui addons page` to open **Other addons** in the config window. Every addon conUI found is listed with each job it shares and who handles it now.

- **Use conUI's** gives the job to conUI. For a whole module, the other addon is turned off for this character after a reload. For a part both can run, conUI's part turns on right away and the other addon stays on.
- **Keep** *(addon name)* leaves the job to the other addon and conUI steps back again. If you turned that addon off with Use conUI's and haven't reloaded yet, Keep turns it back on.
- **Turn off** *(addon name)* shows for addons whose jobs all run next to conUI's. It turns the addon off for this character, after a reload.

Your picks are saved for your whole account, so they stay through reloads and profile switches. conUI never turns another addon on or off without your click.

In chat: `/eui addons` lists what was found, `/eui addons use <addon>` and `/eui addons keep <addon>` pick for one addon, and `/eui addons page` opens the page.

The first time conUI finds an addon it leaves a job to, it says so with one chat line. Turn that line off with **Chat line when an addon is found** on the Other addons page.

## In the setup

When conUI finds an addon on your first login, the setup has a step **Addons you already use**. Each job has two cards: **conUI** (marked Recommended) and **Keep** *(addon name)*. Nothing changes before Finish, and Finish names every addon it turns off. Express setup takes the recommended pick. On the last page, **Revert this** turns those addons back on.

## Addons in your layout

Your layout also has spots for the frames of supported addons you keep. Out of combat, conUI places and sizes their frames on the layout's spot for that job and moves them along when you pick another layout. conUI's own frame for the same job steps aside while the other addon has the spot.

- Supported: XLoot (loot window, roll bars and loot feed), SilverDragon and RareScanner (on the rare card), Bagnon, BetterBags and Baganator (bag and bank corners), MinimapButtonButton (the minimap's button bin corner), TellMeWhen (the first six icon groups on the aura icon spots), TomTom (the waypoint arrow spot), Titan Panel (the data bar edge), HealBot Continued (the party spot, and the raid spot in a raid), and WeaponSwingTimer and 4everSwingTimer (the swing timer spots).
- **Layout spots for other addons** on the Other addons page lists each one with its state. Turn off **Place other addons in the layout** to leave all of them where their own settings put them, or **Place** *(addon name)* to do that for one.
- Where an addon keeps a spot of its own, **Save the spot in** *(addon name)* writes the layout's spot into that addon's own settings, so it stays there without conUI too. You see every value first, and **Undo** puts them back.
- In chat: `/eui addons fit` lists them, and `/eui addons fit on` or `off`, with or without an addon name, switches the spots.

## Addons that work alongside conUI

Some addons are made to work with conUI and never make it step back: conUI places Details!, BigWigs, Deadly Boss Mods and others in your layout and sets them up from the setup's Other addons step (`/eui install addons`).

With RestedXP, the **RestedXP step list** button in the minimap's addon button bin folds RestedXP's list of every guide step away and back; the current step card and the arrow stay. There is also a key for it (Key Bindings > AddOns > conUI). conUI uses RestedXP's own **Show step list** switch and gives the list back at the height you had. Turn the button off with **Step list button on the minimap** under Integrations > RestedXP.

**Sizes to fit conUI** under Integrations > RestedXP sets RestedXP's guide text and arrow text to the size of conUI's own text (General > Accessibility > Large text counts) and lets its arrow, active items and targets grow by as much; a window scale you set goes back to 100 %. You see every value first, and **Undo the size change** puts them back. The guide text changes after a reload.

The layout also places RestedXP's arrow on its waypoint arrow spot and RestedXP's active items and targets beside the guide (movers **RestedXP active items** and **RestedXP targets** in `/eui move`). The two windows follow the guide only while conUI places it. Turn all three off with **Place RestedXP arrow and windows** on the Other addons page.

## For addon authors

Plugins declare which addons do the same job as their modules in the same way. See [Other addons that do the same job](../PLUGINS.md#other-addons-that-do-the-same-job) in the plugin guide.
