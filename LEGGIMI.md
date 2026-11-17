# App Azienda Agricola dei Laghetti

Web app installabile sul telefono, con il logo come icona. Allievi e gestori usano la stessa app: chi accede come **gestore** vede in più l'**area riservata**.

## Cosa fa

**Allievi**
- Si registrano con nome, email e password.
- Prenotano le lezioni di un'ora (mar–ven 17 e 18, sabato 15–18, domenica 9–11; lunedì chiuso), vedono i posti liberi e possono annullare.
- Vedono il proprio **carnet da 10 lezioni con i timbri**: un timbro per ogni lezione fatta, con la data.
- Gare ed eventi, news, cavalli, famiglie, fattoria.

**Gestori (Umberto e Pamela)**
- **Agenda**: per ogni giorno e ora, chi ha prenotato. Con un tocco: *Timbra* (la lezione va sul carnet), *Assente*, *Togli timbro*.
- **Allievi e carnet**: tutti gli allievi con le lezioni rimaste. In alto chi ha il carnet quasi finito. Da qui si attiva un **nuovo carnet da 10** quando viene pagato e si può timbrare una lezione fatta senza prenotazione.
- Contatori: cavalieri di oggi, lezioni da timbrare, carnet da rinnovare.

## Modalità prova

Finché `config.js` è vuoto, l'app funziona in **modalità prova**: dati di esempio salvati solo sul telefono, con i pulsanti "Prova come allievo" e "Prova come gestore". Serve per vederla e mostrarla.

## Attivare l'app vera (archivio condiviso, gratis)

1. Crea un account su **supabase.com** → *New project* (regione: Europe, es. Frankfurt). Annota la password del database.
2. Nel progetto apri **SQL Editor → New query**, incolla tutto il file `database.sql` e premi **Run**.
3. Vai su **Project Settings → API** e copia **Project URL** e la chiave **anon public**.
4. Apri `config.js` e incollale tra gli apici:
   ```js
   supabaseUrl: 'https://xxxx.supabase.co',
   supabaseAnonKey: 'eyJ...',
   ```
   (la chiave *anon* è fatta per stare nell'app: i dati sono protetti dalle regole del database. Non usare mai la chiave *service_role*.)
5. Carica di nuovo i file online (vedi sotto).
6. Umberto e Pamela si registrano dall'app come tutti. Poi in Supabase, **SQL Editor**, esegui (con le loro email):
   ```sql
   update profiles set role = 'admin' where email in ('umberto@...', 'pamela@...');
   ```
   Al prossimo accesso vedranno Agenda e Allievi.
7. Facoltativo: in **Authentication → Providers → Email** puoi disattivare *Confirm email* se non vuoi che gli allievi debbano confermare l'indirizzo.

Cavalieri massimi per lezione: 4. Per cambiarlo modifica `maxPerSlot` in `config.js` **e** il numero in `max_per_slot()` in `database.sql` (poi riesegui quella riga).

## Metterla online con GitHub Pages

1. Su github.com: **+ → New repository**, nome `laghetti`, **Public**, spunta *Add a README file* → **Create repository**.
2. **Add file → Upload files** e trascina **il contenuto** di questa cartella (index.html, app.js, style.css, config.js, manifest.webmanifest, service-worker.js e le immagini .png). Tutti i file stanno insieme, senza cartelle → **Commit changes**.
3. **Settings → Pages** → Branch **main**, cartella **/(root)** → **Save**.
4. Dopo 1–2 minuti: `https://NOME-UTENTE.github.io/laghetti/`

Ogni volta che aggiorni i file, cambia il numero in `service-worker.js` (`laghetti-v2` → `laghetti-v3`) così i telefoni scaricano la versione nuova.

## Installarla sul telefono

- **Android (Chrome)**: menu ⋮ → *Installa app*.
- **iPhone (Safari)**: Condividi → *Aggiungi alla schermata Home*.

## Dove si cambiano i contenuti

In `app.js`, in alto: `EVENTS` (gare ed eventi), `NEWS`, `HORSES` (cavalli: nome, nascita, descrizione, foto), `FARM`, `START` (orari delle lezioni; se li cambi, aggiorna anche `book_slot` in `database.sql`). I testi tra parentesi quadre, come `[PREZZO]`, vanno sostituiti.

Ancora non condivisi tra telefoni: iscrizioni alle gare, news lette, documenti spuntati (restano sul telefono). Le news e gli eventi per ora si modificano nel file.
