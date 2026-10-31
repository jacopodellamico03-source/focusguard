# FocusGuard web: architettura

L'app nativa richiede l'Apple Developer Program a pagamento. Questa web app gratuita, insieme a
Comandi rapidi di iOS 27, blocca Instagram, TikTok e YouTube. La parte `iOS/` resta congelata nel repo.

## Flusso

1. **Automazione iOS "app aperta"** → comando **FG Controllo**: se esiste un pass valido per quell'app non
   fa nulla, altrimenti apre
   `https://jacopodellamico03-source.github.io/focusguard/#/check?app=<instagram|tiktok|youtube>`.
2. **La web app decide:**
   - blocco (orario attivo o limite esaurito): schermata con conto alla rovescia;
   - altrimenti pulsanti "Usa 5/10/15 minuti", che scalano dal budget giornaliero e aprono
     `shortcuts://run-shortcut?name=FG%20Pass&input=text&text=<app>|<scadenza unix>`.
3. **FG Pass** salva la scadenza del pass (azioni di archiviazione di iOS 27, o un file in iCloud Drive come
   ripiego) e riapre l'app.

## Dati e PIN

- Dati solo in Safari (`localStorage`), con esporta/importa backup JSON.
- Niente PWA installata: su iOS la web app nella Home ha una memoria separata da Safari.
- Nessun backend.
- PIN con PBKDF2-SHA256 via WebCrypto, salt casuale, confronto a tempo costante. 600.000 iterazioni, salvate
  nel record: alzarle in futuro non invalida i PIN esistenti.

## Stack e struttura

Vite + TypeScript (strict) + Preact, test con Vitest.

```
web/src/engine/   logica pura: niente DOM, niente localStorage, tempo sempre passato come parametro
web/src/crypto/   PBKDF2: dipende da WebCrypto, quindi fuori dal motore
web/src/main.tsx  segnaposto fino alla W2
```

`tsconfig.engine.json` compila il motore senza la libreria DOM: se usa `document` o `localStorage` non compila.

## Fasi

- **W1 (fatta):** la logica in `web/src/engine/`.
- **W2:** interfaccia e persistenza.
- **W3:** guida ai comandi rapidi.

## Vincoli per la W2 e la W3

1. **Fail-closed.** Se su `#/check` mancano i dati (prima installazione o dati di Safari cancellati) la web app
   **non** offre pass: mostra solo "Importa backup" e "Configura". `AccessDecision.decide` lo prevede già: con
   `rules` o `usage` a `null` restituisce `blocked` con motivo `notConfigured` e `until: null`. La W2 deve passare
   `null` quando i dati mancano, e non una lista vuota: `[]` significa "configurato, senza regole" e lascia passare.
2. **FG Pass rifiuta scadenze oltre 30 minuti da adesso.** Il controllo sta nel comando rapido e va documentato
   nella guida W3. Il motore rispetta lo stesso tetto: i pass offerti da `decide` non superano mai
   `MAX_PASS_MINUTES`.
3. **Idea, comando "FG Backup".** Riceve il JSON di backup dalla web app e lo salva in iCloud Drive a ogni modifica
   delle regole. L'import legge quel file con il selettore di file.

## Decisioni del motore

- **Budget:** una regola con più app condivide il budget, una regola per app lo tiene separato. Se più limiti
  coprono la stessa app vale il più stretto.
- **Il pass scala appena concesso, usato o no.** I pass sovrapposti si sommano: se FG Pass fallisce e si riprova,
  si paga due volte.
- **Mezzanotte locale:** un pass a cavallo scala da ciascun giorno la sua parte (23:55 + 15 minuti = 5 oggi, 10
  domani).
- **Pass offerti:** 5, 10 e 15 minuti, purché finiscano prima del budget e del prossimo blocco, perché FG Controllo
  guarda solo il pass e non si accorgerebbe di un blocco iniziato nel frattempo. Sotto i 5 minuti si offre un solo
  pass col tempo esatto. A meno di un minuto da un blocco la lista è vuota.
- **Meno di un minuto di budget** vale come esaurito.
- **Fine del blocco:** segue la catena dei blocchi successivi fino alla vera fine, con un limite di 7 giorni per le
  regole che coprono tutto il tempo. Il motivo mostrato è la regola che dura di più. Si scorre minuto per minuto:
  così cambi d'ora, finestre concatenate e reset di mezzanotte non hanno casi a parte.
- **Regole non valide:** ignorate da `decide`. L'interfaccia deve impedire di salvarle.

### Differenze da `Packages/RuleEngine`

- `ChangePolicy`: i token di Apple erano opachi e cambiare app era sempre `relaxing`. Qui le app si vedono: togliere
  allenta, aggiungere irrigidisce, fare entrambe le cose allenta.
- Niente minimo di 15 minuti per le finestre: era un vincolo di `DeviceActivitySchedule`.
- `Rule` ha il campo `apps`, e una regola senza app non è valida.
- Non portati: `MonitoringPlan`, `ActivityNaming`, `ShieldDecision`, blocco immediato, opzione disinstallazione,
  notifiche.
- Valori JSON semplici e funzioni che restituiscono valori nuovi, tempi in millisecondi epoch. L'id delle richieste
  è passato dal chiamante, per tenere puro il motore.

## Limiti noti

Sono limiti dell'architettura: il codice non può chiuderli.

- **Dati di Safari.** Cancellarli fa perdere regole, PIN e budget, e la web app torna allo stato fail-closed: i pass
  non vengono offerti, ma basta "Configura" per ripartire da zero. Inoltre Safari può cancellare `localStorage` dopo
  7 giorni di utilizzo senza interazioni con il sito. Le schede private hanno una memoria separata. Il backup conta
  davvero.
- **Orologio.** La web app non può imporre l'ora automatica. Spostare l'orologio salta le attese e il reset di
  mezzanotte.
- **Blocco volontario.** Senza Tempo di utilizzo basta spegnere l'automazione, o lanciare FG Pass a mano. Il tetto di
  30 minuti limita ogni singola esecuzione, non il numero di esecuzioni.
- **PIN offline.** Da 6 a 8 cifre con l'hash in `localStorage`: chi ha accesso agli strumenti di sviluppo di Safari
  può provarle tutte. Il PIN frena l'impulso, non un attacco.
- **Tempo costante.** In JavaScript il confronto è un'approssimazione: il motore può ottimizzare il ciclo.

## Da verificare sul telefono

Non verificato: la W1 non tocca iOS.

- Azioni di archiviazione di iOS 27 per salvare e leggere il pass, e il ripiego con il file in iCloud Drive.
- Automazione "app aperta": che parta senza conferma, e il comportamento quando FG Pass riapre l'app.
- `shortcuts://run-shortcut` aperto da Safari: quante conferme chiede a ogni pass.
- `localStorage`: che i dati restino tra un'apertura e l'altra, e in quali condizioni Safari li cancella.
- Scheda privata attiva: se FG Controllo apre l'URL lì, la web app vede una memoria vuota.
- Tempo di PBKDF2 a 600.000 iterazioni sull'iPhone.
