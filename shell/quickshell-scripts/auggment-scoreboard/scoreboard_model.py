"""League catalogue for the Scoreboard settings picker (ported from Model.js)."""

LEAGUES = [
    {"path": "football/nfl", "label": "NFL", "group": "Football"},
    {"path": "football/college-football", "label": "NCAA Football", "group": "Football"},
    {"path": "football/cfl", "label": "CFL", "group": "Football"},
    {"path": "football/xfl", "label": "XFL", "group": "Football"},
    {"path": "basketball/nba", "label": "NBA", "group": "Basketball"},
    {"path": "basketball/wnba", "label": "WNBA", "group": "Basketball"},
    {"path": "basketball/mens-college-basketball", "label": "NCAA Men's Basketball", "group": "Basketball"},
    {"path": "basketball/womens-college-basketball", "label": "NCAA Women's Basketball", "group": "Basketball"},
    {"path": "basketball/euroleague", "label": "EuroLeague", "group": "Basketball"},
    {"path": "baseball/mlb", "label": "MLB", "group": "Baseball"},
    {"path": "baseball/college-baseball", "label": "NCAA Baseball", "group": "Baseball"},
    {"path": "baseball/milb", "label": "MiLB", "group": "Baseball"},
    {"path": "hockey/nhl", "label": "NHL", "group": "Hockey"},
    {"path": "hockey/mens-college-hockey", "label": "NCAA Hockey", "group": "Hockey"},
    {"path": "soccer/usa.1", "label": "MLS", "group": "Soccer"},
    {"path": "soccer/usa.nwsl", "label": "NWSL", "group": "Soccer"},
    {"path": "soccer/eng.1", "label": "Premier League", "group": "Soccer"},
    {"path": "soccer/esp.1", "label": "La Liga", "group": "Soccer"},
    {"path": "soccer/ger.1", "label": "Bundesliga", "group": "Soccer"},
    {"path": "soccer/ita.1", "label": "Serie A", "group": "Soccer"},
    {"path": "soccer/fra.1", "label": "Ligue 1", "group": "Soccer"},
    {"path": "soccer/mex.1", "label": "Liga MX", "group": "Soccer"},
    {"path": "soccer/uefa.champions", "label": "UEFA Champions League", "group": "Soccer"},
    {"path": "soccer/fifa.world", "label": "FIFA World Cup", "group": "Soccer"},
    {"path": "racing/nascar-cup", "label": "NASCAR Cup", "group": "Racing"},
    {"path": "racing/irl", "label": "IndyCar", "group": "Racing"},
    {"path": "racing/f1", "label": "Formula 1", "group": "Racing"},
    {"path": "golf/pga", "label": "PGA Tour", "group": "Golf"},
]

GROUP_ORDER = ["Football", "Basketball", "Baseball", "Hockey", "Soccer", "Racing", "Golf"]

RACING = {"racing/nascar-cup", "racing/irl", "racing/f1"}


def label_for(path):
    for league in LEAGUES:
        if league["path"] == path:
            return league["label"]
    return str(path).split("/")[-1].upper()


def is_racing(path):
    return path in RACING


def is_golf(path):
    return path == "golf/pga"
