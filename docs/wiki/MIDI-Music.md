# MIDI music

RPG Maker 2000, 2003 and XP music is mostly MIDI (`.mid`). Godot can't play MIDI, so the kit **renders each MIDI file to ordinary audio once, when Godot imports it**. Your game then plays it like any other sound file. Exported games contain only the rendered audio and need no synthesizer.

Just put `.mid` or `.midi` files in a music folder (or import an RPG Maker folder that has them). Godot imports them like any other file; it takes a few seconds per song.

## The sound bank

A MIDI file only says which notes to play on which instrument. The **sound bank** supplies the instruments, so it decides what the music sounds like.

Choose it in **Tools > Resources > MIDI sound bank**, or in the project setting `rpg/audio/sound_bank`:

| Bank | Notes |
| --- | --- |
| **Windows' `gm.dls`** | The default on Windows. Microsoft's GS Wavetable set, the instruments RPG Maker played MIDI with, so the music sounds as players remember it. It exists only on Windows, and the kit never copies it. Check Microsoft's terms before selling a game whose music was rendered with it. |
| **An SF2 soundfont** | Any `.sf2` file, for example the free GeneralUser GS. Press **Copy into project** (it goes to `res://audio/soundfonts/`) so every computer, Linux and macOS included, renders the same music. The `.sf2` itself is not put into exported games. |
| **Built-in instruments** | Simple instruments made by the kit. The default on Linux and macOS. |

If the chosen bank is missing on a computer (for example a project made on Windows opened on Linux), the kit falls back to the built-in instruments and warns once. Each rendered song remembers which bank made it.

After changing the bank, press **Re-render all MIDI** to import every MIDI file again.

## Import options

Select a MIDI file in Godot's FileSystem dock and open the **Import** dock:

| Option | Default | Meaning |
| --- | --- | --- |
| Sound bank | (empty) | Empty uses the project setting |
| Sample rate | 32000 Hz | 22050, 32000 or 44100 Hz: higher is a little clearer and larger |
| Loop | on | See below |
| Volume db | 0 dB | Overall level, −24 to +24 dB |
| Compress (QOA) | on | About 1/5 the size of plain 16-bit audio: about 3 MB for a two-minute song instead of 15 MB |

Press **Reimport** after changing them.

## Looping

The song loops from its first **CC#111** marker (the loop point RPG Maker XP, VX, 2003 and EasyRPG use), or from the start, to the end of the track. Notes still ringing at the end are cut, as in RPG Maker.

## What is rendered

- Notes, programs and banks, volume, expression, pan, the sustain pedal, pitch bend (with its range), modulation (as a light vibrato), and GM/GS/XG resets.
- The bank's envelopes, loops and exclusive classes (a closed hi-hat cuts an open one).
- Up to 64 voices at once.
- **Reverb**: the song's average reverb level is stored with it. Such music plays through an "RPG Music Reverb" bus.

**Not rendered**: chorus, the bank's filters and LFOs, and pan changes in the middle of a note.

## Differences from RPG Maker

- **Tempo**: RPG Maker's MIDI *tempo* setting changes speed without changing pitch. In the kit, a sound's pitch setting changes both, as it does for OGG and WAV.
- The renders were checked by measurement (timing, pitch, levels). How they *sound* depends on the bank: GeneralUser GS sounds richer, `gm.dls` more like classic RPG Maker.
