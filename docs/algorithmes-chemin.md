# Algorithmes de plus court chemin — `dotnet-new-scan`

Quatre algorithmes tournent sur le graphe orienté chargé en mémoire
(`Services/DirectedGraph.cs`, structure CSR). Sélection dans le menu
*Algorithme* du formulaire `/` (`?algo=bfs|dijkstra|dijkstra-bi|astar`).

Les arêtes de `LINE_VIS_EDG` ont **toutes le même poids (1)** : le « coût »
d'un chemin est son nombre d'arêtes. Les quatre algorithmes renvoient donc
**le même plus court chemin** (à un ex æquo près) ; seule la durée change.

## Le graphe de test

| | |
|---|---|
| Nœuds | 100 008 |
| Arêtes | 400 787 |
| Degré moyen | ≈ 4,0 |
| Diamètre observé | ≈ 8–9 arêtes |
| Poids des arêtes | 1 (uniforme) |
| Chargement CSR (au démarrage) | ~1,4–2,0 s, ~12 Mo |
| Repères ALT pour A* (au démarrage) | 6 repères, ~0,2–0,5 s, ~5 Mo |

## Résumé

| Algorithme | Temps (pire cas) | Mémoire | Chemin atteignable — médiane | « Aucun chemin » | Correct si poids ≠ 1 ? |
|---|---|---|---|---|---|
| **BFS bidirectionnel** | O(b^(R/2)) | O(b^(R/2)) | **0,06 ms** | 22,8 ms | ❌ non |
| **Dijkstra** | O((n+m) log n) | O(n) | 22,4 ms | 61,8 ms | ✅ oui |
| **Dijkstra bidirectionnel** | ~O(b^(R/2) log b) | O(b^(R/2)) | **0,37 ms** | **0,001 ms** | ✅ oui |
| **A\* (heuristique ALT)** | O((n+m) log n) | O(n) + O(L·n) repères | 8,3 ms | 103,7 ms | ✅ oui |

`b` = facteur de branchement (≈ degré ≈ 4), `R` = longueur du chemin,
`L` = nombre de repères (6). Mesures : moyenne sur 200–300 appels, hors
serveur web et hors cache, banc d'essai `scratchpad/bench/` — machine de dev,
valeurs indicatives.

Détail par couple testé (ms/appel) :

| Couple (longueur) | BFS bidir. | Dijkstra | Dijkstra bidir. | A\* |
|---|---|---|---|---|
| N1 → N500 (9) | 0,14 | 52,6 | 0,64 | 17,7 |
| N1 → N50 (8) | 0,16 | 22,4 | 0,44 | 8,3 |
| N1 → N99000 (7) | 0,04 | 11,9 | 0,08 | 2,4 |
| N2 → N3 (8) | 0,05 | 24,4 | 0,37 | 11,1 |
| N77 → N88888 (7) | 0,06 | 9,2 | 0,16 | 7,6 |
| N12345 → N67890 (aucun chemin) | 22,8 | 61,8 | 0,001 | 103,7 |

## Avantages / inconvénients pour ce projet

### BFS bidirectionnel — `ShortestPath` (choix par défaut actuel)
Deux fronts (un depuis la source via les successeurs, un depuis la cible via
les prédécesseurs) qui se rejoignent au milieu. File FIFO, pas de tas.

- **+** Le plus rapide ici, de très loin (sous 0,1 ms typique).
- **+** Le plus simple ; aucun précalcul, mémoire minimale.
- **+** Toujours le plus court chemin en nombre d'arêtes.
- **−** Devient **faux** si les arêtes deviennent pondérées (p. ex. coût de
  `Transformation`).
- **−** Sur « aucun chemin », doit épuiser un côté jusqu'à `maxDepth` (~23 ms).

### Dijkstra — `ShortestPathDijkstra`
File de priorité, coût cumulé depuis la source. Un seul front.

- **+** Correct sur graphe pondéré. Base pédagogique de A*.
- **−** ~150 à 350× plus lent que le BFS bidirectionnel ici.
- **−** Unidirectionnel : fige toute la « boule » de rayon R (souvent presque
  tout le graphe).
- **−** Aucun intérêt tant que les poids valent 1.

### Dijkstra bidirectionnel — `ShortestPathDijkstraBi`
Deux Dijkstra en miroir. Arrêt quand `topF + topB ≥ best` (le meilleur
chemin complet déjà trouvé ne peut plus être battu).

- **+** Presque aussi rapide que le BFS bidirectionnel (0,1–0,6 ms) **et**
  correct sur graphe pondéré.
- **+** **Imbattable sur « aucun chemin »** quand un des deux nœuds mène à un
  petit cul-de-sac : un front se vide en quelques microsecondes (0,001 ms).
- **+** Le bon compromis si la pondération arrive un jour.
- **−** Plus complexe : deux tas, condition d'arrêt subtile.
- **−** Peut renvoyer un autre plus court chemin de même longueur (ex æquo).
- **−** Légèrement plus lent que le BFS bidir quand un chemin existe (coût du tas).

### A\* — `ShortestPathAStar` + heuristique ALT
Dijkstra guidé par une estimation `h(n)` du coût restant. Les nœuds n'ayant
ni coordonnées ni poids géographiques, on utilise l'heuristique **ALT**
(*A\*, Landmarks, Triangle inequality*) : `PrepareLandmarks` choisit 6
repères, précalcule leur distance BFS vers/depuis tous les nœuds, et
l'inégalité triangulaire donne une borne inférieure admissible.

- **+** ~3× plus rapide que Dijkstra simple quand un chemin existe.
- **+** Optimal (heuristique ALT admissible et cohérente).
- **+** Sur un vrai graphe géographique ou hiérarchique, l'écart avec
  Dijkstra serait bien plus marqué.
- **−** Sur ce graphe **aléatoire**, l'heuristique est faible (pas de
  structure spatiale) : reste 50 à 200× plus lent que le BFS bidir.
- **−** **Le pire sur « aucun chemin »** (~104 ms) : calcule l'heuristique
  (6 repères × 2) pour chaque nœud touché, sans jamais pouvoir élaguer.
- **−** Coûte un précalcul au démarrage (12 BFS complets) + ~5 Mo.
- **−** Unidirectionnel.

## Verdict

1. **Poids = 1 (situation actuelle) → garder le BFS bidirectionnel.** Rien ne
   le bat et il ne coûte rien.
2. **Si `Transformation` devient un vrai coût → Dijkstra bidirectionnel.**
   Quasi la même vitesse, correct, et excellent sur les « aucun chemin ».
3. **A\*** ne se rentabilise que si le graphe acquiert une structure
   exploitable (couches, coordonnées). Sur le graphe aléatoire actuel, son
   précalcul n'est pas amorti.
4. Le filtre le plus rentable reste la **condensation SCC** (§ 11.5) : elle
   tranche « aucun chemin » en O(1), avant même de choisir un algorithme —
   d'où l'ordre dans `HomeController` : SCC → composantes faibles → parcours.

## Où c'est dans le code

| Fichier | Rôle |
|---|---|
| `Services/DirectedGraph.cs` | Les 4 algorithmes + `PrepareLandmarks` + heuristique ALT |
| `Services/InMemoryGraphService.cs` | Chargement CSR + repères au démarrage, passe-plats |
| `Controllers/HomeController.cs` | `?algo=…` → aiguillage, cache par (algo, source, cible) |
| `Views/Home/Index.cshtml` | Menu déroulant *Algorithme* |
| `scratchpad/bench/` (hors dépôt) | Banc d'essai chronométrage |
