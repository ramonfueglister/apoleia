# EU5 interface: what the windows and tooltips copy

Ramon (29.10.2026): the statistics must reach EU5's level ("hol dir
screenshots und baue nach"). The shots are Paradox's own and stay out of
this public repository; they lie in the project's shared files
(`eu5-referenz/`, 40 images with an index). Sources:

- Developer Diary #1, Population and Living World: https://store.steampowered.com/news/app/3450310/view/1809235871586590
- Developer Diary #3, Trade & Economics: https://store.steampowered.com/news/app/3450310/view/1810503566416798
- Tinto Talks #103, 1.2 Free Content pt. 1: https://store.steampowered.com/news/app/3450310/view/1829528821304950
- Tinto Talks 122, UI and QOL Changes: https://store.steampowered.com/news/app/3450310/view/1842846814440244
- Tinto Talk 124, Economy, Trade & Tariffs: https://store.steampowered.com/news/app/3450310/view/1844115010489008
- Store page screenshots: https://store.steampowered.com/app/3450310

## What we take (app/scripts/ui/)

| EU5 | apoleia |
|---|---|
| Dark slate panels in a thin bronze frame, title centred in a serif, round back/close buttons | `ui_style.gd` frame(), `ui_window.gd` |
| Tabs as raised boards, the chosen one lit | `ui_style.gd` theme(), TabBar |
| Sunken boxes with faintly striped rows; numbers right aligned; gains green, losses red | `ui_style.gd` inset(), `tooltips.gd` rows |
| Tooltip head: title, below it the kind of thing in blue italics ("Market Price") | `tooltips.gd` title, kind |
| Concepts in light blue, each with a tooltip of its own (nested, CK3's system) | `tooltips.gd` [url=term], Tooltips.term() |
| Names (places, goods) in pale gold | `tooltips.gd` [n]…[/n] |
| "Recent Market Price" box in a price tooltip: highest and lowest value at the left, first and last month at the foot | `tooltips.gd` _chart |
| Economy line graph on a dark grid with dates in the corners | `sim_tables.gd` _draw_chart (with the price band Ramon wants kept) |
| Donut with a list of shares (culture of a location) | step 2 |
| Mouse hints at a tooltip's foot ("Select Murcia", "Open Location Menu") | `tooltips.gd` hints |

What we add beyond the shots, as Ramon asked: a tooltip locks after a second
(a gold ring fills), then shows its curve and can be entered; windows can be
moved, sized and folded and remember where they stood.

What we keep from our own first draft (Ramon, 29.10.2026): the price as a
median inside the band of the cheapest and dearest market, the small curves
of each market's last 24 months in the table, the red bars of the hungry.
