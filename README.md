# MacSleep

Programme la mise en veille (ou l'extinction) du Mac le soir et son réveil
(ou allumage) le matin, depuis une fenêtre, sans passer par le Terminal.

```bash
./install.sh        # compile et copie dans /Applications
open /Applications/MacSleep.app
```

Aucune dépendance externe : `swift build` suffit. macOS 14 minimum.

---

## Utilisation

1. **Ajouter une règle** : une action (*Mettre en veille*, *Éteindre* ou
   *Réveiller ou allumer*), une heure et des jours. Autant de règles que
   voulu, par exemple « Éteindre à 2:00 le lundi » et « Réveiller ou allumer à
   9:00 le lundi », plus « Mettre en veille à 23:30 tous les jours ».
2. Cliquez **Enregistrer**. macOS demande le mot de passe administrateur.

Le réveil sort le Mac de veille s'il dort, et l'allume s'il est éteint.

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
- `/Library/Application Support/MacSleep/rules.json` : les règles.

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
