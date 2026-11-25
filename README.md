# ScreenClip

Petite app macOS qui tourne en arrière-plan (icône dans la barre des menus, pas dans le Dock) et copie automatiquement chaque capture d'écran dans le presse-papier, comme sous Windows. Tu fais ta capture, puis ⌘V.

## Fonctions

- **Copie automatique** de chaque capture (⌘⇧3, ⌘⇧4, ⌘⇧5) dans le presse-papier.
- **Historique ›** dans le menu : les 30 dernières captures avec un aperçu. Un clic recopie la capture (option désactivable : le clic l'ouvre alors dans Aperçu).
- **Capture instantanée** : désactive la vignette flottante de macOS, qui retarde l'enregistrement d'environ 5 s.
- **Supprimer le fichier après copie** (envoyé à la Corbeille), pour ne pas encombrer le Bureau.
- **Lancer au démarrage**.

L'historique est stocké dans `~/Library/Application Support/ScreenClip/Historique` (200 captures max).

## Compiler et installer

Nécessite les outils en ligne de commande Xcode (`xcode-select --install`).

```bash
./build.sh
```

```bash
cp -R ScreenClip.app /Applications/ && open /Applications/ScreenClip.app
```

Au premier lancement, macOS demande l'accès au Bureau : clique sur **Autoriser**.
