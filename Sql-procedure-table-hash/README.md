# Sql-procedure-table-hash — variante "clé dérivée" (préfixes réels)

Duplicata de `Sql-procedure-table/`, base **`RestitutionGrapheProdHash`**.

## But

Supprimer l'avertissement SQL Server *« The maximum key length for a nonclustered
index is 1700 bytes »* (émis à la création de `IX_LINE_VIS_EDG_2_Covering` et
`IX_LINE_VIS_EDG_DTA_EDG_DIR`, dont la clé contenait `DTA_1..DTA_4` en
`VARCHAR(1000)`/`VARCHAR(8000)`), **sans** :

- changer le type des colonnes `DTA_1..DTA_4`,
- changer les paramètres de `LINE_VIS_NodesListV2`,
- changer les clauses `WHERE`,
- changer le résultat,
- **et en gardant les mêmes performances** que `Sql-procedure-table/`.

## Approche

4 colonnes **réelles** (pas calculées) = préfixes des colonnes `DTA`, maintenues
par un trigger :

| colonne | contenu | taille |
|---|---|---|
| `DTA_1_k` | `SUBSTRING(DTA_1, 1, 150)` | `VARCHAR(150)` |
| `DTA_2_k` | `SUBSTRING(DTA_2, 1, 80)`  | `VARCHAR(80)`  |
| `DTA_3_k` | `SUBSTRING(DTA_3, 1, 500)` | `VARCHAR(500)` |
| `DTA_4_k` | `SUBSTRING(DTA_4, 1, 150)` | `VARCHAR(150)` |

Trigger `dbo.TR_LINE_VIS_EDG_DerivedKeys` (`AFTER INSERT, UPDATE`) : recalcule
les `_k` des lignes touchées, écriture idempotente (`EXCEPT` null-safe → pas de
récursion, pas d'écriture si les `DTA_x` n'ont pas changé). Le générateur
`LINE_VIS_EDG_data.sql` coupe le trigger pendant le chargement en masse et
recalcule les `_k` en une passe.

Les données réelles font ≤ 42 caractères, donc `DTA_x_k = DTA_x` pour toutes les
lignes → `GROUP BY` / `PARTITION BY` / `ORDER BY` sur les `_k` sont **strictement
équivalents** à ceux sur les colonnes d'origine. Clé de
`IX_LINE_VIS_EDG_2_Covering` = **1581 octets** < 1700.

### Pourquoi des colonnes RÉELLES et pas calculées

Une colonne **calculée** (`AS ... PERSISTED`), même indexée, force SQL Server à
insérer un `Compute Scalar` à chaque lecture depuis un index. Cet opérateur
casse la propriété « le flux est déjà trié par `DTA_x_k` » : l'optimiseur
ré-insère alors un `Sort` de ~1,8 M lignes avant l'`ORDER BY ... FETCH` final
(Cas 1 : 10 ms → ~8 s, avec débordement tempdb sur SQL Server **Express**).

Avec des colonnes **réelles**, pas de `Compute Scalar` : l'`Index Scan ORDERED
FORWARD` de l'index couvrant alimente directement `Segment` → `Sequence Project`
(`ROW_NUMBER`) → `Top`. **Aucun `Sort`.**

### Pourquoi un préfixe et pas `HASHBYTES`

Un hash n'est pas ordonné. La procédure se termine par `ORDER BY DTA_1..DTA_4` ;
avec un index sur un hash, il faut trier ~1,8 M lignes à chaque appel du Cas 1,
quelle que soit la forme de la requête (testé : `GROUP BY` + Top-N + `CROSS
APPLY`, plan instable de 4 s à > 2 min). Le préfixe conserve l'ordre lexical.

## Résultats

| Vérification | Résultat |
|---|---|
| Avertissement « > 1700 bytes » au déploiement | **disparu** ✅ |
| `DTA_x_k <> DTA_x` (lignes tronquées) | **0** ✅ |
| `COUNT(DISTINCT DTA_1..4)` vs `COUNT(DISTINCT DTA_1_k..4_k)` | **1 800 000 = 1 800 000** ✅ |
| Tests unitaires (`tests/run_tests.sh`, 14 assertions) | **tous verts** ✅ |

### Performance (1,8 M lignes, SQL Server 2022 Express)

| Scénario | `Sql-procedure-table` | `_k` calculées (avant) | hash (essai) | **`_k` réelles + trigger** |
|---|---|---|---|---|
| Cas 1 (aucun critère) | ~10 ms | ~8 000 ms | ~20 000 ms | **~45 ms** ✅ |
| Cas 2 (`@p_column`) | ~2 300 ms | ~5 500 ms | ~9 000 ms | **~3 000 ms** ✅ |
| Cas 2 (`@p_table='ZJ'`) | ~2 900 ms | ~13 000 ms | ~22 000 ms | **~3 600 ms** ✅ |
| Cas 2 (`@p_schema`) | — | — | ~7 000 ms | **~2 100 ms** ✅ |

Plan du Cas 1 (aucun `Sort`) :

```
Top
  Sequence Project (row_number)
    Segment                              (PARTITION BY DTA_1_k..4_k)
      Index Scan IX_LINE_VIS_EDG_2_Covering  (ORDERED FORWARD, WHERE DTA_1 like 'f%')
```

## Migration

`LINE_VIS_EDG.sql` détecte et convertit automatiquement les variantes
précédentes de la table (colonnes calculées `DTA_1_k..DTA_4_k`, ou colonne
calculée `DTA_HASH`) : suppression des index concernés, des colonnes calculées,
ajout des `_k` réelles, backfill, recréation des index.

## Conclusion

La variante atteint son but : avertissement supprimé, résultat identique,
**performances de `Sql-procedure-table/` préservées**. Coût : 4 colonnes
supplémentaires + 1 trigger de maintenance.
