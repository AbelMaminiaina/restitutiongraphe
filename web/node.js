const API_BASE = "http://127.0.0.1:8000"; // 127.0.0.1 : "localhost" ajoute un délai sur Windows (IPv6 puis repli IPv4)
const HISTORY_KEY = "restitution.nodeHistory";
const HISTORY_LIMIT = 200;

const nodeTitle = document.getElementById("node-title");
const statusEl = document.getElementById("node-status");
const predTbody = document.getElementById("pred-tbody");
const succTbody = document.getElementById("succ-tbody");
const predCount = document.getElementById("pred-count");
const succCount = document.getElementById("succ-count");
const historyList = document.getElementById("history-list");
const historyCount = document.getElementById("history-count");
const historyClearBtn = document.getElementById("history-clear");
const historyViewGraphBtn = document.getElementById("history-view-graph");

function getNodeIdFromUrl() {
  return new URLSearchParams(window.location.search).get("id");
}

// "via" = comment on est arrivé sur CE nœud depuis le précédent de l'historique :
// "predecesseur" (on a cliqué un de ses prédécesseurs), "successeur" (un de ses
// successeurs), ou null si le lien n'est pas garanti (liste, historique, double-clic
// sur le graphe...). Cette info sert à orienter correctement le graphe d'historique.
function getViaFromUrl() {
  return new URLSearchParams(window.location.search).get("via");
}

function renderRows(tbody, rows) {
  if (rows.length === 0) {
    tbody.innerHTML = `<tr><td colspan="2" class="transform-empty">Aucun</td></tr>`;
    return;
  }
  tbody.innerHTML = rows
    .map(
      (r) =>
        `<tr class="clickable-row" data-node-id="${r.id}">` +
        `<td class="node-id-cell">${r.id}</td>` +
        `<td>${r.transformation ? `<span class="transform-chip">${r.transformation}</span>` : ""}</td>` +
        `</tr>`
    )
    .join("");
}

function wireRowNavigation(tbody, via) {
  tbody.addEventListener("click", (e) => {
    const row = e.target.closest("tr[data-node-id]");
    if (!row) return;
    window.location.href = `node.html?id=${encodeURIComponent(row.dataset.nodeId)}&via=${via}`;
  });
}

wireRowNavigation(predTbody, "predecesseur");
wireRowNavigation(succTbody, "successeur");

/* ---------- Historique de navigation (trace des nœuds visités, par session) ---------- */

const VIA_LABELS = { predecesseur: "← prédécesseur", successeur: "→ successeur" };

function normalizeEntry(entry) {
  // Compat avec un ancien historique enregistré avant l'ajout de "via" (simple string).
  return typeof entry === "string" ? { id: entry, via: null } : entry;
}

function loadHistory() {
  try {
    const raw = JSON.parse(sessionStorage.getItem(HISTORY_KEY) || "[]");
    return raw.map(normalizeEntry);
  } catch {
    return [];
  }
}

function saveHistory(history) {
  try {
    sessionStorage.setItem(HISTORY_KEY, JSON.stringify(history));
  } catch {
    // stockage indisponible (navigation privée, quota...) : l'historique reste en mémoire pour cette page
  }
}

function recordVisit(nodeId, via) {
  const history = loadHistory();
  const last = history[history.length - 1];
  if (!last || last.id !== nodeId) {
    history.push({ id: nodeId, via: via || null });
    while (history.length > HISTORY_LIMIT) history.shift();
    saveHistory(history);
  }
  return history;
}

function renderHistory(history) {
  historyCount.textContent = history.length;

  if (history.length === 0) {
    historyList.innerHTML = `<p class="panel-hint">Aucune visite pour l'instant.</p>`;
    return;
  }

  historyList.innerHTML = history
    .map((entry, i) => {
      const step = i + 1;
      const isCurrent = i === history.length - 1;
      const cls = isCurrent ? "history-item current" : "history-item clickable-row";
      const attr = isCurrent ? "" : ` data-node-id="${entry.id}"`;
      const viaBadge = entry.via
        ? `<span class="history-via">${VIA_LABELS[entry.via]}</span>`
        : "";
      return `<div class="${cls}"${attr}><span class="history-step">${step}</span><span class="node-id-cell">${entry.id}</span>${viaBadge}</div>`;
    })
    .reverse() // le plus récent en haut
    .join("");
}

historyList.addEventListener("click", (e) => {
  const item = e.target.closest(".history-item[data-node-id]");
  if (!item) return;
  // Retour direct depuis l'historique : le lien n'est pas garanti dans les
  // deux sens, donc pas de "via" (orientation inconnue pour ce saut).
  window.location.href = `node.html?id=${encodeURIComponent(item.dataset.nodeId)}`;
});

historyClearBtn.addEventListener("click", () => {
  const nodeId = getNodeIdFromUrl();
  const history = nodeId ? [{ id: nodeId, via: null }] : [];
  saveHistory(history);
  renderHistory(history);
});

historyViewGraphBtn.addEventListener("click", () => {
  window.location.href = "index.html?history=1";
});

/* ---------- Chargement du détail du nœud ---------- */

async function load() {
  const nodeId = getNodeIdFromUrl();
  if (!nodeId) {
    statusEl.textContent = "Aucun nœud spécifié (paramètre ?id= manquant).";
    statusEl.classList.add("error");
    renderHistory(loadHistory());
    return;
  }

  nodeTitle.textContent = `Détail du nœud : ${nodeId}`;
  statusEl.textContent = "Chargement…";
  statusEl.classList.remove("error");
  renderHistory(recordVisit(nodeId, getViaFromUrl()));

  try {
    const res = await fetch(`${API_BASE}/api/node?id=${encodeURIComponent(nodeId)}`);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.detail || `Erreur API (${res.status})`);
    }
    const data = await res.json();

    renderRows(predTbody, data.predecessors);
    renderRows(succTbody, data.successors);
    predCount.textContent = data.predecessors.length;
    succCount.textContent = data.successors.length;
    statusEl.textContent = `${data.predecessors.length} prédécesseur(s), ${data.successors.length} successeur(s).`;
  } catch (err) {
    statusEl.textContent = err.message;
    statusEl.classList.add("error");
  }
}

load();
