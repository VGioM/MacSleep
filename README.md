# MacSleep

Programme la mise en veille (ou l'extinction) du Mac le soir et son réveil
(ou allumage) le matin, depuis une fenêtre, sans passer par le Terminal.

## Installation

Téléchargez `MacSleep-X.Y.Z-macOS-arm64.zip` depuis la
[dernière release](https://github.com/VGioM/MacSleep/releases/latest),
ouvrez-le et glissez **MacSleep.app** dans **Applications**. L'app n'est pas
notarisée par Apple : au premier lancement, ouvrez **Réglages Système →
Confidentialité et sécurité** et cliquez sur **Ouvrir quand même**, ou :

```bash
xattr -dr com.apple.quarantine /Applications/MacSleep.app
```

Ensuite, MacSleep vérifie au lancement (une fois par jour au plus) s'il
existe une nouvelle version et propose de l'installer. Menu **MacSleep →
Rechercher les mises à jour…** pour vérifier tout de suite. Après une mise à
jour, cliquez **Enregistrer** pour que le service passe aussi à la nouvelle
version.

macOS 14 ou plus récent, Mac Apple Silicon.

### Depuis les sources

```bash
./install.sh        # compile et copie dans /Applications
./Tests/run-unit.sh # tests
```

Aucune dépendance externe : `swift build` suffit.

### Publier une version

```bash
./release.sh 1.2.0            # notes tirées des commits
./release.sh 1.2.0 notes.md   # notes écrites à la main
```

Le script compile, teste, committe « Version X.Y.Z », pousse le tag et crée
la release GitHub avec le zip. La mise à jour intégrée n'installe qu'une
version signée avec le même certificat que l'app en place : « VGioM Local
Signing », créé une fois par `./signing-cert.sh`. Sur un autre Mac de build,
importez ce certificat plutôt que d'en créer un nouveau.

---

## Utilisation

1. **Ajouter une règle** : une action (*Mettre en veille*, *Éteindre* ou
   *Réveiller ou allumer*), une heure et des jours. Autant de règles que
   voulu, par exemple « Éteindre à 2:00 le lundi » et « Réveiller ou allumer à
   9:00 le lundi », plus « Mettre en veille à 23:30 tous les jours ».
2. Cliquez **Enregistrer**. macOS demande le mot de passe administrateur.

Le réveil sort le Mac de veille s'il dort, et l'allume s'il est éteint.

**Rattraper la nuit si le Mac se rallume** (activé par défaut) : les règles
sont des événements à une heure précise, pas une plage. Sans cette option,
un Mac rallumé à 0:45 après « Éteindre à 0:30 » et avant « Réveiller à
8:30 » resterait allumé. Avec, le service le remet en veille ou l'éteint
10 minutes plus tard, une seule fois par nuit ; une notification le signale
et MacSleep s'ouvre avec un bouton **Annuler**. Il faut au moins une règle de
réveil pour qu'il y ait une « nuit ».

**Mettre une règle en pause** : l'interrupteur devant chaque règle la garde
dans la liste sans qu'elle agisse, jusqu'à ce qu'on la rallume.

**Ce soir seulement** : sous chaque règle, sa prochaine fois, avec
**Sauter** (rien cette fois-ci) et **Reporter…** (une autre heure, cette
fois-ci seulement, par exemple la veille à 2:00 au lieu de 0:30, ou le
réveil de demain sauté). La règle reprend ensuite comme d'habitude ;
**Rétablir** annule l'exception. Le rattrapage de la nuit en tient compte :
une veille sautée n'est pas « manquée », une veille reportée est rattrapée
après sa nouvelle heure.

**Réveil ponctuel** ajoute un réveil unique, en plus des règles.
**Prochains événements dans macOS** montre ce que le système a réellement
programmé. **Tout désactiver** retire les règles, leurs événements et le
service.

Une fois enregistré, tout est géré par le système : l'app peut être fermée,
déplacée ou jetée.

## Comment ça marche

`pmset repeat` n'accepte qu'un seul couple veille/réveil récurrent. MacSleep
transforme donc ses règles en événements ponctuels `pmset schedule`, signés
« MacSleep » :

```bash
pmset schedule shutdown "10/19/26 02:00:00" MacSleep
pmset schedule wakeorpoweron "10/19/26 09:00:00" MacSleep
pmset -g sched      # lire ce qui est programmé, sans mot de passe
```

Un service système les tient à jour sur les 8 jours à venir :

- `/Library/PrivilegedHelperTools/com.macsleep.helper` : une copie de l'app
  appartenant à root, lancée avec `--sync` ;
- `/Library/LaunchDaemons/com.macsleep.daemon.plist` : le lance au démarrage et
  toutes les heures (rattrapé au réveil si le Mac dormait) ;
- `/Library/Application Support/MacSleep/rules.json` : les règles ;
- `/Library/Application Support/MacSleep/catchup.json` : la dernière nuit
  déjà rattrapée.

La synchro ajoute les événements manquants et retire ceux qu'aucune règle ne
demande plus. Elle ne touche jamais aux événements des autres apps ni aux
réveils ponctuels. Enregistrer des règles supprime l'éventuel planning
`pmset repeat` existant.

Limites :

- `pmset schedule` ne sait pas redémarrer, d'où les trois actions ;
- l'extinction peut être bloquée par un document non enregistré ;
- après un réveil, le Mac suit son réglage de veille habituel.

Journaux : `/Library/Logs/MacSleep.log` (service) et
`~/Library/Logs/MacSleep.log` (app).

## Icône

`Resources/AppIcon.icns` est générée par `swift tools/make-icon.swift`.
