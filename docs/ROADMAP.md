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

## M2 – Eine Insel
- [ ] COD-Entschlüsselung und -Parser, `haeuser.cod` → Gebäudetabelle (ID → Gfx, Größe, Rotationen)
- [ ] SCP-Parser (`INSEL3`, `INSELHAUS`)
- [ ] Isometrischer Renderer: Kacheln, mehrfeldrige Gebäude, korrekte Tiefensortierung
- [ ] Kamera: Scrollen, 3 Zoomstufen, Drehen in 4 Richtungen

**Fertig, wenn** jede Inselvorlage aus `Nord/` und `Sued/` korrekt dargestellt wird.

## M3 – Lebendige Welt
- [ ] Animationen (Wasser, Bäume, Gebäude), Meer und Küsten
- [ ] Figuren aus `figuren.cod` (Träger, Tiere), Schiffe
- [ ] Soundeffekte und Musik
- [ ] Ein Szenario laden (`Szenes/*.cod`): Weltkarte mit mehreren Inseln

## M4 – Bauen
- [ ] UI-Grundgerüst nach `GADDATA` und `ZEI`-Fonts
- [ ] Baumenü, Platzierungsregeln, Straßen, Abriss
- [ ] Kontor, Einflussbereiche, Baukosten (Geld und Material)

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
- Bedeutung der `INSEL3`-Felder und der BSH-Bildtypen
- Wie Gebäudeteile mehrfeldriger Gebäude in `STADTFLD.BSH` angeordnet sind
- Ob diese CD die Königsedition ist (Datum 2001 → vermutlich ja). Dann müssten die Addon-Daten erkannt werden.
