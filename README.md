# trainbot

A Ruby library that scrapes train routes and fares from TheTrainline and returns structured results.

## Usage

```ruby
require 'bot'

segments = Bot::Thetrainline.find(
  'Berlin Hbf',
  "Paris Gare de l'Est",
  DateTime.parse('2026-03-16T00:00:00+00:00')
)
```

Station names must be passed exactly as the API returns them (canonical form, including Unicode characters).

## Docker Compose services

All development tasks run inside Docker. No local Ruby installation is required.

### Run the library

Calls `Bot::Thetrainline.find` with a Berlin → Paris query and pretty-prints the result.

```sh
docker compose run --rm lib
```

### Run the test suite

```sh
docker compose run --rm test
```

### Run the linter

```sh
docker compose run --rm lint
```

## Fixtures

The library is fixture-based — it does not make live HTTP requests. JSON fixtures live in `fixtures/` and are loaded by `Fetcher` at runtime.

### Fixture file naming

Fixture filenames are derived from the station names passed to `find`:

```
{slugify(from)}_{slugify(to)}.json
```

Slugification: lowercase, runs of non-alphanumeric characters replaced with `_`, leading/trailing underscores stripped.

Examples:

| from / to | filename |
|-----------|----------|
| `Berlin Hbf` / `Paris Gare de l'Est` | `berlin_hbf_paris_gare_de_l_est.json` |
| `Berlin Hbf` / `Lisboa Santa Apolónia` | `berlin_hbf_lisboa_santa_apol_nia.json` |

If no fixture file exists for a given route, `Fetcher` raises `ArgumentError`.

### Date shifting

Fixtures contain journeys anchored to a fixed base date. When `find` is called with a `departure_at`, the fetcher shifts all journey timestamps to the requested date while preserving wall-clock times and applying the correct UTC offset for DST transitions (timezone: `Europe/Berlin`). Journeys departing before the requested time are filtered out.

### Adding a new fixture

1. Create a JSON file in `fixtures/` named after the route (see naming convention above).
2. The file must follow the Trainline API response structure:

```json
{
  "data": {
    "journeySearch": {
      "journeys":     { "<id>": { "departAt": "...", "arriveAt": "...", "duration": "PT8H", "sections": [...], "legs": [...] } },
      "sections":     { "<id>": { "alternatives": [...] } },
      "alternatives": { "<id>": { "fares": ["<fare-id>"], "price": { "amount": 19.39, "currencyCode": "GBP" } } },
      "fares":        { "<id>": { "fareType": "<fare-type-id>" } },
      "legs":         { "<id>": { "departureLocation": "<loc-id>", "arrivalLocation": "<loc-id>" } }
    },
    "locations":  { "<id>": { "name": "Berlin Hbf" } },
    "fareTypes":  { "<id>": { "name": "Advance Single" } }
  }
}
```
