# Dateiformate der Originaldaten

Status: ✅ an den echten Dateien geprüft · 🟡 bekannt, aber noch nicht geprüft · ❓ unbekannt

Alle Zahlen sind Little-Endian.

## Bestandsaufnahme (CD-Version, `ANNO1602/ANNO1602/`)

| Ordner / Datei | Inhalt | Anzahl |
|---|---|---|
| `GFX/`, `MGFX/`, `Sgfx/` | Spielwelt-Sprites in 3 Zoomstufen (`STADTFLD`, `SHIP`, `SOLDAT`, `TIERE`, `TRAEGER`, `MAEHER`, `EFFEKTE`, `NUMBERS`) | je 8 BSH |
| `ToolGfx/` | UI-Grafik (`START`, `TOOLS`, `BAUHAUS`, `BAUSHIP`, `SYMBOL` jeweils für 1024/800/640 px), Palette `STADTFLD.COL`, Fonts `ZEI*.ZEI` | 27 |
| `haeuser.cod`, `figuren.cod` | Gebäude- und Figurendefinitionen (verschlüsselter Text) | 2 |
| `Szenes/` | Szenarien und Endlosspiele als `.cod` | 36 |
| `Nord/`, `Sued/` | Inselvorlagen `lit/mit/med/big/large??.scp` (Nord- und Südklima) | 224 / 177 |
| `NORDNAT/`, `SUEDNAT/` | Inseln mit Eingeborenen | 41 / 56 |
| `GADDATA/` | UI-Layouts (`*.GAD`, Klartext) | 50 |
| `SAMPLES/` | Soundeffekte (WAV) | 98 |
| `Speech8/` | Sprachausgabe (WAV, nummeriert) | 473 |
| `MUSIC8/` | Musik (WAV) | 15 |
| `VIDEOSMK/` | Videos (Smacker `.smk`, `NNN.smk` und `NNNs.smk`) | 65 |
| `Game.dat`, `HIGHM.DAT`, `HIGHS.DAT` | Einstellungen (Klartext) und Highscores | 3 |
| `Savegame/` | Spielstände (`.gam`), auf der CD leer | 0 |

## Chunk-Container ✅

Diesen Container nutzen BSH, COL, ZEI, SCP und vermutlich auch die Savegames:

```
char[16]  name     // nullterminiert, Rest ist Müll (z. B. "BSH\0" + Speicherreste)
uint32    length   // Länge der Nutzdaten
uint8[length] data
```
Eine Datei besteht aus einer Folge solcher Chunks.

## BSH – Sprite-Archiv ✅

Ein Chunk `BSH`. Am Anfang der Nutzdaten steht eine Offset-Tabelle:

```
uint32 offsets[n]      // n = offsets[0] / 4, relativ zum Datenanfang
```
Jedes Bild ab `offset`:
```
uint32 width, height, type, length
uint8  rle[...]
```
RLE-Strom (zeilenweise, oben links beginnend):
- `0xFF` – Bildende
- `0xFE` – Zeilenende (x = 0, y += 1)
- sonst `n` transparente Pixel, dann Byte `m` und danach `m` Palettenindizes

Geprüft wurde das mit `GFX/STADTFLD.BSH` (5748 Bilder, Bodenkacheln 64×31, Gebäude wie die Windmühle 64×114) und `ToolGfx/START.BSH` (Startbildschirm 1024×768). Beide werden fehlerfrei dekodiert.

🟡 Was `type` bedeutet, ist noch offen. Bisher war der Wert immer 1.

## COL – Palette ✅

Ein Chunk `COL` mit 1024 Bytes, also 256 × (R, G, B, 0).

## ZEI – Bitmap-Font 🟡

Ein Chunk `ZEI` mit einer Offset-Tabelle wie bei BSH. Vermutlich ist pro Zeichen ein RLE-Bild abgelegt. Die Zuordnung zum Zeichensatz (CP-1252?) muss noch geprüft werden.

## COD – verschlüsselte Skripte ✅ (Verschlüsselung) / 🟡 (Grammatik)

Jedes Byte ist negiert: `klartext = (256 − b) & 0xFF`. Danach liegt deutscher Text in Latin-1/CP-1252 mit CRLF vor.

Bisher beobachtete Grammatik:
- Kommentare beginnen mit `;`
- Konstanten: `IDBODEN = 20101`, Ausdrücke wie `GFXTAFEL+1`
- Blöcke: `Objekt: NAME` … `EndObj;`, auch verschachtelt (z. B. `BGRUPPE` → `BGRUPPE_WARE`)
- Felder: `Nummer: 0`, `@Nummer: …` (relativ/inkrementierend?), `Ware: STOFFE, 0.6` (Listen)
- `ObjFill: 0,MAXGADGET` (Vorbelegung von Defaults)

`haeuser.cod` enthält u. a. die Bevölkerungsgruppen (`BGRUPPE`: Maxwohn, Steuer, Warenbedarf), ID-Bereiche (`IDBODEN`, `IDWALD`, `IDWOHN` …) und alle Gebäude mit Gfx-Index in `STADTFLD.BSH`. Die Szenarien in `Szenes/*.cod` beschreiben Ziele, Spieler und Inseln.

## GAD – UI-Layout ✅ (Klartext)

Unverschlüsselt, aber mit derselben Grammatik wie COD (`Objekt: GADGET`, `Blocknr`, `Gfxnr`, `Kind`, Positionen). Daraus lässt sich die Original-UI nachbauen.

## SCP – Insel ✅ (Container) / 🟡 (Felder)

Chunks:
- `INSEL3` (40 Bytes) – Inselkopf: Größe, Klima, Typ … (Felder noch zu entschlüsseln)
- `INSELHAUS` – Feldliste. 🟡 Laut mdcii-engine sind es 8-Byte-Einträge (Gebäude-ID, x, y, Rotation, Animationsstand …). Für `big00.scp` ergibt das 32672 / 8 = 4084 Einträge.

## Savegames `.gam` / `.szs` ❓

🟡 Vermutlich dieselben Chunks plus `INSEL5`, `KONTOR2`, `SHIP4`, `FIGUR`, `PRODLIST2`, `SPIELER`, `TIMERS` … Zum Prüfen brauchen wir einen Spielstand aus dem Original.

## WAV ✅ · SMK 🟡

WAV ist Standard-PCM. SMK ist Smacker Video, Version 2, das von FFmpeg und libsmacker dokumentiert ist.
