# FocusGuard

App iOS personale per limitare il tempo d'uso delle altre app, costruita sulle API ufficiali
Tempo di utilizzo di Apple (FamilyControls, ManagedSettings, DeviceActivity).
Uso esclusivamente personale, nessuna distribuzione.

## Funzioni

| Funzione | Stato |
| --- | --- |
| Blocco immediato di app scelte | Codice pronto |
| Blocchi a orario (anche notturni, per giorni della settimana) | Codice pronto |
| Limite giornaliero per gruppo di app | Codice pronto |
| Tempo totale (limite su tutte le categorie) | Codice pronto |
| Registro eventi | Codice pronto |
| PIN / Face ID sulle modifiche che allentano le regole | Fase 5 (logica già testata) |
| Schermata di blocco personalizzata, statistiche d'uso | Fase 6 |

## Struttura

```
Packages/RuleEngine/   logica pura + test (gira su Linux)
iOS/Shared/            App Group, persistenza, ManagedSettings, DeviceActivity
iOS/App/               interfaccia SwiftUI
iOS/MonitorExtension/  estensione DeviceActivityMonitor
iOS/Config/            Info.plist ed entitlements
project.yml            progetto XcodeGen
```

## Sviluppo su Ubuntu

```bash
# Test della logica
swift test --package-path Packages/RuleEngine
```

La build iOS completa gira su GitHub Actions (`.github/workflows/ci.yml`): a ogni push su `main`
compila l'app senza firma su un runner macOS. Per installarla sull'iPhone serve la firma
(sezione successiva).

## Installazione sull'iPhone

Richiede l'**Apple Developer Program** (99 USD/anno): l'entitlement Family Controls non è
disponibile con l'account gratuito, e senza di esso le API Tempo di utilizzo non funzionano.

1. Iscriviti e annota il Team ID.
2. Scrivilo in `DEVELOPMENT_TEAM` in `project.yml`.
3. Se il Bundle ID `it.jacopo.focusguard` è già preso, cambialo (insieme all'App Group) in
   `project.yml`, `iOS/Shared/AppGroup.swift` e nei due file `iOS/Config/*.entitlements`.
4. Firma e installa con xtool da Ubuntu, oppure aggiungi la firma al workflow CI e installa il
   `.ipa` con `ideviceinstaller -i FocusGuard.ipa`.
5. Sull'iPhone attiva Impostazioni → Privacy e sicurezza → Modalità sviluppatore.

## Debug

```bash
idevicesyslog | grep it.jacopo.focusguard
```

Nelle build Debug la lista regole ha il pulsante "Sblocca tutto (debug)".
