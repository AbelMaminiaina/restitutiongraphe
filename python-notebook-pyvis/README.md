# Restitution de graphe orienté — notebook Jupyter (networkx + pyvis)

`restitution_graphe.ipynb` construit un graphe orienté avec **networkx** à
partir d'un fichier texte (format `NOEUDS`/`ARETES`, identique au reste du
projet — `exemple.txt` et `exemple_50_noeuds.txt` à la racine du dépôt), puis
le restitue avec **pyvis** (wrapper Python pour [vis.js](https://visjs.org/)) :
zoomable, déplaçable (glisse un nœud), **clique un nœud** pour surligner ses
prédécesseurs (bleu) et successeurs (vert) directs, **survole** un nœud pour
son détail. Les arêtes qui referment un cycle sont en **rouge pointillé**.
Un bouton d'**upload** (section 4) permet aussi de choisir un fichier `.txt`
depuis son poste plutôt qu'un chemin codé en dur.

matplotlib/seaborn ont été écartés : dans un notebook, ils ne produisent
qu'une image statique, sans aucune interaction possible dessus.

## Différence avec `python-notebook/` (la variante plotly)

Chaque appel à `render_directed_graph(...)` écrit un **vrai fichier HTML
autonome** (`graph_exemple.html`, `graph_50.html` — vis.js embarqué en ligne,
utilisable hors ligne), affiché dans le notebook via `<iframe src="...">`.

Comme le script d'interactivité (le clic pour surligner le voisinage) vit
dans ce fichier séparé et pas directement dans la sortie HTML de la cellule,
Jupyter n'a pas besoin de considérer le notebook comme "de confiance"
(*Trust Notebook*) pour que le clic fonctionne — un point de friction
possible avec `python-notebook/`, où le script est injecté directement dans
la sortie de la cellule.

## `index.html` — ouvrable directement, sans Jupyter

Export HTML du notebook déjà exécuté (double-clic direct, aucun serveur ni
Jupyter nécessaire), qui embarque les `<iframe>` vers `graph_exemple.html` et
`graph_50.html`. Ces deux fichiers doivent rester **à côté** de `index.html`
(mêmes chemins relatifs) pour que les graphes s'affichent.

Le bouton d'**upload** (section 4) est l'exception : il passe par
`ipywidgets` et a besoin d'un noyau Python actif pour traiter le fichier —
dans `index.html`, le bouton s'affiche mais l'upload ne fait rien. Pour
l'utiliser, ouvrir le notebook dans Jupyter/DataLab (voir plus bas). Une fois
le graphe généré (en direct dans Jupyter), lui reste pleinement interactif
même exporté en HTML statique, puisque c'est un fichier séparé (voir plus
haut).

Pour regénérer après une modification du notebook :

```bash
python -m nbconvert --to notebook --execute --inplace restitution_graphe.ipynb
python -m nbconvert --to html restitution_graphe.ipynb --output index.html
```

## Utilisation (notebook interactif)

```bash
python -m pip install -r requirements.txt
jupyter lab restitution_graphe.ipynb
# ou : jupyter notebook restitution_graphe.ipynb
# ou : l'ouvrir dans VS Code (extension Jupyter)
```

## Notes techniques

- Le layout hiérarchique (façon Sugiyama, arêtes de cycle exclues du calcul
  des niveaux) est géré nativement par vis.js (`layout.hierarchical`) — pas
  besoin de calculer les positions nous-mêmes comme dans `python-notebook/`.
- Les arêtes de cycle portent une propriété personnalisée `cycle: true` (pas
  un attribut standard vis.js), relue par le script de clic pour garder leur
  style rouge pointillé même quand elles ne sont pas sélectionnées.
- `cdn_resources="in_line"` embarque vis.js directement dans chaque fichier
  généré (comme `include_plotlyjs=True` dans `python-notebook/`) : pas de
  dépendance à un CDN externe pour l'interactivité du graphe. Seule la mise
  en forme Bootstrap de la page (bordure, encadré) charge encore depuis un
  CDN — cosmétique uniquement, sans impact sur le graphe lui-même.
