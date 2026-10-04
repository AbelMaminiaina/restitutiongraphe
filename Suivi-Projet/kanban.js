// ---------------------------------------------------------------------------
// Données
// ---------------------------------------------------------------------------
const STORAGE_KEY = "kanban-suivi-projet";
// COLUMNS, PRIORITY_LABEL et les fonctions Excel/CSV viennent de kanban-excel.js (chargé avant ce fichier)

// État complet du tableau :
// { name, projects: ["nom", ...],
//   tasks: [{id, title, description, project, priority, label, due, column, createdAt}],
//   notes: [{id, date, project, title, participants, content, createdAt}] }   <- comptes rendus des points projet
let state = load();
// Filtre projet affiché : "" = tous les projets, NO_PROJECT = tâches sans projet, sinon le nom du projet.
// Il est mémorisé à part (préférence d'affichage, pas une donnée du tableau).
const FILTER_KEY = STORAGE_KEY + "-filtre";
const NO_PROJECT = "\u0000sans-projet";
let projectFilter = "";
try { projectFilter = localStorage.getItem(FILTER_KEY) || ""; } catch (e) {}
let editingId = null;   // id de la tâche en cours de modification (null = création)
let draggedId = null;   // id de la tâche en cours de glisser-déposer

function load() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const data = JSON.parse(raw);
      if (data && Array.isArray(data.tasks)) {
        // Les anciennes sauvegardes n'ont pas de liste de projets ni de notes : on en crée des vides
        if (!Array.isArray(data.projects)) data.projects = [];
        if (!Array.isArray(data.notes)) data.notes = [];
        return data;
      }
    }
  } catch (e) { /* stockage indisponible ou corrompu : on repart à vide */ }
  return { name: "Mon projet", projects: [], tasks: [], notes: [] };
}

function save() {
  try { localStorage.setItem(STORAGE_KEY, JSON.stringify(state)); } catch (e) {}
}

function newId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
}

// Date du jour au format AAAA-MM-JJ (heure locale), pour comparer aux échéances
function today() {
  const d = new Date();
  return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
}

// Une tâche est en retard si elle a une échéance passée et n'est pas terminée
function isOverdue(task) {
  return task.due && task.column !== "done" && task.due < today();
}

function formatDate(iso) {
  const [y, m, d] = iso.split("-");
  return d + "/" + m + "/" + y;
}

// ---------------------------------------------------------------------------
// Affichage
// ---------------------------------------------------------------------------
const board = document.getElementById("board");
const searchInput = document.getElementById("search");
const projectFilterSelect = document.getElementById("projectFilter");

// Liste triée des projets : ceux créés avec « + Projet » (même sans tâche),
// et ceux présents dans les tâches et dans les notes
function projectNames() {
  const all = state.projects.concat(state.tasks.map(t => t.project), state.notes.map(n => n.project));
  return [...new Set(all.filter(Boolean))].sort((a, b) => a.localeCompare(b, "fr"));
}

// La tâche (ou la note) est-elle visible avec le filtre projet courant ?
function inCurrentProject(task) {
  if (!projectFilter) return true;
  if (projectFilter === NO_PROJECT) return !task.project;
  return task.project === projectFilter;
}

// Remplit la liste déroulante du filtre et les suggestions du champ « Projet »
function renderProjectOptions() {
  const names = projectNames();
  // Si le projet filtré n'existe plus (toutes ses tâches supprimées), on revient à « Tous »
  if (projectFilter && projectFilter !== NO_PROJECT && !names.includes(projectFilter)) projectFilter = "";

  projectFilterSelect.innerHTML = "";
  projectFilterSelect.add(new Option(`Tous les projets (${state.tasks.length})`, ""));
  names.forEach(n => {
    const count = state.tasks.filter(t => t.project === n).length;
    projectFilterSelect.add(new Option(`${n} (${count})`, n));
  });
  const without = state.tasks.filter(t => !t.project).length;
  if (without && names.length) projectFilterSelect.add(new Option(`Sans projet (${without})`, NO_PROJECT));
  projectFilterSelect.value = projectFilter;

  const datalist = document.getElementById("projectList");
  datalist.innerHTML = "";
  names.forEach(n => datalist.appendChild(new Option(n)));
}

function render() {
  document.getElementById("projectTitle").textContent = state.name;
  document.title = state.name + " — Kanban";

  renderProjectOptions();
  const query = searchInput.value.trim().toLowerCase();
  board.innerHTML = "";

  COLUMNS.forEach((col, colIndex) => {
    const colEl = document.createElement("section");
    colEl.className = "column";
    colEl.dataset.column = col.id;

    const tasks = state.tasks.filter(t => t.column === col.id && inCurrentProject(t));
    const visible = tasks.filter(t => matches(t, query));

    const h2 = document.createElement("h2");
    h2.innerHTML = `<span></span><span class="count"></span>`;
    h2.firstChild.textContent = col.name;
    h2.lastChild.textContent = query ? `${visible.length}/${tasks.length}` : tasks.length;
    colEl.appendChild(h2);

    visible.forEach(task => colEl.appendChild(renderCard(task, colIndex)));

    const hint = document.createElement("div");
    hint.className = "hint";
    hint.textContent = "Double-cliquer ici pour ajouter une tâche";
    colEl.appendChild(hint);

    // Double-clic dans la colonne (hors carte) : création directe dans cette colonne
    colEl.addEventListener("dblclick", e => {
      if (!e.target.closest(".card")) openDialog(null, col.id);
    });

    // Glisser-déposer : la colonne accepte les cartes
    colEl.addEventListener("dragover", e => { e.preventDefault(); colEl.classList.add("drag-over"); });
    colEl.addEventListener("dragleave", e => {
      if (!colEl.contains(e.relatedTarget)) colEl.classList.remove("drag-over");
    });
    colEl.addEventListener("drop", e => {
      e.preventDefault();
      colEl.classList.remove("drag-over");
      if (draggedId) moveTask(draggedId, col.id);
    });

    board.appendChild(colEl);
  });

  updateProgress();
}

function matches(task, query) {
  if (!query) return true;
  return [task.title, task.description, task.project, task.label, PRIORITY_LABEL[task.priority]]
    .some(v => (v || "").toLowerCase().includes(query));
}

function renderCard(task, colIndex) {
  const card = document.createElement("article");
  card.className = "card p-" + task.priority + (isOverdue(task) ? " overdue" : "");
  card.draggable = true;
  card.dataset.id = task.id;

  const title = document.createElement("h3");
  title.textContent = task.title;
  card.appendChild(title);

  if (task.description) {
    const p = document.createElement("p");
    p.textContent = task.description;
    card.appendChild(p);
  }

  const meta = document.createElement("div");
  meta.className = "meta";
  // Le nom du projet n'est utile que quand on affiche tous les projets
  if (task.project && !projectFilter) addSpan(meta, "tag project", task.project);
  addSpan(meta, "tag", PRIORITY_LABEL[task.priority]);
  if (task.label) addSpan(meta, "tag", "#" + task.label);
  if (task.due) {
    const late = isOverdue(task);
    addSpan(meta, "due" + (late ? " late" : ""), (late ? "⚠ En retard : " : "📅 ") + formatDate(task.due));
  }
  card.appendChild(meta);

  // Boutons ◀ ▶ (alternative au glisser-déposer, utile sur mobile)
  const actions = document.createElement("div");
  actions.className = "actions";
  const left = makeButton("◀", "Colonne précédente", () => shiftTask(task.id, -1));
  const right = makeButton("▶", "Colonne suivante", () => shiftTask(task.id, +1));
  left.disabled = colIndex === 0;
  right.disabled = colIndex === COLUMNS.length - 1;
  const edit = makeButton("Modifier", "Modifier la tâche", () => openDialog(task.id));
  actions.append(left, edit, right);
  card.appendChild(actions);

  card.addEventListener("dblclick", e => { e.stopPropagation(); openDialog(task.id); });
  card.addEventListener("dragstart", e => {
    draggedId = task.id;
    card.classList.add("dragging");
    e.dataTransfer.effectAllowed = "move";
    e.dataTransfer.setData("text/plain", task.id); // requis par Firefox
  });
  card.addEventListener("dragend", () => { draggedId = null; card.classList.remove("dragging"); });

  return card;
}

function addSpan(parent, cls, text) {
  const s = document.createElement("span");
  s.className = cls;
  s.textContent = text;
  parent.appendChild(s);
}

function makeButton(text, title, onClick) {
  const b = document.createElement("button");
  b.type = "button";
  b.textContent = text;
  b.title = title;
  b.addEventListener("click", e => { e.stopPropagation(); onClick(); });
  return b;
}

// La progression porte sur le projet filtré (ou sur tout le tableau avec « Tous les projets »)
function updateProgress() {
  const tasks = state.tasks.filter(inCurrentProject);
  const total = tasks.length;
  const done = tasks.filter(t => t.column === "done").length;
  const pct = total ? Math.round(done * 100 / total) : 0;
  const late = tasks.filter(isOverdue).length;
  document.getElementById("progressBar").style.width = pct + "%";
  document.getElementById("progressText").textContent =
    `${pct} % — ${done}/${total} terminée(s)` + (late ? ` — ${late} en retard` : "");
  // Le bouton des notes affiche le nombre de points projet du projet filtré
  document.getElementById("notesBtn").textContent = `📝 Points projet (${state.notes.filter(inCurrentProject).length})`;
}

// ---------------------------------------------------------------------------
// Actions sur les tâches
// ---------------------------------------------------------------------------
function moveTask(id, columnId) {
  const task = state.tasks.find(t => t.id === id);
  if (!task || task.column === columnId) return;
  task.column = columnId;
  // On la place en fin de liste pour qu'elle apparaisse en bas de sa nouvelle colonne
  state.tasks = state.tasks.filter(t => t.id !== id).concat(task);
  save(); render();
}

function shiftTask(id, delta) {
  const task = state.tasks.find(t => t.id === id);
  const idx = COLUMNS.findIndex(c => c.id === task.column) + delta;
  if (idx >= 0 && idx < COLUMNS.length) moveTask(id, COLUMNS[idx].id);
}

// ---------------------------------------------------------------------------
// Fenêtre de saisie
// ---------------------------------------------------------------------------
const dialog = document.getElementById("taskDialog");
const form = document.getElementById("taskForm");
const columnSelect = document.getElementById("columnSelect");
COLUMNS.forEach(c => columnSelect.add(new Option(c.name, c.id)));

function openDialog(taskId, columnId) {
  editingId = taskId;
  const task = taskId ? state.tasks.find(t => t.id === taskId) : null;
  document.getElementById("dialogTitle").textContent = task ? "Modifier la tâche" : "Nouvelle tâche";
  document.getElementById("deleteBtn").style.display = task ? "" : "none";
  form.title.value = task ? task.title : "";
  form.description.value = task ? task.description : "";
  // Nouvelle tâche : on pré-remplit avec le projet actuellement filtré
  form.project.value = task ? (task.project || "") : (projectFilter && projectFilter !== NO_PROJECT ? projectFilter : "");
  form.priority.value = task ? task.priority : "moyenne";
  form.label.value = task ? task.label : "";
  form.due.value = task ? task.due : "";
  form.column.value = task ? task.column : (columnId || "backlog");
  dialog.showModal();
  form.title.focus();
}

form.addEventListener("submit", e => {
  e.preventDefault();
  const values = {
    title: form.title.value.trim(),
    description: form.description.value.trim(),
    project: form.project.value.trim(),
    priority: form.priority.value,
    label: form.label.value.trim(),
    due: form.due.value,
    column: form.column.value,
  };
  if (!values.title) return;
  if (editingId) {
    Object.assign(state.tasks.find(t => t.id === editingId), values);
  } else {
    state.tasks.push({ id: newId(), createdAt: new Date().toISOString(), ...values });
  }
  dialog.close(); save(); render();
});

document.getElementById("cancelBtn").addEventListener("click", () => dialog.close());
document.getElementById("deleteBtn").addEventListener("click", () => {
  if (!editingId || !confirm("Supprimer cette tâche ?")) return;
  state.tasks = state.tasks.filter(t => t.id !== editingId);
  dialog.close(); save(); render();
});

document.getElementById("addBtn").addEventListener("click", () => openDialog(null, "backlog"));
searchInput.addEventListener("input", render);
// Bouton « + Projet » : crée un projet vide et l'affiche aussitôt
document.getElementById("addProjectBtn").addEventListener("click", () => {
  const answer = prompt("Nom du nouveau projet :");
  if (answer === null) return;                      // clic sur « Annuler »
  const name = answer.trim();
  if (!name) return;
  // Comparaison sans tenir compte des majuscules : « Graphe » et « graphe » = même projet
  const existing = projectNames().find(n => n.toLowerCase() === name.toLowerCase());
  if (existing) {
    alert(`Le projet « ${existing} » existe déjà.`);
  } else {
    state.projects.push(name);
    save();
  }
  projectFilter = existing || name;
  try { localStorage.setItem(FILTER_KEY, projectFilter); } catch (e) {}
  render();
});

projectFilterSelect.addEventListener("change", () => {
  projectFilter = projectFilterSelect.value;
  try { localStorage.setItem(FILTER_KEY, projectFilter); } catch (e) {}
  render();
});

// ---------------------------------------------------------------------------
// Points projet : comptes rendus datés, rattachés à un projet
//
// Bouton « 📝 Points projet » -> liste des notes du projet filtré (la plus récente en haut)
// -> « + Nouveau point » ou « Modifier » ouvre la fenêtre de saisie d'une note.
// ---------------------------------------------------------------------------
const notesDialog = document.getElementById("notesDialog");
const noteDialog = document.getElementById("noteDialog");
const noteFields = document.getElementById("noteForm").elements;   // champs du formulaire, par leur « name »
let editingNoteId = null;   // id de la note en cours de modification (null = création)

// Trame proposée pour un nouveau point (on peut l'effacer ou la compléter librement)
const NOTE_TEMPLATE = "Avancement :\n- \n\nDécisions :\n- \n\nActions (qui / quoi / quand) :\n- \n\nRisques / points bloquants :\n- ";

function renderNotes() {
  const projet = projectFilter && projectFilter !== NO_PROJECT ? projectFilter
    : projectFilter === NO_PROJECT ? "sans projet" : "tous les projets";
  document.getElementById("notesTitle").textContent = "Points projet — " + projet;

  // Tri : date la plus récente d'abord ; à date égale, la dernière créée d'abord
  const notes = state.notes.filter(inCurrentProject)
    .sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));

  const list = document.getElementById("notesList");
  list.innerHTML = "";
  if (!notes.length) {
    const p = document.createElement("p");
    p.className = "hint";
    p.textContent = "Aucun point projet pour l'instant. Clique sur « + Nouveau point ».";
    list.appendChild(p);
  }
  notes.forEach(note => {
    const item = document.createElement("article");
    item.className = "note";

    const head = document.createElement("div");
    head.className = "meta";
    addSpan(head, "note-date", "📅 " + formatDate(note.date));
    if (note.title) addSpan(head, "note-title", note.title);
    if (note.project && !projectFilter) addSpan(head, "tag project", note.project);
    item.appendChild(head);

    if (note.participants) addSpan(item, "note-people", "👥 " + note.participants);
    const body = document.createElement("p");
    body.textContent = note.content;
    item.appendChild(body);

    const actions = document.createElement("div");
    actions.className = "actions";
    actions.appendChild(makeButton("Modifier", "Modifier ce point", () => openNoteDialog(note.id)));
    item.appendChild(actions);
    item.addEventListener("dblclick", () => openNoteDialog(note.id));
    list.appendChild(item);
  });
}

function openNoteDialog(noteId) {
  editingNoteId = noteId;
  const note = noteId ? state.notes.find(n => n.id === noteId) : null;
  document.getElementById("noteDialogTitle").textContent = note ? "Modifier le point projet" : "Nouveau point projet";
  document.getElementById("deleteNoteBtn").style.display = note ? "" : "none";
  noteFields.date.value = note ? note.date : today();
  noteFields.project.value = note ? note.project : (projectFilter && projectFilter !== NO_PROJECT ? projectFilter : "");
  noteFields.title.value = note ? note.title : "Point projet";
  noteFields.participants.value = note ? note.participants : "";
  noteFields.content.value = note ? note.content : NOTE_TEMPLATE;
  noteDialog.showModal();
  noteFields.content.focus();
}

document.getElementById("noteForm").addEventListener("submit", e => {
  e.preventDefault();
  const values = {
    date: noteFields.date.value || today(),
    project: noteFields.project.value.trim(),
    title: noteFields.title.value.trim(),
    participants: noteFields.participants.value.trim(),
    content: noteFields.content.value.trim(),
  };
  if (editingNoteId) {
    Object.assign(state.notes.find(n => n.id === editingNoteId), values);
  } else {
    state.notes.push({ id: newId(), createdAt: new Date().toISOString(), ...values });
  }
  noteDialog.close(); save(); render(); renderNotes();
});

document.getElementById("cancelNoteBtn").addEventListener("click", () => noteDialog.close());
document.getElementById("deleteNoteBtn").addEventListener("click", () => {
  if (!editingNoteId || !confirm("Supprimer ce point projet ?")) return;
  state.notes = state.notes.filter(n => n.id !== editingNoteId);
  noteDialog.close(); save(); render(); renderNotes();
});

document.getElementById("notesBtn").addEventListener("click", () => { renderNotes(); notesDialog.showModal(); });
document.getElementById("addNoteBtn").addEventListener("click", () => openNoteDialog(null));
document.getElementById("closeNotesBtn").addEventListener("click", () => notesDialog.close());

// ---------------------------------------------------------------------------
// Renommage du projet (clic sur le titre, Entrée pour valider, Échap pour annuler)
// ---------------------------------------------------------------------------
const titleEl = document.getElementById("projectTitle");
titleEl.addEventListener("click", () => {
  if (titleEl.isContentEditable) return;
  titleEl.contentEditable = "true";
  titleEl.focus();
  document.getSelection().selectAllChildren(titleEl);
});
titleEl.addEventListener("keydown", e => {
  if (e.key === "Enter") { e.preventDefault(); titleEl.blur(); }
  if (e.key === "Escape") { titleEl.textContent = state.name; titleEl.blur(); }
});
titleEl.addEventListener("blur", () => {
  titleEl.contentEditable = "false";
  const name = titleEl.textContent.trim();
  if (name) state.name = name;
  save(); render();
});

// ---------------------------------------------------------------------------
// Export / import JSON
// ---------------------------------------------------------------------------
document.getElementById("exportBtn").addEventListener("click", () => {
  const blob = new Blob([JSON.stringify(state, null, 2)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = state.name.replace(/[^\w\-]+/g, "_") + "_" + today() + ".json";
  a.click();
  URL.revokeObjectURL(a.href);
});

const importFile = document.getElementById("importFile");
document.getElementById("importBtn").addEventListener("click", () => importFile.click());
importFile.addEventListener("change", () => {
  const file = importFile.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = JSON.parse(reader.result);
      if (!data || !Array.isArray(data.tasks)) throw new Error("champ 'tasks' manquant");
      if (!confirm(`Remplacer le projet actuel par « ${data.name || "Sans nom"} » (${data.tasks.length} tâches) ?`)) return;
      const validCols = COLUMNS.map(c => c.id);
      state = {
        name: data.name || "Projet importé",
        projects: Array.isArray(data.projects) ? data.projects.map(String).filter(Boolean) : [],
        notes: (Array.isArray(data.notes) ? data.notes : []).map(n => ({
          id: n.id || newId(),
          date: /^\d{4}-\d{2}-\d{2}$/.test(n.date || "") ? n.date : today(),
          project: String(n.project || ""),
          title: String(n.title || ""),
          participants: String(n.participants || ""),
          content: String(n.content || ""),
          createdAt: n.createdAt || new Date().toISOString(),
        })),
        tasks: data.tasks.map(t => ({
          id: t.id || newId(),
          title: String(t.title || "Sans titre"),
          description: String(t.description || ""),
          project: String(t.project || ""),
          priority: PRIORITY_LABEL[t.priority] ? t.priority : "moyenne",
          label: String(t.label || ""),
          due: /^\d{4}-\d{2}-\d{2}$/.test(t.due || "") ? t.due : "",
          column: validCols.includes(t.column) ? t.column : "backlog",
          createdAt: t.createdAt || new Date().toISOString(),
        })),
      };
      save(); render();
    } catch (err) {
      alert("Fichier JSON invalide : " + err.message);
    } finally {
      importFile.value = "";
    }
  };
  reader.readAsText(file);
});

// ---------------------------------------------------------------------------
// Export / import Excel (.xlsx) — les fonctions de lecture/écriture sont dans kanban-excel.js
//
// Import : fichier .xlsx (1re feuille) ou .csv. Les colonnes sont reconnues d'après leur titre
// (1re ligne), dans n'importe quel ordre : Projet, Titre, Description, Priorité, Étiquette,
// Échéance, Statut (et leurs variantes, voir CSV_FIELDS). Seul le titre est obligatoire.
// Les tâches importées s'AJOUTENT à celles du tableau.
// ---------------------------------------------------------------------------

// Export : les tâches du projet filtré (ou toutes avec « Tous les projets »)
document.getElementById("exportXlsxBtn").addEventListener("click", () => {
  const tasks = state.tasks.filter(inCurrentProject);
  const bytes = writeXlsx(tasksToRows(tasks), { sheetName: "Backlog", widths: [22, 40, 50, 11, 16, 12, 12] });
  const name = projectFilter && projectFilter !== NO_PROJECT ? projectFilter : state.name;
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([bytes], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }));
  a.download = name.replace(/[^\w\-]+/g, "_") + "_" + today() + ".xlsx";
  a.click();
  URL.revokeObjectURL(a.href);
});

const importXlsxFile = document.getElementById("importXlsxFile");
document.getElementById("importXlsxBtn").addEventListener("click", () => importXlsxFile.click());
importXlsxFile.addEventListener("change", async () => {
  const file = importXlsxFile.files[0];
  if (!file) return;
  try {
    const rows = await readSpreadsheet(await file.arrayBuffer());
    if (rows.length < 2) throw new Error("le fichier doit contenir une ligne de titres et au moins une tâche");
    const map = mapHeaders(rows[0]);
    if (!("title" in map)) {
      throw new Error("aucune colonne de titre trouvée (attendu : Titre, Tâche, Intitulé…).\n" +
        "Colonnes lues : " + rows[0].join(" | "));
    }

    // Sans colonne « Projet », toutes les lignes vont dans un même projet
    // (par défaut : le projet filtré, sinon le nom du fichier)
    let defaultProject = "";
    if (!("project" in map)) {
      const suggestion = projectFilter && projectFilter !== NO_PROJECT ? projectFilter : file.name.replace(/\.[^.]+$/, "");
      const answer = prompt("Pas de colonne « Projet » dans le fichier.\n" +
        "Nom du projet pour ces tâches (vide = aucun) :", suggestion);
      if (answer === null) return;                   // clic sur « Annuler »
      defaultProject = answer.trim();
    }

    const tasks = rowsToTasks(rows, map, defaultProject, newId);
    const found = CSV_FIELDS.filter(([f]) => f in map).map(([f]) => `${f} ← « ${rows[0][map[f]]} »`);
    if (!confirm(`${tasks.length} tâche(s) à ajouter au tableau.\n\nColonnes reconnues :\n${found.join("\n")}\n\nContinuer ?`)) return;
    state.tasks.push(...tasks);
    save(); render();
  } catch (err) {
    alert("Import impossible : " + err.message);
  } finally {
    importXlsxFile.value = "";
  }
});

render();
