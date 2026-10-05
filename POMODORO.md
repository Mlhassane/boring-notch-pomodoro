# Boring Notch + Pomodoro

Fork de [Boring Notch](https://github.com/TheBoredTeam/boring.notch) avec un
minuteur Pomodoro intégré, dans l'encoche.

## Ce qui a été ajouté

| Fichier | Rôle |
|---|---|
| `boringNotch/managers/PomodoroManager.swift` | Le moteur : minuterie, rounds, historique JSON, notifications, sons |
| `boringNotch/components/Notch/PomodoroView.swift` | L'onglet **Focus** : anneau, contrôles, points de session, stats 7 jours |
| `boringNotch/components/Live activities/PomodoroLiveActivity.swift` | Le widget dans l'encoche quand le panneau est replié |

Fichiers modifiés :

- `models/Constants.swift` — 9 clés `Defaults` (`pomodoro*`)
- `enums/generic.swift` — `NotchViews.pomodoro`
- `components/Tabs/TabSelectionView.swift` — l'onglet « Focus »
- `ContentView.swift` — le switch de vue + la branche « session en cours » dans l'encoche
- `boringNotchApp.swift` — permission de notification au lancement, `shutdown()` à la sortie

## ⚠️ Budget de hauteur à respecter

Le panneau ouvert fait **`openNotchSize` = 640 × 190** (`sizing/matters.swift`), et
`BoringHeader` — qui porte la barre d'onglets — prend
`max(24, effectiveClosedNotchHeight)`, soit **32 pt** sur un écran à encoche.
Il reste donc **158 pt** pour le contenu de l'onglet.

Or le `.background(.black)` de `mainLayout` est appliqué **avant** le
`.frame(height: notchSize.height)`, et un `.frame(height:)` ne clippe pas : un
contenu trop grand **agrandit réellement la forme noire**, ce qui mange les coins
arrondis du bas et pousse la barre d'onglets hors du cadre.

`PomodoroView` est donc dimensionné contre ce budget (anneau 78, controls 36,
espacements 5–6 pt), et le commentaire en tête du fichier le rappelle. Toute
évolution future doit être vérifiée avec :

```bash
# le bas de la forme doit rester à 190 + 8 = 198 pt
screencapture -x -R 380,0,760,260 -t png /tmp/focus.png
```

## Comportement

- **Dans l'encoche, panneau replié** : anneau + temps + compteur `n/4`, dès qu'une
  session est en cours ou en pause.
  **Musique et Pomodoro cohabitent** : l activities musicale garde la bande
  (pochette à gauche, visualiseur à droite) et le minuteur se pose sur le vide noir
  entre les deux, en overlay du rectangle de `MusicLiveActivity()`. L'encoche
  repliée fait environ 200 pt de large, la pochette occupe 20 pt à gauche et le
  visualiseur 20 pt à droite : il reste la place pour l'anneau et le temps.
  L'overlay n'apparaît que quand le panneau est replié ; en developed, cette
  largeur est déjà consommée par le titre et l'artiste.
  Si la musique est inactive, la branche Pomodoro prend toute la bande.
- **Onglet Focus** (2ᵉ onglet) : sélecteur de mode, anneau 25:00, stop / play /
  skip, points de session, minutes du jour, sessions du jour, série de jours,
  histogramme 7 jours, total, effacement de l'historique.
- **Règles de round** : après `pomodoroSessionsPerRound` sessions de focus, pause
  longue ; sinon pause courte. Auto-démarrage configurable des deux transitions.
- **Compte à rebours Stable** : le temps restant est déduit d'une *deadline*
  absolue, et le battement de cœur tourne sur un `Thread` dédié avec sa propre
  run loop. Un `Timer` sur la run loop principale se fait affamer dès qu'une autre
  app est au premier plan — le décompte se figeait au changement de fenêtre.
- **Historique** : JSON dans
  `~/Library/Containers/theboredteam.boringnotch/Data/Library/Application Support/BoringNotchPomodoro/sessions.json`
  (panneau sandboxé). Les sessions de moins de 30 s sont ignorées par les stats.

## Réglages

Tous stockés via `Defaults` (`theboredteam.boringnotch`) :

| Clé | Défaut |
|---|---|
| `pomodoroFocusMinutes` | 25 |
| `pomodoroShortBreakMinutes` | 5 |
| `pomodoroLongBreakMinutes` | 15 |
| `pomodoroSessionsPerRound` | 4 |
| `pomodoroAutoStartBreaks` | true |
| `pomodoroAutoStartFocus` | true |
| `pomodoroSoundEnabled` | true |
| `pomodoroNotifications` | true |
| `pomodoroShowInNotch` | true |

L'app étant **sandboxée**, pour les modifier à la main :

```bash
P="$HOME/Library/Containers/theboredteam.boringnotch/Data/Library/Preferences/theboredteam.boringnotch.plist"
/usr/libexec/PlistBuddy -c "Set :pomodoroFocusMinutes 50" "$P"
```

## Construire

```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
           -configuration Debug -derivedDataPath .build \
           -destination 'platform=macOS' build
```

Sortie : `.build/Build/Products/Debug/Boring Notch.app`

## Licence

Boring Notch est **GPL-3.0**. Ce fork l'est donc aussi : usage personnel sans
contrainte, toute redistribution doit publier le code source sous GPL-3.0.