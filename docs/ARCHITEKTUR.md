# Architektur

## Tech-Stack

**Vorgabe:** nativ auf Apple Silicon.

| Bereich | Wahl | Begründung |
|---|---|---|
| Sprache | **Swift 6** (strict concurrency) | Nativ auf Apple Silicon, speichersicher, schnell genug für ein 2D-Spiel von 1998. Swift 6.4 ist installiert. |
| Build | **Swift Package Manager** | Funktioniert mit den Command Line Tools. Xcode ist optional und nur zum Debuggen von Metal-Frames nötig. |
| Grafik | **Metal** über MetalKit (`MTKView`) | Native GPU-API. Shader werden zur Laufzeit per `makeLibrary(source:)` kompiliert, dafür braucht es kein Xcode. |
| Fenster/Input | **AppKit** | Ein Fenster, Maus und Tastatur, Retina, Vollbild. |
| Audio | **AVAudioEngine** | WAV-Wiedergabe (Samples, Sprache, Musik), Mixing, 3D-Panning nach Kartenposition. |
| Video | Smacker-Decoder (eigener Swift-Port oder `libsmacker`, LGPL) | Für die Intro- und Missionsvideos (`.smk`). |
| Tests | **swift-testing** | Formatparser werden gegen die echten Originaldateien getestet. |

**Verworfene Alternative:** ein portabler C++20-Kern mit SDL wie bei OpenMW. Den würde man nur dann wieder aufgreifen, wenn Linux/Windows früh wichtig werden. Bis dahin halten wir `AnnoFormats` und `AnnoSim` frei von Apple-Frameworks (nur Swift-Standardbibliothek und `Foundation`). Damit bleibt ein späterer Port offen, weil Swift auch auf Linux und Windows läuft.

## Module (SwiftPM-Targets)

```
open1602/
├── Package.swift
├── Sources/
│   ├── AnnoFormats/     # reine Parser, keine Grafik/Audio-Abhängigkeit
│   │   ├── Chunk.swift        # 16-Byte-Name + UInt32-Länge (BSH, COL, ZEI, SCP, Savegames)
│   │   ├── Palette.swift      # STADTFLD.COL
│   │   ├── BSH.swift          # Sprite-Archive, RLE-Dekodierung → indiziertes Bild
│   │   ├── ZEI.swift          # Bitmap-Fonts
│   │   ├── COD.swift          # Entschlüsselung + Parser für haeuser/figuren/Szenarien
│   │   ├── GAD.swift          # UI-Layoutbeschreibungen (Klartext)
│   │   ├── Island.swift       # .scp: INSEL3/INSELHAUS
│   │   └── GameData.swift     # Spielordner-Auflösung (case-insensitive!)
│   ├── AnnoSim/         # deterministische Spielsimulation, kein Rendering
│   │   ├── World.swift        # Karte, Inseln, Felder
│   │   ├── Buildings.swift    # Gebäudetypen aus haeuser.cod
│   │   ├── Economy.swift      # Produktionsketten, Lager, Märkte
│   │   ├── Population.swift   # Bevölkerungsstufen, Bedürfnisse, Steuern
│   │   ├── Units.swift        # Träger, Schiffe, Soldaten (figuren.cod)
│   │   ├── Pathfinding.swift
│   │   ├── AI.swift           # Computergegner, freie Händler, Piraten
│   │   └── Scenario.swift     # Siegbedingungen, Szenario-Skripte
│   ├── AnnoRender/      # Metal: Sprite-Atlanten, Isometrie, Zoomstufen
│   ├── AnnoAudio/
│   ├── AnnoUI/          # Spiel-UI nach GAD-Layouts
│   ├── Open1602/        # App (AppKit, Main Loop)
│   └── anno-tool/       # CLI: Sprites/Inseln exportieren, COD dumpen
└── Tests/
    ├── AnnoFormatsTests/
    └── AnnoSimTests/
```

Abhängigkeiten gehen nur nach unten: `Open1602 → AnnoUI/AnnoRender/AnnoAudio → AnnoSim → AnnoFormats`.

## Kernentscheidungen

### Simulation und Darstellung sind getrennt
- `AnnoSim` läuft mit **festem Tick** (Ziel: Original-Tickrate, noch zu ermitteln) und ist deterministisch. Das braucht man für Replays, Tests und später für Multiplayer im Lockstep.
- Der Renderer liest den Zustand nur und interpoliert Animationen. Die Framerate ist von der Spielgeschwindigkeit entkoppelt.

### Palettenbilder bleiben auf der GPU indiziert
- BSH-Sprites werden als 8-Bit-Index-Texturen (`r8Uint`) in Atlanten gepackt. Die Palette wird im Fragment-Shader angewendet.
- Damit funktionieren Spielerfarben, Palettenanimation (z. B. Wasser) und Effekte wie im Original, ohne Sprites mehrfach zu speichern.
- Die drei Zoomstufen (`GFX` 64×31, `MGFX` 32×15, `Sgfx` 16×7 pro Kachel) werden direkt aus den Originaldateien geladen. Später ist ein freier Zoom per Skalierung denkbar.

### Daten kommen aus den Originaldateien statt aus dem Code
- Gebäude, Figuren, Waren und Szenarien stammen aus den `.cod`-Dateien. Im Code stehen keine Werte wie „Fischerhütte kostet X“.
- Der COD-Parser liefert einen generischen Objektbaum. Typisierte Sichten (`BuildingType` usw.) bauen darauf auf.

### Pfade werden case-insensitive aufgelöst
- Die Originaldaten mischen die Schreibweisen (`Stadtfld.bsh`, `STADTFLD.BSH`, `Sgfx`, `MGFX`). `GameData` indiziert den Ordner einmal und löst Pfade ohne Rücksicht auf Groß- und Kleinschreibung auf. Das ist nötig, falls jemand ein case-sensitives Volume nutzt.

## Rechtlicher Rahmen

- Es kommen keine Originaldaten ins Repository. Auch Testfixtures sind nur Verweise auf Dateien im Spielordner und werden übersprungen, wenn der Ordner fehlt.
- Formatwissen stammt aus der Analyse der Dateien und aus öffentlicher Doku (z. B. *mdcii-engine*). Code aus `1602.EXE` wird weder kopiert noch disassembliert übernommen. Spielverhalten wird beobachtet und nachgebaut.
- Lizenz-Vorschlag: **GPLv3** wie bei OpenMW und OpenGothic.
