# Message codes

Codes in **Show Text** and the other message commands are replaced when the text appears. Where RPG Maker uses numbers, the kit uses **IDs**: `\V[apples]` rather than `\V[1]`.

## Built-in codes

| Code | Shows / does |
| --- | --- |
| `\V[id]` | The value of variable `id` |
| `\S[id]` | `ON` or `OFF`: the state of switch `id` |
| `\N[actor_id]` | The name of the actor, as it is now (after *Change Name*) |
| `\P[n]` | The name of party member *n* (1 is the leader) |
| `\G` | The currency unit (*Database > System*) |
| `\C[n]` | Text colour *n* from here on: 0 is normal, 1–15 the palette below |
| `\I[n]` | Icon *n* of the icon sheet, one character wide. Left out when *System > Show icons* is off or the icon doesn't exist |
| `\.` | Wait ¼ second |
| `\|` | Wait 1 second |
| `\!` | Wait until the player presses a key |
| `\\` | A backslash |

RPG Maker's `\>`, `\<`, `\$` and `\^` are accepted and ignored, so text pasted from RPG Maker doesn't show them.

### Colours for `\C[n]`

| n | Colour | n | Colour |
| --- | --- | --- | --- |
| 0 | white (normal) | 8 | dark grey |
| 1 | light blue | 9 | orange |
| 2 | light red | 10 | blue |
| 3 | light green | 11 | pink |
| 4 | yellow | 12 | lime |
| 5 | purple | 13 | gold |
| 6 | cyan | 14 | lavender |
| 7 | grey | 15 | black |

## Example

```
\C[4]\N[hero]\C[0] found \V[apples] apples\. and \G 50!
```

## Codes from plugins

With [Message codes plus](Plugins.md#message-codes-plus-message_plus):

| Code | Effect |
| --- | --- |
| `<wordwrap>`, `<nowrap>` | Word wrap on or off for this message |
| `<br>` | New line |
| `\{` `\}` | Text one step bigger / smaller |
| `\FS[n]`, `\FS[]` | Text size *n*; back to normal |
| `<b>`…`</b>`, `<i>`…`</i>` | Bold, italic |
| `\M[name]` | A text macro from the plugin's settings |
| `\NB[left]`, `\NB[center]`, `\NB[right]` | Where the speaker's name sits |

With [Letter sounds](Plugins.md#letter-sounds-letter_sounds): `\LS[off]`, `\LS[on]`, `\LS[file]`, `\LS[pitch:120]`, `\LS[volume:50]`, `\LS[]`.

## Your own codes

Extensions can add codes, tags and whole-text passes with `RPG.register_text_code`, `RPG.register_text_tag` and `RPG.register_text_preprocessor`. See [For programmers](For-Programmers.md#message-codes).
