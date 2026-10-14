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

Ein Export aller 37 Dateien ergab 48 380 Bilder. 8 davon sind leer (0×0, in `Start6.bsh` und `TOOLS6.BSH`).

🟡 Was `type` bedeutet, ist noch offen. Bisher war der Wert immer 1.

## COL – Palette ✅

Ein Chunk `COL` mit 1024 Bytes, also 256 × (R, G, B, 0).

## ZEI – Bitmap-Font ✅

Ein Chunk `ZEI` mit einer Offset-Tabelle wie bei BSH, ein RLE-Bild pro Zeichen.
- **Zeichenbereich:** 224 Zeichen für die Codes 32–255 (Latin-1). `ZEI24V`/`ZEI28V` haben nur 33 Zeichen, vermutlich Ziffern.
- **Laufweite:** Die Breite im Kopf ist die Laufweite. Für Unterschneidungen ragen manche Zeichen 1 bis 3 Pixel darüber hinaus.

## GAD – Bauleiste (`BAU.GAD`) ✅

Positionen relativ zur 256 Pixel breiten Leiste rechts. Bildnummern in `TOOLS.BSH`:
- **Kategorien:** 22–29 (gewählt 31–38) bei y = 623/692. Reihenfolge: Militär, Wege, Bergbau, Handwerk, Öffentlich, Farmen, Hafen, Wohnhäuser.
- **Blättern:** Pfeile 40/41.
- **Titel:** Titelleiste 172 bei (6, 354).
- **Gebäudesymbol:** `BAUHAUS.BSH[Baugfx]` im Feld (48, 390, 160×110).
- **Kostensymbole:** 46 Geld, 47 Ziegel, 48 Werkzeug, 49 Holz, 52 Betriebskosten, bei y = 564/594.

Welche Gebäude in welcher Kategorie stehen, steht nicht in den Daten. Open1602 leitet es aus der ID-Gruppe ab (`Id / 100`).

## COD – verschlüsselte Skripte ✅

Jedes Byte ist negiert: `klartext = (256 − b) & 0xFF`. Danach liegt deutscher Text in Latin-1 mit CRLF vor. Implementiert in `Sources/AnnoFormats/COD.swift`.

Grammatik (zeilenweise, `;` leitet Kommentare ein):
- `NAME = Ausdruck` setzt eine Variable. Ausdrücke bestehen aus Zahlen, Variablen und `+`/`−`, zum Beispiel `GFXHANG = GFXBODEN+432`. Sie dürfen Felder des aktuellen Eintrags nennen (`HAUSWACHS = Nummer`).
- `@NAME = +n` erhöht eine Variable.
- `Objekt: NAME` … `EndObj;` öffnet auf oberster Ebene eine Sammlung (`HAUS`, `FIGUR`, `BGRUPPE`), sonst ein Unterobjekt des aktuellen Eintrags (`HAUS_PRODTYP`, `HAUS_BAUKOST`).
- `Feld: Wert, Wert …` setzt ein Feld. `Nummer:` beginnt einen neuen Eintrag. Symbolische Nummern wie `INFRA_WIRT` sind Programmkonstanten und werden fortlaufend vergeben.
- `@Feld: +n` / `@Feld: −n` gilt relativ zum vorherigen Eintrag. Ohne Vorzeichen ist der Wert absolut.
- `ObjFill: 0, MAXHAUS` macht den aktuellen Eintrag zur Vorlage für alle weiteren.
- `ObjFill: n` kopiert Eintrag `n` in den aktuellen.

`haeuser.cod` (Sammlung `HAUS`), Felder für die Darstellung:

| Feld | Bedeutung |
|---|---|
| `Id` | 20000 + ID in den Inseldateien |
| `Gfx` | erstes Bild in `STADTFLD.BSH` |
| `Size` | Grundriss w, h |
| `Rotate` | Bilder pro Drehrichtung (0 = nicht drehbar; 9 bei 3×3 …) |
| `AnimAnz`, `AnimAdd` | Animationsschritte und Bildabstand zwischen ihnen |
| `Posoffs` | Höhe über dem Meer in Pixeln (GFX; MGFX/SGFX halbiert) |
| `RandAnz`, `RandAdd` | Zufallsvariante **der ID** beim Bauen (z. B. 11 Baumarten mit ID-Abstand 2), nicht der Grafik |

Bildindex eines Feldes: `Gfx + Drehung·Rotate + Animation·AnimAdd + Teil`. `Teil` ist der Versatz `(dx, dy)` im gedrehten Grundriss, zurückgerechnet in die zeilenweise Anordnung (siehe `BuildingType.spriteIndex`). Blickrichtungen der Kamera addieren sich zur Drehung des Feldes.

Werte in Anführungszeichen sind Texte. Flags wie `INFRA_WIRT | INFRA_ARZT` und Ausdrücke mit Programmkonstanten (`32-Pos[0]`) bleiben symbolisch.

### Szenarien (`Szenes/*.cod`) ✅

Die Sammlung `SZENE` enthält `Name`, `Size` (Welt 500×350), `Money`, `Natives: NORD, 2` und `Text` sowie zwei Unterobjekte:
- `SZENE_SHIP` mit je Spieler `Playernr`, `Figurnr` (z. B. `HANDEL1`), `Ausricht` (Richtung 0–7) und Waren.
- `SZENE_WELT` mit mehreren Weltvarianten, getrennt durch `Nummer`. Jede Variante hat:
  - `Shippos: Spieler, x, y`
  - `Insel: Größe, x, y [, NORD|SUED [, Nummer [, "Variante"]]]`

Größe 0–4 entspricht `lit`, `mit`, `med`, `big`, `large`. Ohne Nummer wählt das Spiel eine zufällige Basisvorlage. Mit Nummer ist die Vorlage fest, zum Beispiel `Nord/lit16b.scp` oder `Nord/big01s16.scp`. 7 der 214 festen Verweise fehlen auf der CD.

### Figuren (`figuren.cod`) 🟡

Die Sammlung `FIGUR` mit symbolischen Nummern (`HANDEL1`, `HIRSCH` …) hat die Felder `Gfx` (Bild im Archiv `Blocknr`: 2 = `SHIP.BSH`, 5 = `TIERE.BSH`), `Rotate` und `Posoffs`. Unterobjekte `ANIM` enthalten mehrere Animationen mit `AnimOffs`, `AnimAnz`, `AnimSpeed` (ms) und `Kind` (`ENDLESS`, `RANDOM` …).
- **Schiffe:** 8 Richtungen hintereinander. Beschädigte Schiffe liegen 8 Bilder dahinter.
- **Hirsch:** 8 Richtungen à 8 Laufbilder, ab +112 je 6 Grasbilder.
- **Richtungen:** 0 = rechts oben, dann im Uhrzeigersinn.

## GAD – UI-Layout ✅ (Klartext)

Unverschlüsselt, aber mit derselben Grammatik wie COD (`Objekt: GADGET`, `Blocknr`, `Gfxnr`, `Kind`, Positionen). Daraus lässt sich die Original-UI nachbauen.

## SCP – Insel ✅

Chunks:
- `INSEL3`, `INSEL4` oder `INSEL5` (40 bzw. 116 Bytes). Byte 0: Inselnummer, Byte 1: Breite, Byte 2: Höhe, ab Byte 4 `UInt16` x und `UInt16` y auf der Weltkarte. Die restlichen Felder sind noch offen (🟡).
- `INSELHAUS`: 8-Byte-Einträge `UInt16` Gebäude-ID (`Id − 20000`), `UInt8` x, `UInt8` y, `UInt32` Bitfeld mit Drehung (Bits 0–1), Animationsschritt (2–5), unbekannt (6–13), Status (14–16), Zufall (17–21) und Spieler (22–24). Mehrfeldrige Gebäude stehen nur einmal an ihrer Ursprungsecke.
- Besiedelte Varianten (`big01s16.scp`, `big25b.scp`) enthalten zusätzlich `KONTOR2`, `STADT4`, `MARKT2`, `PRODLIST2` usw. Ihr `INSELHAUS` enthält nur die Gebäude, das Gelände stammt aus der Basisvorlage (`big01.scp`, `big25.scp`).

Darstellung: Kacheln 64×31 (GFX), 32×15 (MGFX), 16×7 (SGFX). Ein Feld (sx, sy) im gedrehten Raster liegt bei x = (sx − sy)·w/2, y = (sx + sy)·h/2. Bilder sind an der Kachelunterkante ausgerichtet und um `Posoffs` angehoben. Gezeichnet wird diagonal von hinten nach vorne.

## HIRSCH2 (in Inseln) 🟡

Einträge à 8 Byte: Inselnummer, x, y, dann Unbekanntes (`UInt16` 0x0561 – Zähler?).

## Savegames `.gam` / `.szs` ❓

🟡 Vermutlich dieselben Chunks plus `INSEL5`, `KONTOR2`, `SHIP4`, `FIGUR`, `PRODLIST2`, `SPIELER`, `TIMERS` … Zum Prüfen brauchen wir einen Spielstand aus dem Original.

## WAV ✅ · SMK 🟡

WAV ist Standard-PCM. SMK ist Smacker Video, Version 2, das von FFmpeg und libsmacker dokumentiert ist.
