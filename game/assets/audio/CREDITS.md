# Sound credits

## Kenney — CC0 (public domain)

Most of the bank comes from four of Kenney's audio packs, all released under
**Creative Commons CC0**: no attribution is required and there is no licence risk. It is
recorded here anyway, because knowing where a file came from is worth more than the
licence obliging you to say it.

| pack | used for |
|---|---|
| [Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds) | repulsors, the shoulder turret, the boost, the engine note, explosions, the RPG launch |
| [Impact Sounds](https://kenney.nl/assets/impact-sounds) | punches, metal hits, landings, footsteps, bodies dropping |
| [RPG Audio](https://kenney.nl/assets/rpg-audio) | the cloth whoosh behind dodges and swings, the knife draw |
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) | menu movement, selection, opening and closing |

**Deliberately not used: `confirmation_001.ogg`.** Jurek dislikes it and it had been
pasted onto every success in every project. `bong_001` stands in for selection.

## Written for this game

Four sounds had no honest match in any pack, so they are synthesised — short Python
scripts writing raw PCM, no dependencies and no licence question at all.

| file | why it is not from a pack |
|---|---|
| `thwip.wav` | Nobody ships a web-shooter. It is filtered noise for the pressurised hiss plus a tone falling two octaves for the line paying out. |
| `gunshot.wav`, `gunshot_rifle.wav` | Kenney has no firearms, and a sci-fi laser tells the player the wrong thing about who is shooting at him. A noise transient, a 95 Hz body thump and a short room tail. |
| `lock_beep.wav` | An 85 ms sine with a hard attack, for the rocket lock. Pitched and repeated faster as it closes. |

The generators live with the sounds in the commit history; they are a few dozen lines
each and deliberately not kept as build steps, because these files will never need
regenerating.
