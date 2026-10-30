# Coffee

Application macOS dans la barre de menus pour maintenir le Mac éveillé pendant une durée choisie.

## Utilisation

Ouvrir `/Applications/Coffee.app`, cliquer sur la tasse, choisir les jours, heures et minutes, puis cliquer sur **Activer**. Sélectionner un nombre avant de le modifier à la molette, par glissement ou au clavier. Le bouton **Arrêter** rétablit la veille. Le menu engrenage permet de quitter ou retirer l’autorisation.

## Autorisation initiale

La première configuration autorise uniquement deux commandes :

```
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
```

Le mot de passe n’est jamais mémorisé. L’autorisation reste disponible pour tout programme exécuté sous le même compte. Sa suppression nécessite de cliquer sur **Retirer l’autorisation…** avant de désinstaller l’app. L’emplacement d’une règle déjà accordée peut être conservé dans la préférence macOS `authorizationRulePath` ; une nouvelle configuration utilise `/etc/sudoers.d/coffee-local-<uid>`.

## Compiler

Depuis ce dossier : `sh build.sh`. La sortie est `dist/Coffee.app`. Outils Xcode requis. L’icône est générée par `scripts/generate-icon.swift`. Le paquet est signé localement et non notarié.

## Limites

Le Mac reste éveillé : les tâches locales ne tournent pas pendant une véritable veille. L’extinction de l’écran à la fermeture du capot est une demande à macOS ; le verrouillage et les actions graphiques des agents doivent être vérifiés sur la machine. Garder le Mac ventilé et choisir une durée adaptée. Pas de surveillance thermique ni de batterie dans cette version.

Un processus temporaire tente de restaurer la veille à l’expiration, à l’arrêt ou à la disparition de l’app. En cas d’arrêt forcé de ce processus ou d’échec de récupération, utiliser `sudo pmset -a disablesleep 0` dans Terminal.

## Vérification

`dist/Coffee.app/Contents/MacOS/Coffee --self-test` vérifie les durées et la portée des autorisations sans modifier la veille. `--diagnostics` lit l’état de veille et du capot.
