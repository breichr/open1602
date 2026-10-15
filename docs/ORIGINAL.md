# Beobachtungen am Original

Notizen aus Gameplay-Videos der Originalversion (1024×768). Sie dienen als Referenz für das Verhalten und die Oberfläche, wo die Daten selbst nichts sagen. Die Videos liegen lokal in `videos/` und sind nicht Teil des Repos.

## Bildschirmaufbau

- **Spielfeld:** links, 768×768 bei 1024×768.
- **Leiste:** rechts, 256 Pixel breit (TOOLS #0).
- **Statuszeile oben:** Geld, Werkzeug, Holz, Ziegel und Einwohner, über die Breite verteilt. Im Baumodus stehen die Kosten des gewählten Gebäudes in Klammern dahinter, z. B. `30 (4)`.
- **Leiste unten:** ein Pergamentstreifen. Er zeigt rechts den Namen des Objekts unter der Maus, z. B. „Forsthaus“ oder „Marktplatz“. Links erscheinen Hinweise, z. B. „Geeignet für: Tabak: 50 % – Weintrauben: 100 % – Zuckerrohr: 50 %“ (Fruchtbarkeit der Insel).

## Rechte Leiste (von oben)

1. **Minikarte:** eine Pergamentkarte (TOOLS #17, 186×160) mit braunen Inselsilhouetten. Spielerbesitz ist als farbige Markierung eingetragen (blau, rot …), Schiffe als Punkte. Ein Nordpfeil steht oben links.
2. **Kompass und Lupe:** in TOOLS #0 enthalten. Damit dreht und zoomt man.
3. **Hauptschalter:** Bauen, Kampf, Status, Optionen (TOOLS #9–12, gedrückt #13–16, gewählt mit gelbem Rahmen).
4. **Titelleiste:** TOOLS #172 mit dem Namen der Auswahl. Das ist das gewählte Gebäude oder die Siedlung (z. B. „Florinz“), mit kleinem Symbol rechts.
5. **Inhalt je nach Modus:**
   - **Bauen** (`BAU.GAD`):
     - Gebäudesymbol (BAUHAUS) mit Pfeilen links und rechts. Die Pfeile **drehen** das Gebäude, das „X“ (TOOLS #42) schaltet auf **Abreißen**.
     - Darunter die Produktion als Warensymbol(e), z. B. Wolle → Stoff.
     - Kosten: Geld und rote Betriebskosten, in der Reihe darunter Werkzeug, Holz, Ziegel und Kanonen.
     - Ganz unten 8 Kategorien in 2 Reihen.
     - Ein Klick auf eine Kategorie öffnet ein **Popup** über der oberen Kategoriereihe. Es ist ein grauer Kasten (TOOLS #81–84) mit kleinen Gebäudebildern (TOOLS #86–166). Das gewählte Bild ist gelb umrandet (#85), gesperrte Gebäude zeigen „?“ (#123). Das Raster hat bis zu 3×4 Felder.
   - **Status** (Spielerstatus): Einwohner, Steuererträge, Betriebskosten, Heereskosten, Verkaufserlöse, Einkaufskosten, Bilanz (grün/rot) und Punkte. Darunter stehen drei Schalter: Stadt-, Schiffs- und Missionsinfo.
   - **Haus anklicken:** Porträt und „Anzahl Stufe“ (z. B. „23 Pioniere“, „56 Siedler“), Steuerregler mit Prozent und Ertrag, die geforderten Waren als Symbole, ein senkrechter Zufriedenheitsbalken und unten „Nahrung“ mit eigenem Balken.
   - **Kontor anklicken:** Warenraster der Insel (blätterbar). Darunter Handel mit dem Schiff am Kontor: Pfeile und Mengen 1/5/10/50, Name des Schiffs (z. B. „Enterprise“), 4 Laderaumfelder.
   - **Betrieb anklicken:** Name, Symbol, Auslastung in % und Betriebskosten.
   - **Optionen:** Auflösung (640×480, 800×600, 1024×768), Speichern/Laden usw.

## Bauen

- Außerhalb des eigenen Einflussbereichs wird die Karte abgedunkelt.
- Der Radius des geplanten Kontors oder Marktplatzes erscheint als gelbe gepunktete Linie. Gemessen sind es ≈ 16 bzw. 17 Felder.
- Die Bauvorschau ist eine sandfarbene Silhouette.
- Das Kontor steht direkt an der Küste, sein Steg ragt zum Wasser.

## Spielverlauf (Folge 1–2, Szenario „Nach langer Reise“)

- **Start:** Ein Handelsschiff, das erste Kontor heißt „Kontor I“. Siedlungen und Schiffe haben Namen, z. B. „Honnaver“, „Batzdorf“, „Florinz“ bzw. „Drake“, „Enterprise“.
- **Erste Gebäude:** Marktplatz, Forsthaus, Fischerhütte, Jagdhütte, Schaffarm, Webstube, Kapelle, Wohnhäuser („Haus“), Feldwege.
- **Bevölkerung:** Ab etwa 50–100 Einwohnern steigen Pioniere zu Siedlern auf. Siedler wollen zusätzlich zu Nahrung auch Stoffe und eine Kapelle.
- **Bilanz:** Am Anfang ist sie negativ (−15 … −50), sie dreht mit wachsenden Steuern ins Plus.

## Externe Referenzen (für M5, gegen `haeuser.cod` zu prüfen)

### Baukosten

Eine Gebäudeliste von spieletipps/GIGA, vom Nutzer eingefügt, stimmt bei 22 von 24 Stichproben mit `haeuser.cod` überein. Verglichen wurden Geld, Holz, Ziegel, Werkzeug und Betriebskosten. Abweichungen:
- **Theater:** Werkzeug 2 in der Liste, 6 in den Daten.
- **Große Werft:** Ziegel 63 in der Liste, 6 in den Daten.

Maßgeblich sind die Daten der CD.

### Freischaltung

Die Freischaltung nach Einwohnern ist ein Programmwert. In `haeuser.cod` stehen nur die Stufen (`Bauinfra: INFRA_STUFE_…`). Laut der Liste:

| Stufe | Einwohner | Gebäude |
|---|---|---|
| Pioniere | 30 | Rinderfarm, Fleischerei |
| Siedler | 15 | Pflasterstraße, Steinbrücke, Steinbruch, Steinmetz, Feuerwehr |
| Siedler | 30 | Palisade, Holztor, Kontor II |
| Siedler | 40 | Tabak-, Zuckerrohr- und Gewürzplantage, Tabakwaren, Rumbrennerei |
| Siedler | 50 | Wirtshaus |
| Siedler | 75 | Getreidefarm, Getreidemühle, Bäckerei |
| Siedler | 100 | Werkzeugschmiede, Schule |
| Siedler | 120 | Erzmine, Erzschmelze, kleine Werft |
| Siedler | 200 | Wachtürme, Mauer, Tore, Burg, Platz I, Schwertschmiede |
| Bürger | 50 | Arzt |
| Bürger | 100 | Kontor III, Galgen |
| Bürger | 150 | Goldmine, Kirche |
| Bürger | 200 | Baumwollplantage, Weberei, Schneiderei |
| Bürger | 210 | Badehaus |
| Bürger | 250 | Kontor IV, Hochschule, Goldschmiede, Platz II, Zierbaum |
| Bürger | 400 | Kanonengießerei |
| Bürger | 450 | Tiefe Erzmine |
| Kaufleute | 300 | Theater |
| Kaufleute | 400 | Große Burg, Musketenbauer |
| Kaufleute | 500 | Große Werft |
| Aristokraten | 600 | Festung |
| Aristokraten | 1500 | Schloss |
| Aristokraten | 2500 | Kathedrale |

### Produktionsketten (annoinfo.de)

Angegeben ist jeweils der Ausstoß der ganzen Kette in t/min. Die Werte dienen als Ziel für die Tickrate der Simulation.

| Ware | Kette | t/min |
|---|---|---|
| Holz | Forsthaus | 2,80 |
| Nahrung | Fischerhütte | 0,75 |
| Nahrung | Jagdhütte | 2,00 |
| Nahrung | Rinderfarm → Fleischerei | 2,30 |
| Nahrung | Getreidefarm → Mühle → Bäckerei | 3,00 |
| Stoffe | Schaffarm → Webstube | 1,95 |
| Stoffe | Baumwollplantage → Weberei | 3,10 |
| Ziegel | Steinbruch → Steinmetz | 2,90 |
| Alkohol | Weingut | 1,15 |
| Alkohol | Zuckerrohrplantage → Rumbrennerei | 2,30 |
| Gewürze | Gewürzplantage | 1,40 |
| Tabakwaren | Tabakplantage → Tabakwaren | 1,90 |
| Kakao | Kakaoplantage | 1,40 |
| Kleidung | Schneiderei | 2,00 |
| Werkzeug | Erzmine + Forsthaus → Erzschmelze → Werkzeugschmiede | 3,30 |
| Schwerter, Kanonen, Musketen | jeweils über die Erzschmelze | 1,15 |
| Schmuck | Goldmine → Goldschmiede | 2,50 |

Verbrauch pro Einwohner nennt die Seite nicht. Er steht in `haeuser.cod` unter `BGRUPPE_WARE`.
