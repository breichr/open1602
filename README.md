# open1602

Eine freie Neuimplementierung der Engine von **Anno 1602 – Erschaffung einer neuen Welt** (Sunflowers/Max Design, 1998)

Das Projekt enthält **keine** Originaldaten. Grafiken, Sounds, Inseln und Szenarien werden zur Laufzeit aus einer legal erworbenen Kopie des Spiels geladen (CD- oder GOG-Version).

## Ziele

- Läuft nativ auf Apple Silicon (arm64, Metal). Weitere Plattformen kommen später in Frage.
- Lädt die Originaldaten unverändert und spielt sich wie das Original.
- Moderne Komfortfunktionen: beliebige Auflösungen, Retina, Zoom, Fenstermodus.
- Einfach zu installieren über Homebrew (`brew install --cask breichr/tap/open1602`).
- Sauber getrennter Kern (Formate und Simulation), den man testen kann.

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [docs/ARCHITEKTUR.md](docs/ARCHITEKTUR.md) | Tech-Stack, Modulaufteilung, Datenfluss |
| [docs/FORMATE.md](docs/FORMATE.md) | Dateiformate der Originaldaten (verifiziert / offen) |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Meilensteine von „Sprites anzeigen“ bis „spielbar“ |

## Originaldaten

Die Engine erwartet den Spielordner, also das Verzeichnis mit `1602.EXE`, `haeuser.cod`, `GFX/` und weiteren Inhalten. Lokal liegt er für die Entwicklung unter `ANNO1602/ANNO1602/`. Er ist per `.gitignore` ausgeschlossen und **darf nie committet werden**.

## Bauen und ausprobieren

Voraussetzung: Swift 6 (Xcode oder Command Line Tools) auf macOS 14+.

```bash
swift build -c release
swift test
.build/release/anno-tool info
.build/release/anno-tool export-bsh --all --out export
.build/release/Open1602
```

In der App wechselt **Tab** zwischen Startbildschirm, Welt, Inselansicht und Sprite-Viewer.

- **Welt:** ein Endlosspiel bzw. Szenario mit Inseln, Schiffen und Tieren. N/P wechselt das Szenario, G erzeugt eine neue Zufallswelt.
- **Bauen:** Kategorie in der Leiste rechts wählen, mit den Pfeilen (oder `[` `]`) blättern und auf die Karte klicken. Zuerst ein Kontor an die Küste setzen. Straßen zieht man mit gedrückter Maustaste. `,` und `.` drehen das Gebäude, D schaltet auf Abreißen, Rechtsklick oder Esc bricht ab. Die Karte verschiebt man durch Ziehen (ohne Werkzeug), mit Rechts-Ziehen, über das Trackpad oder per Klick in die Minikarte.
- **M / S:** Musik bzw. Umgebungsgeräusche an und aus.
- **Inselansicht:** Pfeiltasten, Ziehen oder Trackpad scrollen. +/− wechselt die Zoomstufe, R/⇧R dreht den Blick, N/P wechselt die Insel.
- **Sprite-Viewer:** ←/→ blättern durch die Bilder, ↑/↓ wechseln die Datei, +/− zoomen.

Hinweis für Builds ohne Xcode: Swift 6.4 aus den Command Line Tools findet das Makro-Plugin von swift-testing sporadisch nicht. `Package.swift` gibt den Plugin-Pfad deshalb explizit mit.

Den Spielordner findet die Engine über `--data DIR`, die Umgebungsvariable `OPEN1602_DATA` oder unter `./ANNO1602/ANNO1602`.

## Lizenz

GPLv3, siehe [LICENSE](LICENSE).
