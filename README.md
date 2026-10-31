# FocusGuard

Strumento personale per limitare il tempo d'uso di Instagram, TikTok e YouTube sull'iPhone: una web app
gratuita che lavora insieme a Comandi rapidi di iOS 27. Non richiede l'account Apple a pagamento.
Uso esclusivamente personale, nessuna distribuzione.

## Come funziona

1. All'apertura di un'app, un'automazione di iOS lancia il comando **FG Controllo**. Se esiste un pass valido non
   fa nulla, altrimenti apre la web app in Safari.
2. La **web app** decide: mostra il blocco con il conto alla rovescia, oppure i pulsanti "Usa 5/10/15 minuti", che
   scalano dal budget giornaliero.
3. Il comando **FG Pass** salva la scadenza del pass e riapre l'app.

I dati restano in Safari, con backup JSON da esportare e importare, senza backend. I dettagli, le decisioni e i
limiti noti sono in [`web/DESIGN.md`](web/DESIGN.md).

## Stato

| Fase | Contenuto | Stato |
| --- | --- | --- |
| W1 | Logica: regole, budget, pass, PIN, attese, registro eventi | Fatta, con test |
| W2 | Interfaccia e persistenza | Da fare |
| W3 | Guida ai comandi rapidi | Da fare |

Per ora non c'è niente da usare sul telefono: la pagina web è un segnaposto e i comandi rapidi non sono ancora
stati provati.

## Struttura

```
web/src/engine/   logica pura + test
web/src/crypto/   hash del PIN (PBKDF2 via WebCrypto)
web/DESIGN.md     architettura
iOS/, Packages/, project.yml   app nativa congelata
```

## Sviluppo

Serve Node LTS. Da `web/`:

```bash
npm ci
npm test
npm run build
```

Il workflow `.github/workflows/ci.yml` esegue test e build della web app a ogni push su `main` e sulle pull request.

## App nativa (congelata)

L'app nativa in SwiftUI, basata sulle API Tempo di utilizzo di Apple, resta nel repo come riferimento ma non è più
sviluppata. Il suo codice è stato solo compilato, mai provato su un telefono: per installarla servirebbe l'**Apple
Developer Program** (99 USD/anno), perché l'entitlement Family Controls non è disponibile con l'account gratuito.

```
Packages/RuleEngine/   logica pura + test (gira su Linux)
iOS/Shared/            App Group, persistenza, ManagedSettings, DeviceActivity
iOS/App/               interfaccia SwiftUI
iOS/MonitorExtension/  estensione DeviceActivityMonitor
iOS/Config/            Info.plist ed entitlements
project.yml            progetto XcodeGen
```

La build iOS è in `.github/workflows/ios.yml`: esegue i test di `RuleEngine` e compila l'app senza firma su un runner
macOS. Parte solo se cambiano `iOS/`, `Packages/` o `project.yml`, oppure a mano con "Run workflow".

```bash
# Test della logica nativa, su Ubuntu
LC_ALL=C swift test --package-path Packages/RuleEngine -Xswiftc -use-ld=lld
```
