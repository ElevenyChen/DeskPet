#!/usr/bin/env python3
"""Sprite pipeline for DeskPet.

Sprites/ is a GENERATED directory: do not hand-edit frames there. Put source
images somewhere else (cat_image/ is git-ignored for this purpose), then use
this script to import, trim and validate.

Subcommands
-----------
  check                 Validate Sprites/ layout: contiguous numbering, same
                        canvas size within a state, no stray files.
  trim                  Crop transparent borders. All frames of one state share
                        one crop box (union bbox), so frames stay aligned and
                        the app's window aspect stays stable within a state.
                        Optionally downscale so the longest side <= --max-side.
  import SRC STATE[/GROUP]
                        Copy images from SRC (any names, sorted) into
                        Sprites/STATE[/GROUP]/0.png, 1.png, ... then trim that
                        state. --chroma removes a green-screen background.

Typical flow when adding an action:
  python3 scripts/prepare_sprites.py import cat_image/grooming_paw grooming/paw
  python3 scripts/prepare_sprites.py check
  then clean build in Xcode (Cmd+Shift+K) so the new files get copied.

Requires Pillow:  python3 -m pip install pillow
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.exit("Pillow is required: python3 -m pip install pillow")

ROOT = Path(__file__).resolve().parents[1]
SPRITES = ROOT / "DeskPet" / "Sprites"

# Folders under Sprites/ that are not animation states.
NON_STATE_DIRS = {"icon"}
# Files allowed to sit next to frames.
IGNORED_FILES = {".DS_Store", "README.txt"}

# Display budget: cat window base is 160pt, slider max 3x, Retina 2x => 960px.
DEFAULT_MAX_SIDE = 1024
DEFAULT_PAD = 8


# ---------------------------------------------------------------- discovery --

def frame_files(folder: Path) -> list[Path]:
    """Return 0.png, 1.png, ... in order, stopping at the first gap."""
    frames: list[Path] = []
    i = 0
    while (folder / f"{i}.png").is_file():
        frames.append(folder / f"{i}.png")
        i += 1
    return frames


def state_dirs() -> list[Path]:
    return sorted(
        p for p in SPRITES.iterdir()
        if p.is_dir() and not p.name.startswith(".") and p.name not in NON_STATE_DIRS
    )


def groups_of(state: Path) -> list[Path]:
    """Subfolders that contain frames (action groups)."""
    return sorted(
        p for p in state.iterdir()
        if p.is_dir() and not p.name.startswith(".") and frame_files(p)
    )


def frame_folders(state: Path) -> list[Path]:
    """Folders the app would actually read for this state."""
    groups = groups_of(state)
    if groups:
        return groups
    return [state] if frame_files(state) else []


# -------------------------------------------------------------------- check --

def check(verbose: bool = True) -> int:
    errors: list[str] = []
    warnings: list[str] = []
    total_frames = 0
    total_bytes = 0

    for state in state_dirs():
        groups = groups_of(state)
        flat = frame_files(state)
        if groups and flat:
            warnings.append(f"{state.name}: has both groups and flat frames; the app ignores the flat frames")
        folders = frame_folders(state)
        if not folders:
            warnings.append(f"{state.name}: no frames (app falls back to built-in art)")
            continue

        sizes_in_state: set[tuple[int, int]] = set()
        for folder in folders:
            frames = frame_files(folder)
            rel = folder.relative_to(SPRITES)
            # stray files: pngs not in the contiguous sequence, or junk
            for f in sorted(folder.iterdir()):
                if f.is_dir() or f.name in IGNORED_FILES or f in frames:
                    continue
                if f.suffix.lower() == ".png":
                    errors.append(f"{rel}/{f.name}: not part of 0..{len(frames) - 1} sequence (gap or bad name)")
                else:
                    warnings.append(f"{rel}/{f.name}: unexpected file")
            sizes_in_group: set[tuple[int, int]] = set()
            for f in frames:
                with Image.open(f) as im:
                    if im.mode != "RGBA":
                        errors.append(f"{rel}/{f.name}: mode {im.mode}, expected RGBA (transparent background)")
                    sizes_in_group.add(im.size)
                total_bytes += f.stat().st_size
            total_frames += len(frames)
            if len(sizes_in_group) > 1:
                errors.append(f"{rel}: frames have different sizes {sorted(sizes_in_group)}; the cat will jump between frames")
            sizes_in_state |= sizes_in_group
            if verbose:
                size = next(iter(sizes_in_group)) if len(sizes_in_group) == 1 else "mixed"
                print(f"  {str(rel):28s} {len(frames):2d} frames  {size}")
        if len(sizes_in_state) > 1:
            warnings.append(f"{state.name}: groups have different canvas sizes {sorted(sizes_in_state)}; window will shift when the group changes")

    if verbose:
        print(f"\n{total_frames} frames, {total_bytes / 1e6:.1f} MB")
    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    if not errors:
        print("OK")
    return 1 if errors else 0


# --------------------------------------------------------------------- trim --

def trim_state(state: Path, pad: int, max_side: int | None, dry_run: bool) -> tuple[int, int]:
    """Trim every frame folder of a state with ONE shared crop box.

    Frames are aligned top-left on a canvas as large as the largest frame in
    the state (so a frame that is 1px off, as AI generators sometimes produce,
    gets normalised instead of causing a jump). Returns (bytes_before, bytes_after).
    """
    all_frames = [f for folder in frame_folders(state) for f in frame_files(folder)]
    if not all_frames:
        return 0, 0

    sizes: dict[Path, tuple[int, int]] = {}
    box = None
    for f in all_frames:
        with Image.open(f) as im:
            sizes[f] = im.size
            bb = im.convert("RGBA").getchannel("A").getbbox()
        if bb is None:
            continue
        box = bb if box is None else (
            min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3])
        )
    if box is None:
        print(f"  {state.name}: fully transparent frames, skipped")
        return 0, 0

    w = max(s[0] for s in sizes.values())
    h = max(s[1] for s in sizes.values())
    distinct = sorted(set(sizes.values()))
    if len(distinct) > 1:
        spread = max(abs(a - w) + abs(b - h) for a, b in distinct)
        level = "WARN " if spread > 16 else "note "
        print(f"  {level}{state.name}: canvas sizes {distinct} aligned top-left onto {w}x{h}")

    left = max(0, box[0] - pad)
    top = max(0, box[1] - pad)
    right = min(w, box[2] + pad)
    bottom = min(h, box[3] + pad)
    crop = (left, top, right, bottom)
    cw, ch = right - left, bottom - top
    scale = 1.0
    if max_side and max(cw, ch) > max_side:
        scale = max_side / max(cw, ch)
    target = (max(1, round(cw * scale)), max(1, round(ch * scale)))

    before = after = 0
    for f in all_frames:
        size_before = f.stat().st_size
        before += size_before
        unchanged = sizes[f] == (w, h) and crop == (0, 0, w, h) and scale == 1.0
        if unchanged or dry_run:
            after += size_before
            continue
        with Image.open(f) as im:
            src = im.convert("RGBA")
            if src.size != (w, h):
                canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                canvas.alpha_composite(src, (0, 0))
                src = canvas
            out = src.crop(crop)
            if scale != 1.0:
                out = out.resize(target, Image.Resampling.LANCZOS)
            out.save(f, optimize=True)
        after += f.stat().st_size
    tag = "(dry run) " if dry_run else ""
    print(f"  {tag}{state.name:14s} {w}x{h} -> crop {cw}x{ch} -> {target[0]}x{target[1]}  [{len(all_frames)} frames]")
    return before, after


def trim(states: list[str], pad: int, max_side: int | None, dry_run: bool) -> int:
    targets = state_dirs()
    if states:
        targets = [SPRITES / s for s in states]
        missing = [t.name for t in targets if not t.is_dir()]
        if missing:
            sys.exit(f"no such state folder: {', '.join(missing)}")
    before = after = 0
    for state in targets:
        b, a = trim_state(state, pad, max_side, dry_run)
        before += b
        after += a
    if before:
        print(f"\n{before / 1e6:.1f} MB -> {after / 1e6:.1f} MB")
    return 0


# ------------------------------------------------------------------- import --

def remove_chroma(im: Image.Image, key=(0, 255, 0), tolerance: int = 72) -> Image.Image:
    """Turn green-screen pixels transparent (for AI-generated sheets without alpha)."""
    rgba = im.convert("RGBA")
    px = rgba.load()
    w, h = rgba.size
    kr, kg, kb = key
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if abs(r - kr) <= tolerance and abs(g - kg) <= tolerance and abs(b - kb) <= tolerance:
                px[x, y] = (0, 0, 0, 0)
            elif g > 180 and r < 80 and b < 80:  # halo
                px[x, y] = (r, g, b, 0)
    return rgba


def do_import(src: Path, dest_spec: str, chroma: bool, pad: int, max_side: int | None, replace: bool) -> int:
    if not src.is_dir():
        sys.exit(f"source folder not found: {src}")
    parts = dest_spec.strip("/").split("/")
    if not 1 <= len(parts) <= 2 or not all(parts):
        sys.exit("destination must be STATE or STATE/GROUP")
    state_name = parts[0]
    dest = SPRITES.joinpath(*parts)

    images = sorted(
        p for p in src.iterdir()
        if p.is_file() and p.suffix.lower() in {".png", ".webp", ".jpg", ".jpeg"}
    )
    if not images:
        sys.exit(f"no images in {src}")

    state_dir = SPRITES / state_name
    if len(parts) == 2 and frame_files(state_dir):
        print(f"WARN  {state_name}/ has flat frames; once a group exists the app ignores them")

    if dest.exists():
        if not replace:
            sys.exit(f"{dest.relative_to(ROOT)} already exists; pass --replace to overwrite")
        shutil.rmtree(dest)
    dest.mkdir(parents=True)

    for i, p in enumerate(images):
        with Image.open(p) as im:
            out = remove_chroma(im) if chroma else im.convert("RGBA")
            out.save(dest / f"{i}.png", optimize=True)
    print(f"imported {len(images)} frames -> {dest.relative_to(ROOT)}")

    trim_state(state_dir, pad, max_side, dry_run=False)
    print("\nvalidating ...")
    rc = check(verbose=False)
    print("Reminder: clean build (Cmd+Shift+K) so Xcode copies the new files into the bundle.")
    return rc


# --------------------------------------------------------------------- main --

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("check", help="validate Sprites/ layout")

    t = sub.add_parser("trim", help="crop transparent borders (shared box per state)")
    t.add_argument("states", nargs="*", help="state folders to trim (default: all)")
    t.add_argument("--pad", type=int, default=DEFAULT_PAD, help=f"transparent padding to keep (default {DEFAULT_PAD})")
    t.add_argument("--max-side", type=int, default=DEFAULT_MAX_SIDE, help=f"downscale so longest side <= N, 0 = never (default {DEFAULT_MAX_SIDE})")
    t.add_argument("--dry-run", action="store_true")

    i = sub.add_parser("import", help="import source images into a state/group")
    i.add_argument("src", type=Path)
    i.add_argument("dest", help="STATE or STATE/GROUP, e.g. grooming/paw")
    i.add_argument("--chroma", action="store_true", help="remove pure-green background")
    i.add_argument("--replace", action="store_true", help="overwrite an existing group")
    i.add_argument("--pad", type=int, default=DEFAULT_PAD)
    i.add_argument("--max-side", type=int, default=DEFAULT_MAX_SIDE)

    args = ap.parse_args(argv)
    if not SPRITES.is_dir():
        sys.exit(f"Sprites folder not found: {SPRITES}")

    if args.cmd == "check":
        return check()
    if args.cmd == "trim":
        return trim(args.states, args.pad, args.max_side or None, args.dry_run)
    if args.cmd == "import":
        return do_import(args.src, args.dest, args.chroma, args.pad, args.max_side or None, args.replace)
    return 2


if __name__ == "__main__":
    sys.exit(main())
