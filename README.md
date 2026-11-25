# 📸 ScreenClip

**Les captures d'écran du Mac, directement dans le presse-papier — comme sur Windows.**

ScreenClip est une petite app macOS qui tourne discrètement en arrière-plan. Elle n'a pas d'icône dans le Dock : elle vit uniquement dans la barre des menus, en haut de l'écran. Dès que tu prends une capture d'écran, elle la copie dans le presse-papier. Tu n'as plus qu'à faire **⌘V** où tu veux : Discord, Messages, Notion, Photoshop…

![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![Taille](https://img.shields.io/badge/d%C3%A9pendances-aucune-brightgreen)

---

## ✨ Fonctionnalités

| | Fonction | Détail |
|---|---|---|
| 📋 | **Copie automatique** | Chaque capture (⌘⇧3, ⌘⇧4, ⌘⇧5) part directement dans le presse-papier. |
| 🕘 | **Historique** | Un sous-menu affiche tes 30 dernières captures avec un grand aperçu. Un clic en recopie une. |
| ⚡ | **Capture instantanée** | Désactive la vignette flottante de macOS, qui retarde l'enregistrement d'environ 5 secondes. |
| 🗑️ | **Supprimer après copie** | La capture est envoyée à la Corbeille une fois copiée, pour garder le Bureau propre. |
| 🚀 | **Lancer au démarrage** | ScreenClip démarre toute seule avec le Mac. |
| ✅ | **Retour visuel** | L'icône devient une coche verte pendant une seconde quand la copie a réussi. |

---

## 📦 Installation

### 1. Prérequis

Les outils en ligne de commande d'Xcode (gratuits) :

```bash
xcode-select --install
```

### 2. Télécharger et compiler

```bash
git clone https://github.com/Nolek0/ScreenClip.git
```

```bash
cd ScreenClip && ./build.sh
```

### 3. Installer et lancer

```bash
cp -R ScreenClip.app /Applications/ && open /Applications/ScreenClip.app
```

Au premier lancement, macOS affiche **« ScreenClip souhaite accéder aux fichiers de votre dossier Bureau »**. Clique sur **Autoriser** : c'est là que macOS enregistre tes captures.

> 💡 Coche ensuite **Lancer au démarrage** dans le menu pour ne plus avoir à t'en occuper.

---

## 🖱️ Utilisation

1. Prends une capture comme d'habitude : **⌘⇧3** (écran entier), **⌘⇧4** (zone) ou **⌘⇧5** (outil complet).
2. L'icône 📷 dans la barre des menus devient une ✅.
3. Colle avec **⌘V**.

### Le menu

Clique sur l'icône 📷 dans la barre des menus :

```
ScreenClip
Dossier : Desktop
─────────────────────────────────────
🕘 Historique                       ›
─────────────────────────────────────
✓ Copier automatiquement
  Capture instantanée (sans vignette)
✓ Copier au clic dans l'historique
  Supprimer le fichier après copie
  Lancer au démarrage
─────────────────────────────────────
Quitter ScreenClip                ⌘Q
```

| Option | Ce qu'elle fait |
|---|---|
| **Historique ›** | Ouvre la liste des dernières captures avec leur aperçu. |
| **Copier automatiquement** | Met ScreenClip en pause ou la réactive. |
| **Capture instantanée** | Supprime le délai d'environ 5 s de macOS avant l'enregistrement de la capture. |
| **Copier au clic dans l'historique** | Coché : un clic copie la capture. Décoché : un clic l'ouvre dans Aperçu. |
| **Supprimer le fichier après copie** | Envoie la capture à la Corbeille après la copie. Elle reste dans l'historique. |
| **Lancer au démarrage** | Démarre ScreenClip à l'ouverture de session. L'app doit être dans `/Applications`. |

### L'historique

- Les **30 dernières** captures sont affichées dans le menu, les plus récentes en haut.
- ScreenClip garde sa propre copie des **200 dernières** captures dans :
  `~/Library/Application Support/ScreenClip/Historique`
- En bas du sous-menu : **Ouvrir le dossier de l'historique** et **Vider l'historique** (les fichiers vont à la Corbeille).

---

## ⚙️ Comment ça marche

1. ScreenClip lit le dossier où macOS enregistre les captures (le Bureau par défaut, ou celui choisi dans ⌘⇧5 › Options). Si tu changes de dossier, elle s'en rend compte en environ 10 secondes.
2. Elle surveille ce dossier. Quand un nouveau fichier apparaît, elle vérifie qu'il porte le marqueur que macOS ajoute à toutes les captures d'écran (`kMDItemIsScreenCapture`). Les autres fichiers que tu ajoutes au Bureau sont ignorés.
3. L'image est mise dans le presse-papier, puis une copie est rangée dans l'historique.

**Pourquoi il y a parfois un délai ?** Par défaut, macOS affiche une vignette en bas à droite pendant environ 5 secondes et n'enregistre le fichier qu'après. Active **Capture instantanée** pour le supprimer. Ça revient à décocher « Afficher la vignette flottante » dans ⌘⇧5 › Options.

---

## 🛠️ Développement

```
ScreenClip/
├── main.swift      # App, barre des menus, surveillance du dossier, presse-papier
├── History.swift   # Stockage de l'historique, miniatures, lignes d'aperçu du menu
└── build.sh        # Compile et crée ScreenClip.app (signature ad hoc)
```

- Pas de projet Xcode et aucune dépendance : seulement `swiftc`, AppKit et ServiceManagement.
- `LSUIElement = true` dans l'`Info.plist` : c'est ce qui enlève l'icône du Dock.
- Après une modification : `./build.sh`, puis recopie `ScreenClip.app` dans `/Applications`.

> ⚠️ L'app est signée « ad hoc ». macOS peut donc redemander l'accès au Bureau après chaque recompilation. Clique simplement sur **Autoriser**.

---

## 🧹 Désinstaller

1. Menu 📷 › décoche **Lancer au démarrage**, puis **Quitter ScreenClip**.
2. Supprime l'app et son historique :

```bash
rm -rf /Applications/ScreenClip.app ~/Library/Application\ Support/ScreenClip
```

3. Si tu avais activé **Capture instantanée** et que tu veux retrouver la vignette de macOS :

```bash
defaults write com.apple.screencapture show-thumbnail -bool true
```
