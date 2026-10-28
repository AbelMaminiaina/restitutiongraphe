/* ==================================================================
   Jeu de démonstration (bouton « Charger l'exemple »)
   ==================================================================

   Même contenu que exemple.xlsx (régénéré par `node generer-exemple.mjs`,
   qui relit CE fichier : une seule source de vérité).

   Le scénario reprend le cas d'usage de la spécification :
     « Un rapport financier affiche un faux résultat. »
     - le chiffre CA_TTC_MENSUEL du RAPPORT_FINANCIER vient de la table
       DWH.DM.FAIT_VENTES,
     - elle-même alimentée par la table intermédiaire DWH.STG.VENTES,
     - elle-même chargée depuis un fichier CSV externe (SFTP.EXTERNE.VENTES_CSV)
       dont la colonne DATE_VENTE a un mauvais format de date.
   Cliquer CA_TTC_MENSUEL puis « Amont » remonte toute la chaîne.

   Identifiant d'un asset = SYSTÈME.SCHÉMA.OBJET.COLONNE
   (= dta_4.dta_3.dta_2.dta_1 dans le fichier Excel).

   Trois « feuilles » :
     lineage    : format historique (dta_*, edg_dir, edg_*, txn_dta) + statut
     assets     : fiche descriptive de chaque asset (type, propriétaire,
                  description, criticité, donnée personnelle PII/RGPD…)
     historique : journal des modifications (qui, quand, quoi)
   ================================================================== */

var EXEMPLE = (function () {
  // "A.B.C.D" -> ["D","C","B","A"] : l'ordre des colonnes dta_1..dta_4
  // (dta_1 = dernier morceau = la colonne, dta_4 = premier = le système).
  function quatreMorceaux(id) {
    const p = id.split(".");
    while (p.length < 4) p.unshift(""); // complète à gauche si moins de 4 morceaux
    return [p[3], p[2], p[1], p[0]];
  }

  // Une ligne de lineage : [donnée, sens, traitement, transformation, statut]
  //   sens "I" : la donnée ENTRE dans le traitement  (donnée -> traitement)
  //   sens "O" : le traitement PRODUIT la donnée     (traitement -> donnée)
  function L(dta, dir, edg, txn, statut) {
    return [...quatreMorceaux(dta), dir, ...quatreMorceaux(edg), txn, statut || "Validé"];
  }

  const CSV = "SFTP.EXTERNE.VENTES_CSV.";
  const CRM = "CRM.DBO.CLIENT.";
  const STG = "DWH.STG.VENTES.";
  const FAIT = "DWH.DM.FAIT_VENTES.";
  const DIM = "DWH.DM.DIM_CLIENT.";
  const RFIN = "BI.POWERBI.RAPPORT_FINANCIER.";
  const RMKT = "BI.POWERBI.RAPPORT_MARKETING.";
  const JV = "ETL.SSIS.JOB_VENTES.";
  const JC = "ETL.SSIS.JOB_CLIENT.";
  const DS = "BI.POWERBI.DATASET.";

  const lineage = [
    ["dta_1", "dta_2", "dta_3", "dta_4", "edg_dir", "edg_1", "edg_2", "edg_3", "edg_4", "txn_dta", "statut"],
    // 1) Fichier CSV externe -> table intermédiaire (staging)
    L(CSV + "ID_CLIENT", "I", JV + "CHARGEMENT_STG", "copie directe"),
    L(CSV + "DATE_VENTE", "I", JV + "CHARGEMENT_STG", "copie brute (texte JJ/MM/AAAA)"),
    L(CSV + "MONTANT_HT", "I", JV + "CHARGEMENT_STG", "CAST(MONTANT_HT AS DECIMAL(18,2))"),
    L(STG + "ID_CLIENT", "O", JV + "CHARGEMENT_STG", "copie directe"),
    L(STG + "DATE_VENTE", "O", JV + "CHARGEMENT_STG", "copie brute (texte JJ/MM/AAAA)"),
    L(STG + "MONTANT_HT", "O", JV + "CHARGEMENT_STG", "CAST(MONTANT_HT AS DECIMAL(18,2))"),
    // 2) Staging -> table de faits
    L(STG + "MONTANT_HT", "I", JV + "CALCUL_TTC", "Montant_TTC = Montant_HT * (1 + TAUX)"),
    L("API.FISCAL.TVA.TAUX", "I", JV + "CALCUL_TTC", "TAUX = taux normal (0.20)", "À valider"),
    L(FAIT + "MONTANT_TTC", "O", JV + "CALCUL_TTC", "Montant_TTC = Montant_HT * 1.2"),
    L(STG + "DATE_VENTE", "I", JV + "CONVERSION_DATE", "CONVERT(DATE, DATE_VENTE, 103)"),
    L(FAIT + "DATE_VENTE", "O", JV + "CONVERSION_DATE", "CONVERT(DATE, DATE_VENTE, 103)"),
    L(STG + "ID_CLIENT", "I", JV + "LOOKUP_CLIENT", "Customer_Key = lookup(ID_Client)"),
    L(DIM + "CUSTOMER_KEY", "I", JV + "LOOKUP_CLIENT", "jointure sur ID_Client"),
    L(FAIT + "CUSTOMER_KEY", "O", JV + "LOOKUP_CLIENT", "Customer_Key = lookup(ID_Client)"),
    // 3) CRM -> dimension client (données personnelles)
    L(CRM + "ID_CLIENT", "I", JC + "CHARGEMENT_DIM", "clé métier"),
    L(CRM + "NOM", "I", JC + "CHARGEMENT_DIM", "UPPER(TRIM(NOM))"),
    L(CRM + "EMAIL", "I", JC + "CHARGEMENT_DIM", "LOWER(EMAIL)"),
    L(DIM + "CUSTOMER_KEY", "O", JC + "CHARGEMENT_DIM", "clé de substitution (IDENTITY)"),
    L(DIM + "NOM_CLIENT", "O", JC + "CHARGEMENT_DIM", "UPPER(TRIM(NOM))"),
    L(DIM + "EMAIL", "O", JC + "CHARGEMENT_DIM", "LOWER(EMAIL)"),
    L(CRM + "IBAN", "I", JC + "MASQUAGE_IBAN", "LEFT(IBAN,4) + '****' + RIGHT(IBAN,4)"),
    L(DIM + "IBAN_MASQUE", "O", JC + "MASQUAGE_IBAN", "LEFT(IBAN,4) + '****' + RIGHT(IBAN,4)"),
    // 4) Entrepôt -> rapports Power BI
    L(FAIT + "MONTANT_TTC", "I", DS + "AGREGATION_MENSUELLE", "SUM(MONTANT_TTC) par mois"),
    L(FAIT + "DATE_VENTE", "I", DS + "AGREGATION_MENSUELLE", "regroupement par mois"),
    L(FAIT + "CUSTOMER_KEY", "I", DS + "AGREGATION_MENSUELLE", "COUNT(DISTINCT CUSTOMER_KEY)"),
    L(RFIN + "CA_TTC_MENSUEL", "O", DS + "AGREGATION_MENSUELLE", "SUM(MONTANT_TTC) par mois"),
    L(RFIN + "NB_CLIENTS", "O", DS + "AGREGATION_MENSUELLE", "COUNT(DISTINCT CUSTOMER_KEY)"),
    L(DIM + "EMAIL", "I", DS + "EXTRACTION_EMAILS", "filtre clients opt-in"),
    L(RMKT + "LISTE_EMAILS", "O", DS + "EXTRACTION_EMAILS", "filtre clients opt-in", "À valider"),
  ];

  // Fiche descriptive : id, nature, type, propriétaire, description, criticité, pii, statut
  const A = (id, nature, type, owner, description, criticite, pii, statut) => [
    id, nature, type, owner, description, criticite, pii ? "Oui" : "Non", statut || "Validé",
  ];
  const D = "Donnée";
  const T = "Traitement";
  const assets = [
    ["id", "nature", "type", "proprietaire", "description", "criticite", "pii", "statut"],
    A(CSV + "ID_CLIENT", D, "Fichier", "Équipe Ventes", "Identifiant client reçu du partenaire", "Moyenne"),
    A(CSV + "DATE_VENTE", D, "Fichier", "Équipe Ventes", "Date de la vente (texte, format attendu JJ/MM/AAAA)", "Haute"),
    A(CSV + "MONTANT_HT", D, "Fichier", "Équipe Ventes", "Montant hors taxes de la vente", "Haute"),
    A(CRM + "ID_CLIENT", D, "Colonne", "Direction Commerciale", "Clé métier du client dans le CRM", "Moyenne"),
    A(CRM + "NOM", D, "Colonne", "Direction Commerciale", "Nom du client", "Haute", true),
    A(CRM + "EMAIL", D, "Colonne", "Direction Commerciale", "Adresse e-mail du client", "Critique", true),
    A(CRM + "IBAN", D, "Colonne", "Direction Financière", "Coordonnées bancaires du client", "Critique", true),
    A("API.FISCAL.TVA.TAUX", D, "API", "Direction Financière", "Taux de TVA exposé par l'API fiscale", "Moyenne", false, "À valider"),
    A(STG + "ID_CLIENT", D, "Colonne", "Équipe Data", "Copie de l'identifiant client (staging)", "Faible"),
    A(STG + "DATE_VENTE", D, "Colonne", "Équipe Data", "Date de vente brute (texte)", "Moyenne"),
    A(STG + "MONTANT_HT", D, "Colonne", "Équipe Data", "Montant HT typé DECIMAL", "Moyenne"),
    A(FAIT + "CUSTOMER_KEY", D, "Colonne", "Équipe Data", "Clé de substitution du client", "Moyenne"),
    A(FAIT + "DATE_VENTE", D, "Colonne", "Équipe Data", "Date de vente convertie en DATE", "Haute"),
    A(FAIT + "MONTANT_TTC", D, "Colonne", "Direction Financière", "Montant TTC = HT * 1,2", "Haute"),
    A(DIM + "CUSTOMER_KEY", D, "Colonne", "Équipe Data", "Clé de substitution du client", "Moyenne"),
    A(DIM + "NOM_CLIENT", D, "Colonne", "Direction Commerciale", "Nom du client normalisé", "Haute", true),
    A(DIM + "EMAIL", D, "Colonne", "Direction Commerciale", "E-mail du client normalisé", "Critique", true),
    A(DIM + "IBAN_MASQUE", D, "Colonne", "Direction Financière", "IBAN masqué (non identifiant)", "Moyenne"),
    A(RFIN + "CA_TTC_MENSUEL", D, "Rapport", "Direction Financière", "Chiffre d'affaires TTC mensuel (reporting réglementaire BCBS 239)", "Critique"),
    A(RFIN + "NB_CLIENTS", D, "Rapport", "Direction Financière", "Nombre de clients actifs par mois", "Haute"),
    A(RMKT + "LISTE_EMAILS", D, "Rapport", "Marketing", "Liste de diffusion des clients opt-in", "Critique", true, "À valider"),
    A(JV + "CHARGEMENT_STG", T, "Traitement", "Équipe Data", "Chargement du CSV partenaire en staging", "Moyenne"),
    A(JV + "CALCUL_TTC", T, "Traitement", "Équipe Data", "Calcul du montant TTC", "Haute"),
    A(JV + "CONVERSION_DATE", T, "Traitement", "Équipe Data", "Conversion texte -> DATE (style 103)", "Haute"),
    A(JV + "LOOKUP_CLIENT", T, "Traitement", "Équipe Data", "Recherche de la clé client", "Moyenne"),
    A(JC + "CHARGEMENT_DIM", T, "Traitement", "Équipe Data", "Alimentation de la dimension client", "Haute"),
    A(JC + "MASQUAGE_IBAN", T, "Traitement", "Équipe Data", "Pseudonymisation de l'IBAN (RGPD)", "Haute"),
    A(DS + "AGREGATION_MENSUELLE", T, "Traitement", "Équipe BI", "Agrégats mensuels du dataset financier", "Haute"),
    A(DS + "EXTRACTION_EMAILS", T, "Traitement", "Équipe BI", "Extraction des e-mails pour le marketing", "Haute"),
  ];

  const historique = [
    ["date", "utilisateur", "role", "action", "type_cible", "cible", "detail"],
    ["2026-10-01T09:00:00.000Z", "import", "Administrateur", "IMPORT", "base", "exemple.xlsx", "Chargement initial"],
    ["2026-10-20T14:12:00.000Z", "m.durand", "Data Steward / Data Analyst", "CRÉATION", "asset", "API.FISCAL.TVA.TAUX", "type : API ; criticité : Moyenne"],
    ["2026-10-20T14:15:00.000Z", "m.durand", "Data Steward / Data Analyst", "CRÉATION", "relation", "API.FISCAL.TVA.TAUX=>" + JV + "CALCUL_TTC", "règle : TAUX = taux normal (0.20)"],
    ["2026-10-22T10:40:00.000Z", "s.martin", "Data Steward / Data Analyst", "CRÉATION", "asset", RMKT + "LISTE_EMAILS", "type : Rapport ; criticité : Critique ; PII"],
  ];

  return { lineage, assets, historique };
})();

// Permet à generer-exemple.mjs (Node.js) de relire ces données.
if (typeof module !== "undefined") module.exports = EXEMPLE;
