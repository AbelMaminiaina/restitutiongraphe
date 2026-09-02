# Sql-procedure-table-hash — variante "clé dérivée" (option 2)

Duplicata de `Sql-procedure-table/`, base **`RestitutionGrapheProdHash`**.

## But

Supprimer l'avertissement SQL Server *« The maximum key length for a nonclustered
index is 1700 bytes »* (émis à la création de `IX_LINE_VIS_EDG_2_Covering` et
`IX_LINE_VIS_EDG_DTA_EDG_DIR`, dont la clé contient `DTA_1..DTA_4` en
`VARCHAR(1000)`/`VARCHAR(8000)`), **sans** :

- changer le type des colonnes `DTA_1..DTA_4`,
- changer les paramètres de `LINE_VIS_NodesListV2`,
- changer les clauses `WHERE`,
- changer le résultat.

## Approche

4 colonnes calculées **PERSISTED** = préfixes des colonnes `DTA` :

| colonne | définition | taille |
|---|---|---|
| `DTA_1_k` | `SUBSTRING(DTA_1, 1, 150)` | `VARCHAR(150)` |
| `DTA_2_k` | `SUBSTRING(DTA_2, 1, 80)`  | `VARCHAR(80)`  |
| `DTA_3_k` | `SUBSTRING(DTA_3, 1, 500)` | `VARCHAR(500)` |
| `DTA_4_k` | `SUBSTRING(DTA_4, 1, 150)` | `VARCHAR(150)` |

Les données réelles font ≤ 42 caractères, donc `DTA_x_k = DTA_x` pour toutes les
lignes → `GROUP BY` / `PARTITION BY` / `ORDER BY` sur les `_k` sont **strictement
équivalents** à ceux sur les colonnes d'origine. Les index passent leur clé sur
les `_k` (courtes) → clé de `IX_LINE_VIS_EDG_2_Covering` = **1581 octets** < 1700.

**Préfixe et pas `HASHBYTES`** : un hash n'est pas ordonné → il casserait le
`ORDER BY DTA_1..4` final encore plus.

## Résultat des tests

| Vérification | Résultat |
|---|---|
| Avertissement « > 1700 bytes » au déploiement | **disparu** ✅ |
| `DTA_x_k <> DTA_x` (lignes tronquées) | **0** ✅ |
| `COUNT(DISTINCT DTA_1..4)` vs `COUNT(DISTINCT DTA_1_k..4_k)` | **1 800 000 = 1 800 000** ✅ |
| Tests unitaires (`tests/run_tests.sh`, 14 assertions) | **tous verts** ✅ |
| **Performance** | **régression forte** ❌ |

### La régression de performance

| Scénario | `Sql-procedure-table` | `Sql-procedure-table-hash` |
|---|---|---|
| Cas 1 (aucun critère) | ~10 ms | **~8 000 ms** |
| Cas 2 (`@p_column`) | ~2 300 ms | **~5 500 ms** |
| Cas 2 (`@p_table='ZJ'`) | ~2 900 ms | **~13 000 ms** |

**Cause** : quand la requête référence à la fois `DTA_1_k` (clé d'index) et
`DTA_1` (colonne d'origine, en `INCLUDE`), l'optimiseur choisit de **recalculer**
`DTA_1_k = SUBSTRING(DTA_1, …)` pendant le scan au lieu de le lire dans la clé.
Il perd alors l'information « le scan est déjà trié par `DTA_1_k` » et ré-insère
un opérateur **`Sort`** de ~1,8 M lignes larges (colonne `DTA_3`), qui déborde en
tempdb (~460 Mo).

Essais infructueux pour éviter ce `Sort` :
`SET ARITHABORT/ANSI_WARNINGS ON` (session + corps de procédure), hints
`INDEX(...)`, `WHERE` porté sur `DTA_x_k`, index de couverture **sans** `INCLUDE`
(clé seule + key lookup) → toutes les variantes gardent le `Sort` ou l'aggravent.

## Conclusion

L'option 2 **atteint son but fonctionnel** (avertissement supprimé, résultat
identique) mais **ne préserve pas l'optimisation**. À ne pas adopter en l'état.

Recommandations, par ordre de préférence :

1. **Garder `Sql-procedure-table/`** : l'avertissement est inoffensif (clé
   réelle ~112 octets pour une limite de 1700). Ajouter au besoin une contrainte
   `CHECK (DATALENGTH(DTA_1)+…+DATALENGTH(LIN_UID) <= 1600)` pour rendre le cas
   pathologique impossible, et un commentaire.
2. **Redimensionner** réellement les colonnes `DTA_1..DTA_4` (elles contiennent
   ≤ 42 car.) : `DTA_3` en `VARCHAR(500)`, etc. → clé < 1700, `DTA_3` reste dans
   la clé, plan et perf inchangés. (Rejeté par la demande initiale.)
