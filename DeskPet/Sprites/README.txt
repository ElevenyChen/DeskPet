DeskPet Custom Sprites Guide
============================

Want to use your own cat? Replace the PNG files in any folder below,
and DeskPet will use your images instead of the built-in Unicode art.


HOW IT WORKS
------------

Each folder = one animation state (idle, walking, sleeping, etc.).
Each PNG in the folder = one frame of that animation.
The app plays frames in order: 0.png -> 1.png -> 2.png -> ... -> loop.

You don't have to customize every folder.
If a folder is empty, the app falls back to the built-in Unicode art for that state.


ACTION GROUPS (NEW)
-------------------

Each state folder supports multiple "action groups" — subfolders that each
contain a separate set of animation frames. When the cat enters a state,
one group is picked at random, and frames play from that group.

This lets you have multiple visual variations for the same state. For example,
sleeping/ could have a side-view group and a front-view group:

    Sprites/
      sleeping/
        side/             <- action group "side"
          0.png           <- side-view frame 1
          1.png           <- side-view frame 2
          2.png           <- side-view frame 3
        front/            <- action group "front"
          0.png           <- front-view frame 1
          1.png           <- front-view frame 2

Each time the cat falls asleep, it randomly picks either "side" or "front"
and plays that group's frames in order.

Rules:
- Group names can be anything (no spaces recommended). e.g. side, front, curled, stretched
- Each group follows the same frame naming: 0.png, 1.png, 2.png...
- Groups are independent — they can have different numbers of frames
- If a state folder has BOTH loose PNGs (0.png, 1.png) AND subfolders,
  only the subfolders (groups) are used; loose files are ignored
- If a state folder has NO subfolders, the old flat layout still works
- You can mix: use groups for sleeping/ but flat files for idle/

Example with multiple states using groups:

    Sprites/
      idle/
        0.png                <- flat layout (single animation)
        1.png
        2.png
      sleeping/
        side/                <- group: side view sleeping
          0.png
          1.png
          2.png
        front/               <- group: front view sleeping
          0.png
          1.png
        curled/              <- group: curled up sleeping
          0.png
          1.png
          2.png
          3.png
      walk_right/
        normal/              <- group: normal walk
          0.png
          1.png
          2.png
        sneaky/              <- group: sneaky tiptoe walk
          0.png
          1.png
          2.png
          3.png


FILE NAMING
-----------

Files MUST be named as sequential numbers starting from 0:

    0.png       <- first frame (required)
    1.png       <- second frame
    2.png       <- third frame
    ...

- Names must be exactly "0.png", "1.png", etc. No leading zeros (not "01.png").
- No gaps allowed: if you have 0.png and 2.png but no 1.png, only frame 0 loads.
- You can have 1 frame (just 0.png) or up to 20 frames per folder/group.


IMAGE SPECS
-----------

- Format: PNG with transparent background (alpha channel)
- Size: 150x100 px recommended (matches the cat window)
  - Larger images are fine, they scale down proportionally
  - Keep all frames in one folder/group the same size for smooth animation
- Orientation: face forward for idle/reminder/dragged, face sideways for walk


FOLDERS
-------

idle/           Standing still. The default state.
                Suggested: 2-4 frames (blink, tail wag)
                Frame rate: 0.6s per frame

sleeping/       Sleeping (bread loaf + zzZ).
                Suggested: 4-6 frames (breathing motion)
                Frame rate: 0.8s per frame
                Great for groups: side view, front view, curled up

lying_down/     Lying down before falling asleep (bread loaf, no zzZ).
                Suggested: 2-4 frames (tail twitch)
                Frame rate: 1.0s per frame

walk_right/     Walking to the right (side view).
                Suggested: 2-4 frames (leg movement)
                Frame rate: 0.25s per frame

walk_left/      Walking to the left (side view).
                Suggested: 2-4 frames (can mirror walk_right)
                Frame rate: 0.25s per frame

reminder/       Alert state when a reminder fires.
                Suggested: 2-4 frames (surprised expression)
                Frame rate: 0.4s per frame

dragged/        Being picked up / dragged by mouse.
                Suggested: 1-2 frames (stretched body, dangling legs)
                Note: the cat window stretches taller (160x200) during drag
                Frame rate: 0.3s per frame

attacking/      Cat attacking / swiping claws (triggered by clicking 5-15 times).
                Suggested: 2-4 frames (paw swipe, claws out)
                Frame rate: 0.2s per frame
                If this folder is empty, the cat shows a "!" instead.

playing/        Playful behavior (randomly triggered from idle).
                Suggested: 2-4 frames (batting at a toy, pouncing)
                Frame rate: 0.5s per frame
                This state only triggers if sprites exist in this folder.

chasing_tail/   Cat spinning to chase its own tail (randomly triggered from idle).
                Suggested: 2-4 frames (turning in circles)
                Frame rate: 0.25s per frame
                This state only triggers if sprites exist in this folder.

belly_up/       Cat rolling over to show its belly (randomly triggered from idle).
                Suggested: 2-4 frames (rolling over, paws in the air, wiggling)
                Frame rate: 0.6s per frame
                This state only triggers if sprites exist in this folder.
                Great for groups: quick_roll, lazy_stretch, happy_wiggle

grooming/       Cat grooming itself — licking paw, licking fur (randomly triggered from idle).
                Suggested: 3-6 frames (licking paw, washing face, licking side)
                Frame rate: 0.7s per frame
                This state only triggers if sprites exist in this folder.
                Great for groups: lick_paw, lick_fur, wash_face

paw_print/      Footprint left behind while walking.
                Only uses 0.png (single image, not animated).
                Suggested: 20x16 px, very small

icon/           Custom app icon (replaces Dock + menu bar icon).
                Only uses 0.png (single image).
                Suggested: 512x512 px or larger


QUICK START
-----------

1. Draw or export your cat frames as PNG with transparent background
2. Put them in the matching folder, named 0.png, 1.png, 2.png...
   - Or create subfolders for multiple variations (action groups)
3. Restart DeskPet
4. Done! Your cat is now in the app

Example: custom idle with 3 frames (flat):

    Sprites/
      idle/
        0.png    <- eyes open
        1.png    <- eyes half closed
        2.png    <- eyes closed (blink)

Example: sleeping with 2 action groups:

    Sprites/
      sleeping/
        side/
          0.png    <- side view, inhale
          1.png    <- side view, exhale
        belly_up/
          0.png    <- belly up, paws curled
          1.png    <- belly up, paws stretched


TIPS
----

- Start with idle/ and walk_right/ — those are the most visible states
- For walk_left/, you can horizontally flip your walk_right/ images
- The sleeping/ folder is great for action groups (side, front, curled, etc.)
- Keep file sizes small (under 100KB per frame) for smooth playback
- If something looks wrong, check: file names start from 0? no gaps? PNG format?
- Action groups are picked fresh each time the cat enters that state
