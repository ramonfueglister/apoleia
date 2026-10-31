extends ScrollContainer
## A page of the statistics' cards, after Victoria 3's statistics and EU5's
## economy panel: every card the same size and built the same, its name
## over its figure (a chart of one measure, or of two or three that belong
## together), at the axis only the top and bottom value, under it the first
## and last month; two cards to a row, so their figures start and end on
## one line. What a card's numbers say now (Knaflic: the finding, computed
## from them) is in its name's tooltip, and all findings stand as one list,
## the "Lage", on an overview, each line a link to its card's page. The
## line charts share one month under the mouse and mark what happened
## (built, famine, price shocks). Every line, bar, row and good has a
## tooltip.
##
## A page is one of PAGES: the realm's overview (its figures and the
## Lage), the classes side by side, or the charts of one topic (the views
## of sim_tables.gd); a market's overview or charts (market_window.gd).
## sim_tables.gd hands it the tables (history, population, farms, state,
## classes, goods) with show_tables(), market_window.gd take_market()'s
## answer with show_market(); it only draws them. set_span() picks the
## months the charts show; a click on a line of the Lage emits go(page).

signal go(page: String)
## A creditor in the list was chosen (S134): its household's window.
signal household_chosen(household: int)

const UiStyle = preload("res://scripts/ui/ui_style.gd")
const Tooltips = preload("res://scripts/ui/tooltips.gd")
const Charts = preload("res://scripts/ui/charts.gd")
const Vic3Style = preload("res://scripts/ui/vic3_style.gd")
const CARD_MIN := 240.0 # two side by side even in a market's window
const GAP := 10 # between cards, across and down
const PAD := 8 # inside a card
const PLOT_PX := 168.0 # a card's figure: a chart, rows, bars or a curve
const LINE_PX := 22.0 # the legend's line under it, kept when empty
const CARD_BACK := Color("303134") # a card's board, a shade over the window's
const CARD_EDGE := Color(1.0, 1.0, 1.0, 0.07) # its rim, barely there
const OTHER := Color("6d7479") # the medal of "Andere", the rest
const BARS_MAX := 6 # rows of a share card before "Andere"
const BAR_ROW := 24.0 # BARS_MAX rows and "Andere" fill PLOT_PX
const BAR_PX := 8.0 # a bar's height in its trough, as the menu's (Vic3)
const MEDAL_R := 10.5
const NAME_X := 31.0 # a row's name, right of its medal
const SHARE_PX := 56.0 # a row's share at the right
const FED_ROW := 28.0 # six rows (the Gini's) fill PLOT_PX
const FED_NAME_PX := 108.0
const LAGE_NAME_PX := 210.0 # a line of the Lage: its card's name, then what it says
const CLASS_GAP := 8.0 # between two classes' columns
const CLASS_PX := 482.0 # a class's column, as Victoria 3's population
const CLASS_LINE := 26.0 # a line in a section of the column
const CLASS_FACE := Rect2(6, 92, 0, 100) # the class's picture, the width the column's
const CLASS_FACE_R := 36.0 # its medal, in the stead of a face
## What a class's column shows, top down: [CLASS_ROWS key, top, height,
## how]. "big" a figure under the name, "note" a line under it, "state"
## the line under the picture, "head" a section's head, "line" a line of a
## section with its icon (or none) and name.
const CLASS_PARTS := [
	["persons", 30.0, 34.0, "big"],
	["share", 64.0, 22.0, "note"],
	["eaten", 194.0, 26.0, "state"],
	["money_head", 222.0, 36.0, "money"],
	["money_share", 266.0, 28.0, "head", "des Geldes"],
	["households", 296.0, CLASS_LINE, "line", "family-house", "Haushalte"],
	["gini", 324.0, CLASS_LINE, "line", "scales", "Gini"],
	["", 358.0, 28.0, "head", "Bedarf"],
	["eaten", 388.0, CLASS_LINE, "line", "wheat", "Korn"],
	["clothes", 416.0, CLASS_LINE, "line", "roman-toga", "Kleidung"],
	["ragged", 444.0, CLASS_LINE, "line", "", "Zerlumpt"],
]
## The medals' icons in assets/ui/icons (Vic3Style.icon), white, tinted
## when drawn; a name without one shows its first letter.
const ICONS := {
	"Hofleute": "family-house", "Im Zelt": "camping-tent", "Lohnarbeit": "anvil", "Händler": "two-coins", "Oberschicht": "roman-toga",
	"Bauern": "wheat", "Pächter": "field", "Tagelöhner": "walking-boot", "Handwerker": "anvil", "Adel": "laurel-crown",
	"Geistliche": "greek-temple", "Gelehrte": "open-book", "Beamte": "scroll-quill", "Offiziere": "eagle-emblem",
	"Unternehmer": "scales", "Soldaten": "centurion-helmet", "Unfreie": "manacles", "Familienhof": "family-house", "Pachthof": "field", "Gut": "barn", "Alle": "scales",
}
## The goods table's rows in apoleia_sim::grain::GOOD_KEYS order; the
## history has each one's price as good_<key>.
const GOOD_KEYS: Array[String] = ["wool", "iron", "cloth", "tools", "pottery", "pork"]
## The classes in the order of the history's fed_<key> (grain/tables.rs).
const FED_KEYS: Array[String] = ["court", "tent", "wage", "trader", "elite"]
const FED_NAMES: Array[String] = ["Hofleute", "Im Zelt", "Lohnarbeit", "Händler", "Oberschicht"]
## A class keeps its colour in every chart (the ring of money, what it ate):
## the series colours in this order pass the colour-blind checks on the board.
const FED_COLOURS: Array[Color] = [Color("b8893a"), Color("1f9cc4"), Color("cf5f44"), Color("8f6fd0"), Color("6f9a3a")]
const TREND := Color("a09889") # a figure's small curve, its current value in gold
## What the state's bars are, for their tooltips.
const BAR_ABOUT := {
	"tax": "Denar aus dem Verkauf von Korn aus den Staatsspeichern seit Beginn: Zehntkorn, Pachtkorn vom Staatsland und gepfändetes Korn.",
	"land_tax": "Grundsteuer in Denar, die Höfe seit Beginn für ihre eigenen Felder gezahlt haben.",
	"head_tax": "Kopfsteuer in Denar, die Haushalte seit Beginn für ihre Erwachsenen gezahlt haben.",
	"rent": "Pacht in Denar, die Höfe auf Staatsland seit Beginn gezahlt haben.",
	"estates": "Geld von Toten ohne Erben, das seit Beginn an den Staat gefallen ist.",
	"wages": "Löhne, die der Staat seit Beginn seinen Dienern gezahlt hat: Soldaten, Beamten, Bauarbeitern.",
	"public_works": "Lohn, den der Staat seit Beginn für öffentliche Arbeit gezahlt hat: aus dem Geld, das über seiner Reserve lag.",
	"minted": "Denare, die der Staat seit Beginn neu geprägt hat.",
	"cash": "Was heute in der Staatskasse liegt.",
}
## The state's budget, a line per item of the history's months (Denar): the
## money it takes in and pays out. The taxes share one hue, as the
## occupations of a class in the lists. [key, colour, what it is]; the name
## is the sim's label without "im Monat".
const BUDGET_IN := [
	["land_tax_d", Color("d4b889"), "Grundsteuer der Höfe für ihre eigenen Felder: ein Anteil am üblichen Ertrag eines Hektars, einmal im Jahr nach der Ernte."],
	["head_tax_d", Color("eadcc4"), "Kopfsteuer für jeden Erwachsenen (15 bis 60 Jahre): Taglöhne im Jahr, Höfe nach der Ernte, alle anderen am ersten Tag des Jahres."],
	["tax_d", Color("b8893a"), "Geld aus dem Verkauf von Korn aus den Staatsspeichern: Zehntkorn, Pachtkorn vom Staatsland und gepfändetes Korn."],
	["rent_d", Color("cf5f44"), "Pacht in Geld von Höfen auf Staatsland."],
	["estates_d", Color("6f9a3a"), "Geld von Toten ohne Erben, das an den Staat fällt."],
]
const BUDGET_OUT := [
	["wages_d", Color("8f6fd0"), "Lohn für Soldaten, Beamte und die Bauarbeiter der Bauaufträge."],
	["public_works_d", Color("1f9cc4"), "Lohn für öffentliche Arbeit, bezahlt aus dem Geld über der Reserve der Kasse."],
	["interest_d", Color("c9a227"), "Zinsen an die Gläubiger der Staatsschuld, einmal im Jahr, und bei einer Tilgung oder einem Rückkauf der Zins bis zu diesem Tag."],
]
const BUDGET_ROW := 34.0 # a line of the budget: its name and value, under them its bar
const BUDGET_HEAD := 30.0
const YEAR_DAYS := 360
const TAX_CARDS: Array[String] = ["arrears", "arrears_households", "seized", "auctions", "debt", "debt_flow", "debt_rate"]
## S134: creditors in the list, and their faces' size.
const CREDITORS_SHOWN := 10
const CREDITOR_FACE_PX := 34.0
## S134: the Zwangsanleihe's buttons: share of the richest households'
## spare money, per cent, at FORCED_RATE per cent (PLACEHOLDER: shares;
## the rate of Venice's Monte Vecchio, 1262).
const FORCED_SHARES: Array[int] = [10, 25, 50]
const FORCED_RATE := 5
## S133, S134: what each choice of the spending and debt laws does, by
## card, law and choice.
const CHOICE_ABOUT := {
	"spend_laws:0:0": "Die Staatsspeicher kaufen kein Korn zu; sie halten, was Zehnt und Pacht bringen.",
	"spend_laws:0:1": "Die Staatsspeicher kaufen mit dem Geld über der Reserve der Kasse Korn bei den Händlern, bis zu einem Monat des Absatzes ihres Marktes, aber nur, solange sich das Lagern lohnt, wie bei jedem privaten Lager.",
	"spend_laws:0:2": "Wie «bis 1 Monat», bis zu drei Monaten des Absatzes.",
	"spend_laws:0:3": "Wie «bis 1 Monat», bis zu einem Jahr des Absatzes.",
	"spend_laws:1:0": "Der Staat hilft nicht; wer hungert, bettelt am Markt um Almosen.",
	"spend_laws:1:1": "Die öffentliche Arbeit stellt zuerst Haushalte ein, denen das Geld für einen Monat Essen fehlt.",
	"spend_laws:1:2": "Wer beim Essen zu wenig hat und es nicht bezahlen kann, bekommt den Rest seines Monatsbedarfs aus dem Staatsspeicher seines Marktes, so weit dieser reicht.",
	"debt_laws:0:0": "Der Staat leiht nicht. Fehlt Geld für den Lohn, prägt er neues.",
	"debt_laws:0:1": "Der Staat darf höchstens so viel schulden, wie er im letzten Jahr eingenommen hat. Er leiht erst, wenn die Kasse unter die Hälfte ihrer Reserve fällt.",
	"debt_laws:0:2": "Der Staat darf höchstens so viel schulden, wie er in drei Jahren einnimmt.",
	"debt_laws:0:3": "Keine Grenze: Nur die Gläubiger bremsen, wenn ihnen das Risiko zu gross wird. Dann bieten sie teuer oder gar nicht.",
	"debt_laws:1:0": "Neue Anleihen sind Renten: Der Staat zahlt nur Zins, ohne Laufzeit, und kauft sie zum Nennwert zurück, wenn die Kasse mehr hat als ihre Reserve.",
	"debt_laws:1:1": "Neue Anleihen laufen fünf Jahre; dann zahlt der Staat sie zurück. Kurze Laufzeit ist oft billiger, zwingt aber, bald wieder zu leihen.",
	"debt_laws:1:2": "Neue Anleihen laufen zehn Jahre; dann zahlt der Staat sie zurück.",
	"debt_laws:1:3": "Neue Anleihen laufen dreissig Jahre; dann zahlt der Staat sie zurück.",
	"debt_laws:2:0": "Reicht die Kasse für Zins und Tilgung nicht, prägt der Staat das Fehlende neu. Die Gläubiger verlieren nichts.",
	"debt_laws:2:1": "Reicht die Kasse nicht, zahlt sie jedem Gläubiger denselben Anteil; der Rest ist verloren. Die Gläubiger merken es sich und verlangen künftig mehr Zins.",
	"debt_laws:2:2": "Reicht die Kasse nicht, zahlt sie jedem Gläubiger denselben Anteil; der Rest wird zu einer neuen Rente mit tieferem Zins. Kleinerer Verlust, kleinerer Schaden am Ruf.",
	"debt_laws:3:0": "Kein Höchstzins für private Kredite, sobald es sie gibt. Den Staat bindet das Zinsgesetz nicht.",
	"debt_laws:3:1": "Höchstzins 12 % im Jahr für private Kredite, wie in Rom, sobald es sie gibt. Den Staat bindet er nicht.",
	"debt_laws:3:2": "Höchstzins 5 % im Jahr für private Kredite, wie im Reich ab 1654, sobald es sie gibt. Den Staat bindet er nicht.",
	"debt_laws:3:3": "Zinsverbot: Der Staat darf nur Renten verkaufen, gleich was die Laufzeit sagt, denn der Rentenkauf galt als Kauf, nicht als Darlehen.",
}
const YEARS_PX := 210.0 # the budget's years, a bar each
## A figure's tooltip: what it is, where that needs saying.
const TILE_ABOUT := {
	"cash": "Die Kasse behält eine Reserve und zahlt, was darüber liegt, als öffentliche Arbeit aus. Steigt oder fällt sie, ist das weder gut noch schlecht.",
	"income_y": "Was der Staat in den letzten zwölf Monaten eingenommen hat. Die Steuern sind einmal im Jahr fällig, darum zählt das ganze Jahr.",
	"spending_y": "Was der Staat in den letzten zwölf Monaten ausgegeben hat.",
	"arrears": "Grund- und Kopfsteuer, die Haushalte dem Staat schulden.",
	"arrears_households": "Haushalte, die dem Staat Steuern schulden.",
}

## The goods' names before the goods table names them (GOOD_KEYS order).
const GOOD_NAMES: Array[String] = ["Wolle", "Eisen", "Kleidung", "Werkzeug", "Keramik", "Schweinefleisch"]
## Every card: [kind, name, unit, what it shows (its name's tooltip)]. kind:
## line (a chart over the months), shares (sorted bars of a whole), rows
## (small multiples by class), lorenz, bars (the state's money), text, and
## the wide ones: tiles (the figures), lage (the findings), classes. The
## goods' cards ("good0" … and a market's "m_good0" …) are made by _spec.
const CARDS := {
	"tiles": ["tiles", "", "", ""],
	"lage": ["lage", "Lage", "", "Was die Zahlen gerade sagen, ein Satz je Diagramm, nach Themen. Ein Klick auf eine Zeile öffnet ihr Diagramm."],
	"classes": ["classes", "Die Schichten", "", "Jede Schicht mit ihren Menschen und Haushalten, was sie gegessen hat, ihrem Geld je Kopf, wie ungleich es verteilt ist (Gini) und ihrer Kleidung."],
	"persons": ["line", "Menschen", "", "Alle Menschen auf der Karte, jeder einzeln simuliert."],
	"life": ["line", "Geburten und Todesfälle", "", "Geburten und Todesfälle im Monat. Die ersten Kinder kommen erst nach etwa neun Monaten zur Welt."],
	"hunger": ["line", "Hungertote", "", "Menschen, die im Monat an Hunger sterben."],
	"moves": ["line", "Umzüge", "", "Menschen, die im Monat umziehen, und Menschen, die im Monat die Karte verlassen."],
	"tents": ["line", "Im Zelt", "", "Menschen, die ohne Haus im Zelt leben."],
	"jobs": ["shares", "Menschen nach Beruf", "", "Die Menschen nach dem Beruf ihres Haushalts."],
	"price": ["line", "Kornpreis", "D/kg", "Jeder Markt hat seinen eigenen Kornpreis. Die Linie ist der Median der Märkte, das Band reicht vom billigsten zum teuersten Markt, höchstens bis zum doppelten Median, damit ein teurer Markt wie Rom die Linie nicht flach drückt."],
	"fed": ["rows", "Gegessen nach Schicht", "", "Wie viel ihres Kornbedarfs jede Schicht im Monat gegessen hat. 100 % heisst satt. Alle Zeilen haben dieselbe Skala; rot ist, was zum Sattwerden fehlte."],
	"harvest": ["line", "Ernte und Verkauf", "t", "Korn, das die Höfe im Monat ernten, und Korn, das die Märkte im Monat verkaufen."],
	"granaries": ["line", "Getreide in Speichern", "t", "Korn in den Speichern des Staates (Steuerkorn), der Grundherren (Pachtkorn) und der Händler auf den Märkten."],
	"flows": ["line", "Korn ausser Handel", "t", "Korn im Monat, das verdirbt, über den Kartenrand verkauft wird, zwischen fernen Märkten gehandelt oder als Almosen verteilt wird."],
	"spoiled": ["line", "Verdorbenes Korn", "t", "Korn, das im Monat in Speichern und Lagern verdirbt."],
	"export": ["line", "Korn über den Kartenrand", "t", "Korn, das Händler im Monat über den Kartenrand verkaufen."],
	"traded": ["line", "Fernhandel mit Korn", "t", "Korn, das im Monat zwischen fernen Märkten der Karte gehandelt wird."],
	"alms": ["line", "Almosen", "t", "Korn, das im Monat als Almosen an Hungernde verteilt wird."],
	"clothes": ["line", "Kleidung vom Bedarf", "%", "Kleidung, die die Haushalte besitzen, gemessen an dem, was sie brauchen."],
	"real": ["line", "Reallohn", "kg", "Der Taglohn eines Marktes in Korn zu dessen Preis: so viel kann ein Tag Arbeit kaufen. Gestrichelt der Bedarf: so viel muss ein Lohnarbeiter je Arbeitstag verdienen, damit sein Teil der Familie satt wird (Bedarf der Familie durch ihre Erwachsenen und 290 Arbeitstage im Jahr, nach Columella). Das Band reicht vom ärmsten bis zum reichsten Zehntel der Märkte."],
	"wage": ["line", "Taglohn", "D", "Der Taglohn in Denar, der Median der Märkte."],
	"work": ["line", "Arbeitstage in der Woche", "Tage", "Arbeitstage der letzten Woche, die jemand gesucht und niemanden gefunden hat, und die jemand angeboten hat, ohne eingestellt zu werden."],
	"money": ["shares", "Geld nach Schicht", "", "Alles Geld der Haushalte nach Schicht, bei Bauern mit dem Geld ihres Hofs. Der weisse Strich: ihr Anteil an den Menschen."],
	"lorenz": ["lorenz", "Wer hat das Geld", "", "Die Lorenzkurve des Geldes je Kopf: nach rechts die Menschen vom ärmsten zum reichsten, nach oben ihr Anteil an allem Geld. Auf der Diagonale hätten alle gleich viel. Die Fläche zwischen Diagonale und Kurve ist der Gini. Gezählt wird nur Bargeld (Denar), nicht Land, Vieh oder Vorräte."],
	"gini_rows": ["rows", "Ungleichheit nach Schicht", "", "Der Gini des Geldes je Kopf: 0 heisst, alle haben gleich viel; 1 heisst, einer hat alles. Oben über alle Menschen, darunter innerhalb jeder Schicht. Alle Zeilen haben dieselbe Skala. Gezählt wird nur Bargeld (Denar), nicht Land, Vieh oder Vorräte."],
	"farms": ["shares", "Höfe nach Art", "", "Familienhof: die Familie bebaut ihr eigenes Land. Pachthof: sie bebaut gepachtetes Land. Gut: ein Grundherr lässt sein Land bebauen."],
	"land": ["shares", "Felder der Höfe", "", "Die Felder aller Höfe: was gesät ist und was brach liegt."],
	"farm_count": ["line", "Höfe", "", "Alle Höfe auf der Karte am Monatsende."],
	"farm_store": ["line", "Hoflager", "t", "Korn in den Lagern der Höfe am Monatsende."],
	"cash": ["line", "Staatskasse", "D", "Denar in der Staatskasse am Ende jedes Monats. Die Kasse behält eine Reserve: den Staatslohn eines Jahres und was die offenen Bauaufträge noch kosten. Was darüber liegt, zahlt sie als öffentliche Arbeit aus."],
	"state": ["bars", "Geld des Staates seit Beginn", "", "Was der Staat seit Beginn eingenommen und ausgegeben hat, und was heute in der Kasse liegt."],
	"held": ["line", "Geld im Umlauf", "D", "Alle Denar ausserhalb der Staatskasse am Monatsende, und was der Staat seit Beginn neu geprägt hat."],
	"tax_grain": ["line", "Steuerkorn", "t", "Korn, das der Staat seit Beginn als Steuer eingezogen hat."],
	"income": ["line", "Einnahmen im Monat", "D", "Denar, die der Staat im Monat einnimmt: Grund- und Kopfsteuer, Geld aus dem Verkauf von Korn aus seinen Speichern (Zehnt, Pacht vom Staatsland), Pacht in Geld und das Geld von Toten ohne Erben."],
	"spending": ["line", "Ausgaben im Monat", "D", "Denar, die der Staat im Monat ausgibt: Staatslohn für Soldaten, Beamte und Bauarbeiter, und Lohn für öffentliche Arbeit aus dem Geld über seiner Reserve."],
	"budget": ["budget", "Haushalt im letzten Jahr", "D", "Was der Staat in den letzten zwölf Monaten eingenommen und ausgegeben hat, Posten für Posten, und darunter, was nicht in diese Summen gehört. Die Steuern sind einmal im Jahr fällig, darum zählt das ganze Jahr und nicht ein Monat."],
	"laws": ["laws", "Steuergesetz", "", "Für jede Steuer eine von sechs Stufen. Eine neue Stufe gilt ab der nächsten Fälligkeit: der Zehnt bei der Ernte, die Grundsteuer nach der Ernte, die Kopfsteuer der Höfe nach der Ernte und aller anderen am ersten Tag des Jahres. Wer nicht zahlen kann, kommt in den Steuerrückstand."],
	"budget_years": ["years", "Haushalt nach Jahren", "D", "Jedes Jahr ein Balken: nach oben die Einnahmen nach Posten, nach unten die Ausgaben. Das laufende Jahr ist noch nicht voll."],
	"arrears": ["line", "Steuerrückstand", "D", "Grund- und Kopfsteuer, die Haushalte dem Staat am Monatsende schulden. Ist der Rückstand ein Jahr alt, pfändet der Staat bald nach der nächsten Ernte Geld und Korn, ausser dem Essen bis zur nächsten Ernte und dem Saatgut; nach zwei Jahren wird ein eigener Hof versteigert. Die Steuern eines Guts zahlt sein Grundherr."],
	"arrears_households": ["line", "Haushalte im Rückstand", "", "Haushalte, die dem Staat am Monatsende Steuern schulden."],
	"seized": ["line", "Pfändungen", "D", "Geld und Korn, das der Staat im Monat für Rückstände pfändet, das Korn zum Ankaufspreis; und Rückstand, den er als uneinbringlich abschreibt, wenn nach zwei Jahren nichts mehr zu holen ist."],
	"auctions": ["line", "Zwangsversteigerungen", "Höfe", "Eigene Höfe, die im Monat für zwei Jahre Steuerrückstand versteigert werden: die Familie bleibt als Pächter des Käufers. Bietet niemand, fällt der Hof an den Staat (Domäne)."],
	"spend_laws": ["choices", "Ausgabengesetze", "", "Wofür der Staat Geld und Korn ausgibt, ausser Lohn und öffentlicher Arbeit: ob seine Speicher Korn zukaufen und wie er Bedürftigen hilft. Eine Wahl gilt ab dem nächsten Tag."],
	"debt_laws": ["choices", "Schuldgesetz", "", "Ob und wie viel der Staat leihen darf, wie lange neue Anleihen laufen, was geschieht, wenn die Kasse Zins oder Tilgung nicht zahlen kann, und das Zinsgesetz. Den Zins setzt niemand: Er entsteht aus den Geboten der Gläubiger. Darunter die Zwangsanleihe als einmaliger Erlass."],
	"creditors": ["creditors", "Gläubiger", "", "Die Haushalte, die dem Staat am meisten geliehen haben, mit dem mittleren Zins ihrer Anleihen. Ein Klick öffnet den Haushalt."],
	"debt": ["line", "Staatsschuld", "D", "Was der Staat seinen Gläubigern am Monatsende schuldet, zum Nennwert der Anleihen. Erlaubt das Schuldgesetz keine Schuld, bleibt sie bei null."],
	"debt_flow": ["line", "Anleihen und Zinsen", "D", "Neue Anleihen im Monat, Zinsen, Tilgung und Rückkauf, und was Gläubiger in einem Staatsbankrott verloren haben. Der Staat leiht erst, wenn die Kasse unter die Hälfte ihrer Reserve fällt."],
	"debt_rate": ["line", "Zins der Staatsschuld", "%", "Der Zins der letzten Anleihe: das Gebot des teuersten Gläubigers, den der Staat noch nehmen musste. Jeder Gläubiger verlangt, was er sonst verdienen würde, dazu einen Aufschlag für das Risiko, das er sieht, und für die Laufzeit."],
	"public_days": ["line", "Öffentliche Arbeit", "Tage", "Arbeitstage im Monat, die der Staat als öffentliche Arbeit bezahlt, zum Taglohn des Marktes. Im ersten Jahr noch keine: dann kennt die Kasse ihre Reserve noch nicht."],
	"m_price": ["line", "Kornpreis", "D/kg", "Der Kornpreis dieses Marktes am Monatsende. Grau: der Median aller Märkte. Vor den letzten zehn Jahren steht jedes Jahr als sein Mittel."],
	"goods": ["goods", "Warenpreise", "D", "Der Preis jeder Ware ist der Median der Märkte, gewichtet nach ihren Menschen. Darunter sein Verlauf im gewählten Zeitraum."],
	"m_goods": ["goods", "Warenpreise", "D", "Der Preis jeder Ware an diesem Markt, darunter sein Verlauf im gewählten Zeitraum. Über einer Ware steht, warum sie kostet, was sie kostet."],
	"m_why": ["text", "Warum dieser Preis", "", "Was die Händler dieses Marktes zu ihrem Kornpreis bewegt: ihr Lager gegen ihren Plan, die Jahreszeit, der Lagerboden, Käufer ohne Ware."],
	"m_hungry": ["line", "Hungernd", "%", "Anteil der Menschen der Region, die ihr Korn kaufen und im Monat nicht satt wurden."],
	"m_store": ["line", "Lager und Verkauf", "t", "Korn im Lager der Händler dieses Marktes am Monatsende, und Korn, das sie im Monat verkauft haben."],
	"m_real": ["line", "Reallohn", "kg", "Der Taglohn hier in Korn zum Preis hier: so viel kann ein Tag Arbeit an diesem Markt kaufen."],
	"m_people": ["shares", "Wer hier lebt", "", "Die Menschen der Region nach der Schicht ihres Haushalts."],
	"m_money": ["shares", "Geld nach Schicht", "", "Alles Geld der Haushalte der Region nach Schicht, bei Bauern mit dem Geld ihres Hofs. Der weisse Strich: ihr Anteil an den Menschen."],
	"m_persons": ["line", "Menschen", "", "Die Menschen der Region am Monatsende, und wie viele davon im Zelt leben."],
	"m_public": ["line", "Öffentliche Arbeit", "Tage", "Arbeitstage im Monat, die der Staat an diesem Markt als öffentliche Arbeit bezahlt hat, zum Taglohn hier."],
	"m_gini": ["line", "Arm und Reich", "", "Der Gini des Geldes je Kopf in der Region: 0 heisst, alle haben gleich viel; 1 heisst, einer hat alles. Grau: über alle Menschen der Karte. Gezählt wird nur Bargeld."],
}
## The cards each page shows, in reading order: the wide ones (tiles,
## lage, classes, text) across the page, the others two to a row.
const PAGES := {
	"overview": ["tiles", "lage"],
	"people": ["classes"],
	"people_charts": ["persons", "life", "hunger", "moves", "tents", "jobs"],
	"grain_charts": ["price", "fed", "harvest", "granaries", "flows", "spoiled", "export", "traded", "alms"],
	"money_charts": ["real", "wage", "work", "money", "lorenz", "gini_rows"],
	"goods_charts": ["goods", "clothes", "good0", "good1", "good2", "good3", "good4", "good5"],
	"farms_charts": ["farms", "land", "farm_count", "farm_store"],
	"budget_charts": ["tiles", "budget", "laws", "spend_laws", "debt_laws", "budget_years", "arrears", "arrears_households", "seized", "auctions", "debt", "debt_flow", "debt_rate", "creditors"],
	"state_charts": ["cash", "state", "income", "spending", "public_days", "held", "tax_grain"],
	"market": ["tiles", "m_why", "lage", "m_people", "m_money", "m_goods"],
	"market_charts": ["m_price", "m_hungry", "m_store", "m_real", "m_gini", "m_persons", "m_good0", "m_good1", "m_good2", "m_good3", "m_good4", "m_good5", "m_public"],
}
## The cards across the page, as Victoria 3 gives its main graph the width:
## each topic's leading chart and the one that sums it up.
const WIDE: Array[String] = ["persons", "jobs", "price", "fed", "flows", "real", "gini_rows", "goods", "clothes", "cash", "state", "budget", "laws", "spend_laws", "debt_laws", "budget_years", "m_price",
	"m_persons", "m_goods"]
## The findings in the Lage's order: the topics as their pages; "goods"
## is the good that moved most.
const LAGE_REALM: Array[String] = ["persons", "life", "hunger", "moves", "tents", "jobs", "price", "fed", "harvest", "granaries",
	"spoiled", "export", "traded", "alms", "real", "wage", "work", "money", "lorenz", "gini_rows", "goods", "clothes", "farms", "land",
	"farm_count", "farm_store", "budget", "arrears", "seized", "auctions", "cash", "state", "income", "spending", "public_days", "held",
	"tax_grain"]
const LAGE_MARKET: Array[String] = ["m_price", "m_hungry", "m_store", "m_real", "m_public", "m_persons", "m_gini", "m_people", "m_money", "goods"]
## A topic's name over its lines in the Lage, by the page of its charts.
const TOPICS := {"people_charts": "Menschen", "grain_charts": "Korn", "money_charts": "Geld", "goods_charts": "Waren",
	"farms_charts": "Höfe", "budget_charts": "Staat", "state_charts": "Staat"}
## The classes' table, a line per measure: [key, name, what it is].
const CLASS_ROWS := [
	["persons", "Menschen", "Die Menschen der Schicht."],
	["share", "Anteil an allen", "Ihr Anteil an allen Menschen."],
	["households", "Haushalte", "Die Haushalte der Schicht."],
	["eaten", "Gegessen vom Bedarf", "Wie viel ihres Kornbedarfs die Schicht im letzten Monat gegessen hat. 100 % heisst satt."],
	["money_head", "Geld je Kopf", "Das Geld der Schicht in Denar durch ihre Menschen, bei Bauern mit dem Geld ihres Hofs."],
	["money_share", "Anteil am Geld", "Ihr Anteil an allem Geld der Haushalte."],
	["gini", "Gini des Geldes", "Wie ungleich das Geld je Kopf in der Schicht verteilt ist: 0 heisst, alle haben gleich viel; 1 heisst, einer hat alles."],
	["clothes", "Kleidung vom Bedarf", "Kleidung, die die Haushalte der Schicht besitzen, gemessen an dem, was sie brauchen."],
	["ragged", "Unter halber Kleidung", "Haushalte, die weniger als die Hälfte der Kleidung haben, die sie brauchen."],
]
## How the classes are named as a sentence's subject, and whether as many.
const FED_SUBJECTS: Array[String] = ["Die Hofleute", "Die Menschen im Zelt", "Die Lohnarbeiter", "Die Händler", "Die Oberschicht"]
const FED_DATIVES: Array[String] = ["den Hofleuten", "den Menschen im Zelt", "den Lohnarbeitern", "den Händlern", "der Oberschicht"]

## sim_tables.gd's day format: date(day) "Martius, Jahr 3"
var date: Callable
var page := "overview" # one of PAGES
var _tables := {}
var _column: VBoxContainer
var _grid: GridContainer # the row the next card goes into
var _tiles: HBoxContainer
var _heads := {} # card key -> its name's label
var _lines := {} # chart key -> {control, series: Array, unit, days, hover, legend, hidden}
var _shares := {} # card key -> {control, names, values, colours, ref, ref_name, total, unit, title, hover, foot}
var _icons := {} # name -> its medal's icon, or null
var _bars: Control
var _bar_rows: Array = [] # [label, value, key]
var _says := {} # card key -> what its numbers say now, see _find_all
var _good_tips := {} # good card key -> its name's tooltip
var _goods: GridContainer # the goods' tiles, each its price and its course
var _lage: VBoxContainer
var _classes: HBoxContainer
var _events := {} # day -> what happened that month (history), see _find_events
## Months shown in the line charts: 12, 120 or 0 for all.
var _span := 0
var _market := false # one market's page (show_market) instead of the realm's
var _tile_specs: Array = [] # the figures: [key, name, unit, scale, falling good, neutral (no colour for its change)]
var _lorenz: Control
var _lorenz_now := PackedFloat64Array() # the curve's points at 0, 10 … 100 % of the people
var _lorenz_then := PackedFloat64Array()
var _lorenz_when := ""
var _lorenz_hover := -1
var _reasons: Label
var _sums := {} # card key -> name -> amount: the shares, kept for the findings of pages without their card
var _class_table: Control
var _class_names := PackedStringArray()
var _class_cells := [] # per line of CLASS_ROWS: per class [text, colour]
var _class_hover := Vector2i(-1, -1) # column, part of CLASS_PARTS
var set_tax: Callable # (law, level): the sim's set_tax, handed by sim_tables.gd; the laws' buttons call it
var _budget: Control
var _budget_sides := [[], []] # income, spending: per item {key, name, colour, about, year, before, months}
var _budget_extra := [] # what is not in the sums: [name, value text, about]
var _budget_hover := Vector2i(-1, -1) # side, row
var _years: Control
var _years_legend: HFlowContainer
var _year_rows := [] # per year {year, part (not full yet), in, out}: each item's Denar
var _year_names := [[], []] # income, spending: per item [name, colour]
var _year_hover := -1
var _laws_box: VBoxContainer
var _laws := [] # tax_law(): per law {law, name, level, levels, rate, unit, denar}
var _law_buttons := [] # per law its six buttons
var _law_notes := [] # per law the line under its buttons
var _law_wanted := {} # law row -> the level the player chose, until the sim has it
var set_spend: Callable # (law, choice): S133, handed by sim_tables.gd
var set_debt: Callable # (law, choice): S134, handed by sim_tables.gd
var forced_loan: Callable # (share, rate): S134, handed by sim_tables.gd
var face_of: Callable # (household) -> Texture2D or null: its face from sim_tables.gd's list faces, asked for if missing
var _choice_boxes := {} # card key -> its rows of laws
var _choice_buttons := {} # card key -> per law its buttons
var _choice_laws := {} # card key -> the laws as last shown: {law, name, choice, choices}
var _choice_wanted := {} # "card:law row" -> the choice the player made, until the sim has it
var _forced_buttons := []
var _forced_note: Label
var _creditors_box: VBoxContainer
var _creditors_note: Label

func _init(date_fn: Callable, page_name := "overview") -> void:
	date = date_fn
	page = page_name
	_market = page.begins_with("market")
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER # its width never widens the window
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", GAP)
	add_child(_column)
	resized.connect(func(): # two cards to a row while both keep CARD_MIN
		for c in _column.get_children():
			if c is GridContainer:
				c.columns = 2 if size.x <= 0.0 or size.x >= CARD_MIN * 2.0 + GAP + 12.0 else 1)
	if page == "budget_charts":
		_tile_specs = [["cash", "Staatskasse", " D", 1.0, false, true], ["income_y", "Einnahmen im Jahr", " D", 1.0, false, true],
			["spending_y", "Ausgaben im Jahr", " D", 1.0, false, true], ["arrears", "Steuerrückstand", " D", 1.0, true],
			["arrears_households", "Säumige Haushalte", "", 1.0, true]]
	elif _market:
		_tile_specs = [["price", "Kornpreis", " D/kg", 1.0, true], ["share_hungry", "Hungernd", " %", 100.0, true],
			["real_wage", "Reallohn", " kg", 1.0, false], ["persons", "Menschen", "", 1.0, false], ["gini", "Gini", "", 1.0, true]]
	else:
		_tile_specs = [["persons", "Menschen", "", 1.0, false], ["price_median", "Kornpreis", " D/kg", 1.0, true],
			["eaten", "Gegessen", " %", 100.0, false], ["real_p50", "Reallohn", " kg", 1.0, false],
			["cash", "Staatskasse", " D", 1.0, false, true]]
	for key in PAGES[page]:
		_add(key)

## Card `key`: [kind, name, unit, about], the goods' made from their keys.
static func _spec(key: String) -> Array:
	if CARDS.has(key):
		return CARDS[key]
	var r := int(key.right(1))
	return ["line", GOOD_NAMES[r], "D", "Der Preis von %s an diesem Markt am Monatsende." % GOOD_NAMES[r] if key.begins_with("m_")
		else "Der Preis von %s: der Median der Märkte, gewichtet nach ihren Menschen." % GOOD_NAMES[r]]

func _add(key: String) -> void:
	match _spec(key)[0]:
		"tiles":
			_tiles_strip()
		"lage":
			_lage_card()
		"classes":
			_classes_card()
		"text":
			_reasons_card()
		"shares":
			_shares_card(key)
		"rows":
			_rows_card(key)
		"lorenz":
			_lorenz_card()
		"bars":
			_bar_card()
		"budget":
			_budget_card()
		"laws":
			_laws_card()
		"choices":
			_choices_card(key)
		"creditors":
			_creditors_card()
		"years":
			_years_card()
		"goods":
			_goods_card(key)
		_:
			_line_card(key)

## The page that shows card `key` with its chart (the Lage's links).
static func page_of(key: String, market := false) -> String:
	if key == "goods":
		return "market_charts" if market else "goods_charts"
	for p in PAGES:
		if p.ends_with("charts") and p.begins_with("market") == market and key in PAGES[p]:
			return p
	return ""

## The months the charts show: 12, 120 or 0 for all.
func set_span(months: int) -> void:
	if months == _span:
		return
	_span = months
	if _tables.is_empty():
		return
	if _market:
		show_market(_tables)
	else:
		show_tables(_tables)

## The time buttons for set_span: "1 Jahr", "10 Jahre", "Alles", the one
## chosen lit; `picked` gets the months.
static func span_buttons(picked: Callable, now := 0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for span in [[12, "1 Jahr"], [120, "10 Jahre"], [0, "Alles"]]:
		var b := Button.new()
		b.text = span[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = span[0] == now
		b.custom_minimum_size = Vector2(64, 30)
		b.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
		b.pressed.connect(func():
			for other in row.get_children():
				other.button_pressed = other == b
			picked.call(span[0]))
		row.add_child(b)
	return row

## The tables by kind ("history", "population", "farms", "state",
## "classes", "goods"), each as take_table() gave it. Every page gets all
## of them: its cards take what they show, the Lage the findings of all.
func show_tables(tables: Dictionary) -> void:
	_tables = tables
	var h: Dictionary = tables.get("history", {})
	var d: Dictionary = h.get("data", {})
	if not d.is_empty():
		_events = _find_events(d)
		_set_line("persons", h, [{"key": "persons", "name": "Menschen", "colour": Charts.SERIES[1]}])
		_set_line("life", h, [{"key": "births", "name": "Geburten", "colour": Charts.SERIES[1]},
			{"key": "deaths", "name": "Todesfälle", "colour": Charts.SERIES[2]}])
		_set_line("hunger", h, [{"key": "hunger_deaths", "name": "Hungertote", "colour": Charts.RED}])
		_set_line("moves", h, [{"key": "moved", "name": "Umgezogen", "colour": Charts.SERIES[1]},
			{"key": "left", "name": "Verlassen die Karte", "colour": Charts.SERIES[2]}])
		_set_line("tents", h, [{"key": "tent_persons", "name": "Im Zelt", "colour": Charts.SERIES[1]}])
		_set_line("price", h, [{"key": "price_median", "name": "Median", "colour": Charts.SERIES[0], "lo": "price_min", "hi": "price_max",
			"band": "Spanne"}])
		_set_rows("fed", d)
		_set_line("harvest", h, [{"key": "harvest_t", "name": "Ernte", "colour": Charts.SERIES[0]},
			{"key": "sold_t", "name": "Verkauft", "colour": Charts.SERIES[1]}])
		_set_line("granaries", h, [{"key": "horrea_t", "name": "Staat", "colour": Charts.SERIES[3]},
			{"key": "lords_t", "name": "Grundherren", "colour": Charts.SERIES[2]},
			{"key": "market_store_t", "name": "Märkte", "colour": Charts.SERIES[0]}])
		_set_line("flows", h, [{"key": "spoiled_t", "name": "Verdorben", "colour": Charts.SERIES[2]},
			{"key": "export_t", "name": "Ausfuhr", "colour": Charts.SERIES[3]},
			{"key": "traded_t", "name": "Fernhandel", "colour": Charts.SERIES[1]},
			{"key": "alms_t", "name": "Almosen", "colour": Charts.SERIES[4]}])
		_set_line("spoiled", h, [{"key": "spoiled_t", "name": "Verdorben", "colour": Charts.SERIES[2]}])
		_set_line("export", h, [{"key": "export_t", "name": "Ausfuhr", "colour": Charts.SERIES[3]}])
		_set_line("traded", h, [{"key": "traded_t", "name": "Fernhandel", "colour": Charts.SERIES[1]}])
		_set_line("alms", h, [{"key": "alms_t", "name": "Almosen", "colour": Charts.SERIES[4]}])
		_set_line("real", h, [{"key": "real_p50", "name": "Median", "colour": Charts.SERIES[4], "lo": "real_p10", "hi": "real_p90",
			"band": "Spanne"},
			{"key": "need_wage", "name": "Bedarf", "colour": Charts.RED, "dashed": true}])
		_set_line("wage", h, [{"key": "wage", "name": "Taglohn", "colour": Charts.SERIES[0]}])
		_set_line("work", h, [{"key": "vacant", "name": "Gesucht", "colour": Charts.SERIES[1]},
			{"key": "idle", "name": "Liegen geblieben", "colour": Charts.SERIES[2]}])
		_set_rows("gini_rows", d)
		if _lorenz != null:
			_set_lorenz(d)
		_set_line("clothes", h, [{"key": "clothes", "name": "Alle Haushalte", "colour": Charts.SERIES[3], "scale": 100.0}])
		for r in GOOD_KEYS.size():
			_set_line("good%d" % r, h, [{"key": "good_" + GOOD_KEYS[r], "name": GOOD_NAMES[r], "colour": Charts.SERIES[0]}])
		_set_line("farm_count", h, [{"key": "farms", "name": "Höfe", "colour": Charts.SERIES[0]}])
		_set_line("farm_store", h, [{"key": "farm_store_t", "name": "Hoflager", "colour": Charts.SERIES[0]}])
		_set_line("cash", h, [{"key": "cash", "name": "Staatskasse", "colour": Charts.SERIES[3]}])
		_set_line("held", h, [{"key": "money_held", "name": "Im Umlauf", "colour": Charts.SERIES[0]},
			{"key": "minted", "name": "Geprägt seit Beginn", "colour": Charts.SERIES[3]}])
		_set_line("tax_grain", h, [{"key": "tax_grain_t", "name": "Steuerkorn", "colour": Charts.SERIES[0]}])
		_set_line("income", h, [{"key": "land_tax_d", "name": "Grundsteuer", "colour": BUDGET_IN[0][1]},
			{"key": "head_tax_d", "name": "Kopfsteuer", "colour": BUDGET_IN[1][1]},
			{"key": "tax_d", "name": "Verkauf aus Staatsspeichern", "colour": Charts.SERIES[0]},
			{"key": "rent_d", "name": "Pacht", "colour": Charts.SERIES[2]},
			{"key": "estates_d", "name": "Erbloser Nachlass", "colour": Charts.SERIES[4]}])
		_set_line("spending", h, [{"key": "wages_d", "name": "Staatslohn", "colour": Charts.SERIES[3]},
			{"key": "public_works_d", "name": "Öffentliche Arbeit", "colour": Charts.SERIES[1]}])
		_set_line("public_days", h, [{"key": "public_days", "name": "Öffentliche Arbeit", "colour": Charts.SERIES[1]}])
		_set_line("arrears", h, [{"key": "arrears", "name": "Steuerrückstand", "colour": Charts.SERIES[2]}])
		_set_line("arrears_households", h, [{"key": "arrears_households", "name": "Haushalte", "colour": Charts.SERIES[2]}])
		_set_line("seized", h, [{"key": "seized_d", "name": "Gepfändet", "colour": Charts.SERIES[2]},
			{"key": "written_off_d", "name": "Abgeschrieben", "colour": Charts.SERIES[3]}])
		_set_line("auctions", h, [{"key": "auctions", "name": "Versteigert", "colour": Charts.SERIES[0]},
			{"key": "domains", "name": "An den Staat", "colour": Charts.SERIES[3]}])
		_set_line("debt", h, [{"key": "debt", "name": "Staatsschuld", "colour": Charts.SERIES[3]}])
		_set_line("debt_flow", h, [{"key": "debt_issued_d", "name": "Neue Anleihen", "colour": Charts.SERIES[0]},
			{"key": "interest_d", "name": "Zinsen", "colour": Charts.SERIES[3]},
			{"key": "debt_repaid_d", "name": "Getilgt und zurückgekauft", "colour": Charts.SERIES[1]},
			{"key": "debt_lost_d", "name": "Im Staatsbankrott verloren", "colour": Charts.RED}])
		_set_line("debt_rate", h, [{"key": "debt_rate", "name": "Zins der letzten Anleihe", "colour": Charts.SERIES[3]}])
		if page == "budget_charts":
			_set_budget(h)
			_set_years(h)
			_set_laws(tables.get("laws", []), d)
			_set_choices("spend_laws", tables.get("spend", []))
			_set_choices("debt_laws", tables.get("debt", {}).get("laws", []))
			_set_creditors(tables.get("debt", {}))
			_fill_tiles(_with_year_sums(d))
		else:
			_fill_tiles(d)
	var pop: Dictionary = tables.get("population", {})
	if not pop.is_empty() and pop.data.has("occupation"):
		var sums := {}
		for r in pop.data.persons.size():
			var job: String = pop.data.occupation[r]
			sums[job] = sums.get(job, 0.0) + float(pop.data.persons[r])
		_set_shares("jobs", sums, "Menschen")
	var farms: Dictionary = tables.get("farms", {})
	if not farms.is_empty():
		var sums := {}
		for key in ["family", "tenant", "estate"]:
			if farms.data.has(key):
				sums[farms.labels[Array(farms.columns).find(key)]] = _total(farms.data[key])
		_set_shares("farms", sums, "Höfe")
		if farms.data.has("area_ha") and farms.data.has("sown_ha"):
			var sown := _total(farms.data.sown_ha)
			_set_shares("land", {"Gesät": sown, "Brach": maxf(0.0, _total(farms.data.area_ha) - sown)}, "ha",
				{"Gesät": Charts.SERIES[0], "Brach": OTHER})
			if farms.data.has("state_ha") and _shares.has("land"):
				_shares.land.foot.text += " Davon Staatsland gepachtet: %s ha." % _num(_total(farms.data.state_ha))
	var classes: Dictionary = tables.get("classes", {})
	if not classes.is_empty() and classes.data.has("money"):
		var sums := {}
		var people := {}
		for r in classes.data.kind.size():
			sums[classes.data.kind[r]] = float(classes.data.money[r])
			if classes.data.has("persons"):
				people[classes.data.kind[r]] = float(classes.data.persons[r])
		var fixed := {}
		for k in FED_NAMES.size():
			fixed[FED_NAMES[k]] = FED_COLOURS[k]
		_set_shares("money", sums, "Denar", fixed, people, "Menschen")
		_set_classes(classes, d)
	var goods: Dictionary = tables.get("goods", {})
	if not goods.is_empty() and goods.data.has("price"):
		_set_goods(goods, d)
	var state: Dictionary = tables.get("state", {})
	if not state.is_empty():
		_bar_rows = []
		for item in [["land_tax", 1.0], ["head_tax", 1.0], ["tax", 1.0], ["rent", 1.0], ["estates", 1.0], ["wages", -1.0], ["public_works", -1.0],
				["minted", 1.0], ["cash", 1.0]]:
			var i := Array(state.columns).find(item[0])
			if i >= 0:
				_bar_rows.append([state.labels[i], float(state.data[item[0]][0]) * item[1], item[0]])
		if _bars != null:
			_bars.custom_minimum_size.y = maxf(PLOT_PX, 4.0 + _bar_rows.size() * BAR_ROW)
			_bars.queue_redraw()
	_find_all(d)

static func _total(col) -> float:
	var sum := 0.0
	for v in col:
		sum += float(v)
	return sum

# ------------------------------------------------------------------ figures

## The figures as a stat strip across the page: cells of two greens in one
## gold line, as the menus' (Vic3) strips.
func _tiles_strip() -> void:
	var strip := PanelContainer.new()
	strip.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.STAT, UiStyle.GOLD_DIM, 1, 2, 0))
	_column.add_child(strip)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 0)
	strip.add_child(_tiles)
	_grid = null
## The figures as a stat strip: the name in the concepts' colour, the value, the
## change since the month before, a small curve.
func _fill_tiles(d: Dictionary) -> void:
	if _tiles == null: # a page without the figures
		return
	var specs := _tile_specs
	if _tiles.get_child_count() == 0:
		for s in specs:
			_tiles.add_child(_tile(s[0]))
	for k in specs.size():
		var s: Array = specs[k]
		var tile: PanelContainer = _tiles.get_child(k)
		if not d.has(s[0]):
			tile.visible = false
			continue
		var vals := PackedFloat64Array()
		for v in d[s[0]]:
			vals.append(float(v) * s[3])
		var n := vals.size()
		var box: VBoxContainer = tile.get_child(0)
		(box.get_child(0) as Label).text = s[1]
		(box.get_child(1) as Label).text = (Charts.label(vals[n - 1]) + s[2]) if n > 0 else "…"
		var moved := _change(vals, n - 2, s[4], s.size() > 5 and s[5])
		var change := box.get_child(2) as Label
		change.text = moved[0]
		change.add_theme_color_override("font_color", moved[1])
		var spark: Control = box.get_child(3)
		spark.set_meta("values", vals.slice(maxi(0, n - 24)))
		spark.queue_redraw()
		tile.set_meta("tip", {"id": "tile:" + s[0], "title": s[1], "kind": "Übersicht",
			"rows": [["Diesen Monat", box.get_child(1).text], ["Vormonat", (Charts.label(vals[n - 2]) + s[2]) if n > 1 else "–"],
				["Vor einem Jahr", (Charts.label(vals[n - 13]) + s[2]) if n > 12 else "–"]],
			"spark": vals, "spark_title": "Alle Monate seit Beginn", "spark_unit": s[2].strip_edges(),
			"spark_from": date.call(int(d.day[0])) if n > 0 else "", "spark_to": date.call(int(d.day[n - 1])) if n > 0 else "",
			"colour": Charts.SERIES[0],
			"text": TILE_ABOUT.get(s[0], "")})

## "▲ 3.4 %" from month `before` to the last, and its colour: a gain is
## green, unless `falling_good` (a price); `neutral` (the treasury, which
## spends what lies above its reserve) is neither good nor bad.
static func _change(vals: PackedFloat64Array, before: int, falling_good: bool, neutral := false) -> Array:
	var n := vals.size()
	if before < 0 or before >= n - 1 or vals[before] == 0.0:
		return ["", UiStyle.TEXT]
	var pct := (vals[n - 1] - vals[before]) / absf(vals[before]) * 100.0
	if absf(pct) < 0.05:
		return ["± 0 %", UiStyle.DIM]
	var good := pct < 0.0 if falling_good else pct > 0.0
	return ["%s %.1f %%" % ["▲" if pct > 0.0 else "▼", absf(pct)], UiStyle.TEXT if neutral else (UiStyle.GAIN if good else UiStyle.LOSS)]

func _tile(key: String) -> PanelContainer:
	var tile := PanelContainer.new()
	var cell := UiStyle.board(0, UiStyle.STAT if _tiles.get_child_count() % 2 == 0 else UiStyle.STAT_B)
	cell.set_border_width_all(0)
	cell.content_margin_left = 12
	cell.content_margin_right = 10
	cell.content_margin_top = 6
	cell.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", cell)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	box.add_child(_label("", UiStyle.CONCEPT, UiStyle.SIZE_TEXT))
	box.add_child(_label("…", UiStyle.VALUE, UiStyle.SIZE_HEAD + 4))
	box.add_child(_label("", UiStyle.TEXT, UiStyle.SIZE_SMALL))
	for l in box.get_children(): # long names clip, the strip keeps the window's width
		(l as Label).clip_text = true
		(l as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var spark := Control.new()
	spark.custom_minimum_size = Vector2(0, 28)
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark.draw.connect(func(): # one quiet trend for all, as the figures' colours mean nothing
		Charts.spark(spark, Rect2(Vector2(0, 4), spark.size - Vector2(6, 8)), spark.get_meta("values", PackedFloat64Array()), TREND,
			PackedFloat64Array(), PackedFloat64Array(), NAN, NAN, UiStyle.GOLD_LIT))
	box.add_child(spark)
	Tooltips.attach(tile, func(_at: Vector2) -> Dictionary: return tile.get_meta("tip", {}))
	return tile

# ------------------------------------------------------------------ cards

func _add_grid() -> void:
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_child(_grid)

## A card as Victoria 3's statistics: a board a shade lighter than the
## window, its name centred on top, under it its figure. Every card is
## built so (name LINE_PX, figure PLOT_PX, legend or foot LINE_PX), so two
## side by side are equally tall and their figures start and end on one
## line. The name's tooltip says what the numbers say now and what the card
## shows. `wide` cards (the Lage, the classes, a text) span the page.
func _card(key: String, wide := false) -> VBoxContainer:
	wide = wide or key in WIDE
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.box(CARD_BACK, CARD_EDGE, 1, 3, PAD))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wide:
		_column.add_child(card)
		_grid = null # the next cards start a row under it
	else:
		card.custom_minimum_size = Vector2(CARD_MIN, 0)
		if _grid == null:
			_add_grid()
		_grid.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var head := _label(_spec(key)[1], UiStyle.TITLE, UiStyle.SIZE_TEXT)
	head.add_theme_font_override("font", UiStyle.title_font())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.custom_minimum_size = Vector2(0, LINE_PX)
	head.clip_text = true
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	Tooltips.attach(head, func(_at: Vector2) -> Dictionary: return _card_tip(key))
	box.add_child(head)
	_heads[key] = head
	return box

## A card's name: what its numbers say now (the finding), then what it shows.
func _card_tip(key: String) -> Dictionary:
	var title: String = _heads[key].text
	var tip: Dictionary = _good_tips.get(key, {}).duplicate()
	if tip.is_empty():
		tip = {"id": "card:" + key, "title": title, "kind": "Diagramm", "text": _spec(key)[3]}
	if _says.has(key):
		tip.text = "[n]%s[/n]\n%s" % [_says[key], tip.get("text", "")]
	return tip

func _line_card(key: String) -> void:
	var box := _card(key)
	var chart := Control.new()
	chart.custom_minimum_size = Vector2(0, PLOT_PX)
	chart.mouse_filter = Control.MOUSE_FILTER_PASS # the wheel still scrolls
	box.add_child(chart)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 12)
	legend.add_theme_constant_override("v_separation", 0)
	legend.custom_minimum_size = Vector2(0, LINE_PX)
	box.add_child(legend)
	var entry := {"control": chart, "series": [], "unit": _spec(key)[2], "days": PackedInt64Array(), "hover": -1, "legend": legend,
		"hidden": {}, "marks": PackedInt32Array()}
	_lines[key] = entry
	chart.draw.connect(func():
		var days: PackedInt64Array = entry.days
		var from: String = date.call(int(days[0])) if days.size() > 0 else ""
		var to: String = date.call(int(days[days.size() - 1])) if days.size() > 0 else ""
		Charts.line_chart(chart, Rect2(Vector2.ZERO, chart.size), entry.series, UiStyle.serif(), entry.unit, from, to, entry.hover, entry.marks))
	chart.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var m: int = Charts.month_at(Rect2(Vector2.ZERO, chart.size), entry.days.size(), e.position.x, chart)
			if m != entry.hover:
				_hover_all(m))
	chart.mouse_exited.connect(func(): _hover_all(-1))
	Tooltips.attach(chart, func(_at: Vector2) -> Dictionary: return _line_tip(key))

## A line chart's series from the history: [{key, name, colour, lo?, hi?,
## band?, dashed?, scale?, muted?}].
func _set_line(key: String, h: Dictionary, specs: Array) -> void:
	if not _lines.has(key): # a card this page does not show
		return
	var entry: Dictionary = _lines[key]
	var d: Dictionary = h.data
	var series := []
	for s in specs:
		if not d.has(s.key):
			continue
		var scale: float = s.get("scale", 1.0) # shares as per cent
		var scaled := func(key: String) -> PackedFloat64Array:
			var out := PackedFloat64Array()
			for v in d[key]:
				out.append(float(v) * scale)
			return out.slice(_first(out.size()))
		var one := {"name": s.name, "colour": s.colour, "values": scaled.call(s.key),
			"dashed": s.get("dashed", false), "hidden": entry.hidden.has(s.name), "muted": s.get("muted", false)}
		if s.has("mute_above"): # emphasis: only the lines that tell the story keep their colour
			var low := INF
			for v in one.values:
				low = minf(low, v)
			one.muted = low >= s.mute_above
		if s.has("lo") and d.has(s.lo) and d.has(s.hi):
			one.lo = scaled.call(s.lo)
			one.hi = scaled.call(s.hi)
			one.band = s.get("band", "Spanne")
		series.append(one)
	entry.series = series
	if key in TAX_CARDS: # a game from before the tax law: no card
		entry.control.get_parent().get_parent().visible = not series.is_empty()
	var days := PackedInt64Array(Array(d.day))
	entry.days = days.slice(_first(days.size()))
	if d.has("yearly"):
		entry.yearly = Array(d.yearly).slice(_first(days.size()))
	var marks := PackedInt32Array()
	for i in entry.days.size():
		if _events.has(int(entry.days[i])):
			marks.append(i)
	entry.marks = marks
	var legend: HFlowContainer = entry.legend
	for c in legend.get_children():
		c.queue_free()
	if series.size() > 1 or series.size() == 1 and series[0].has("lo"):
		for s in series:
			var sw := _swatch(Charts.MUTED if s.get("muted", false) else s.colour, s.name)
			if series.size() > 1: # a click hides or shows the line, as EU5's legends
				_toggle(sw, entry, s.name)
			legend.add_child(sw)
		for one in series:
			if one.has("lo"):
				legend.add_child(_swatch(Color(one.colour, 0.35), one.band))
	entry.control.queue_redraw()

## One month under the mouse for all line charts, as linked views: the
## same month stands out in every chart at once.
func _hover_all(m: int) -> void:
	for key in _lines:
		var entry: Dictionary = _lines[key]
		var want := m if m < entry.days.size() else -1
		if entry.hover != want:
			entry.hover = want
			entry.control.queue_redraw()

## The first row the chosen span shows of n months.
func _first(n: int) -> int:
	return 0 if _span <= 0 else maxi(0, n - _span)

## A legend entry that hides and shows its series on a click.
func _toggle(sw: HBoxContainer, entry: Dictionary, name: String) -> void:
	sw.mouse_filter = Control.MOUSE_FILTER_STOP
	sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sw.modulate.a = 0.4 if entry.hidden.has(name) else 1.0
	Tooltips.attach(sw, func(_at: Vector2) -> Dictionary: return {"id": "legend:" + name, "title": name,
		"kind": "Linie", "hints": [["Klick", "ausblenden" if not entry.hidden.has(name) else "einblenden"]]})
	sw.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if entry.hidden.has(name):
				entry.hidden.erase(name)
			else:
				entry.hidden[name] = true
			sw.modulate.a = 0.4 if entry.hidden.has(name) else 1.0
			for one in entry.series:
				if one.name == name:
					one.hidden = entry.hidden.has(name)
			entry.control.queue_redraw())

## The month under the mouse: each series' value, the band's ends.
func _line_tip(key: String) -> Dictionary:
	var title: String = _heads[key].text
	var entry: Dictionary = _lines[key]
	var m: int = entry.hover
	if m < 0 or entry.series.is_empty():
		return {}
	var unit: String = entry.unit
	var rows := []
	for s in entry.series:
		if m < s.values.size() and not s.hidden:
			rows.append([s.name, Charts.label(s.values[m], unit), s.colour if s.colour == Charts.RED else UiStyle.TEXT])
			if s.has("lo"):
				rows.append(["  Unten im Band", Charts.label(s.lo[m], unit)])
				rows.append(["  Oben im Band", Charts.label(s.hi[m], unit)])
	if key == "real" and entry.series.size() > 1 and m < entry.series[1].values.size():
		var gap: float = entry.series[0].values[m] - entry.series[1].values[m]
		rows.append(["Median über dem Nötigen" if gap >= 0.0 else "Median fehlt zum Nötigen", Charts.label(absf(gap), unit),
			UiStyle.GAIN if gap >= 0.0 else UiStyle.LOSS])
	if m > 0:
		var before: float = entry.series[0].values[m - 1]
		var now: float = entry.series[0].values[m]
		var diff := now - before
		rows.append(["Zum Vormonat", ("+" if diff > 0.0 else ("−" if diff < 0.0 else "±")) + Charts.label(absf(diff), unit)])
	var tip := {"id": "line:%s:%d" % [key, m], "title": title, "kind": date.call(int(entry.days[m])), "rows": rows}
	var happened: Array = _events.get(int(entry.days[m]), [])
	if not happened.is_empty():
		tip.text = "[n]In diesem Monat:[/n] " + "; ".join(happened) + "."
	if entry.has("yearly") and m < entry.yearly.size() and entry.yearly[m]:
		tip.text = "Vor den letzten zehn Jahren behält der Markt jedes Jahr als sein Mittel: dieser Wert gilt für das ganze Jahr."
	return tip

# ------------------------------------------------------------------ shares and the classes' rows

## Shares of a whole as sorted bars, as the menu's (Vic3) lists: a medal,
## the name, the bar in its trough, the share. The largest on top, the
## smallest folded into "Andere" at the foot. `ref` (set by _set_shares)
## marks a second share per row as a tick: on the money card, the people.
func _shares_card(key: String) -> void:
	var box := _card(key)
	var rows := Control.new()
	rows.custom_minimum_size = Vector2(0, PLOT_PX)
	rows.mouse_filter = Control.MOUSE_FILTER_PASS # the wheel still scrolls
	box.add_child(rows)
	var foot := _foot()
	box.add_child(foot)
	var entry := {"control": rows, "names": PackedStringArray(), "values": PackedFloat64Array(), "colours": [],
		"ref": PackedFloat64Array(), "ref_name": "", "total": 0.0, "unit": "", "title": _spec(key)[1], "hover": -1, "foot": foot}
	_shares[key] = entry
	rows.draw.connect(func(): _draw_shares(rows, entry))
	rows.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var i := int(e.position.y / BAR_ROW)
			if i >= entry.names.size():
				i = -1
			if i != entry.hover:
				entry.hover = i
				rows.queue_redraw())
	rows.mouse_exited.connect(func():
		entry.hover = -1
		rows.queue_redraw())
	Tooltips.attach(rows, func(at: Vector2) -> Dictionary: return _shares_tip(key, int(at.y / BAR_ROW)))

## `sums` name -> amount; `colours` name -> the colour a name keeps in
## every chart (the classes), the others get a plain medal; `ref` name ->
## a second amount drawn as a tick, named `ref_name`.
func _set_shares(key: String, sums: Dictionary, unit: String, colours := {}, ref := {}, ref_name := "") -> void:
	_sums[key] = sums
	if not _shares.has(key):
		return
	var entry: Dictionary = _shares[key]
	var names := sums.keys()
	names.sort_custom(func(a, b): return sums[a] > sums[b])
	var ref_total := 0.0
	for name in ref:
		ref_total += float(ref[name])
	var shown := PackedStringArray()
	var values := PackedFloat64Array()
	var refs := PackedFloat64Array()
	var hues := []
	var rest := 0.0
	var rest_ref := 0.0
	var total := 0.0
	for i in names.size():
		var v := float(sums[names[i]])
		total += v
		var r := float(ref.get(names[i], 0.0)) / ref_total if ref_total > 0.0 else 0.0
		if i < BARS_MAX or names.size() == BARS_MAX + 1:
			shown.append(names[i])
			values.append(v)
			refs.append(r)
			hues.append(colours.get(names[i], Color.TRANSPARENT))
		else:
			rest += v
			rest_ref += r
	if rest > 0.0:
		shown.append("Andere")
		values.append(rest)
		refs.append(rest_ref)
		hues.append(OTHER)
	entry.names = shown
	entry.values = values
	entry.colours = hues
	entry.ref = refs if ref_total > 0.0 else PackedFloat64Array()
	entry.ref_name = ref_name
	entry.total = total
	entry.unit = unit
	var rows: Control = entry.control
	rows.custom_minimum_size.y = maxf(PLOT_PX, BAR_ROW * shown.size())
	var foot: Label = entry.foot
	foot.text = "Zusammen %s %s." % [_num(total), unit]
	if ref_total > 0.0:
		foot.text += " Der weisse Strich: Anteil an den %s." % ref_name
	rows.queue_redraw()

func _draw_shares(ci: Control, entry: Dictionary) -> void:
	var n: int = entry.names.size()
	var total: float = entry.total
	if n == 0 or total <= 0.0:
		return
	var font := UiStyle.serif()
	var top := 0.0 # the longest bar or tick fills the trough
	var name_w := 0.0
	for i in n:
		top = maxf(top, entry.values[i] / total)
		if i < entry.ref.size():
			top = maxf(top, entry.ref[i])
		name_w = maxf(name_w, font.get_string_size(entry.names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_TEXT).x)
	var x0 := NAME_X + minf(name_w, 140.0) + 10.0
	var x1 := ci.size.x - SHARE_PX - 8.0
	for i in n:
		var y := i * BAR_ROW
		var mid := y + (BAR_ROW - 2.0) * 0.5
		ci.draw_rect(Rect2(0, y, ci.size.x, BAR_ROW - 2.0), UiStyle.ROW if i % 2 == 0 else UiStyle.ROW_DARK)
		if i == entry.hover:
			ci.draw_rect(Rect2(0, y, ci.size.x, BAR_ROW - 2.0), UiStyle.HOVER)
		_medal(ci, Vector2(MEDAL_R + 5.0, mid), entry.names[i], entry.colours[i])
		UiStyle.text_at(ci, Vector2(NAME_X, mid + 5.0), entry.names[i], UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, x0 - NAME_X - 6.0, font)
		var share: float = entry.values[i] / total
		var trough := Rect2(x0, mid - BAR_PX * 0.5 - 2.0, x1 - x0, BAR_PX + 4.0)
		var inner := trough.size.x - 4.0
		_bar(ci, trough, x0 + 2.0, x0 + 2.0 + inner * share / top, UiStyle.GOLD)
		if i < entry.ref.size() and entry.ref[i] > 0.0:
			var x: float = x0 + 2.0 + inner * entry.ref[i] / top
			ci.draw_line(Vector2(x, trough.position.y - 3.0), Vector2(x, trough.end.y + 3.0), UiStyle.EDGE, 4.0)
			ci.draw_line(Vector2(x, trough.position.y - 2.0), Vector2(x, trough.end.y + 2.0), UiStyle.TEXT, 2.0)
		UiStyle.text_at(ci, Vector2(x1 + 4.0, mid + 5.0), _pct(share * 100.0) + " %", UiStyle.VALUE, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, SHARE_PX, font)

func _shares_tip(key: String, i: int) -> Dictionary:
	var entry: Dictionary = _shares[key]
	if i < 0 or i >= entry.names.size() or entry.total <= 0.0:
		return {}
	var share: float = entry.values[i] / entry.total * 100.0
	var rows := [[entry.unit, _num(entry.values[i])], ["Anteil", _pct(share) + " %"]]
	if i < entry.ref.size():
		rows.append(["Anteil an den " + entry.ref_name, _pct(entry.ref[i] * 100.0) + " %"])
		if entry.ref[i] > 0.0:
			rows.append(["Je Kopf, gemessen am Schnitt", "%s×" % _pct(share / (entry.ref[i] * 100.0))])
	return {"id": "share:%s:%d" % [key, i], "title": entry.names[i], "kind": entry.title, "rows": rows}

## Small multiples by class, a row each with the class, its curve on one
## scale for all rows, and its value now (or in the month under the mouse):
## "fed" what each class ate (red is what was missing to eat one's fill),
## "gini_rows" how unequal its money is, the Gini over all people on top.
func _rows_card(key: String) -> void:
	var box := _card(key)
	var rows := Control.new()
	rows.custom_minimum_size = Vector2(0, PLOT_PX)
	rows.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(rows)
	var foot := _foot()
	box.add_child(foot)
	# a line chart for _hover_all: the month under the mouse is shared
	var entry := {"control": rows, "series": [], "days": PackedInt64Array(), "hover": -1, "row": -1, "lo": 90.0, "hi": 100.0,
		"foot": foot, "kind": key, "title": _spec(key)[1]}
	_lines[key] = entry
	rows.draw.connect(func(): _draw_rows(rows, entry))
	rows.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var row := int(e.position.y / FED_ROW)
			if row != entry.row:
				entry.row = row
				rows.queue_redraw()
			var plot := _row_plot(rows, 0)
			var n: int = entry.days.size()
			var m := -1
			if n > 1 and e.position.x >= plot.position.x - 4.0 and e.position.x <= plot.end.x + 4.0:
				m = clampi(roundi((e.position.x - plot.position.x) / plot.size.x * (n - 1)), 0, n - 1)
			if m != entry.hover:
				_hover_all(m))
	rows.mouse_exited.connect(func():
		entry.row = -1
		rows.queue_redraw()
		_hover_all(-1))
	Tooltips.attach(rows, func(at: Vector2) -> Dictionary: return _rows_tip(key, int(at.y / FED_ROW)))

## The rows of card `key` from the history: fed_<class> in per cent, or
## the Gini over all (gini) and gini_<class>.
func _set_rows(key: String, d: Dictionary) -> void:
	if not _lines.has(key):
		return
	var entry: Dictionary = _lines[key]
	var fed := key == "fed"
	var series := []
	var lo := 100.0
	var hi := 0.0
	var specs := [] if fed else [["gini", "Alle", OTHER]]
	for k in FED_KEYS.size():
		specs.append([("fed_" if fed else "gini_") + FED_KEYS[k], FED_NAMES[k], FED_COLOURS[k]])
	for spec in specs:
		var all := _col(d, spec[0], 100.0 if fed else 1.0)
		if all.is_empty():
			continue
		var values := all.slice(_first(all.size()))
		lo = minf(lo, _lowest(values))
		hi = maxf(hi, _highest(values))
		series.append({"name": spec[1], "colour": spec[2], "values": values, "all": all})
	entry.series = series
	if fed:
		entry.lo = clampf(floorf((lo - 5.0) / 10.0) * 10.0, 0.0, 90.0) # room below the lowest
		entry.hi = 100.0
	else: # a tenth of room below the lowest, so the rows' differences show
		entry.lo = clampf(floorf((lo - 0.05) * 10.0) / 10.0, 0.0, 0.9)
		entry.hi = clampf(ceilf(hi * 10.0) / 10.0, entry.lo + 0.1, 1.0)
	var days := PackedInt64Array(Array(d.day))
	entry.days = days.slice(_first(days.size()))
	var foot: Label = entry.foot
	if fed:
		foot.text = "Alle Zeilen von %d bis 100 %%, rot fehlt zum Sattwerden." % int(entry.lo)
	else:
		foot.text = "Alle Zeilen von %s bis %s. Je höher, desto ungleicher." % [Charts.label(entry.lo), Charts.label(entry.hi)]
	entry.control.custom_minimum_size.y = maxf(PLOT_PX, FED_ROW * series.size())
	entry.control.queue_redraw()

## Row k's plot: right of the medal and name, left of the value.
func _row_plot(ci: Control, k: int) -> Rect2:
	var x0 := NAME_X + FED_NAME_PX
	return Rect2(x0, k * FED_ROW + 4.0, ci.size.x - x0 - SHARE_PX - 10.0, FED_ROW - 10.0)

func _draw_rows(ci: Control, entry: Dictionary) -> void:
	var font := UiStyle.serif()
	var fed: bool = entry.kind == "fed"
	var lo: float = entry.lo
	var hi: float = entry.hi
	for row in entry.series.size():
		var s: Dictionary = entry.series[row]
		var y: float = row * FED_ROW
		var mid := y + (FED_ROW - 2.0) * 0.5
		ci.draw_rect(Rect2(0, y, ci.size.x, FED_ROW - 2.0), UiStyle.ROW if row % 2 == 0 else UiStyle.ROW_DARK)
		if row == entry.row:
			ci.draw_rect(Rect2(0, y, ci.size.x, FED_ROW - 2.0), UiStyle.HOVER)
		_medal(ci, Vector2(MEDAL_R + 5.0, mid), s.name, s.colour)
		UiStyle.text_at(ci, Vector2(NAME_X, mid + 5.0), s.name, UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, FED_NAME_PX - 6.0, font)
		var plot := _row_plot(ci, row)
		ci.draw_rect(plot.grow(1.0), UiStyle.EDGE)
		ci.draw_rect(plot, UiStyle.CHART)
		var vals: PackedFloat64Array = s.values
		var n := vals.size()
		var y_of := func(v: float) -> float: return plot.end.y - 1.0 - (clampf(v, lo, hi) - lo) / (hi - lo) * (plot.size.y - 2.0)
		var x_of := func(i: int) -> float: return plot.position.x + plot.size.x * float(i) / float(maxi(1, n - 1))
		var full: float = y_of.call(100.0)
		if fed:
			for part in Charts.dashes(PackedVector2Array([Vector2(plot.position.x, full), Vector2(plot.end.x, full)]), 4.0, 3.0):
				ci.draw_polyline(part, UiStyle.DIM, 1.0)
		if n >= 2:
			# the gap to 100 %, a polygon per run of hungry months
			var i := 0
			while fed and i < n:
				if vals[i] >= 99.999:
					i += 1
					continue
				var gap := PackedVector2Array([Vector2(x_of.call(maxi(0, i - 1)), full)])
				if i == 0:
					gap.append(Vector2(x_of.call(0), full))
				while i < n and vals[i] < 99.999:
					gap.append(Vector2(x_of.call(i), y_of.call(vals[i])))
					i += 1
				gap.append(Vector2(x_of.call(mini(i, n - 1)), full))
				if gap[0] == gap[1]:
					gap.remove_at(0)
				if gap.size() >= 3 and Geometry2D.triangulate_polygon(gap).size() > 0:
					ci.draw_colored_polygon(gap, Color(Charts.RED, 0.3))
			var line := PackedVector2Array()
			for j in n:
				line.append(Vector2(x_of.call(j), y_of.call(vals[j])))
			ci.draw_polyline(line, Charts.SERIES[0], 1.5, true)
		var hovered: bool = entry.hover >= 0 and entry.hover < n
		var m: int = entry.hover if hovered else n - 1
		if hovered and n >= 2:
			var x: float = x_of.call(m)
			ci.draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(UiStyle.TEXT, 0.45), 1.0)
			ci.draw_circle(Vector2(x, y_of.call(vals[m])), 2.5, UiStyle.VALUE)
		if n > 0:
			var text := ("%d %%" % floori(vals[m])) if fed else "%.2f" % vals[m]
			UiStyle.text_at(ci, Vector2(ci.size.x - SHARE_PX - 6.0, mid + 5.0), text,
				UiStyle.LOSS if fed and vals[m] < 99.0 else UiStyle.VALUE, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, SHARE_PX, font)

## A row: the month under the mouse (or the last), its lowest (fed) or
## highest (Gini) month, how many it counts, and its whole curve since the start.
func _rows_tip(key: String, row: int) -> Dictionary:
	var entry: Dictionary = _lines[key]
	if row < 0 or row >= entry.series.size():
		return {}
	var fed := key == "fed"
	var s: Dictionary = entry.series[row]
	var vals: PackedFloat64Array = s.values
	var n := vals.size()
	if n == 0:
		return {}
	var m: int = entry.hover if entry.hover >= 0 and entry.hover < n else n - 1
	var worst := 0
	for i in n:
		if (vals[i] < vals[worst]) if fed else (vals[i] > vals[worst]):
			worst = i
	var show := func(v: float) -> String: return ("%d %%" % floori(v)) if fed else "%.2f" % v
	var rows := [["Gegessen vom Bedarf" if fed else "Gini des Geldes", show.call(vals[m]), UiStyle.LOSS if fed and vals[m] < 99.0 else UiStyle.TEXT]]
	if m > 0:
		rows.append(["Vormonat", show.call(vals[m - 1])])
	rows.append(["Tiefster Monat" if fed else "Ungleichster Monat", "%s, %s" % [show.call(vals[worst]), date.call(int(entry.days[worst]))]])
	var classes: Dictionary = _tables.get("classes", {})
	if not classes.is_empty() and classes.data.has("persons"):
		var r := Array(classes.data.kind).find(s.name)
		if r >= 0:
			rows.append(["Menschen heute", _num(float(classes.data.persons[r]))])
	var tip := {"id": "%s:%s:%d" % [key, s.name, m], "title": s.name, "kind": date.call(int(entry.days[m])), "rows": rows}
	var happened: Array = _events.get(int(entry.days[m]), [])
	if not happened.is_empty():
		tip.text = "[n]In diesem Monat:[/n] " + "; ".join(happened) + "."
	var all: PackedFloat64Array = s.all
	if all.size() > 1:
		var h: Dictionary = _tables.get("history", {}).get("data", {})
		tip.spark = all
		tip.spark_title = "Gegessen seit Beginn" if fed else "Gini seit Beginn"
		tip.spark_unit = "%" if fed else ""
		if fed:
			var full := PackedFloat64Array()
			full.resize(all.size())
			full.fill(100.0)
			tip.spark_ref = full # satt
		tip.colour = Charts.SERIES[0]
		if h.has("day"):
			tip.spark_from = date.call(int(h.day[0]))
			tip.spark_to = date.call(int(h.day[h.day.size() - 1]))
	return tip

## A bar as the menu's (Vic3) bars: a dark trough with a thin edge, the bar
## BAR_PX high inside it, dark where it starts and light where it ends.
func _bar(ci: CanvasItem, trough: Rect2, start: float, end: float, colour: Color) -> void:
	ci.draw_rect(trough, UiStyle.CHART_GRID)
	ci.draw_rect(trough, UiStyle.EDGE, false, 1.0)
	if absf(end - start) < 0.5:
		return
	var a := Vector2(start, trough.position.y + (trough.size.y - BAR_PX) * 0.5)
	var b := Vector2(end, a.y)
	var dark := colour.darkened(0.45)
	var light := colour.lightened(0.2)
	ci.draw_polygon(PackedVector2Array([a, b, b + Vector2(0, BAR_PX), a + Vector2(0, BAR_PX)]),
		PackedColorArray([dark, light, light, dark]))

## A row's round medal in a gold rim, as the menu's (Vic3) lists: its icon
## when it has one, else its first letter; on the colour the
## entity keeps in every chart, or dark.
func _medal(ci: CanvasItem, at: Vector2, name: String, colour: Color, radius := MEDAL_R) -> void:
	var rim := radius / MEDAL_R
	ci.draw_circle(at, radius + rim, UiStyle.EDGE)
	ci.draw_circle(at, radius, UiStyle.GOLD)
	ci.draw_circle(at, radius - 1.5 * rim, colour.darkened(0.3) if colour.a > 0.0 else UiStyle.INSET)
	var icon := _icon(name)
	if icon != null:
		var side := (radius - 2.5 * rim) * 2.0 * (0.82 if radius > MEDAL_R else 1.0)
		ci.draw_texture_rect(icon, Rect2(at - Vector2(side, side) * 0.5, Vector2(side, side)), false, UiStyle.TEXT)
	else:
		UiStyle.text_at(ci, at + Vector2(-radius, 4.0 * rim), name.left(1), UiStyle.TEXT, roundi((UiStyle.SIZE_SMALL - 1) * rim), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, UiStyle.bold())

func _icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = Vic3Style.icon(ICONS[name]) if ICONS.has(name) else null
	return _icons[name]

# ------------------------------------------------------------------ goods

## All goods at a glance across the page, three to a row: each its name,
## price, change against the month before and its course.
func _goods_card(key: String) -> void:
	var box := _card(key, true)
	_goods = GridContainer.new()
	_goods.columns = 3
	_goods.add_theme_constant_override("h_separation", 6)
	_goods.add_theme_constant_override("v_separation", 6)
	box.add_child(_goods)

func _good_tile(r: int) -> PanelContainer:
	var tile := PanelContainer.new()
	var back := UiStyle.box(UiStyle.ROW if r % 2 == 0 else UiStyle.ROW_DARK, Color(UiStyle.GOLD_DIM, 0.6), 1, 2, 0)
	back.content_margin_left = 8
	back.content_margin_right = 8
	back.content_margin_top = 4
	back.content_margin_bottom = 4
	tile.add_theme_stylebox_override("panel", back)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	var name := _label("", UiStyle.CONCEPT, UiStyle.SIZE_TEXT)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name)
	top.add_child(_label("", UiStyle.VALUE, UiStyle.SIZE_TEXT))
	box.add_child(_label("", UiStyle.DIM, UiStyle.SIZE_SMALL))
	var spark := Control.new()
	spark.custom_minimum_size = Vector2(0, 40)
	spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spark.draw.connect(func(): # small multiples in one hue: the name says which good
		Charts.board(spark, Rect2(Vector2.ZERO, spark.size), false)
		Charts.spark(spark, Rect2(Vector2(4, 4), spark.size - Vector2(10, 8)), spark.get_meta("values", PackedFloat64Array()), Charts.SERIES[0]))
	box.add_child(spark)
	Tooltips.attach(tile, func(_at: Vector2) -> Dictionary: return tile.get_meta("tip", {}))
	return tile

## The goods' tiles from the goods table and the history, each with the
## tooltip of its chart's name and its price since the start.
func _fill_good_tiles(goods: Dictionary, h: Dictionary) -> void:
	if _goods == null:
		return
	var n: int = mini(goods.data.good.size(), GOOD_KEYS.size())
	while _goods.get_child_count() < n:
		_goods.add_child(_good_tile(_goods.get_child_count()))
	for r in n:
		var tile: PanelContainer = _goods.get_child(r)
		var all := _col(h, "good_" + GOOD_KEYS[r])
		var change := _change(all, all.size() - 2, true)
		var box: VBoxContainer = tile.get_child(0)
		(box.get_child(0).get_child(0) as Label).text = goods.data.good[r]
		(box.get_child(0).get_child(1) as Label).text = "%s D je %s" % [Charts.label(float(goods.data.price[r])), goods.data.unit[r]]
		var moved := box.get_child(1) as Label
		moved.text = change[0] + ("  zum Vormonat" if change[0] != "" else "")
		moved.add_theme_color_override("font_color", UiStyle.DIM) # dearer is good for the maker, bad for the buyer
		var spark: Control = box.get_child(2)
		spark.set_meta("values", all.slice(_first(all.size())))
		spark.queue_redraw()
		var tip: Dictionary = _good_tips.get(("m_good%d" if _market else "good%d") % r, {}).duplicate()
		if all.size() > 1:
			tip.spark = all
			tip.spark_title = "Preis seit Beginn"
			tip.spark_unit = "D"
			tip.spark_from = date.call(int(h.day[0]))
			tip.spark_to = date.call(int(h.day[h.day.size() - 1]))
			tip.colour = Charts.SERIES[0]
		tile.set_meta("tip", tip)

## Each good's card (a line chart of its price): its name and unit from the
## goods table, and its name's tooltip with its price, store and flows
## since the start (one market's: why it costs what it costs there).
func _set_goods(goods: Dictionary, h: Dictionary) -> void:
	for r in mini(goods.data.good.size(), GOOD_KEYS.size()):
		var key := ("m_good%d" if _market else "good%d") % r
		var all := _col(h, "good_" + GOOD_KEYS[r])
		var unit: String = goods.data.unit[r]
		var price := float(goods.data.price[r])
		var rows := [["Preis", "%s D je %s" % [Charts.label(price), unit]],
			["Vormonat", Charts.label(all[all.size() - 2]) + " D" if all.size() > 1 else "–"],
			["Vor einem Jahr", Charts.label(all[all.size() - 13]) + " D" if all.size() > 12 else "–"],
			["Marktlager", "%s %s" % [Charts.label(float(goods.data.store[r])), unit]]]
		# the flows since the start once the tooltip is locked, so it opens short
		var since := []
		for col in [["made", "hergestellt"], ["bought", "gekauft"], ["moved", "zwischen Märkten gehandelt"],
				["imported", "von ausserhalb gekauft"], ["exported", "nach ausserhalb verkauft"]]:
			if goods.data.has(col[0]):
				since.append("[n]%s %s[/n] %s" % [Charts.label(float(goods.data[col[0]][r])), unit, col[1]])
		var tip := {"id": "good:%d" % r, "title": goods.data.good[r], "kind": "Ware", "rows": rows, "text": _spec(key)[3]}
		if goods.data.has("why") and str(goods.data.why[r]) != "":
			tip.text += " " + str(goods.data.why[r])
		if not since.is_empty():
			tip.more = "Seit Beginn: " + ", ".join(since) + "."
		_good_tips[key] = tip
		if _heads.has(key):
			_heads[key].text = goods.data.good[r]
		if _lines.has(key):
			_lines[key].unit = "D/" + unit
			_lines[key].control.queue_redraw()
	_fill_good_tiles(goods, h)

# ------------------------------------------------------------------ the Lage

func _lage_card() -> void:
	var box := _card("lage", true)
	_lage = VBoxContainer.new()
	_lage.add_theme_constant_override("separation", 0)
	box.add_child(_lage)

## The findings as one list by topic, a line each: its card's name, what it
## says. A click on a line opens its card's page.
func _set_lage() -> void:
	if _lage == null:
		return
	for c in _lage.get_children():
		c.queue_free()
	var topic := ""
	var k := 0
	for key in (LAGE_MARKET if _market else LAGE_REALM):
		if not _says.has(key):
			continue
		var to := page_of(key, _market)
		if not _market and TOPICS.get(to, "") != topic:
			topic = TOPICS.get(to, "")
			var name := _label(topic, UiStyle.GOLD, UiStyle.SIZE_SMALL)
			name.add_theme_font_override("font", UiStyle.title_font())
			name.custom_minimum_size = Vector2(0, LINE_PX + (6.0 if k > 0 else 0.0))
			name.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_lage.add_child(name)
		_lage.add_child(_lage_line(key, to, k))
		k += 1

func _lage_line(key: String, to: String, k: int) -> PanelContainer:
	var row := PanelContainer.new()
	var back := UiStyle.box(UiStyle.ROW if k % 2 == 0 else UiStyle.ROW_DARK, Color.TRANSPARENT, 0, 0, 0)
	back.content_margin_left = 8
	back.content_margin_right = 8
	back.content_margin_top = 2
	back.content_margin_bottom = 2
	row.add_theme_stylebox_override("panel", back)
	row.mouse_filter = Control.MOUSE_FILTER_PASS # the wheel still scrolls
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var title: String = _heads[key].text if _heads.has(key) else _spec(key)[1]
	var name := _label(title, UiStyle.CONCEPT if to != "" else UiStyle.TEXT, UiStyle.SIZE_TEXT)
	name.custom_minimum_size = Vector2(LAGE_NAME_PX * (0.75 if _market else 1.0), 0) # a market's window is narrower
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name)
	var says := _label(_says[key], UiStyle.TEXT, UiStyle.SIZE_TEXT)
	says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	says.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	says.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(says)
	var tip := {"id": "lage:" + key, "title": title, "kind": TOPICS.get(to, "Lage"), "text": _spec(key)[3]}
	if to != "":
		tip.hints = [["Klick", "Diagramm öffnen"]]
		var lit := back.duplicate()
		lit.bg_color = UiStyle.SELECTED
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.mouse_entered.connect(func(): row.add_theme_stylebox_override("panel", lit))
		row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", back))
		row.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				go.emit(to))
	Tooltips.attach(row, func(_at: Vector2) -> Dictionary: return tip)
	return row

# ------------------------------------------------------------------ the classes side by side

## The classes side by side as Victoria 3's population: a framed column
## per class, its medal and name on top, its people as a big figure, its
## medal large where Victoria 3 has a face, whether it is fed, its money a
## head, then sections of lines (CLASS_PARTS), in the colours of the table
## before them. What a class did not eat shows red.
func _classes_card() -> void:
	var box := _card("classes", true)
	_class_table = Control.new()
	_class_table.custom_minimum_size = Vector2(0, CLASS_PX)
	_class_table.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_class_table)
	_class_table.draw.connect(_draw_classes)
	for spec in CLASS_PARTS: # loaded before the first draw, which shows a texture loaded in it as a blank square
		if spec.size() > 4 and spec[3] == "line" and spec[4] != "":
			_icons["file:" + spec[4]] = Vic3Style.icon(spec[4])
	_class_table.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var at := _class_at(e.position)
			if at != _class_hover:
				_class_hover = at
				_class_table.queue_redraw())
	_class_table.mouse_exited.connect(func():
		_class_hover = Vector2i(-1, -1)
		_class_table.queue_redraw())
	Tooltips.attach(_class_table, func(at: Vector2) -> Dictionary: return _class_tip(_class_at(at)))

## The class (column) and the part of its column (CLASS_PARTS) at `p`; -1
## between the columns and outside the parts.
func _class_at(p: Vector2) -> Vector2i:
	var n := _class_names.size()
	if n == 0:
		return Vector2i(-1, -1)
	var w := _class_width(n)
	var r := mini(int(p.x / (w + CLASS_GAP)), n - 1)
	if p.x - r * (w + CLASS_GAP) > w:
		return Vector2i(-1, -1)
	for k in CLASS_PARTS.size():
		if p.y >= CLASS_PARTS[k][1] and p.y < CLASS_PARTS[k][1] + CLASS_PARTS[k][2]:
			return Vector2i(r, k)
	return Vector2i(r, -1)

func _class_width(n: int) -> float:
	return (_class_table.size.x - CLASS_GAP * (n - 1)) / n

## The cells from the classes table, the Gini of each class from the history.
func _set_classes(classes: Dictionary, d: Dictionary) -> void:
	if _class_table == null:
		return
	var data: Dictionary = classes.data
	var n: int = data.kind.size()
	_class_names = PackedStringArray(Array(data.kind))
	var people := _total(data.get("persons", []))
	var money := _total(data.money)
	_class_cells = []
	for spec in CLASS_ROWS:
		var line := []
		for r in n:
			var text := "–"
			var colour := UiStyle.VALUE
			var key: String = spec[0]
			if key == "share" and people > 0.0:
				text = _pct(float(data.persons[r]) / people * 100.0) + " %"
			elif key == "money_share" and money > 0.0:
				text = _pct(float(data.money[r]) / money * 100.0) + " %"
			elif key == "gini":
				var g := _col(d, "gini_" + FED_KEYS[FED_NAMES.find(data.kind[r])]) if FED_NAMES.has(data.kind[r]) else PackedFloat64Array()
				text = "%.2f" % g[g.size() - 1] if g.size() > 0 else "–"
			elif not data.has(key):
				pass
			elif key == "eaten":
				text = "%d %%" % floori(float(data.eaten[r]) * 100.0)
				colour = UiStyle.LOSS if float(data.eaten[r]) < 0.99 else UiStyle.VALUE
			elif key == "clothes":
				text = "%d %%" % roundi(float(data.clothes[r]) * 100.0)
			elif key == "money_head":
				text = _num(float(data.money_head[r]))
			else:
				text = _num(float(data[key][r]))
			line.append([text, colour])
		_class_cells.append(line)
	_class_table.queue_redraw()

## A cell of the classes: [text, colour] of `key` (CLASS_ROWS) for class `r`.
func _class_cell(key: String, r: int) -> Array:
	for line in CLASS_ROWS.size():
		if CLASS_ROWS[line][0] == key and line < _class_cells.size() and r < _class_cells[line].size():
			return _class_cells[line][r]
	return ["–", UiStyle.VALUE]

func _draw_classes() -> void:
	var ci := _class_table
	var n := _class_names.size()
	if n == 0:
		return
	var font := UiStyle.serif()
	var bold := UiStyle.bold()
	var w := _class_width(n)
	for r in n:
		var x := r * (w + CLASS_GAP)
		var name := _class_names[r]
		var k := FED_NAMES.find(name)
		var colour: Color = FED_COLOURS[k] if k >= 0 else OTHER
		ci.draw_rect(Rect2(x, 0, w, CLASS_PX), UiStyle.INSET)
		# the head: medal and name in one line, centred
		var name_w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_TEXT).x
		var left := x + maxf(6.0, (w - MEDAL_R * 2.0 - 6.0 - name_w) * 0.5)
		_medal(ci, Vector2(left + MEDAL_R, 16.0), name, colour)
		UiStyle.text_at(ci, Vector2(left + MEDAL_R * 2.0 + 6.0, 22.0), name, UiStyle.TEXT, UiStyle.SIZE_TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, x + w - left - MEDAL_R * 2.0 - 10.0, font)
		# the picture: its medal large
		var face := Rect2(x + CLASS_FACE.position.x, CLASS_FACE.position.y, w - CLASS_FACE.position.x * 2.0, CLASS_FACE.size.y)
		_medal(ci, face.get_center(), name, colour, CLASS_FACE_R)
		for part in CLASS_PARTS.size():
			_draw_class_part(ci, part, r, Rect2(x, CLASS_PARTS[part][1], w, CLASS_PARTS[part][2]), font, bold)
		ci.draw_rect(Rect2(x, 0, w, CLASS_PX), CARD_EDGE, false, 1.0)

## One part of a class's column (CLASS_PARTS[part]) in `at`.
func _draw_class_part(ci: CanvasItem, part: int, r: int, at: Rect2, font: Font, bold: Font) -> void:
	var spec: Array = CLASS_PARTS[part]
	var cell := _class_cell(spec[0], r) if spec[0] != "" else ["", UiStyle.VALUE]
	var lit := _class_hover == Vector2i(r, part)
	var base := at.position.y + at.size.y * 0.5 + 6.0 # a line's baseline, its text centred
	match spec[3]:
		"big":
			UiStyle.text_at(ci, Vector2(at.position.x, at.end.y - 4.0), cell[0], UiStyle.VALUE, UiStyle.SIZE_HEAD + 6,
				HORIZONTAL_ALIGNMENT_CENTER, at.size.x, bold)
		"note":
			UiStyle.text_at(ci, Vector2(at.position.x, base), cell[0] + " der Menschen", UiStyle.DIM, UiStyle.SIZE_SMALL,
				HORIZONTAL_ALIGNMENT_CENTER, at.size.x, font)
		"state":
			var short: bool = cell[1] == UiStyle.LOSS
			UiStyle.text_at(ci, Vector2(at.position.x, base), "Hungert" if short else "Satt", UiStyle.LOSS if short else UiStyle.TEXT,
				UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_CENTER, at.size.x, font)
		"money":
			ci.draw_line(Vector2(at.position.x + 10.0, at.position.y), Vector2(at.end.x - 10.0, at.position.y), CARD_EDGE, 1.0)
			var figure: String = cell[0] + " D"
			var rest := " je Kopf"
			var fw := bold.get_string_size(figure, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_HEAD + 2).x
			var rw := font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_TEXT).x
			var from := at.position.x + maxf(4.0, (at.size.x - fw - rw) * 0.5)
			UiStyle.text_at(ci, Vector2(from, base + 2.0), figure, UiStyle.VALUE, UiStyle.SIZE_HEAD + 2, HORIZONTAL_ALIGNMENT_LEFT, -1, bold)
			UiStyle.text_at(ci, Vector2(from + fw, base + 2.0), rest, UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT,
				maxf(0.0, at.end.x - from - fw - 4.0), font)
		"head": # a band with a chevron, its figure and its name
			var band := at.grow_individual(-4.0, 0.0, -4.0, 0.0)
			ci.draw_rect(band, UiStyle.ROW_HEAD)
			var c := Vector2(band.position.x + 12.0, band.get_center().y)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-4, -2), c + Vector2(0, 2), c + Vector2(4, -2)]), UiStyle.GOLD, 1.5, true)
			var figure: String = cell[0] + " " if spec[0] != "" else ""
			var fw := font.get_string_size(figure, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_TEXT).x
			UiStyle.text_at(ci, Vector2(band.position.x + 22.0, base), figure, UiStyle.VALUE, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, font)
			UiStyle.text_at(ci, Vector2(band.position.x + 22.0 + fw, base), spec[4], UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT,
				maxf(0.0, band.end.x - band.position.x - 26.0 - fw), font)
		"line": # a tile as Victoria 3's needs: icon, name, figure at the right
			var tile := Rect2(at.position.x + 4.0, at.position.y + 1.0, at.size.x - 8.0, at.size.y - 2.0)
			ci.draw_rect(tile, UiStyle.ROW)
			var name_x := tile.position.x + 6.0
			var icon: Texture2D = _icons.get("file:" + spec[4])
			if icon != null:
				ci.draw_texture_rect(icon, Rect2(tile.position.x + 4.0, tile.position.y + 4.0, 16.0, 16.0), false, UiStyle.DIM)
				name_x += 20.0
			var fw := font.get_string_size(cell[0], HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.SIZE_SMALL).x
			UiStyle.text_at(ci, Vector2(name_x, base - 1.0), spec[5], UiStyle.TEXT, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_LEFT,
				maxf(0.0, tile.end.x - name_x - fw - 10.0), font)
			UiStyle.text_at(ci, Vector2(tile.position.x, base - 1.0), cell[0], cell[1], UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT,
				tile.size.x - 6.0, font)
	if lit:
		ci.draw_rect(at.grow_individual(-4.0, 0.0, -4.0, 0.0), UiStyle.HOVER)

## A class: all its measures and what it ate since the start; the part
## under the mouse says what it is.
func _class_tip(at: Vector2i) -> Dictionary:
	if at.x < 0:
		return {}
	var name := _class_names[at.x]
	var rows := []
	for line in mini(CLASS_ROWS.size(), _class_cells.size()):
		var cell: Array = _class_cells[line][at.x]
		var text: String = cell[0] + (" D" if CLASS_ROWS[line][0] == "money_head" else "")
		rows.append([CLASS_ROWS[line][1], text, cell[1] if cell[1] == UiStyle.LOSS else UiStyle.TEXT])
	var tip := {"id": "class:%d:%d" % [at.x, at.y], "title": name, "kind": "Schicht", "rows": rows}
	var key: String = CLASS_PARTS[at.y][0] if at.y >= 0 else ""
	for spec in CLASS_ROWS:
		if spec[0] == key:
			tip.text = "[n]%s:[/n] %s" % [spec[1], spec[2]]
	var k := FED_NAMES.find(name)
	var h: Dictionary = _tables.get("history", {}).get("data", {})
	var fed := _col(h, "fed_" + FED_KEYS[k], 100.0) if k >= 0 else PackedFloat64Array()
	if fed.size() > 1:
		tip.spark = fed
		tip.spark_title = "Gegessen seit Beginn"
		tip.spark_unit = "%"
		tip.colour = FED_COLOURS[k]
		tip.spark_from = date.call(int(h.day[0]))
		tip.spark_to = date.call(int(h.day[h.day.size() - 1]))
	return tip

# ------------------------------------------------------------------ the state's money

func _bar_card() -> void:
	var box := _card("state")
	_bars = Control.new()
	_bars.custom_minimum_size = Vector2(0, PLOT_PX)
	_bars.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_bars)
	var foot := _foot()
	foot.text = "Denar seit Beginn; was ausgegeben wurde, nach links."
	box.add_child(foot)
	_bars.draw.connect(func():
		var font := UiStyle.serif()
		var top := 1.0
		for r in _bar_rows:
			top = maxf(top, absf(r[1]))
		var label_w := 216.0
		var value_w := 80.0
		var x1 := _bars.size.x - value_w - 8.0
		var mid := (label_w + x1) * 0.5
		var half := (x1 - label_w) * 0.5 - 2.0
		for k in _bar_rows.size():
			var y := 4.0 + k * BAR_ROW
			var v: float = _bar_rows[k][1]
			var colour := UiStyle.GAIN if v >= 0.0 else UiStyle.LOSS
			_bars.draw_rect(Rect2(0, y, _bars.size.x, BAR_ROW - 4.0), UiStyle.ROW if k % 2 == 0 else UiStyle.ROW_DARK)
			var trough := Rect2(label_w, y + (BAR_ROW - 4.0 - BAR_PX) * 0.5 - 2.0, x1 - label_w, BAR_PX + 4.0)
			_bar(_bars, trough, mid, mid + signf(v) * absf(v) / top * half, colour) # from nothing in the middle
			_bars.draw_line(Vector2(mid, trough.position.y - 3.0), Vector2(mid, trough.end.y + 3.0), UiStyle.GOLD, 1.0)
			UiStyle.text_at(_bars, Vector2(6, y + 16.0), _bar_rows[k][0], UiStyle.CONCEPT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, label_w - 8.0, font)
			UiStyle.text_at(_bars, Vector2(_bars.size.x - value_w - 6.0, y + 16.0), ("+" if v > 0.0 else ("−" if v < 0.0 else "")) + Charts.label(absf(v)),
				colour, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, value_w, font))
	Tooltips.attach(_bars, func(at: Vector2) -> Dictionary:
		var k := int((at.y - 4.0) / BAR_ROW)
		if k < 0 or k >= _bar_rows.size():
			return {}
		var v: float = _bar_rows[k][1]
		return {"id": "bar:%d" % k, "title": _bar_rows[k][0], "kind": "Geld des Staates", "text": BAR_ABOUT.get(_bar_rows[k][2], ""),
			"rows": [["Denar", ("+" if v > 0.0 else ("−" if v < 0.0 else "")) + Charts.label(absf(v))]]})

# ------------------------------------------------------------------ the state's budget

## The budget as Victoria 3's: the income at the left, the spending at the
## right, each item with its sum over the last twelve months and a bar on
## one scale for both sides; under them the balance and what is not in the
## sums (the Zehnt as grain, what was seized, what was written off).
func _budget_card() -> void:
	var box := _card("budget")
	_budget = Control.new()
	_budget.custom_minimum_size = Vector2(0, PLOT_PX)
	_budget.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_budget)
	_budget.draw.connect(_draw_budget)
	_budget.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var at := _budget_at(e.position)
			if at != _budget_hover:
				_budget_hover = at
				_budget.queue_redraw())
	_budget.mouse_exited.connect(func():
		_budget_hover = Vector2i(-1, -1)
		_budget.queue_redraw())
	Tooltips.attach(_budget, func(at: Vector2) -> Dictionary: return _budget_tip(_budget_at(at)))

## Each item of BUDGET_IN and BUDGET_OUT the history has, summed over the
## last twelve months and the twelve before.
func _set_budget(h: Dictionary) -> void:
	if _budget == null:
		return
	var d: Dictionary = h.data
	var n: int = d.day.size()
	for side in 2:
		var items := []
		for spec in (BUDGET_IN if side == 0 else BUDGET_OUT):
			if not d.has(spec[0]):
				continue
			var vals := _col(d, spec[0])
			var before := 0.0
			for v in vals.slice(maxi(0, n - 24), maxi(0, n - 12)):
				before += v
			items.append({"key": spec[0], "name": _label_of(h, spec[0]), "colour": spec[1], "about": spec[2], "year": _year_sum(vals),
				"before": before if n > 12 else -1.0, "months": vals})
		_budget_sides[side] = items
	_budget_extra = []
	if d.has("tithe_t"):
		var grain := _year_sum(_col(d, "tithe_t"))
		var worth := _year_sum(_col(d, "tithe_d")) if d.has("tithe_d") else 0.0
		_budget_extra.append(["Zehnt abgeliefert", "%s t, zum Ankaufspreis %s D" % [Charts.label(grain), Charts.label(worth)],
			"Korn, das die Höfe als Zehnt bei der Ernte in die Staatsspeicher abliefern. Zu Geld wird es erst, wenn der Staat es verkauft (Verkauf aus Staatsspeichern), darum steht es nicht in der Summe."])
	if d.has("seized_d"):
		_budget_extra.append(["Gepfändet", Charts.label(_year_sum(_col(d, "seized_d"))) + " D",
			"Geld und Korn, das der Staat für Steuerrückstand gepfändet hat, das Korn zum Ankaufspreis. Das Geld steckt schon in Grund- und Kopfsteuer, das Korn kommt beim Verkauf aus den Staatsspeichern."])
	if d.has("written_off_d"):
		_budget_extra.append(["Uneinbringlich abgeschrieben", Charts.label(_year_sum(_col(d, "written_off_d"))) + " D",
			"Steuerrückstand, den der Staat nach zwei Jahren abschreibt, weil nichts mehr zu holen ist."])
	if d.has("debt_issued_d") and d.has("debt_repaid_d"):
		var issued := _year_sum(_col(d, "debt_issued_d"))
		var repaid := _year_sum(_col(d, "debt_repaid_d"))
		if issued > 0.0 or repaid > 0.0:
			_budget_extra.append(["Anleihen", "%s D geliehen, %s D getilgt" % [Charts.label(issued), Charts.label(repaid)],
				"Geld, das der Staat im letzten Jahr bei seinen Gläubigern geliehen und ihnen zurückgezahlt hat. Geliehenes Geld ist keine Einnahme und Tilgung keine Ausgabe, darum steht beides nicht in der Summe; die Zinsen stehen bei den Ausgaben."])
	var rows := maxi(_budget_sides[0].size(), _budget_sides[1].size())
	_budget.custom_minimum_size.y = BUDGET_HEAD + rows * BUDGET_ROW + 10.0 + LINE_PX + _budget_extra.size() * LINE_PX
	_budget.queue_redraw()

## A history column's name without "im Monat": the sim's own words.
static func _label_of(h: Dictionary, key: String) -> String:
	var i := Array(h.get("columns", [])).find(key)
	var name: String = h.labels[i] if i >= 0 else key
	return name.trim_suffix(" im Monat")

static func _side_total(items: Array) -> float:
	var sum := 0.0
	for it in items:
		sum += float(it.year)
	return sum

## The budget's halves: x and width of side 0 (income) and 1 (spending).
func _budget_half(side: int) -> Vector2:
	var w := (_budget.size.x - 16.0) * 0.5
	return Vector2(side * (w + 16.0), w)

## Side and row under `at`; row -1 the head, -2 nothing; side 2 the lines
## under the sums, its row the line.
func _budget_at(at: Vector2) -> Vector2i:
	var rows := maxi(_budget_sides[0].size(), _budget_sides[1].size())
	var below := BUDGET_HEAD + rows * BUDGET_ROW + 10.0 + LINE_PX
	if at.y >= below:
		var k := int((at.y - below) / LINE_PX)
		return Vector2i(2, k) if k < _budget_extra.size() else Vector2i(-1, -1)
	var side := 0 if at.x < _budget_half(1).x else 1
	var row := int((at.y - BUDGET_HEAD) / BUDGET_ROW) if at.y >= BUDGET_HEAD else -1
	if row >= _budget_sides[side].size():
		return Vector2i(-1, -1)
	return Vector2i(side, row)

func _draw_budget() -> void:
	var font := UiStyle.serif()
	var top := 1.0
	for side in 2:
		for it in _budget_sides[side]:
			top = maxf(top, float(it.year))
	var rows := maxi(_budget_sides[0].size(), _budget_sides[1].size())
	for side in 2:
		var half := _budget_half(side)
		var x0 := half.x
		var w := half.y
		var items: Array = _budget_sides[side]
		var sign_colour := UiStyle.GAIN if side == 0 else UiStyle.LOSS # as the state's bars and Victoria 3's budget
		_budget.draw_rect(Rect2(x0, 0, w, BUDGET_HEAD - 4.0), UiStyle.BAR) # the section's band, as Victoria 3's
		_budget.draw_line(Vector2(x0, BUDGET_HEAD - 4.0), Vector2(x0 + w, BUDGET_HEAD - 4.0), UiStyle.GOLD_DIM, 1.0)
		UiStyle.text_at(_budget, Vector2(x0 + 8.0, 19.0), "Einnahmen" if side == 0 else "Ausgaben", UiStyle.TITLE, UiStyle.SIZE_TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, w * 0.5, font)
		var total := _side_total(items)
		UiStyle.text_at(_budget, Vector2(x0 + w * 0.5, 19.0), ("+" if side == 0 else "−") + Charts.label(total) + " D", sign_colour,
			UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5 - 8.0, UiStyle.bold())
		for k in rows:
			var y := BUDGET_HEAD + k * BUDGET_ROW
			_budget.draw_rect(Rect2(x0, y, w, BUDGET_ROW - 2.0), UiStyle.ROW if k % 2 == 0 else UiStyle.ROW_DARK)
			if k >= items.size():
				continue
			var it: Dictionary = items[k]
			if _budget_hover == Vector2i(side, k):
				_budget.draw_rect(Rect2(x0, y, w, BUDGET_ROW - 2.0), UiStyle.HOVER)
			_budget.draw_rect(Rect2(x0 + 8.0, y + 7.0, 11.0, 11.0), it.colour)
			_budget.draw_rect(Rect2(x0 + 8.0, y + 7.0, 11.0, 11.0), UiStyle.EDGE, false, 1.0)
			UiStyle.text_at(_budget, Vector2(x0 + 26.0, y + 17.0), it.name, UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT,
				w - 26.0 - 96.0, font)
			UiStyle.text_at(_budget, Vector2(x0 + w - 106.0, y + 17.0), ("+" if side == 0 else "−") + Charts.label(it.year) + " D", sign_colour,
				UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 100.0, font)
			var trough := Rect2(x0 + 26.0, y + 22.0, w - 32.0, 6.0)
			_budget.draw_rect(trough, UiStyle.CHART_GRID)
			var fill := trough.size.x * clampf(float(it.year) / top, 0.0, 1.0)
			if fill >= 1.0:
				var a := trough.position
				var b := a + Vector2(fill, 0.0)
				var dark := Color(it.colour).darkened(0.35)
				var light := Color(it.colour).lightened(0.15)
				_budget.draw_polygon(PackedVector2Array([a, b, b + Vector2(0, 6), a + Vector2(0, 6)]), PackedColorArray([dark, light, light, dark]))
	var y2 := BUDGET_HEAD + rows * BUDGET_ROW + 6.0
	_budget.draw_line(Vector2(0, y2), Vector2(_budget.size.x, y2), UiStyle.GOLD_DIM, 1.0)
	var balance := _side_total(_budget_sides[0]) - _side_total(_budget_sides[1])
	UiStyle.text_at(_budget, Vector2(4.0, y2 + 20.0), "Saldo im letzten Jahr", UiStyle.CONCEPT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font)
	UiStyle.text_at(_budget, Vector2(_budget.size.x - 200.0, y2 + 20.0), ("+" if balance > 0.0 else ("−" if balance < 0.0 else ""))
		+ Charts.label(absf(balance)) + " D", UiStyle.TEXT, UiStyle.SIZE_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 194.0, UiStyle.bold())
	for k in _budget_extra.size():
		var y := y2 + 4.0 + LINE_PX * (k + 1)
		if _budget_hover == Vector2i(2, k):
			_budget.draw_rect(Rect2(0, y, _budget.size.x, LINE_PX), UiStyle.HOVER)
		UiStyle.text_at(_budget, Vector2(4.0, y + 16.0), _budget_extra[k][0], UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font)
		UiStyle.text_at(_budget, Vector2(_budget.size.x - 300.0, y + 16.0), _budget_extra[k][1], UiStyle.DIM, UiStyle.SIZE_SMALL,
			HORIZONTAL_ALIGNMENT_RIGHT, 294.0, font)

func _budget_tip(at: Vector2i) -> Dictionary:
	if at.x == 2:
		var e: Array = _budget_extra[at.y]
		return {"id": "budget:x%d" % at.y, "title": e[0], "kind": "Nicht in der Summe", "text": e[2], "rows": [["Im letzten Jahr", e[1]]]}
	if at.x < 0 or at.y < 0:
		return {}
	var it: Dictionary = _budget_sides[at.x][at.y]
	var total := _side_total(_budget_sides[at.x])
	var rows := [["Im letzten Jahr", Charts.label(it.year) + " D"]]
	if float(it.before) >= 0.0:
		rows.append(["Im Jahr davor", Charts.label(it.before) + " D"])
	if total > 0.0:
		rows.append(["Anteil", _pct(float(it.year) / total * 100.0) + " %"])
	var months: PackedFloat64Array = it.months
	return {"id": "budget:%s" % it.key, "title": it.name, "kind": "Einnahme" if at.x == 0 else "Ausgabe", "text": it.about, "rows": rows,
		"spark": months, "spark_title": "Jeder Monat seit Beginn", "spark_unit": "D", "colour": it.colour}

## The laws as Victoria 3's tax levels: per tax a row of six buttons, the
## level in force lit; under it what the level is and what the tax brought.
func _laws_card() -> void:
	var box := _card("laws")
	_laws_box = VBoxContainer.new()
	_laws_box.add_theme_constant_override("separation", 6)
	box.add_child(_laws_box)
	var foot := _foot()
	foot.text = "Eine neue Stufe gilt ab der nächsten Fälligkeit; Zehnt und Grundsteuer nach der Ernte."
	box.add_child(foot)

func _set_laws(laws: Array, d: Dictionary) -> void:
	if _laws_box == null:
		return
	_laws_box.get_parent().get_parent().visible = not laws.is_empty() # a sim without the tax law
	if laws.size() != _law_buttons.size():
		for c in _laws_box.get_children():
			c.queue_free()
		_law_buttons = []
		_law_notes = []
		for k in laws.size():
			_law_row(k, laws[k])
	_laws = laws
	var brought := {0: "tithe_d", 1: "land_tax_d", 2: "head_tax_d"}
	for k in laws.size():
		var law: Dictionary = laws[k]
		if _law_wanted.get(k, -1) == int(law.level):
			_law_wanted.erase(k)
		var lit: int = _law_wanted.get(k, int(law.level))
		for lv in _law_buttons[k].size():
			_law_buttons[k][lv].set_pressed_no_signal(lv == lit)
			_law_buttons[k][lv].disabled = not set_tax.is_valid()
		var note := "%s %s" % [_num(float(law.rate)), law.unit] if int(law.level) > 0 else "keine"
		if float(law.get("denar", 0.0)) > 0.0:
			note += ", etwa %s D %s" % [_num(float(law.denar)), "je ha und Jahr" if int(law.law) == 1 else "je Erwachsenen und Jahr"]
		var col: String = brought.get(int(law.law), "")
		if d.has(col):
			note += "  ·  im letzten Jahr %s D%s" % [Charts.label(_year_sum(_col(d, col))), " (Korn zum Ankaufspreis)" if col == "tithe_d" else ""]
		if _law_wanted.has(k):
			note = "Neu «%s» ab der nächsten Fälligkeit  ·  jetzt %s" % [law.levels[_law_wanted[k]], note]
		_law_notes[k].text = note

func _law_row(k: int, law: Dictionary) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_laws_box.add_child(row)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	row.add_child(line)
	var name := _label(str(law.name), UiStyle.CONCEPT, UiStyle.SIZE_TEXT)
	name.custom_minimum_size = Vector2(130, 0)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name)
	var buttons := []
	var levels: PackedStringArray = law.levels
	for lv in levels.size():
		var b := Button.new()
		b.text = levels[lv]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
		b.pressed.connect(_pick_law.bind(k, lv))
		Tooltips.attach(b, func(_at: Vector2) -> Dictionary:
			var now: Dictionary = _laws[k]
			var tip := {"id": "law:%d:%d" % [k, lv], "title": "%s: %s" % [law.name, levels[lv]], "kind": "Steuerstufe",
				"text": "Ein Klick setzt die Stufe; sie gilt ab der nächsten Fälligkeit." if lv != int(now.level) else "Diese Stufe gilt jetzt."}
			var rates: Array = Array(now.get("rates", []))
			if lv < rates.size(): # what the level is, in the law's unit
				tip["rows"] = [["Satz", ("%s %s" % [_num(float(rates[lv])), now.unit]) if int(rates[lv]) > 0 else "keine Steuer"]]
			return tip)
		line.add_child(b)
		buttons.append(b)
	_law_buttons.append(buttons)
	var note := _label("", UiStyle.DIM, UiStyle.SIZE_SMALL)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # a second line, not an ellipsis
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 134)
	pad.add_child(note)
	row.add_child(pad)
	_law_notes.append(note)

func _pick_law(k: int, level: int) -> void:
	if not set_tax.is_valid() or k >= _laws.size():
		return
	set_tax.call(int(_laws[k].law), level)
	if level == int(_laws[k].level):
		_law_wanted.erase(k)
	else:
		_law_wanted[k] = level
	var d: Dictionary = _tables.get("history", {}).get("data", {})
	_set_laws(_laws, d)

## S133, S134: the spending laws and the debt law as rows of buttons, one
## per choice, the choice in force lit (as the tax laws); under the debt
## law the Zwangsanleihe.
func _choices_card(key: String) -> void:
	var box := _card(key)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	box.add_child(rows)
	_choice_boxes[key] = rows
	_choice_buttons[key] = []
	var foot := _foot()
	if key == "debt_laws":
		box.add_child(_forced_row())
		foot.text = "Eine Wahl gilt ab dem nächsten Monat; laufende Anleihen behalten Zins und Laufzeit."
	else:
		foot.text = "Eine Wahl gilt ab dem nächsten Tag."
	box.add_child(foot)

func _set_choices(key: String, laws: Array) -> void:
	if not _choice_boxes.has(key):
		return
	var rows: VBoxContainer = _choice_boxes[key]
	rows.get_parent().get_parent().visible = not laws.is_empty() # a sim without these laws
	if laws.size() != _choice_buttons[key].size():
		for c in rows.get_children():
			c.queue_free()
		_choice_buttons[key] = []
		for k in laws.size():
			_choice_row(key, k, laws[k])
	_choice_laws[key] = laws
	var setter: Callable = set_spend if key == "spend_laws" else set_debt
	for k in laws.size():
		var wanted := "%s:%d" % [key, k]
		if _choice_wanted.get(wanted, -1) == int(laws[k].choice):
			_choice_wanted.erase(wanted)
		var lit: int = _choice_wanted.get(wanted, int(laws[k].choice))
		var buttons: Array = _choice_buttons[key][k]
		for c in buttons.size():
			buttons[c].set_pressed_no_signal(c == lit)
			buttons[c].disabled = not setter.is_valid()
	if key == "debt_laws":
		for b in _forced_buttons:
			b.disabled = not forced_loan.is_valid()

func _choice_row(key: String, k: int, law: Dictionary) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	_choice_boxes[key].add_child(line)
	var name := _label(str(law.name), UiStyle.CONCEPT, UiStyle.SIZE_TEXT)
	name.custom_minimum_size = Vector2(130, 0)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(name)
	var buttons := []
	var choices: PackedStringArray = law.choices
	for c in choices.size():
		var b := Button.new()
		b.text = choices[c]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
		b.pressed.connect(_pick_choice.bind(key, k, c))
		var about: String = CHOICE_ABOUT.get("%s:%d:%d" % [key, int(law.law), c], "")
		Tooltips.attach(b, func(_at: Vector2) -> Dictionary:
			var now: Dictionary = _choice_laws[key][k]
			return {"id": "choice:%s:%d:%d" % [key, k, c], "title": "%s: %s" % [law.name, choices[c]], "kind": "Gesetz",
				"text": about + ("\n\nDas gilt jetzt." if c == int(now.choice) else "\n\nEin Klick setzt es.")})
		line.add_child(b)
		buttons.append(b)
	_choice_buttons[key].append(buttons)

func _pick_choice(key: String, k: int, c: int) -> void:
	var setter: Callable = set_spend if key == "spend_laws" else set_debt
	var laws: Array = _choice_laws.get(key, [])
	if not setter.is_valid() or k >= laws.size():
		return
	setter.call(int(laws[k].law), c)
	var wanted := "%s:%d" % [key, k]
	if c == int(laws[k].choice):
		_choice_wanted.erase(wanted)
	else:
		_choice_wanted[wanted] = c
	_set_choices(key, laws)

## The Zwangsanleihe: a button per share of the spare money; a click
## orders it once, raised at the next monthly turn.
func _forced_row() -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	row.add_child(line)
	var name := _label("Zwangsanleihe", UiStyle.CONCEPT, UiStyle.SIZE_TEXT)
	name.custom_minimum_size = Vector2(130, 0)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name)
	for share in FORCED_SHARES:
		var b := Button.new()
		b.text = "%d %% des Bargelds" % share
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(70, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
		b.pressed.connect(_order_forced.bind(share))
		var text := "Die reichsten Haushalte, deren Geld über einem Jahr Essen mindestens zehn Jahreslöhne erreicht, müssen dem Staat %d %% davon leihen, zu %d %% Zins, im Rahmen der Schuldengrenze. Was dieser Zins unter dem liegt, was sie sonst verlangt hätten, merken sie sich als Verlust." % [share, FORCED_RATE]
		Tooltips.attach(b, func(_at: Vector2) -> Dictionary:
			return {"id": "forced:%d" % share, "title": "Zwangsanleihe ausschreiben", "kind": "Erlass", "text": text})
		line.add_child(b)
		_forced_buttons.append(b)
	_forced_note = _label("", UiStyle.DIM, UiStyle.SIZE_SMALL)
	_forced_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 134)
	pad.add_child(_forced_note)
	row.add_child(pad)
	return row

func _order_forced(share: int) -> void:
	if not forced_loan.is_valid():
		return
	forced_loan.call(share, FORCED_RATE)
	_forced_note.text = "Ausgeschrieben: %d %% des Bargelds zu %d %%, erhoben im nächsten Monat." % [share, FORCED_RATE]

## S134: the largest creditors, a face and a link each.
func _creditors_card() -> void:
	var box := _card("creditors")
	_creditors_note = _label("", UiStyle.DIM, UiStyle.SIZE_SMALL)
	_creditors_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_creditors_note)
	_creditors_box = VBoxContainer.new()
	_creditors_box.add_theme_constant_override("separation", 2)
	box.add_child(_creditors_box)

func _set_creditors(debt: Dictionary) -> void:
	if _creditors_box == null:
		return
	_creditors_box.get_parent().get_parent().visible = not debt.is_empty() # a sim without the debt
	var list: Array = debt.get("creditors", [])
	if list.is_empty():
		_creditors_note.text = "Der Staat schuldet niemandem etwas."
	else:
		_creditors_note.text = "Staatsschuld %s D, Zinsen %s D im Jahr, letzte Anleihe zu %s %%." % [Charts.label(float(debt.get("debt", 0.0))),
			Charts.label(float(debt.get("interest_year", 0.0))), _num(float(debt.get("rate", 0.0)))]
	for c in _creditors_box.get_children():
		c.queue_free()
	for i in mini(list.size(), CREDITORS_SHOWN):
		var cr: Dictionary = list[i]
		var household: int = int(cr.household)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var face := TextureRect.new()
		face.custom_minimum_size = Vector2(CREDITOR_FACE_PX, CREDITOR_FACE_PX)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if face_of.is_valid():
			var tex = face_of.call(household)
			if tex is Texture2D:
				face.texture = tex
		line.add_child(face)
		var link := Button.new()
		link.text = "Haushalt %d" % household
		link.flat = true
		link.focus_mode = Control.FOCUS_NONE
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT
		link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		link.add_theme_font_size_override("font_size", UiStyle.SIZE_SMALL)
		link.pressed.connect(func(): household_chosen.emit(household))
		line.add_child(link)
		line.add_child(_label("%s D" % Charts.label(float(cr.amount)), UiStyle.TEXT, UiStyle.SIZE_SMALL))
		line.add_child(_label("%s %%" % _num(float(cr.rate)), UiStyle.DIM, UiStyle.SIZE_SMALL))
		_creditors_box.add_child(line)

## The budget's years: a bar each, the income stacked up from the middle
## line, the spending down, in the items' colours.
func _years_card() -> void:
	var box := _card("budget_years")
	_years = Control.new()
	_years.custom_minimum_size = Vector2(0, YEARS_PX)
	_years.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_years)
	_years_legend = HFlowContainer.new()
	_years_legend.add_theme_constant_override("h_separation", 12)
	_years_legend.custom_minimum_size = Vector2(0, LINE_PX)
	box.add_child(_years_legend)
	_years.draw.connect(_draw_years)
	_years.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var k := _year_at(e.position.x)
			if k != _year_hover:
				_year_hover = k
				_years.queue_redraw())
	_years.mouse_exited.connect(func():
		_year_hover = -1
		_years.queue_redraw())
	Tooltips.attach(_years, func(at: Vector2) -> Dictionary: return _year_tip(_year_at(at.x)))

func _set_years(h: Dictionary) -> void:
	if _years == null:
		return
	var d: Dictionary = h.data
	var specs := [BUDGET_IN.filter(func(s): return d.has(s[0])), BUDGET_OUT.filter(func(s): return d.has(s[0]))]
	var names := [[], []]
	for side in 2:
		for s in specs[side]:
			names[side].append([_label_of(h, s[0]), s[1]])
	var by_year := {}
	var order := []
	var days: Array = Array(d.day)
	for i in days.size():
		var yr := int(days[i]) / YEAR_DAYS
		if not by_year.has(yr):
			by_year[yr] = {"year": yr + 1, "months": 0, "in": PackedFloat64Array(), "out": PackedFloat64Array()}
			by_year[yr]["in"].resize(specs[0].size())
			by_year[yr]["out"].resize(specs[1].size())
			order.append(yr)
		var row: Dictionary = by_year[yr]
		row.months += 1
		for k in specs[0].size():
			row["in"][k] += float(d[specs[0][k][0]][i])
		for k in specs[1].size():
			row["out"][k] += float(d[specs[1][k][0]][i])
	_year_rows = []
	for yr in order:
		var row: Dictionary = by_year[yr]
		row.part = row.months < 12
		_year_rows.append(row)
	if names != _year_names:
		_year_names = names
		for c in _years_legend.get_children():
			c.queue_free()
		for side in 2:
			for nm in names[side]:
				_years_legend.add_child(_swatch(nm[1], nm[0]))
	_years.queue_redraw()

func _years_plot() -> Rect2:
	return Rect2(84.0, 6.0, maxf(10.0, _years.size.x - 90.0), YEARS_PX - 30.0)

func _year_at(x: float) -> int:
	var plot := _years_plot()
	if _year_rows.is_empty() or x < plot.position.x or x > plot.end.x:
		return -1
	return clampi(int((x - plot.position.x) / plot.size.x * _year_rows.size()), 0, _year_rows.size() - 1)

static func _sum(vals: PackedFloat64Array) -> float:
	var s := 0.0
	for v in vals:
		s += v
	return s

func _draw_years() -> void:
	var plot := _years_plot()
	Charts.board(_years, plot, false)
	var n := _year_rows.size()
	if n == 0:
		return
	var up := 0.0
	var down := 0.0
	for row in _year_rows:
		up = maxf(up, _sum(row["in"]))
		down = maxf(down, _sum(row.out))
	if up + down <= 0.0:
		return
	var inner := plot.grow(-4.0)
	var scale := inner.size.y / (up + down)
	var zero := inner.position.y + up * scale
	var slot := inner.size.x / n
	var bw := maxf(2.0, slot * 0.72)
	var font := UiStyle.serif()
	for k in n:
		var row: Dictionary = _year_rows[k]
		var x := inner.position.x + k * slot + (slot - bw) * 0.5
		if k == _year_hover:
			_years.draw_rect(Rect2(inner.position.x + k * slot, inner.position.y, slot, inner.size.y), UiStyle.HOVER)
		var alpha := 0.55 if row.part else 1.0
		var y := zero
		for i in row["in"].size():
			var hgt: float = row["in"][i] * scale
			if hgt > 0.0:
				_years.draw_rect(Rect2(x, y - hgt, bw, hgt), Color(_year_names[0][i][1], alpha))
				y -= hgt
				if hgt > 3.0:
					_years.draw_line(Vector2(x, y), Vector2(x + bw, y), UiStyle.CHART, 1.0) # a gap between the parts
		y = zero
		for i in row.out.size():
			var hgt: float = row.out[i] * scale
			if hgt > 0.0:
				_years.draw_rect(Rect2(x, y, bw, hgt), Color(_year_names[1][i][1], alpha))
				y += hgt
				if hgt > 3.0:
					_years.draw_line(Vector2(x, y), Vector2(x + bw, y), UiStyle.CHART, 1.0)
	_years.draw_line(Vector2(plot.position.x, zero), Vector2(plot.end.x, zero), UiStyle.GOLD, 1.0)
	UiStyle.text_at(_years, Vector2(0, inner.position.y + 10.0), "+" + Charts.label(up, "D"), UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT,
		plot.position.x - 6.0, font)
	UiStyle.text_at(_years, Vector2(0, zero + 5.0), "0", UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT, plot.position.x - 6.0, font)
	UiStyle.text_at(_years, Vector2(0, inner.end.y), "−" + Charts.label(down, "D"), UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT,
		plot.position.x - 6.0, font)
	var every := maxi(1, ceili(n / 6.0))
	for k in range(0, n, every):
		var cx := inner.position.x + (k + 0.5) * slot
		UiStyle.text_at(_years, Vector2(cx - 40.0, YEARS_PX - 6.0), "Jahr %d" % _year_rows[k].year, UiStyle.DIM, UiStyle.SIZE_SMALL,
			HORIZONTAL_ALIGNMENT_CENTER, 80.0, UiStyle.italic())

func _year_tip(k: int) -> Dictionary:
	if k < 0 or k >= _year_rows.size():
		return {}
	var row: Dictionary = _year_rows[k]
	var rows := []
	for side in 2:
		var vals: PackedFloat64Array = row["in"] if side == 0 else row.out
		for i in vals.size():
			if vals[i] > 0.0:
				rows.append([_year_names[side][i][0], ("+" if side == 0 else "−") + Charts.label(vals[i]) + " D"])
	var balance := _sum(row["in"]) - _sum(row.out)
	rows.append(["Saldo", ("+" if balance > 0.0 else ("−" if balance < 0.0 else "")) + Charts.label(absf(balance)) + " D"])
	return {"id": "year:%d" % k, "title": "Jahr %d%s" % [row.year, " (bis jetzt)" if row.part else ""], "kind": "Haushalt", "rows": rows}

## The history with the budget's sums over the last twelve months of each
## month, for the figures: income_y, spending_y.
func _with_year_sums(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	var n: int = d.day.size()
	for side in 2:
		var month := PackedFloat64Array()
		month.resize(n)
		for spec in (BUDGET_IN if side == 0 else BUDGET_OUT):
			if d.has(spec[0]):
				for i in n:
					month[i] += float(d[spec[0]][i])
		var run := PackedFloat64Array()
		run.resize(n)
		var sum := 0.0
		for i in n:
			sum += month[i]
			if i >= 12:
				sum -= month[i - 12]
			run[i] = sum
		out["income_y" if side == 0 else "spending_y"] = run
	return out

# ------------------------------------------------------------------ rich and poor

## Who holds the money, as a Lorenz curve: the people from the poorest to
## the richest along, their share of all money up. The straight diagonal
## would be everyone equal; the further the curve sags below it, the more
## unequal. Grey: the curve at the start of the chosen months.
func _lorenz_card() -> void:
	var box := _card("lorenz")
	_lorenz = Control.new()
	_lorenz.custom_minimum_size = Vector2(0, PLOT_PX)
	_lorenz.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_lorenz)
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 12)
	legend.custom_minimum_size = Vector2(0, LINE_PX)
	box.add_child(legend)
	legend.add_child(_swatch(Charts.SERIES[0], "Heute"))
	legend.add_child(_swatch(Charts.MUTED, "Zu Beginn"))
	legend.add_child(_swatch(UiStyle.DIM, "Alle gleich"))
	_lorenz.draw.connect(_draw_lorenz)
	_lorenz.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseMotion:
			var plot := _lorenz_plot()
			var q := clampi(roundi((e.position.x - plot.position.x) / plot.size.x * 10.0), 0, 10)
			q = q if q > 0 and q < 10 else -1
			if q != _lorenz_hover:
				_lorenz_hover = q
				_lorenz.queue_redraw())
	_lorenz.mouse_exited.connect(func():
		_lorenz_hover = -1
		_lorenz.queue_redraw())
	Tooltips.attach(_lorenz, func(_at: Vector2) -> Dictionary: return _lorenz_tip())

## The curve's 11 points (0, 10 … 100 % of the people) of history row i.
static func _lorenz_at(d: Dictionary, i: int) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0])
	for q in range(1, 10):
		var col: Array = d.get("lorenz_%d0" % q, [])
		if i < 0 or i >= col.size():
			return PackedFloat64Array()
		out.append(float(col[i]))
	out.append(1.0)
	return out

func _set_lorenz(d: Dictionary) -> void:
	var n: int = d.get("day", []).size()
	_lorenz_now = _lorenz_at(d, n - 1)
	var first := _first(n)
	_lorenz_then = _lorenz_at(d, first) if first < n - 1 else PackedFloat64Array()
	_lorenz_when = date.call(int(d.day[first])) if n > 0 else ""
	_lorenz.queue_redraw()

## The plot, square, left in the card; the axes' names at its sides.
func _lorenz_plot() -> Rect2:
	var side := minf(_lorenz.size.y - 38.0, _lorenz.size.x - 140.0)
	return Rect2(Vector2(44.0, 12.0), Vector2(side, side))

func _draw_lorenz() -> void:
	var r := _lorenz_plot()
	var font := UiStyle.serif()
	Charts.board(_lorenz, Rect2(Vector2.ZERO, _lorenz.size), false)
	var at := func(p: float, m: float) -> Vector2: return Vector2(r.position.x + p * r.size.x, r.end.y - m * r.size.y)
	for k in range(0, 5):
		var v := k * 0.25
		_lorenz.draw_line(at.call(0.0, v), at.call(1.0, v), UiStyle.CHART_GRID, 1.0)
		_lorenz.draw_line(at.call(v, 0.0), at.call(v, 1.0), UiStyle.CHART_GRID, 1.0)
		UiStyle.text_at(_lorenz, at.call(0.0, v) + Vector2(-40.0, 5.0), "%d %%" % roundi(v * 100.0), UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT, 34.0, font)
	UiStyle.text_at(_lorenz, Vector2(r.position.x, r.end.y + 17.0), "arm", UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_LEFT, -1, UiStyle.italic())
	UiStyle.text_at(_lorenz, Vector2(r.position.x, r.end.y + 17.0), "reich", UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x, UiStyle.italic())
	for part in Charts.dashes(PackedVector2Array([at.call(0.0, 0.0), at.call(1.0, 1.0)]), 6.0, 4.0):
		_lorenz.draw_polyline(part, UiStyle.DIM, 1.0, true)
	var curve := func(pts: PackedFloat64Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for q in pts.size():
			out.append(at.call(q / 10.0, pts[q]))
		return out
	if _lorenz_now.size() == 11:
		# the gap to everyone equal, the Gini's area, faintly
		var area: PackedVector2Array = curve.call(_lorenz_now)
		area.reverse()
		area.append(at.call(0.0, 0.0))
		if Geometry2D.triangulate_polygon(area).size() > 0:
			_lorenz.draw_colored_polygon(area, Color(Charts.SERIES[0], 0.14))
	if _lorenz_then.size() == 11:
		_lorenz.draw_polyline(curve.call(_lorenz_then), Charts.MUTED, 1.5, true)
	if _lorenz_now.size() == 11:
		var line: PackedVector2Array = curve.call(_lorenz_now)
		_lorenz.draw_polyline(line, Color(0, 0, 0, 0.4), 4.5, true)
		_lorenz.draw_polyline(line, Charts.SERIES[0], 2.5, true)
		if _lorenz_hover > 0:
			var p := line[_lorenz_hover]
			_lorenz.draw_line(Vector2(p.x, r.position.y), Vector2(p.x, r.end.y), Color(UiStyle.TEXT, 0.35), 1.0)
			_lorenz.draw_circle(p, 5.0, UiStyle.CHART)
			_lorenz.draw_circle(p, 3.5, Charts.SERIES[0])
		# beside the plot, the two numbers that say it
		var x := r.end.x + 14.0
		var w := _lorenz.size.x - x - 6.0
		var poor := _lorenz_now[5]
		var rich := 1.0 - _lorenz_now[9]
		var line_at := r.position.y + 18.0
		for item in [["%s %%" % _pct(rich * 100.0), "des Geldes hat das reichste Zehntel"], ["%s %%" % _pct(poor * 100.0), "hat die ärmere Hälfte"]]:
			UiStyle.text_at(_lorenz, Vector2(x, line_at), item[0], UiStyle.VALUE, UiStyle.SIZE_HEAD + 4, HORIZONTAL_ALIGNMENT_LEFT, w, font)
			var y := line_at + 6.0
			for part in _wrap(item[1], w, UiStyle.SIZE_SMALL):
				y += 17.0
				UiStyle.text_at(_lorenz, Vector2(x, y), part, UiStyle.DIM, UiStyle.SIZE_SMALL, HORIZONTAL_ALIGNMENT_LEFT, w, font)
			line_at = y + 30.0

## `text` broken into lines of at most `width` px.
static func _wrap(text: String, width: float, font_size: int) -> PackedStringArray:
	var f := UiStyle.serif()
	var lines := PackedStringArray()
	var now := ""
	for word in text.split(" "):
		var next := word if now == "" else now + " " + word
		if now != "" and f.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(now)
			now = word
		else:
			now = next
	if now != "":
		lines.append(now)
	return lines

func _lorenz_tip() -> Dictionary:
	if _lorenz_now.size() != 11:
		return {}
	var q := _lorenz_hover
	if q <= 0:
		return {"id": "lorenz", "title": "Wer hat das Geld", "kind": "Lorenzkurve",
			"rows": [["Reichstes Zehntel", "%s %% des Geldes" % _pct((1.0 - _lorenz_now[9]) * 100.0)],
				["Ärmere Hälfte", "%s %% des Geldes" % _pct(_lorenz_now[5] * 100.0)]]}
	var rows := [["Die ärmsten %d %%" % (q * 10), "%s %% des Geldes" % _pct(_lorenz_now[q] * 100.0)],
		["Die reichsten %d %%" % (100 - q * 10), "%s %% des Geldes" % _pct((1.0 - _lorenz_now[q]) * 100.0)]]
	if _lorenz_then.size() == 11:
		rows.append(["Die ärmsten %d %%, %s" % [q * 10, _lorenz_when], "%s %%" % _pct(_lorenz_then[q] * 100.0), Charts.MUTED])
	return {"id": "lorenz:%d" % q, "title": "Die ärmsten %d %% der Menschen" % (q * 10), "kind": "Lorenzkurve", "rows": rows}

# ------------------------------------------------------------------ one market

## The market window's numbers (market_window.gd): take_market()'s answer,
## the market's row of the markets table with its "history" and "classes".
func show_market(d: Dictionary) -> void:
	_tables = d
	var h: Dictionary = _monthly(d.get("history", {}))
	var hd: Dictionary = h.get("data", {})
	if not hd.is_empty():
		_events = _find_events(hd)
		_set_line("m_price", h, [{"key": "price", "name": "Hier", "colour": Charts.SERIES[0]},
			{"key": "price_all", "name": "Median aller Märkte", "colour": Charts.SERIES[0], "muted": true}])
		_set_line("m_hungry", h, [{"key": "share_hungry", "name": "Hungernd", "colour": Charts.RED, "scale": 100.0}])
		_set_line("m_store", h, [{"key": "store_t", "name": "Lager", "colour": Charts.SERIES[0]},
			{"key": "sold_t", "name": "Verkauft im Monat", "colour": Charts.SERIES[1]}])
		_set_line("m_real", h, [{"key": "real_wage", "name": "Reallohn", "colour": Charts.SERIES[4]}])
		_set_line("m_persons", h, [{"key": "persons", "name": "Menschen", "colour": Charts.SERIES[1]},
			{"key": "tent_persons", "name": "Im Zelt", "colour": Charts.SERIES[2]}])
		_set_line("m_gini", h, [{"key": "gini", "name": "Hier", "colour": Charts.SERIES[3]},
			{"key": "gini_all", "name": "Alle Menschen der Karte", "colour": Charts.SERIES[3], "muted": true}])
		for r in GOOD_KEYS.size():
			_set_line("m_good%d" % r, h, [{"key": "good_" + GOOD_KEYS[r], "name": GOOD_NAMES[r], "colour": Charts.SERIES[0]}])
		_set_line("m_public", h, [{"key": "public_days", "name": "Öffentliche Arbeit", "colour": Charts.SERIES[1]}])
		_fill_tiles(hd)
	var classes: Dictionary = d.get("classes", {})
	if not classes.is_empty() and classes.data.has("persons"):
		var people := {}
		var money := {}
		var fixed := {}
		for r in classes.data.kind.size():
			var name: String = classes.data.kind[r]
			if float(classes.data.persons[r]) <= 0.0:
				continue
			people[name] = float(classes.data.persons[r])
			money[name] = float(classes.data.money[r])
			fixed[name] = FED_COLOURS[FED_NAMES.find(name)] if FED_NAMES.has(name) else OTHER
		_set_shares("m_people", people, "Menschen", fixed)
		_set_shares("m_money", money, "Denar", fixed, people, "Menschen")
	if d.has("data"):
		if _reasons != null:
			_reasons.text = str(d.data.get("why", [""])[0])
		_set_goods(_market_goods(d), hd)
	_find_market(hd, d)

## The market's history with each year before the last ten (kept as the
## year's mean, grain/tables.rs) spread over its twelve months, so the
## charts' months stay months; "yearly" marks the spread months.
static func _monthly(h: Dictionary) -> Dictionary:
	if h.is_empty() or not h.data.has("day"):
		return h
	var d: Dictionary = h.data
	var days: Array = d.day
	var n := days.size()
	var out := {}
	for key in d:
		out[key] = []
	out.yearly = []
	for i in n:
		# the first entry is a year too when the next one is a year later
		var gap: int = (int(days[i]) - int(days[i - 1])) if i > 0 else ((int(days[1]) - int(days[0])) if n > 1 else 30)
		var repeat := maxi(1, roundi(gap / 30.0))
		for k in repeat:
			for key in d:
				out[key].append(int(days[i]) - (repeat - 1 - k) * 30 if key == "day" else d[key][i])
			out.yearly.append(repeat > 1)
	var copy := h.duplicate()
	copy.data = out
	return copy

## A goods table (as the realm's) from the market's row: each good's price
## and store, and why it costs what it costs.
func _market_goods(d: Dictionary) -> Dictionary:
	var data: Dictionary = d.data
	var cols := Array(d.columns)
	var out := {"good": [], "unit": [], "price": [], "store": [], "why": []}
	for key in GOOD_KEYS:
		var at := cols.find("price_" + key)
		if at < 0:
			continue
		out.good.append(String(d.labels[at]).trim_prefix("Preis "))
		var store := cols.find("store_" + key)
		out.unit.append(d.units[store] if store >= 0 else "")
		out.price.append(float(data["price_" + key][0]))
		out.store.append(float(data["store_" + key][0]) if store >= 0 else 0.0)
		out.why.append(str(data.get("why_" + key, [""])[0]))
	return {"data": out}

## Why the grain costs what it costs here (the markets table's reasons),
## across the page.
func _reasons_card() -> void:
	var box := _card("m_why", true)
	_reasons = _label("", UiStyle.TEXT, UiStyle.SIZE_TEXT)
	_reasons.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reasons.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_reasons.custom_minimum_size = Vector2(0, LINE_PX * 2)
	box.add_child(_reasons)

## The market cards' findings, as _find_all the realm's.
func _find_market(d: Dictionary, row: Dictionary) -> void:
	var says := {}
	var n: int = d.get("day", []).size()
	if n > 0:
		var price := _col(d, "price")
		var all := _col(d, "price_all")
		if price.size() == n:
			says.m_price = "Korn kostet hier %s D/kg, %s." % [_num(price[n - 1]), _against_year(price, "teurer", "billiger")]
			if all.size() == n and all[n - 1] > 0.0:
				var vs := price[n - 1] / all[n - 1] - 1.0
				says.m_price += (" Das ist etwa der Median aller Märkte." if absf(vs) < 0.05 else
					" Das ist %s %% %s als der Median aller Märkte." % [_pct(absf(vs) * 100.0), "teurer" if vs > 0.0 else "billiger"])
		var hungry := _col(d, "share_hungry", 100.0)
		if hungry.size() == n:
			var months := 0
			for v in hungry.slice(maxi(0, n - 12)):
				months += 1 if v >= 1.0 else 0
			says.m_hungry = ("Diesen Monat wurden %s %% der Käufer nicht satt." % _pct(hungry[n - 1])) if hungry[n - 1] >= 0.5 else "Diesen Monat wurden alle Käufer satt."
			if months > 0:
				says.m_hungry += " In %d der letzten 12 Monate hungerte mindestens jeder Hundertste." % months
		var store := _col(d, "store_t")
		var sold := _col(d, "sold_t")
		if store.size() == n and sold.size() == n:
			var month := _year_sum(sold) / float(mini(12, n))
			if month <= 0.0:
				says.m_store = "Hier wird kaum Korn verkauft."
			elif store[n - 1] < month * 0.5:
				says.m_store = "Das Lager ist so gut wie leer: es reicht nicht für einen halben Monat Verkauf."
			else:
				var months := roundi(store[n - 1] / month)
				says.m_store = "Das Lager reicht für etwa %s Verkauf." % ("einen Monat" if months == 1 else "%d Monate" % months)
		var real := _col(d, "real_wage")
		if real.size() == n:
			says.m_real = "Ein Taglohn kauft hier %s kg Korn, %s." % [_num(real[n - 1]), _against_year(real, "mehr", "weniger")]
		var persons := _col(d, "persons")
		var tents := _col(d, "tent_persons")
		if persons.size() == n:
			says.m_persons = "In der Region leben %s Menschen, %s." % [_num(persons[n - 1]), _against_year(persons, "mehr", "weniger")]
			if tents.size() == n and tents[n - 1] >= 0.5:
				says.m_persons += " %s davon im Zelt." % _num(tents[n - 1])
		var days := _col(d, "public_days")
		var paid := _col(d, "public_wage")
		if days.size() == n:
			says.m_public = ("Im letzten Jahr bezahlte der Staat hier keine öffentliche Arbeit." if _year_sum(days) <= 0.0
				else "Im letzten Jahr bezahlte der Staat hier %s Tage öffentliche Arbeit%s." % [_num(_year_sum(days)),
					(" für %s Denar" % _num(_year_sum(paid))) if paid.size() == n else ""])
		var gini := _col(d, "gini")
		var gini_all := _col(d, "gini_all")
		if gini.size() == n and gini_all.size() == n:
			says.m_gini = "Gini %.2f, %s als über die ganze Karte (%.2f)." % [gini[n - 1], "gleicher verteilt" if gini[n - 1] < gini_all[n - 1] else "ungleicher verteilt", gini_all[n - 1]]
	var people := _top(_sums.get("m_people", {}))
	if not people.is_empty():
		says.m_people = "Die meisten hier sind %s: %d %% der Menschen." % [people[0], roundi(people[1] * 100.0)]
	var money := _top(_sums.get("m_money", {}))
	if not money.is_empty():
		says.m_money = "%s halten %d %% des Geldes." % [money[0], roundi(money[1] * 100.0)]
	var goods: Dictionary = _market_goods(row) if row.has("data") else {}
	if not goods.is_empty() and n > 1:
		var moved := -1.0
		for r in goods.data.good.size():
			var price := _col(d, "good_" + GOOD_KEYS[r])
			if price.size() == n and price[_year_back(n)] > 0.0:
				var change := absf(price[n - 1] / price[_year_back(n)] - 1.0)
				if change > moved:
					moved = change
					says.goods = "Am stärksten verändert: %s, %s." % [goods.data.good[r], _against_year(price, "teurer", "billiger")]
					says.m_goods = says.goods
	for r in GOOD_KEYS.size():
		var price := _col(d, "good_" + GOOD_KEYS[r])
		if price.size() == n and n > 0:
			says["m_good%d" % r] = "%s kostet hier %s D, %s." % [GOOD_NAMES[r], _num(price[n - 1]), _against_year(price, "mehr", "weniger")]
	_says = says
	_set_lage()

# ------------------------------------------------------------------ what happened, what it says

## What happened in which month, from the history: what the player built
## (the counts grew), a famine (at least 20 dead from hunger and three
## times the year's usual), a grain price a quarter up or down in a month.
## A run of famine or shock months is marked at its first. Day -> [text].
func _find_events(d: Dictionary) -> Dictionary:
	var out := {}
	var n: int = d.get("day", []).size()
	var note := func(i: int, text: String) -> void:
		var day := int(d.day[i])
		if not out.has(day):
			out[day] = []
		out[day].append(text)
	var builds := [["farms_built", "Ein Hof gebaut", "%d Höfe gebaut"], ["roads_built", "Ein Strassenstück gebaut", "%d Strassenstücke gebaut"],
		["fields_built", "Ein Feldstück angelegt", "%d Feldstücke angelegt"]]
	var famine := false
	var shock := false
	for i in range(1, n):
		for b in builds:
			if d.has(b[0]):
				var grew := int(d[b[0]][i]) - int(d[b[0]][i - 1])
				if grew > 0:
					note.call(i, b[1] if grew == 1 else b[2] % grew)
		if d.has("hunger_deaths"):
			var dead := float(d.hunger_deaths[i])
			var before := PackedFloat64Array()
			for j in range(maxi(0, i - 12), i):
				before.append(float(d.hunger_deaths[j]))
			before.sort()
			var now := dead >= 20.0 and dead >= 3.0 * before[before.size() / 2]
			if now and not famine:
				note.call(i, "Hungersnot: %s Hungertote" % Charts.label(dead))
			famine = now
		var price_key := "price_median" if d.has("price_median") else "price" # the realm's or one market's
		if d.has(price_key) and not (d.has("yearly") and d.yearly[i]):
			var p0 := float(d[price_key][i - 1])
			var change := (float(d[price_key][i]) - p0) / p0 if p0 > 0.0 else 0.0
			var now := absf(change) >= 0.25
			if now and not shock:
				note.call(i, ("Teuerung: Korn %s %% teurer" if change > 0.0 else "Preissturz: Korn %s %% billiger") % _pct(absf(change) * 100.0))
			shock = now
	return out

## Each card's finding: one sentence on what its numbers say now, against
## a year before (or the start, while the game is younger), computed from
## the tables, so a page has the findings of all cards (its Lage) and not
## only of its own.
func _find_all(d: Dictionary) -> void:
	var says := {}
	var n: int = d.get("day", []).size()
	var period := "Im letzten Jahr" if n > 12 else "Seit Beginn"
	if n > 0:
		var persons := _col(d, "persons")
		says.persons = "%s Menschen, %s." % [_num(persons[n - 1]), _against_year(persons, "mehr", "weniger")]
		var born := _year_sum(_col(d, "births"))
		var died := _year_sum(_col(d, "deaths"))
		says.life = "%s %s Geburten und %s Todesfälle: %s." % [period, _num(born), _num(died),
			"es werden mehr geboren, als sterben" if born > died else "es sterben mehr, als geboren werden"]
		var starved := _year_sum(_col(d, "hunger_deaths"))
		says.hunger = ("%s ist niemand verhungert." % period) if starved < 0.5 else ("%s sind %s Menschen verhungert." % [period, _num(starved)])
		if d.has("moved"):
			var left := _year_sum(_col(d, "left"))
			says.moves = "%s sind %s Menschen umgezogen" % [period, _num(_year_sum(_col(d, "moved")))]
			says.moves += (" und %s haben die Karte verlassen." % _num(left)) if left >= 0.5 else "; niemand hat die Karte verlassen."
		var tents := _col(d, "tent_persons")
		if tents.size() == n:
			says.tents = "%s Menschen leben im Zelt, %s." % [_num(tents[n - 1]), _against_year(tents, "mehr", "weniger")]
		var price := _col(d, "price_median")
		if price.size() == n:
			says.price = "Korn kostet im Median %s D/kg, %s." % [_num(price[n - 1]), _against_year(price, "teurer", "billiger")]
			if n > 3 and price[n - 1] <= _lowest(price) * 1.0001:
				says.price += " Tiefster Stand seit Beginn."
			elif n > 3 and price[n - 1] >= _highest(price) * 0.9999:
				says.price += " Höchster Stand seit Beginn."
		var worst := -1
		var short := 0
		for k in FED_KEYS.size():
			var fed := _col(d, "fed_" + FED_KEYS[k], 100.0)
			if fed.size() == n and fed[n - 1] < 99.0:
				short += 1
				if worst < 0 or fed[n - 1] < _col(d, "fed_" + FED_KEYS[worst], 100.0)[n - 1]:
					worst = k
		if worst < 0:
			says.fed = "Alle Schichten essen sich satt."
		else:
			says.fed = "%s %s nur %d %% ihres Kornbedarfs." % [FED_SUBJECTS[worst], "isst" if worst == 4 else "essen",
				floori(_col(d, "fed_" + FED_KEYS[worst], 100.0)[n - 1])]
			if short > 1:
				says.fed += " %d Schichten bekommen nicht genug." % short
		var harvest := _col(d, "harvest_t")
		if n >= 24:
			var last := _year_sum(harvest)
			var before := _year_sum(harvest.slice(0, n - 12))
			says.harvest = "Ernte im letzten Jahr %s t, %s." % [_num(last), _versus(last, before, "mehr", "weniger", "im Jahr davor")]
		else:
			says.harvest = "%s %s t geerntet." % [period, _num(_year_sum(harvest))]
		var stored := _col(d, "horrea_t")
		for key in ["lords_t", "market_store_t"]:
			var more := _col(d, key)
			for i in mini(stored.size(), more.size()):
				stored[i] += more[i]
		if stored.size() == n:
			says.granaries = "In den Speichern liegen %s t Korn, %s." % [_num(stored[n - 1]), _against_year(stored, "mehr", "weniger")]
		says.spoiled = "%s sind %s t Korn verdorben." % [period, _num(_year_sum(_col(d, "spoiled_t")))]
		says.flows = says.spoiled
		if _year_sum(_col(d, "export_t")) > 0.0:
			says.flows += " %s t gingen über den Kartenrand." % _num(_year_sum(_col(d, "export_t")))
		var out := _year_sum(_col(d, "export_t"))
		says.export = ("%s gingen %s t Korn über den Kartenrand." % [period, _num(out)]) if out >= 0.5 else ("%s ging kaum Korn über den Kartenrand." % period)
		says.traded = "%s wurden %s t Korn zwischen fernen Märkten gehandelt." % [period, _num(_year_sum(_col(d, "traded_t")))]
		var given := _year_sum(_col(d, "alms_t"))
		says.alms = ("%s wurden %s t Korn als Almosen verteilt." % [period, _num(given)]) if given >= 0.05 else ("%s wurden kaum Almosen verteilt." % period)
		var clothes := _col(d, "clothes", 100.0)
		if clothes.size() == n:
			says.clothes = "Die Haushalte haben %d %% der Kleidung, die sie brauchen." % roundi(clothes[n - 1])
		var p10 := _col(d, "real_p10")
		var p50 := _col(d, "real_p50")
		var need := _col(d, "need_wage")
		if p10.size() == n and need.size() == n and p50.size() == n:
			var w := [_num(p10[n - 1]), _num(p50[n - 1]), _num(need[n - 1])]
			if p10[n - 1] < need[n - 1]:
				says.real = "Im ärmsten Zehntel der Märkte bringt ein Taglohn %s kg Korn, nötig wären %s kg." % [w[0], w[2]]
			elif p50[n - 1] < need[n - 1]:
				says.real = "Am Median bringt ein Taglohn %s kg Korn, nötig wären %s kg." % [w[1], w[2]]
			else:
				says.real = "Ein Taglohn reicht überall: selbst im ärmsten Zehntel der Märkte bringt er %s kg, nötig sind %s kg." % [w[0], w[2]]
		var wage := _col(d, "wage")
		if wage.size() == n:
			says.wage = "Ein Taglohn bringt im Median %s Denar, %s." % [_num(wage[n - 1]), _against_year(wage, "mehr", "weniger")]
		var vacant := _col(d, "vacant")
		var idle := _col(d, "idle")
		if vacant.size() == n and idle.size() == n:
			if idle[n - 1] > vacant[n - 1] * 1.2:
				says.work = "Arbeit fehlt: %s Arbeitstage blieben liegen, %s wurden vergeblich gesucht." % [_num(idle[n - 1]), _num(vacant[n - 1])]
			elif vacant[n - 1] > idle[n - 1] * 1.2:
				says.work = "Arbeiter fehlen: %s Arbeitstage wurden vergeblich gesucht, %s blieben liegen." % [_num(vacant[n - 1]), _num(idle[n - 1])]
			else:
				says.work = "Gesuchte und angebotene Arbeit halten sich die Waage."
		var lorenz := _lorenz_at(d, n - 1)
		if lorenz.size() == 11:
			says.lorenz = "Das reichste Zehntel hat %s %% des Geldes, die ärmere Hälfte %s %%." % [_pct((1.0 - lorenz[9]) * 100.0), _pct(lorenz[5] * 100.0)]
		var most := -1
		var least := -1
		var gini := PackedFloat64Array()
		for k in FED_KEYS.size():
			var g := _col(d, "gini_" + FED_KEYS[k])
			gini.append(g[n - 1] if g.size() == n else 0.0)
			if gini[k] > 0.0:
				most = k if most < 0 or gini[k] > gini[most] else most
				least = k if least < 0 or gini[k] < gini[least] else least
		if most >= 0 and most != least:
			says.gini_rows = "Am ungleichsten ist das Geld bei %s verteilt (%.2f), am gleichsten bei %s (%.2f)." % [
				FED_DATIVES[most], gini[most], FED_DATIVES[least], gini[least]]
		var farms := _col(d, "farms")
		if farms.size() == n:
			says.farm_count = "%s Höfe, %s." % [_num(farms[n - 1]), _against_year(farms, "mehr", "weniger")]
		var farm_store := _col(d, "farm_store_t")
		if farm_store.size() == n:
			says.farm_store = "In den Hoflagern liegen %s t Korn, %s." % [_num(farm_store[n - 1]), _against_year(farm_store, "mehr", "weniger")]
		var cash := _col(d, "cash")
		if cash.size() == n:
			says.cash = "In der Kasse liegen %s Denar, %s." % [_num(cash[n - 1]), _against_year(cash, "mehr", "weniger")]
		var held := _col(d, "money_held")
		if held.size() == n:
			says.held = "Im Umlauf sind %s Denar, %s." % [_num(held[n - 1]), _against_year(held, "mehr", "weniger")]
		var income := 0.0
		var parts := PackedStringArray()
		var biggest := ["", 0.0]
		for spec in BUDGET_IN:
			income += _year_sum(_col(d, spec[0]))
		for spec in BUDGET_IN:
			var v := _year_sum(_col(d, spec[0]))
			if d.has(spec[0]) and income > 0.0 and v / income >= 0.005:
				var name := _label_of(_tables.get("history", {}), spec[0])
				parts.append("%s %% %s" % [_pct(v / income * 100.0), name])
				if v > biggest[1]:
					biggest = [name, v]
		if income > 0.0:
			says.income = "Im %s nahm der Staat %s Denar ein: %s." % ["letzten Jahr" if n > 12 else "ersten Jahr bisher", _num(income), ", ".join(parts)]
		var wages_d := _year_sum(_col(d, "wages_d"))
		var works_d := _year_sum(_col(d, "public_works_d"))
		if d.has("wages_d") and wages_d + works_d > 0.0:
			says.spending = "Im %s gab der Staat %s Denar aus, %d %% davon für öffentliche Arbeit." % [
				"letzten Jahr" if n > 12 else "ersten Jahr bisher", _num(wages_d + works_d), roundi(works_d / (wages_d + works_d) * 100.0)]
		var spent := 0.0
		for spec in BUDGET_OUT:
			spent += _year_sum(_col(d, spec[0]))
		if income > 0.0 or spent > 0.0:
			var balance := income - spent
			says.budget = "Im %s nahm der Staat %s Denar ein und gab %s aus, %s Denar %s." % ["letzten Jahr" if n > 12 else "ersten Jahr bisher",
				_num(income), _num(spent), _num(absf(balance)), "mehr ein als aus" if balance >= 0.0 else "mehr aus als ein"]
			if biggest[1] > 0.0:
				says.budget += " Am meisten brachte: %s." % biggest[0]
		var arrears := _col(d, "arrears")
		var owing := _col(d, "arrears_households")
		if arrears.size() == n:
			says.arrears = ("Niemand schuldet dem Staat Steuern." if arrears[n - 1] < 1.0 else
				"%s Haushalte schulden dem Staat %s Denar Steuern, %s." % [_num(owing[n - 1]) if owing.size() == n else "Einige", _num(arrears[n - 1]),
					_against_year(arrears, "mehr", "weniger")])
			says.arrears_households = says.arrears
		var seized := _col(d, "seized_d")
		if seized.size() == n:
			says.seized = "Im letzten Jahr pfändete der Staat %s Denar in Geld und Korn und schrieb %s Denar ab." % [_num(_year_sum(seized)),
				_num(_year_sum(_col(d, "written_off_d")))]
		var sold := _col(d, "auctions")
		if sold.size() == n:
			var fell := _year_sum(_col(d, "domains"))
			says.auctions = "Im letzten Jahr wurden %s Höfe versteigert, %s fielen ohne Käufer an den Staat." % [_num(_year_sum(sold)), _num(fell)]
			var ha_price := _col(d, "land_price")
			for i in range(ha_price.size() - 1, -1, -1):
				if ha_price[i] > 0.0:
					says.auctions += " Zuletzt brachte ein Hektar %s Denar (%s)." % [_num(ha_price[i]), date.call(int(d.day[i]))]
					break
		var days := _col(d, "public_days")
		if days.size() == n:
			if _year_sum(days) <= 0.0:
				says.public_days = ("Im letzten Jahr bezahlte der Staat keine öffentliche Arbeit: die Kasse lag nicht über ihrer Reserve." if n > 12
					else "Im ersten Jahr bezahlt der Staat noch keine öffentliche Arbeit: die Kasse kennt ihre Reserve erst nach einem Jahr.")
			else:
				says.public_days = "Diesen Monat bezahlte der Staat %s Tage öffentliche Arbeit, im letzten Jahr %s Tage." % [_num(days[n - 1]), _num(_year_sum(days))]
		var taxed := _col(d, "tax_grain_t")
		if taxed.size() == n:
			says.tax_grain = "Seit Beginn hat der Staat %s t Korn als Steuer eingezogen" % _num(taxed[n - 1])
			says.tax_grain += (", %s t davon im letzten Jahr." % _num(taxed[n - 1] - taxed[_year_back(n)])) if n > 12 else "."
		for r in GOOD_KEYS.size():
			var good := _col(d, "good_" + GOOD_KEYS[r])
			if good.size() == n:
				says["good%d" % r] = "%s kostet im Median %s D, %s." % [GOOD_NAMES[r], _num(good[n - 1]), _against_year(good, "mehr", "weniger")]
	var jobs := _top(_sums.get("jobs", {}))
	if not jobs.is_empty():
		says.jobs = "Die meisten arbeiten als %s: %d %% der Menschen." % [jobs[0], roundi(jobs[1] * 100.0)]
	var kinds := _top(_sums.get("farms", {}))
	if not kinds.is_empty():
		says.farms = "Am häufigsten: %s, %d %% der Höfe." % [kinds[0], roundi(kinds[1] * 100.0)]
	var land: Dictionary = _sums.get("land", {})
	if land.get("Gesät", 0.0) + land.get("Brach", 0.0) > 0.0:
		var sown: float = land["Gesät"] / (land["Gesät"] + land["Brach"]) * 100.0
		says.land = "%d %% der Felder sind gesät, %d %% liegen brach." % [roundi(sown), 100 - roundi(sown)]
	var classes: Dictionary = _tables.get("classes", {})
	if not classes.is_empty() and classes.data.has("money"):
		var top := Array(classes.data.kind).find(FED_NAMES[4])
		var money := _total(classes.data.money)
		var people := _total(classes.data.get("persons", []))
		if top >= 0 and money > 0.0:
			says.money = "Die Oberschicht hält %d %% des Geldes" % roundi(float(classes.data.money[top]) / money * 100.0)
			if people > 0.0:
				says.money += ", ist aber nur %s %% der Menschen" % _pct(float(classes.data.persons[top]) / people * 100.0)
			says.money += "."
	var goods: Dictionary = _tables.get("goods", {})
	if not goods.is_empty() and n > 1:
		var moved := -1.0
		for r in mini(goods.data.good.size(), GOOD_KEYS.size()):
			var price := _col(d, "good_" + GOOD_KEYS[r])
			if price.size() == n and price[_year_back(n)] > 0.0:
				var change := absf(price[n - 1] / price[_year_back(n)] - 1.0)
				if change > moved:
					moved = change
					says.goods = "Am stärksten verändert: %s, %s." % [goods.data.good[r], _against_year(price, "teurer", "billiger")]
	var paid := 0.0
	var got := 0.0
	for r in _bar_rows:
		if r[2] in ["wages", "public_works"]:
			paid -= float(r[1])
		elif r[2] in ["land_tax", "head_tax", "tax", "rent", "estates"]:
			got += float(r[1])
	if paid > 0.0:
		says.state = "Seit Beginn decken die Einnahmen %d %% dessen, was der Staat an Löhnen zahlt." % roundi(got / paid * 100.0)
	var laws: Array = _tables.get("laws", [])
	if not laws.is_empty():
		var parts := PackedStringArray()
		for law in laws:
			parts.append("%s %s" % [law.name, law.levels[int(law.level)]])
		says.laws = "Jetzt: %s." % ", ".join(parts)
	_says = says
	_set_lage()

## The largest of `sums` (name -> amount) and its share of all: [name, share], or [].
static func _top(sums: Dictionary) -> Array:
	var total := 0.0
	var best := ""
	for name in sums:
		total += float(sums[name])
		if best == "" or float(sums[name]) > float(sums[best]):
			best = name
	return [best, float(sums[best]) / total] if total > 0.0 else []

## A history column as floats, times `scale`.
static func _col(d: Dictionary, key: String, scale := 1.0) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for v in d.get(key, []):
		out.append(float(v) * scale)
	return out

## The row a year before the last (or the first).
static func _year_back(n: int) -> int:
	return n - 13 if n > 12 else 0

## The last twelve months added up (or all).
static func _year_sum(vals: PackedFloat64Array) -> float:
	var sum := 0.0
	for v in vals.slice(maxi(0, vals.size() - 12)):
		sum += v
	return sum

static func _lowest(vals: PackedFloat64Array) -> float:
	var low := INF
	for v in vals:
		low = minf(low, v)
	return low

static func _highest(vals: PackedFloat64Array) -> float:
	var high := -INF
	for v in vals:
		high = maxf(high, v)
	return high

## "5 % mehr als vor einem Jahr": the last value against a year before.
static func _against_year(vals: PackedFloat64Array, up: String, down: String) -> String:
	var n := vals.size()
	if n < 2:
		return "noch ohne Vergleich"
	return _versus(vals[n - 1], vals[_year_back(n)], up, down, "vor einem Jahr" if n > 12 else "zu Beginn")

static func _versus(now: float, before: float, up: String, down: String, when: String) -> String:
	if absf(before) < 1e-9:
		return "zuvor nichts"
	var pct := (now - before) / absf(before) * 100.0
	if absf(pct) < 1.0:
		return "etwa gleich wie %s" % when
	return "%s %% %s als %s" % [_pct(absf(pct)), up if pct > 0.0 else down, when]

## A number in a sentence, Swiss style: 9’740, 56k, 1.6.
static func _num(v: float) -> String:
	var a := absf(v)
	if a >= 1000.0 and a < 1.0e4:
		return "%s%d’%03d" % ["-" if v < 0.0 else "", int(a) / 1000, int(a) % 1000]
	return Charts.label(v)

static func _pct(p: float) -> String:
	return ("%.1f" % p) if p < 10.0 else ("%d" % roundi(p))

# ------------------------------------------------------------------ parts

func _swatch(colour: Color, text: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flag := Control.new() # EU5's little pennant
	flag.custom_minimum_size = Vector2(9, 13)
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag.draw.connect(func():
		var shape := PackedVector2Array([Vector2(0, 0), Vector2(9, 0), Vector2(9, 13), Vector2(4.5, 9.5), Vector2(0, 13)])
		flag.draw_colored_polygon(shape, colour)
		flag.draw_rect(Rect2(0, 0, 9, 3), Color(1, 1, 1, 0.25))
		shape.append(shape[0])
		flag.draw_polyline(shape, UiStyle.EDGE, 1.0, true))
	line.add_child(flag)
	var label := _label(text, UiStyle.TEXT, UiStyle.SIZE_SMALL)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(label)
	return line

## A card's foot under its figure: one quiet line, cut short with an
## ellipsis, so every card in a row ends on the same line.
static func _foot() -> Label:
	var foot := _label("", UiStyle.DIM, UiStyle.SIZE_SMALL)
	foot.clip_text = true
	foot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.custom_minimum_size = Vector2(0, LINE_PX)
	return foot

static func _label(text: String, colour: Color, font_size: int) -> Label:
	return UiStyle.label(text, colour, font_size)
