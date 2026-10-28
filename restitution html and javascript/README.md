# restitution html and javascript — Saisie et cartographie du lignage de données

Copie du projet `javascript/` (import Excel + graphe **cytoscape**), étendue en
**application de saisie de lignage (data lineage)** : 100 % navigateur, 100 %
hors ligne, aucune installation.

> **Objectif** : cartographier le cycle de vie de la donnée en retraçant son
> origine, ses transformations et sa destination finale, pour assurer la
> gouvernance, la transparence et la conformité des données.

## Lancer

Double-cliquez sur **`index.html`**, puis **« Charger l'exemple »**.

Les librairies (cytoscape, dagre, xlsx) sont **en local** dans `vendor/`.
La base saisie est **sauvegardée automatiquement dans le navigateur**
(localStorage) : on la retrouve en rouvrant la page. Pour la partager ou
l'archiver : **« Exporter .xlsx »**.

## Ce que fait l'application (spécification → écran)

| Spécification | Où / comment |
| --- | --- |
| **Transparence** : d'où viennent les données | Cliquez un nœud → onglet **Fiche** : parents / enfants directs + règle de transformation |
| **Analyse d'impact** | Bouton **↓ Aval** (barre d'outils ou fiche) ; la fiche liste les **rapports impactés** |
| **Conformité & audit** (RGPD, BCBS 239) | Onglet **Critiques** + filtre **« données personnelles + propagation »** ; onglet **Historique** |
| **Confiance** : validation manuelle | Onglet **Validation** : file des éléments « À valider », boutons Valider / Rejeter (motif) |
| **Rôles** | Menu **Rôle** en haut : Administrateur / Data Steward / Consommateur (lecture seule) |
| **Niveau micro / macro** | Menu **Niveau** : colonne à colonne (`ID_Client → Customer_Key`) ou table à table |
| **Filtres et recherche** | Champ **Rechercher** + **↑ Amont** / **↓ Aval** / **↕ Les deux** (Entrée = les deux) |
| **Fiche descriptive de l'asset** | Nom, type (table, colonne, fichier, rapport, API, base, traitement), propriétaire (Data Owner), description métier, **niveau de criticité**, donnée personnelle (PII/RGPD), statut, créé / modifié / validé par |
| **Historique et versioning** | Chaque création, modification (ancienne → nouvelle valeur), validation, rejet, suppression, import est journalisé (**qui, quand, quoi**) ; visible dans la fiche et l'onglet Historique ; exporté dans Excel |
| **Saisie manuelle** | Onglet **Saisie** : déclarer un **asset**, une **relation Parent → Enfant** et sa **règle de transformation** (ex. `Montant_TTC = Montant_HT * 1.2`) |

### Données critiques

Une donnée est **critique** si sa criticité est *Haute* ou *Critique*, ou si
c'est une **donnée personnelle (PII / RGPD)**. Dans le graphe :

- **bordure rouge** = donnée critique, **🔒** = donnée personnelle ;
- menu **Couleur → par criticité** : Faible (gris), Moyenne (bleu), Haute (orange), Critique (rouge) ;
- menu **Afficher** : « données critiques + leur lignage », « données personnelles + propagation » ;
- onglet **Critiques** : compteurs, liste triée par criticité, nombre d'éléments
  en aval, bouton **« Tracer la propagation (aval) »**.

### Représentation (cytoscape)

- Formes par type : colonne (rectangle arrondi), table (rectangle), fichier
  (coin coupé), rapport (étiquette arrondie), API (étiquette), base (tonneau),
  traitement (hexagone).
- **Regrouper par table** : les colonnes sont dessinées dans la boîte de leur table.
- Statut : **tirets jaunes** = à valider, **pointillés rouges** = rejeté.
- Sélection : **jaune** = amont, **vert** = aval.
- **Règles sur les flèches** : affiche la transformation sur chaque arête.

### Rôles

| Action | Administrateur | Data Steward / Analyst | Consommateur |
| --- | :-: | :-: | :-: |
| Consulter, rechercher, exporter | ✔ | ✔ | ✔ |
| Créer / modifier assets et relations | ✔ | ✔ | |
| Valider / rejeter | ✔ | ✔ | |
| Importer (remplace la base) | ✔ | ✔ | |
| Supprimer, vider la base | ✔ | | |

Toute création ou modification passe au statut **« À valider »**. Le nom saisi
dans **Utilisateur** est celui inscrit dans l'historique.

### Cas d'usage (jeu d'exemple)

*Un rapport financier affiche un faux résultat.* Tapez `CA_TTC` dans la
recherche → **↑ Amont** : le chiffre `CA_TTC_MENSUEL` vient de la table
`DWH.DM.FAIT_VENTES`, alimentée par la table intermédiaire `DWH.STG.VENTES`,
elle-même chargée depuis le fichier CSV externe `SFTP.EXTERNE.VENTES_CSV`
(colonne `DATE_VENTE` en texte `JJ/MM/AAAA`). La fiche liste les **origines**.

## Format du fichier Excel

Le classeur peut contenir **3 feuilles**, reconnues par leurs en-têtes :

1. **lineage** (obligatoire) — le format d'origine du projet `javascript/`,
   plus une colonne `statut` optionnelle :

   | `dta_1`…`dta_4` | `edg_dir` | `edg_1`…`edg_4` | `txn_dta` | `statut` |
   | --- | --- | --- | --- | --- |

   asset « données » = `dta_4.dta_3.dta_2.dta_1`, traitement =
   `edg_4.edg_3.edg_2.edg_1` ; `I` = données → traitement, `O` = traitement → données.
2. **assets** (optionnelle) : `id`, `nature` (Donnée / Traitement), `type`,
   `proprietaire`, `description`, `criticite`, `pii` (Oui/Non), `statut`
   (+ colonnes d'audit `cree_par`, `cree_le`, `modifie_par`…).
3. **historique** (optionnelle) : `date`, `utilisateur`, `role`, `action`,
   `type_cible`, `cible`, `detail`.

Un **ancien fichier** (une seule feuille lineage) s'importe tel quel :
criticité « Faible », statut « Validé » par défaut. L'export produit les 3
feuilles et se ré-importe à l'identique.

## Fichiers

| Fichier | Rôle |
| --- | --- |
| `index.html` | Structure de la page (barre du haut, barre d'outils, graphe, onglets) |
| `style.css` | Thème sombre (repris de `javascript/`) + onglets, formulaires, badges |
| `app.js` | Toute la logique, commentée et découpée en 15 sections (voir l'en-tête) |
| `exemple-data.js` | Données du bouton « Charger l'exemple » (source unique) |
| `generer-exemple.mjs` | `node generer-exemple.mjs` → réécrit `exemple.xlsx` depuis `exemple-data.js` |
| `exemple.xlsx` | Le jeu d'exemple (3 feuilles) |
| `exemple-cas-limites.xlsx`, `exemple-sans-edg_dir.xlsx`, `generer-cas-limites.mjs` | Repris de `javascript/` (format d'origine) |
| `build.mjs` | `node build.mjs` → `dist/lineage.html` : un seul fichier autonome à distribuer |
| `vendor/` | cytoscape 3.30.2, dagre, cytoscape-dagre 2.5.0, xlsx 0.18.5 |

## Partager (`dist/`)

`node build.mjs` (Node.js ≥ 18 ; le premier build télécharge `terser` via
`npx`) produit `dist/` : `lineage.html` (~970 Ko, tout intégré), lanceurs
`Ouvrir le lineage.bat` / `.command`, `exemple.xlsx`, `LISEZ-MOI.txt`.
`dist/` est ignoré par git.

> La base est stockée **dans le navigateur de chaque utilisateur** : il n'y a
> pas de serveur partagé. Pour travailler à plusieurs, échangez les fichiers
> exportés (`Exporter .xlsx` → `Importer un .xlsx`).

## Débogage

Ouvrir `index.html?debug=1` avec les outils de développement (F12) ouverts :
l'exécution s'arrête aux points `brk(...)` du code (lecture Excel, rendu,
sélection).
