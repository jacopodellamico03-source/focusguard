# FocusGuard — istruzioni per Claude Code

App iOS personale (non distribuita) per limitare il tempo d'uso delle app sul mio iPhone.
Sviluppo su Ubuntu; la compilazione iOS avviene in CI (GitHub Actions, macOS) o con xtool.

## Architettura

- `Packages/RuleEngine/` — logica pura in Swift, **nessun import di framework Apple oltre Foundation**.
  Si testa su Linux: `swift test --package-path Packages/RuleEngine`.
  Ogni decisione (bloccare o no, validazione, cosa riavviare, quando chiedere il PIN) vive qui.
- `iOS/Shared/` — codice compilato sia nell'app sia nelle estensioni: App Group, persistenza JSON,
  `ShieldController` (ManagedSettings), `ActivityScheduler` (DeviceActivity).
- `iOS/App/` — SwiftUI, `AppModel` (@Observable, @MainActor).
- `iOS/MonitorExtension/` — `DeviceActivityMonitor`: legge, chiede a `ShieldDecision`, esegue, registra.
- `project.yml` — XcodeGen. Il `.xcodeproj` è generato e non va committato.

## Identificativi

- Bundle ID app: `it.jacopo.focusguard`; estensione: `it.jacopo.focusguard.monitor`
- App Group: `group.it.jacopo.focusguard` (in `iOS/Shared/AppGroup.swift` e nei due `.entitlements`)
- Deployment target: iOS 17.4 · Swift language mode 5

## Regole

- Solo API pubbliche: FamilyControls, ManagedSettings, DeviceActivity. Mai API private.
- Le app sono token opachi (`ApplicationToken`): non provare a ricavarne nome o bundle ID.
- Estensioni: memoria molto limitata. Niente SwiftData, niente rete, niente lavori pesanti.
- File nell'App Group scritti con `.completeFileProtectionUntilFirstUserAuthentication`.
- Uno `ManagedSettingsStore` per regola (`.rule(id)`) più `.manual`.
- Nuova logica → prima in RuleEngine con test XCTest, poi il collegamento iOS.
- Log con `Log.app` / `Log.monitor` (OSLog, subsystem `it.jacopo.focusguard`).
- Testi dell'interfaccia in italiano.
- Se non sei sicuro della firma di un'API Apple, dillo e indica cosa verificare nella documentazione.

## Comandi

- Test logica (Ubuntu): `swift test --package-path Packages/RuleEngine`
- Build iOS: push su `main` o "Run workflow" in GitHub Actions (job `ios-build`)
- Log dal telefono: `idevicesyslog | grep it.jacopo.focusguard`

## Stato

- [x] Fase 1–4: autorizzazione, blocco immediato, blocchi a orario, limiti giornalieri (codice scritto, da provare su device)
- [ ] Fase 5: PIN in Keychain + Face ID + Cooldown (logica `ChangePolicy`/`Cooldown` già in RuleEngine; vedi i `TODO(Fase 5)` in `AppModel`)
- [ ] Fase 6: estensioni ShieldConfiguration, ShieldAction, DeviceActivityReport
- [ ] Firma e installazione: richiede Apple Developer Program (Family Controls non disponibile con account gratuito)

## Da verificare sul dispositivo

- `DeviceActivityEvent(..., includesPastActivity: true)`: che la soglia non scatti in anticipo.
- `intervalDidStart` quando il monitoraggio parte a finestra già aperta (l'app blocca comunque subito).
