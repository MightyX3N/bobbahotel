---
title: Getting started
order: 1
description: What Bobba Hotel is, what you need, and how to start a hotel of your own.
---

# Getting started

Bobba Hotel is a Habbo-style hotel you run yourself. It's a **Garry's Mod gamemode**: rooms you build and
decorate, avatars, chat, a shop, trading, friends, groups, wired - the hotel you remember, but yours. Play
alone, with friends, or run a public hotel on a server. Everything in it - furni, clothes, rooms, windows,
wired boxes, phone apps - can be added or changed by addons from the Steam Workshop.

There's also a **desktop app** that runs the same hotel without Garry's Mod, and players on the desktop app
and in Garry's Mod can be in the same hotel.

> **In development.** Bobba Hotel isn't on the Workshop yet. What's here works and is played and tested
> every day, but things still change quickly. See the [changelog](../changelog.html) for what's new and the
> [roadmap](../roadmap.html) for what's coming.

## What you need

- **Garry's Mod** (any recent version). Nothing else to install: GMod has the database built in.
- For Habbo's furni, clothes and look: the **Habbo content** addon (`bobba_habbo`), which downloads them
  from Habbo while you play. See [The Habbo addon](habbo-addon.html).
- Or the **desktop app** instead of Garry's Mod (Windows; see [The desktop app](desktop.html)).

## Installing (for now)

Until it's on the Workshop, Bobba Hotel comes from its GitHub repository:

1. Download the repository (the green **Code** button, **Download ZIP**) and unpack it.
2. Copy into your `garrysmod` folder (usually `Steam/steamapps/common/GarrysMod/garrysmod`):
   - `gamemodes/bobbahotel` into `garrysmod/gamemodes/`
   - `addons/bobbahotel` (the hotel's fonts) and `addons/bobba_habbo` (Habbo's content) into `garrysmod/addons/`
3. Start Garry's Mod and pick **Bobba Hotel** in the gamemode list (bottom right of the main menu).

## Starting a hotel

| How | What happens |
| --- | --- |
| **Singleplayer** | Start a game on any map. You see the start screen, check in to your hotel, and play alone. |
| **Peer to peer / listen server** | Start with more than one player slot; friends join you from the server browser or Steam. You're the hotel's owner. |
| **Dedicated server** | `srcds -game garrysmod +gamemode bobbahotel +map gm_construct`. Give yourself `superadmin` (or use ULX / SAM) to manage the hotel. |
| **Desktop app** | Open `Bobba Hotel.exe`, add a hotel or host one. See [The desktop app](desktop.html). |

The map doesn't matter: the hotel draws its own rooms over it.

## Your first minutes

1. **The start screen** (when you host): your hotels and the ones you've added. Check in.
2. **The hotel's page**: news, who's online, your friends. Click **Enter hotel**.
3. **Pick a starter room**: new players choose a decorated room of their own, with a gift inside.
4. **A short tutorial**: walk, open the gift, move a furni, say something - and get a few credits.

From there, [Playing](playing.html) explains the hotel, and [Running a hotel](hosting.html) the Manage
screen, settings and permissions.

## Two looks

Bobba Hotel has two complete user interfaces, and the hotel picks one (players can pick for themselves):

- **Classic** - Habbo's own windows, as nitro-react has them: the toolbar, navigator, catalogue, inventory,
  friend list, messenger, wired windows. The Habbo pack starts in this one.
- **Phone and tablet** - Bobba Hotel's own look: a phone you take out of your pocket and a tablet for the
  bigger apps, with a home screen, widgets, notifications and an app for everything.

Switch with `bobba_ui habbo` or `bobba_ui phone` in the console, or in Settings.
