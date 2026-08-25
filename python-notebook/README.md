# Restitution de graphe orienté — notebook Jupyter (networkx + plotly)

`restitution_graphe.ipynb` construit un graphe orienté à partir d'un fichier
texte **uploadé** (format `NOEUDS`/`ARETES`, identique au reste du projet —
voir `exemple.txt` ou `exemple_50_noeuds.txt` à la racine du dépôt) avec
**networkx** (parsing, détection de cycle, layout hiérarchique), puis le
restitue avec **plotly** : zoomable, déplaçable, **clique un nœud** pour
surligner ses prédécesseurs/successeurs directs, **survole** pour le détail.

Il n'y a pas de chemin codé en dur ni de graphe par défaut : le bouton
d'**upload** (`ipywidgets.FileUpload`) est le seul point d'entrée — tant
qu'aucun fichier n'est choisi, rien ne s'affiche.

matplotlib/seaborn ont été écartés : dans un notebook, ils ne produisent
qu'une image statique, sans aucune interaction possible dessus. matplotlib
reste la bonne option pour un rendu non-interactif
(`src/restitution/`) ou pour du clic *hors* notebook — `python-script/`
ouvre une vraie fenêtre graphique interactive.

## `index.html` — ouvrable directement, sans Jupyter

`index.html` est un export HTML du notebook déjà exécuté : **double-clic
direct**, aucun serveur ni Jupyter nécessaire — comme `web/index.html` ou
`python-mvc/index.html`. Une fois un graphe affiché, le clic sur les nœuds
fonctionne aussi dans cet export (le survol/clic Plotly est géré en
JavaScript pur, pas via ipywidgets, donc actif même sans noyau Python).

L'**upload** lui-même est l'exception : il passe par `ipywidgets` et a
besoin d'un noyau Python actif pour traiter le fichier — dans `index.html`,
le bouton s'affiche mais l'upload ne fait rien, donc **aucun graphe ne
s'affiche** dans l'export statique tant qu'il n'a pas été rouvert dans un
notebook actif. Pour l'utiliser, ouvrir le notebook dans Jupyter/DataLab
(voir plus bas).

Pour le regénérer après une modification du notebook :

```bash
python -m nbconvert --to html restitution_graphe.ipynb --output index.html
```

## Utilisation (notebook interactif)

```bash
python -m pip install -r requirements.txt
jupyter lab restitution_graphe.ipynb
# ou : jupyter notebook restitution_graphe.ipynb
# ou : l'ouvrir dans VS Code (extension Jupyter)
```

Pour le réexécuter en ligne de commande (sans interface) et regénérer les
sorties :

```bash
python -m nbconvert --to notebook --execute --inplace restitution_graphe.ipynb
```

## Notes techniques sur le clic Plotly

- Le clic est géré par une fonction JS pure (`Plotly.restyle` sur
  l'événement natif `plotly_click`), pas par `ipywidgets`/`FigureWidget` :
  ça fonctionne aussi bien avec un noyau actif que dans un export HTML
  statique ou sur GitHub, où aucun noyau Python n'est disponible.
- Chaque figure embarque `plotly.js` en ligne (`include_plotlyjs=True`)
  plutôt que de charger un CDN externe : dans du HTML de sortie de
  notebook, un `<script src="...">` externe est inséré dynamiquement et se
  charge en asynchrone (même sans l'attribut `async`), donc l'ordre
  d'exécution avec le script suivant n'est pas garanti — `Plotly` pouvait
  ne pas encore être défini au moment de l'appel `Plotly.newPlot()`.
- `plotly.js` n'est embarqué **qu'une seule fois** (au premier graphe) :
  deux figures qui l'embarquent chacune séparément se marchent dessus (la
  2e écrase `window.Plotly` pendant que la 1re en a encore besoin), donc
  les figures suivantes réutilisent l'instance déjà chargée.
