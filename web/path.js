const API_BASE = "http://127.0.0.1:8000"; // 127.0.0.1 : "localhost" ajoute un délai sur Windows (IPv6 puis repli IPv4)

const sourceInput = document.getElementById("path-source-input");
const targetInput = document.getElementById("path-target-input");
const searchBtn = document.getElementById("path-search-btn");
const clearBtn = document.getElementById("path-clear-btn");
const banner = document.getElementById("path-result-banner");
const chain = document.getElementById("path-chain");
const cyContainer = document.getElementById("path-cy");

let cy = null;

function setBanner(message, kind) {
  banner.textContent = message;
  banner.className = `path-result-banner ${kind}`;
}

function renderChain(path) {
  chain.innerHTML = path
    .map((id, i) => {
      const chip = `<button type="button" class="chip" data-node-id="${id}">${id}</button>`;
      return i === 0 ? chip : `<span class="path-arrow">→</span>${chip}`;
    })
    .join("");
}

chain.addEventListener("click", (e) => {
  const chip = e.target.closest(".chip[data-node-id]");
  if (!chip) return;
  window.location.href = `node.html?id=${encodeURIComponent(chip.dataset.nodeId)}`;
});

function renderGraph(path) {
  if (cy) cy.destroy();

  const nodeIds = [...new Set(path)];
  const elements = [
    ...nodeIds.map((id) => ({ data: { id, label: id } })),
    ...path.slice(0, -1).map((id, i) => ({
      data: { id: `${id}->${path[i + 1]}`, source: id, target: path[i + 1] },
    })),
  ];

  cy = cytoscape({
    container: cyContainer,
    elements,
    style: [
      {
        selector: "node",
        style: {
          "background-color": "#4C72B0",
          label: "data(label)",
          color: "#fff",
          "text-valign": "center",
          "text-halign": "center",
          "font-size": 12,
          width: 42,
          height: 42,
        },
      },
      {
        selector: "edge",
        style: {
          width: 3,
          "line-color": "#16a34a",
          "target-arrow-color": "#16a34a",
          "target-arrow-shape": "triangle",
          "curve-style": "bezier",
        },
      },
    ],
    layout: { name: "dagre", rankDir: "LR", nodeSep: 30, rankSep: 70 },
  });

  cy.$id(path[0]).style("background-color", "#0ea5e9");
  cy.$id(path[path.length - 1]).style("background-color", "#f59e0b");

  cy.on("dbltap", "node", (evt) => {
    window.location.href = `node.html?id=${encodeURIComponent(evt.target.id())}`;
  });
}

async function search() {
  const source = sourceInput.value.trim();
  const target = targetInput.value.trim();

  if (!source || !target) {
    setBanner("Renseigne un nœud source et un nœud cible.", "not-found");
    return;
  }

  setBanner("Recherche en cours…", "found");
  chain.innerHTML = "";
  if (cy) {
    cy.destroy();
    cy = null;
  }

  try {
    const res = await fetch(
      `${API_BASE}/api/path?source=${encodeURIComponent(source)}&target=${encodeURIComponent(target)}`
    );

    if (res.status === 404) {
      setBanner(`✗ Aucun chemin de "${source}" vers "${target}".`, "not-found");
      return;
    }
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(body.detail || `Erreur API (${res.status})`);
    }

    const { path } = await res.json();
    const hops = path.length - 1;
    setBanner(`✓ Un chemin existe (${hops} arête${hops > 1 ? "s" : ""}).`, "found");
    renderChain(path);
    renderGraph(path);
  } catch (err) {
    setBanner(err.message, "not-found");
  }
}

searchBtn.addEventListener("click", search);

[sourceInput, targetInput].forEach((input) => {
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") search();
  });
});

clearBtn.addEventListener("click", () => {
  sourceInput.value = "";
  targetInput.value = "";
  banner.className = "path-result-banner";
  banner.textContent = "";
  chain.innerHTML = "";
  if (cy) {
    cy.destroy();
    cy = null;
  }
});
