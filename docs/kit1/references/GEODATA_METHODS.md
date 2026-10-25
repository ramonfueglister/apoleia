# Wissenschaftliche Methodenbasis

Stand 25.10.2026 · `kit1-landscape-v5` · Status `erforscht` für die unten
benannten Methoden, **keine validierte Kit-1-Implementierung**. Die Nutzerfreigabe
betrifft nachvollziehbare, fehlerkontrollierte Ableitung aus Realgeodaten. Sie
schreibt keine Bibliothek, Engine oder vollständige Implementierung aller Papers vor.

| Quelle | Belegte Methode und Nutzen | Grenze für Kit 1 |
|---|---|---|
| Peter Lindstrom, David Koller, William Ribarsky, Larry F. Hodges, Nick Faust, Gregory A. Turner: **Real-Time, Continuous Level of Detail Rendering of Height Fields**, SIGGRAPH 1996, S. 109–118. [Paper](https://www.cs.princeton.edu/courses/archive/spr01/cs598b/papers/lindstrom96.pdf), [DOI](https://doi.org/10.1145/237170.237217) | Höhenfeldvereinfachung mit kamerabezogener Screen-Space-Fehlerschwelle und gradueller lokaler Detailanpassung. | Bildschirmabweichung ist kein Nachweis geografischer Meter-Genauigkeit; nicht automatisch Schutz aller Küsten/Flussnetze. |
| Hugues Hoppe: **View-Dependent Refinement of Progressive Meshes**, SIGGRAPH 1997, S. 189–198. [Autoren-PDF](https://hhoppe.com/vdrpm.pdf) | Selektive Netzverfeinerung nach Sichtparametern und Screen-Space-Geometriefehler; Geomorphs für weichere Detailübergänge. | Das Paper liefert nicht den vollständigen Übergang einer flachen Erdkarte zur Diorama-Kamera. Diesen muss der eigene Adapter spezifizieren und prüfen. |
| Andreas Fabri, **CGAL 2D Polyline Simplification**, Dokumentationsstand 6.2.1 am Abruf 25.10.2026. [Offizielle Beschreibung](https://doc.cgal.org/latest/Polyline_simplification_2/index.html) | Vereinfachung von Linienmengen mit Erhalt ihrer Topologie: keine neuen Schnittpunkte, keine Änderung der Polygonverschachtelung. Kosten-/Stoppfunktionen steuern Reduktion. | Topologie allein erhält weder jede kulturell/geografisch wichtige Form noch alle Abstände. Zusätzliche Feature-Schutzregeln nötig. Kein CGAL-Installationsauftrag. |
| John P. Snyder: **Map Projections: A Working Manual**, USGS Professional Paper 1395, 1987. [Publikation/DOI](https://doi.org/10.3133/pp1395) | Referenz für Erdprojektionen und ihre unterschiedlichen Eigenschaften/Verzerrungen. | Keine einzelne flache Weltprojektion erhält überall gleichzeitig Winkel, Flächen und Längen. Auswahl und Verzerrung müssen offengelegt werden. |

Die Methodendarstellungen sind paraphrasiert. Es werden keine fremden
Implementierungen oder Paperabbildungen in das Produkt kopiert. Originale und
Software unterliegen ihren eigenen Rechten. Die genannten Veröffentlichungen
sind Methodenquellen, keine Evidenz für historische Geografie von 180 n. Chr.

Die operative Übersetzung in dieses Kit ist eine **eigene Designentscheidung**:
[GENERALIZATION](../operations/GENERALIZATION.md) sowie `geodata_policy` und
`derivation` legen messbare Belege fest. Eine mögliche quadratische Fehlerfunktion
(QEM) oder durchschnittlicher Fehler wäre allein keine strikte maximale
Abstandsgrenze; Algorithmuskosten nicht als gemessene geografische Genauigkeit ausgeben.
