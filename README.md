# Fokus — uppgifter och fokustid

En PWA som är två appar i en: en uppgiftshanterare byggd på Things modell, och en
fokustimer som överlever att appen stängs. De möts i raden — varje uppgift kan
startas som ett pass, och tiden bokförs på uppgiftens livsområde.

Allt sparas lokalt på enheten. Inget konto, ingen server.

## Kör lokalt

```bash
node server.mjs
# http://localhost:4870
```

Ingen build, inga beroenden. Bara statiska filer.

## Filer

| Fil | Roll |
|---|---|
| `index.html` | Hela app-skalet: fyra vyer + ikonsprite |
| `styles.css` | Designsystem (tokens → layout → komponenter), ljust och mörkt tema |
| `app.js` | All logik: state, timer, notiser, vyer. En IIFE, inga beroenden |
| `sw.js` | Service worker: offline-cache (network-first) + larm |
| `manifest.webmanifest` | PWA-manifest för installation på hemskärmen |
| `server.mjs` | Minimal statisk server för lokal utveckling |
| `tools/make_icons.py` | Genererar app-ikonerna (ren stdlib, inga beroenden) |

## Uppgiftsmodellen

Lånad rakt av från Things, för att den är genomtänkt:

```
Livsområde (fast: Socialt, Struktur, Pengar/Karriär, Utseende/Hälsa)
  └── Projekt
        ├── Rubrik
        └── Uppgift
              ├── Anteckningar
              ├── Checklista
              └── Taggar
```

Var en uppgift hamnar avgörs av **två fält, inte av vilken lista den ligger i**:

| Fält | Värden | Betydelse |
|---|---|---|
| `when` | `null` · `'someday'` · `'ÅÅÅÅ-MM-DD'` | när den ska göras |
| `deadline` | `null` · `'ÅÅÅÅ-MM-DD'` | när den måste vara klar |

Listorna är vyer över de fälten och äger ingenting:

| Lista | Innehåller |
|---|---|
| Inkorg | varken livsområde eller projekt |
| Idag | `when` ≤ idag, plus deadlines som gått ut |
| Kommande | `when` > idag, grupperat per dag |
| När som helst | sorterad någonstans, men utan dag |
| Någon gång | `when === 'someday'` |
| Loggbok | avklarade, grupperade per dag |

`S.tasks` är **en platt array och ordningen i den _är_ sorteringen**. Rubriker
ligger i samma array (`type:'heading'`), så ett projekts rubriker och uppgifter
växlar av sig själva utan något ordningsfält. Det magiska plusset räknar om
släpppunkten till ett index i den arrayen.

Gammal data migreras en gång vid inläsning (`migrate()` i `app.js`) — en uppgift
från v1 får varje nytt fält och hamnar i **När som helst**.

## Så fungerar timern

State ligger i `S.timer` som `{status, durationMs, startedAt, elapsedBefore}`.
Återstående tid räknas alltid ut från `Date.now()` — aldrig genom att räkna ner en
variabel. Därför stämmer tiden även om telefonen låses, fliken fryses eller appen
stängs helt: vid nästa öppning återupptas passet på rätt sekund, och ett pass som
hann ta slut loggas med rätt sluttid.

## Notiser

Tre nivåer, i fallande ordning av tillförlitlighet:

1. **Notification Triggers** (`TimestampTrigger`, Chromium): larmet schemaläggs i
   systemet och kommer fram även när appen är helt stängd.
2. **Service worker-timeout**: fungerar så länge workern lever — täcker vanliga
   fall där appen ligger i bakgrunden en kortare stund.
3. **Vid återkomst**: när appen blir synlig igen upptäcks ett avslutat pass
   direkt, notisen visas och passet loggas med korrekt sluttid.

På iPhone krävs iOS 16.4+ *och* att appen är tillagd på hemskärmen för att notiser
ska vara tillåtna alls. Utan en push-server kan iOS inte väcka appen på schemalagd
tid — därför gäller nivå 3 där. Tiden blir alltid rätt.

## Lagring

Allt ligger i `localStorage` under nyckeln `fokus.state.v1` (nyckeln behöll sitt
namn vid v2 — `state.v` i objektet är versionen som styr migreringen), och appen begär
`navigator.storage.persist()` så att data inte vräks ut vid utrymmesbrist.
Inget konto, ingen server, inget lämnar enheten. Export/import av en JSON-backup
finns under **Mer → Dina data**.

## Ikoner

```bash
python3 tools/make_icons.py
```

Ritar om alla PNG-ikoner (192, 512, maskable, apple-touch, badge) från kod.
