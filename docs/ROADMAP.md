# Roadmap

Jeder Meilenstein endet mit etwas, das man sieht oder ausprobieren kann.

## M0 – Fundament ✅
- [x] `Package.swift` (Targets `AnnoFormats`, `anno-tool`, `AnnoFormatsTests`), Git-Repo, GPLv3
- [x] `GameData`: Spielordner finden (`--data`, `OPEN1602_DATA`, `./ANNO1602/ANNO1602`) und Pfade case-insensitive auflösen
- [x] `Chunk`, `Palette`, `BSH` inkl. Tests gegen die Originaldateien
- [x] `anno-tool export-bsh <datei> | --all` → PNGs, `anno-tool info`

**Ergebnis:** Alle 37 BSH-Dateien mit zusammen 48 380 Bildern werden fehlerfrei exportiert, 8 davon sind leer (0×0). Die anderen Targets aus [ARCHITEKTUR.md](ARCHITEKTUR.md) kommen mit ihren Meilensteinen dazu.

## M1 – Erstes Bild ✅
- [x] macOS-App `Open1602` (AppKit, `MTKView`, Retina, Vollbild mit ⌃⌘F)
- [x] Palettenshader: Sprites liegen als `rg8Uint` (Index + Deckkraft) auf der GPU, die Palette wird im Fragment-Shader angewendet
- [x] Sprite-Atlas aus BSH (Shelf-Packing, 4096er-Seiten): `STADTFLD.BSH` braucht wenige Seiten
- [x] Startbildschirm (`START.BSH`) anzeigen, seitenverhältnistreu skaliert
- [x] Sprite-Viewer (Tab): ←/→ Bild, ⇧ für 10er-Schritte, Bild↑/↓ für 100er-Schritte, ↑/↓ Datei, +/− Zoom
- [x] Spielordner: `--data`, `OPEN1602_DATA`, `./ANNO1602/ANNO1602`, gespeicherter Pfad, sonst Auswahldialog
- [x] `--snapshot DATEI [--viewer BSH --image N]` rendert offscreen ein PNG (für Tests und Bug-Reports)

**Ergebnis:** Der GPU-Renderer gibt den Startbildschirm pixelgenau wie die CPU-Dekodierung aus. Ein Offscreen-Test vergleicht dafür jedes Pixel.

## M2 – Eine Insel ✅
- [x] COD-Entschlüsselung und -Parser: `haeuser.cod` (491 Gebäude) und `figuren.cod` (96 Figuren) ohne unverstandene Zeilen
- [x] Gebäudetabelle (ID → Grafik, Größe, Drehungen, Animation, Höhe)
- [x] SCP-Parser (`INSEL3/4/5`, `INSELHAUS`), besiedelte Varianten auf ihre Basisvorlage gelegt
- [x] Isometrischer Renderer: Kacheln, mehrfeldrige Gebäude, Höhen, korrekte Zeichenreihenfolge (ein Draw-Call über alle Atlasseiten)
- [x] Kamera: Scrollen (Pfeiltasten, Ziehen, Trackpad), 3 Zoomstufen (+/−), Drehen in 4 Richtungen (R / ⇧R), Inselwechsel (N/P)

**Ergebnis:** Alle 401 Inseln aus `Nord/` und `Sued/` gehen vollständig, ohne unbekannte IDs und mit gültigen Bildindizes auf, inklusive besiedelter Varianten mit Städten. Ausnahme: `big13s19.scp` passt nicht zu seiner Basis (30×30 statt 70×60).

**Offen für später:** Inseln in `NORDNAT/` und `SUEDNAT/` (Eingeborene) und die Szenario-Syntax in `Szenes/*.cod`.

## M3 – Lebendige Welt ✅
- [x] Spielschleife (60 fps) mit Animationen nach `AnimTime` (Meer, Brandung, Flüsse, Gebäude)
- [x] Szenarien (`Szenes/*.cod`): Weltkarte 500×350 mit zufällig gewählten Inselvorlagen (deterministischer Startwert), feste Vorlagen in Tutorials/Kampagnen, Eingeborenen-Inseln (`NORDNAT/`, `SUEDNAT/`)
- [x] Gemeinsamer Atlas für Gelände, Schiffe und Tiere; Figuren werden in Tiefenreihenfolge zwischen die Kacheln einsortiert
- [x] Startschiffe der Spieler (`SZENE_SHIP`/`Shippos`) mit Ausrichtung, die sich mit der Kamera dreht
- [x] Hirsche aus `HIRSCH2` ziehen über die Inseln (laufen und grasen)
- [x] Musik aus `MUSIC8/` (zufällige Reihenfolge, M), Umgebung: Wellen je nach Meeranteil, Vogelrufe über Land (S)
- [x] Nur der sichtbare Ausschnitt wird gezeichnet (Culling)

**Ergebnis:** Alle 87 Skriptdateien (Gebäude, Figuren, 36 Szenarien, 49 UI-Layouts) werden vollständig geparst. Endlosspiele und Szenarien erzeugen spielbereite Welten.

**Offen für später:** Träger und Marktkarren (brauchen die Wirtschaft, M5), fahrende Schiffe (M6), Spielerfarben der Schiffe und Flaggen, Soundeffekte von Gebäuden.

## M4 – Bauen ✅
- [x] Neues Modul `AnnoSim`: Spielstand (Spieler, Siedlungen, Lager) und Bauregeln, ohne Darstellung
- [x] Bauleiste nach `GADDATA/BAU.GAD` mit Originalgrafiken (TOOLS, BAUHAUS) und ZEI-Schrift: 8 Kategorien, Gebäude blättern, Kosten
- [x] Minikarte mit Sichtrahmen (Klick springt), Statuszeile mit Geld und Inselvorrat
- [x] Bauvorschau grün/rot, Drehen (`,` `.`), Straßen ziehen mit automatischer Form, Abreißen (D)
- [x] Kontor an der Küste: Erstes Kontor baut aus der Schiffsladung, der Rest wird ins Kontor entladen; Einflussbereich
- [x] Platzierungsregeln: freier Boden (Bäume werden gerodet), Strand (Fischerei, Steg), Berghang (Minen), Fluss (Brücken), fremdes Gebiet
- [x] Baukosten aus `HAUS_BAUKOST` (Geld, Holz, Werkzeug, Ziegel), Zufallsvarianten (`RandAnz`) beim Bauen

**Ergebnis:** Man kann auf einer Zufallswelt ein Kontor gründen und eine erste Siedlung mit Wohnhäusern, Wegen und Betrieben bauen.

**Vereinfachungen/offen:**
- Kontor-Radius geschätzt (13 Felder, `RADIUS_HQ` steht nicht in den Daten)
- Gebäudenamen aus `Language.dll` fehlen noch (Platzhalter aus den Daten)
- Kein Abrissrückgewinn
- Werft und Steg: Regeln vereinfacht
- Marktplatz fehlt (keine Baukosten in `haeuser.cod`?)
- Die Hauptschalter oben in der Leiste haben noch keine Funktion

## M5 – Wirtschaft (Kern des Spiels)
- [ ] Produktionsketten (Holz, Fisch, Stoffe, Alkohol …), Lager, Marktkarren
- [ ] Bevölkerungsstufen Pioniere → Siedler → Bürger → Kaufleute → Aristokraten
- [ ] Bedürfnisse, Zufriedenheit, Steuern, Betriebskosten
- [ ] Spielgeschwindigkeit und Tick-Timing wie im Original (Messung am Original nötig)

**Fertig, wenn** ein Endlosspiel bis zu den Kaufleuten spielbar ist.

## M6 – Seefahrt und Handel
- [ ] Schiffe steuern, Pathfinding auf See, Handelsrouten
- [ ] Freie Händler, Kontorhandel, Piraten
- [ ] Neue Inseln besiedeln

## M7 – Gegner und Militär
- [ ] Computergegner (Wirtschafts-KI), Diplomatie
- [ ] Soldaten, Burgen, Kriegsschiffe, Belagerung
- [ ] Eingeborene, Katastrophen (Vulkan, Pest, Feuer, Dürre)

## M8 – Vollständigkeit
- [ ] Szenarien mit Siegbedingungen, Tutorials, Videos (SMK) und Sprachausgabe
- [ ] Laden und Speichern (eigenes Format, später auch Original-`.gam` importieren)
- [ ] Hauptmenü, Optionen, Highscores

## M9 – Installation über Homebrew
- [ ] Release-Builds für arm64 über CI (GitHub Actions), versionierte Tags
- [ ] App-Bundle signieren und notarisieren
- [ ] Eigener Tap `breichr/homebrew-tap` mit Cask für `Open1602.app` und Formula für `anno-tool`
- [ ] Beim ersten Start nach dem Spielordner fragen und den Pfad merken. Originaldaten sind nie Teil des Pakets.
- [ ] Später: Aufnahme in das offizielle `homebrew/cask`, sobald das Projekt die Kriterien erfüllt (Bekanntheit, stabile Releases)

**Fertig, wenn** folgende Befehle eine startfähige App installieren:
```bash
brew tap breichr/tap
brew install --cask open1602
```

## Später
- Multiplayer (Lockstep, deterministische Simulation)
- Anno 1602 *Königsedition* bzw. das Addon *Neue Inseln, neue Abenteuer*
- Portierung auf Linux/Windows
- Komfort: freier Zoom, UI-Skalierung, Statistiken, Mod-Support

## Offene Fragen
- Original-Tickrate und Zeitmodell der Simulation
- Restliche Felder in `INSEL3/4/5` (Klima, Vorlagennummer?) und Bedeutung der BSH-Bildtypen
- Welche Basis `Nord/big13s19.scp` und `SUEDNAT/BIG15.SCP` haben (beide 30×30)
- Bedeutung von `Posoffs` bei Figuren (Ankerpunkt der Bilder) und der Felder in `HIRSCH2` ab Byte 3
- Ob diese CD die Königsedition ist (Datum 2001 → vermutlich ja). Dann müssten die Addon-Daten erkannt werden.
