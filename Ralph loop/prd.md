# PRD

## Přehled
*(Stručný popis projektu či funkce.)*

## Cílová skupina
*(Pro koho je aplikace/funkce určena.)*

## Hlavní funkčnosti
*(Seznam klíčových požadavků a funkcí, které má aplikace splňovat.)*

## Tech Stack
- Backend: *např. ASP.NET Core 7 (C#), EF Core*
- Frontend: *např. Blazor WASM / ASP.NET MVC*
- Testování: *NUnit (jednotkové testy), Playwright pro .NET (UI testy)*
- Další: *např. SignalR, API integrace...*

## Omezení a předpoklady
- Úkoly musí být dostatečně malé, aby šly dokončit v jedné iteraci agenta.
- Veškeré ověřování musí být spustitelné lokálně (např. `dotnet build`, `dotnet test` apod.).
- Všechny změny na frontendu musí být ověřeny vizuálně v prohlížeči (automatizované UI testy).
- Kód by měl být navržen s ohledem na testovatelnost (oddělení odpovědností, injekce závislostí).

## Kritéria úspěchu
- Všechny definované úkoly mají `"passes": true` (tj. splněno včetně testů).
- Proběhly a prošly všechny příslušné testy (jednotkové i UI).
- Uživatelské rozhraní je responzivní a design odpovídá zadání (bez zásadních nedostatků UX).
- Agent na konci vypíše přesně `<promise>COMPLETE</promise>`.

---

## Task List *(DO NOT EDIT EXCEPT "passes")*

```json
[
  {
    "id": 1,
    "title": "Popište úkol zde",
    "description": "Detailní popis úkolu a akceptační kritéria jeho splnění.",
    "passes": false
  }
]
