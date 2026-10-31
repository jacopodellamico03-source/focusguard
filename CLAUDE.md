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
- Uno `ManagedSettingsStore` per regola (`.rule(id)`) più `.manual` e `.protection` (disinstallazione, ora automatica).
- Nuova logica → prima in RuleEngine con test XCTest, poi il collegamento iOS.
- Log con `Log.app` / `Log.monitor` (OSLog, subsystem `it.jacopo.focusguard`).
- Testi dell'interfaccia in italiano.
- Se non sei sicuro della firma di un'API Apple, dillo e indica cosa verificare nella documentazione.

## Comandi

- Test logica (Ubuntu): `LC_ALL=C swift test --package-path Packages/RuleEngine -Xswiftc -use-ld=lld` (con il linker di default la build fallisce su questo sistema)
- Build iOS: push su `main` o "Run workflow" in GitHub Actions (job `ios-build`)
- Log dal telefono: `idevicesyslog | grep it.jacopo.focusguard`

## Stato

- [x] Fase 1–4: autorizzazione, blocco immediato, blocchi a orario, limiti giornalieri (codice scritto, da provare su device)
- [x] Fase 5: PIN in Keychain + Face ID + attesa di 10 minuti con conferma entro 30, blocco disinstallazione opzionale (temporaneo se spento senza restrizioni attive), ora automatica, reset del PIN dimenticato dopo 24 ore, notifiche locali a fine attesa (codice scritto, da provare su device)
- [ ] Fase 6: estensioni ShieldConfiguration, ShieldAction, DeviceActivityReport
- [ ] Firma e installazione: richiede Apple Developer Program (Family Controls non disponibile con account gratuito)

## Da verificare sul dispositivo

- `DeviceActivityEvent(..., includesPastActivity: true)`: che la soglia non scatti in anticipo.
- `intervalDidStart` quando il monitoraggio parte a finestra già aperta (l'app blocca comunque subito).
- `denyAppRemoval`: se vale per tutte le app o solo per FocusGuard, e se regge con autorizzazione `.individual` (revocabile dalle Impostazioni).
- `requireAutomaticDateAndTime`: se iOS lo rispetta con autorizzazione `.individual`.
- `PINStore` e Face ID: creazione, verifica e cambio PIN (la CI li compila soltanto, non li esegue).
- Il Keychain sopravvive alla disinstallazione: dopo una reinstallazione deve tornare la schermata di creazione PIN.
- Modifica confermata a un limite già scattato: dopo il riavvio del monitoraggio la soglia deve riscattare se l'uso la supera già.
- Selettore del blocco immediato: se aggiorna la selezione solo alla conferma. Se la aggiornasse a ogni tocco, a blocco attivo la richiesta catturerebbe solo il primo cambio.
- Pulsanti "Conferma"/"Annulla" nelle righe della lista: che non si attivino a vicenda.
- Reset del PIN: "PIN dimenticato?" (in Impostazioni, Cambia PIN e richiesta del PIN, anche durante il blocco dei tentativi) avvia l'attesa di 24 ore e diventa il conto alla rovescia; la riga resta visibile riaprendo l'app, la conferma non chiede nulla e porta a `PINSetupView`, chiudendo il foglio o la schermata da cui è partita; regole e blocchi restano attivi per tutto il tempo.
- Opzione disinstallazione: senza regole attive né blocco immediato si disattiva subito, compare la nota e si riaccende da sola alla prima regola o al blocco immediato; con almeno uno dei due parte l'attesa e, confermata, resta spenta finché non la si riattiva a mano.
- Notifiche, permesso: il dialogo compare alla prima richiesta creata e non all'avvio; se negato, una sola riga in cima alla lista e in Impostazioni, solo con richieste in corso, e l'app funziona uguale; riattivandolo dalle Impostazioni di iOS le notifiche mancanti partono al rientro nell'app.
- Notifiche, consegna: una a fine attesa e una 5 minuti prima della scadenza, anche ad app chiusa e dopo un riavvio del telefono; testi generici sulla schermata di blocco.
- Notifiche, cancellazione: annullando o confermando spariscono sia le programmate sia le consegnate; se la richiesta scade ad app chiusa, quella consegnata resta finché non si riapre l'app.
- Notifiche con Full Immersion: se arrivano in ritardo l'avviso dei 5 minuti perde senso (`.timeSensitive` richiederebbe un entitlement in più, non aggiunto).
