const API_BASE = "http://127.0.0.1:8000"; // 127.0.0.1 : "localhost" ajoute un délai sur Windows (IPv6 puis repli IPv4)
const RESULT_LIMIT = 100; // on n'affiche que les 100 premiers résultats sur cette page

const totalLabel = document.getElementById("nodes-total");
const statusEl = document.getElementById("nodes-status");
const tbody = document.getElementById("nodes-tbody");
const searchInput = document.getElementById("nodes-search-input");
const searchBtn = document.getElementById("nodes-search-btn");
const clearBtn = document.getElementById("nodes-search-clear");

async function fetchNodes(query) {
  const params = new URLSearchParams({ page: 1, pageSize: RESULT_LIMIT });
  if (query) params.set("q", query);
  const res = await fetch(`${API_BASE}/api/nodes?${params.toString()}`);
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.detail || `Erreur API (${res.status})`);
  }
  return res.json();
}

function renderRows(nodes) {
  tbody.innerHTML = nodes
    .map((n) => {
      const chips = n.transformations.length
        ? n.transformations.map((t) => `<span class="transform-chip">${t}</span>`).join("")
        : `<span class="transform-empty">aucune</span>`;
      return `<tr class="clickable-row" data-node-id="${n.id}"><td class="node-id-cell">${n.id}</td><td>${chips}</td></tr>`;
    })
    .join("");
}

tbody.addEventListener("click", (e) => {
  const row = e.target.closest("tr[data-node-id]");
  if (!row) return;
  window.location.href = `node.html?id=${encodeURIComponent(row.dataset.nodeId)}`;
});

async function load(query) {
  statusEl.textContent = "Chargement…";
  statusEl.classList.remove("error");

  try {
    const data = await fetchNodes(query);
    renderRows(data.nodes);

    totalLabel.textContent = `${data.total.toLocaleString("fr-FR")} nœuds distincts`;
    statusEl.textContent = query
      ? `${data.nodes.length} premier(s) résultat(s) sur ${data.total} correspondant à "${query}".`
      : `${data.nodes.length} premiers nœuds affichés sur ${data.total.toLocaleString("fr-FR")}.`;
  } catch (err) {
    statusEl.textContent = err.message;
    statusEl.classList.add("error");
    tbody.innerHTML = "";
  }
}

searchBtn.addEventListener("click", () => {
  load(searchInput.value.trim());
});

searchInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") searchBtn.click();
});

clearBtn.addEventListener("click", () => {
  searchInput.value = "";
  load("");
});

load("");
