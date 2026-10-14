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
