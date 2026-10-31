# OmniBar

Una barra delle applicazioni per macOS in basso sullo schermo, con menu Start, elenco dei documenti aperti per ogni app, file recenti, widget Bitcoin e temi. Scritta in Swift/SwiftUI + AppKit, senza dipendenze esterne.

*A bottom taskbar for macOS with a Start menu, per-app document lists, recent files, a Bitcoin widget and themes. Native Swift/SwiftUI + AppKit, no third-party dependencies. The UI is in Italian.*

![OmniBar, tema scuro](docs/images/bar-dark.png)
![OmniBar, tema Halloween](docs/images/bar-halloween.png)

## Funzioni

- **Menu Start**: app aggiunte, *Consigliati* con i file aperti di recente, *Tutte le app*, ricerca di app **e file** (Invio apre, ↑↓ per scegliere), menu di arresto.
- **App fissate e aperte** in un'unica barra, con indicatore dell'app attiva. Le app non fissate compaiono solo finché hanno finestre aperte.
- **Elenco dei documenti per app**: passando sopra un'icona o cliccandola si vedono tutti i documenti aperti, anche quelli ridotti a icona. Un clic porta in primo piano il documento scelto, la ✕ lo chiude.
- **Documenti recenti** nel clic destro su ogni app (Word, Excel, lettore PDF…).
- **Cartelle e file fissati**: trascinali sulla barra.
- **Screenshot** di una porzione o di tutto lo schermo, salvati e copiati negli appunti.
- **Widget Bitcoin**: prezzo in euro, variazione e grafico delle 24 ore. Con un clic si apre un grafico da 24 ore a 1 anno (dati CoinGecko).
- **Impostazioni rapide**: rete, volume, batteria, tema.
- **Mostra desktop**, sul bordo destro della barra.
- **Temi**: Sistema, Chiaro, Scuro, **Halloween** 🎃.
- **Scorciatoie**: ⌃⌥1…9 apre l'app n-esima, ⌃⌥Spazio apre Start, ⌃⌥D mostra il desktop.
- **Avvio automatico** con il Mac, da attivare dal menu del clic destro sulla barra.

| Elenco documenti | Bitcoin | Impostazioni rapide |
|---|---|---|
| ![](docs/images/window-list.png) | ![](docs/images/btc.png) | ![](docs/images/quick-settings.png) |

## Requisiti

macOS 14 (Sonoma) o successivo, su Apple Silicon o Intel.

## Installazione

### Dalla Release
1. Scarica `OmniBar.zip` dalla pagina [Releases](../../releases), estrailo e sposta `OmniBar.app` in **Applicazioni**.
2. L'app non è notarizzata da Apple, quindi al primo avvio macOS la blocca. Apri **Impostazioni di Sistema › Privacy e sicurezza** e premi **Apri comunque**.

### Dal codice sorgente
Bastano i Command Line Tools (`xcode-select --install`), Xcode non serve:

```sh
./scripts/bundle.sh            # crea build/OmniBar.app
./scripts/bundle.sh universal  # Apple Silicon + Intel
open build/OmniBar.app
```

## Permessi

Si concedono in **Impostazioni di Sistema › Privacy e sicurezza**.

| Permesso | A cosa serve |
|---|---|
| **Accessibilità** | Elencare le finestre e i documenti aperti, portarli in primo piano, ripristinarli, chiuderli |
| **Registrazione schermo** | Titoli delle finestre e screenshot |
| **Automazione › System Events** | Sospendi, Riavvia, Arresta e Logout dal menu Start (viene chiesto al primo uso) |

Con la firma ad-hoc, macOS può richiedere i permessi dopo ogni ricompilazione. Per evitarlo, firma l'app con un'identità stabile: imposta `OMNIBAR_SIGN_IDENTITY` oppure crea `scripts/signing.local` con `OMNIBAR_SIGN_IDENTITY="Nome identità"`.

## Limiti noti

- macOS non permette a un'app di riservare spazio sul bordo dello schermo, quindi le finestre ingrandite possono finire sotto la barra. Conviene nascondere il Dock in automatico (clic destro sulla barra › *Nascondi automaticamente il Dock*).
- Le schede dentro una stessa finestra (per esempio più PDF a schede) compaiono come un solo documento.
- Vengono elencate solo le finestre della scrivania (Spazio) corrente.
- Le icone della barra dei menu di altre app non compaiono nella tray.
- La barra compare solo sullo schermo principale.

## Sviluppo

- `.build/debug/OmniBar --snapshot <cartella>` salva in PNG la barra e i pannelli, poi esce.
- I log diagnostici vanno in `~/Library/Logs/OmniBar.log`.
- Il codice usa solo API pubbliche di macOS: NSWorkspace, Accessibility, ScreenCaptureKit, Spotlight (NSMetadataQuery), CoreAudio, IOKit, Carbon per le scorciatoie globali, ServiceManagement.

OmniBar è ispirata a barre delle applicazioni come uBar e a quella di Windows 11, ma non ne contiene codice.

## Licenza

[MIT](LICENSE) © 2026 csvnm
