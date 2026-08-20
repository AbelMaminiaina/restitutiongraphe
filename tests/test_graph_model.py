from pathlib import Path

import pytest

from restitution.models.graph import GraphModel


def test_from_file(tmp_path: Path) -> None:
    file = tmp_path / "graphe.txt"
    file.write_text(
        "NOEUDS\nA\nB\nC\nARETES\nA B\nB C\nA C\n",
        encoding="utf-8",
    )

    model = GraphModel.from_file(file)

    assert model.graph.is_directed()
    assert set(model.graph.nodes) == {"A", "B", "C"}
    assert set(model.graph.edges) == {("A", "B"), ("B", "C"), ("A", "C")}
    assert model.node_count == 3
    assert model.edge_count == 3


def test_from_text_rejects_empty_graph() -> None:
    with pytest.raises(ValueError):
        GraphModel.from_text("NOEUDS\nARETES\n")


def test_from_text_rejects_content_outside_section() -> None:
    with pytest.raises(ValueError):
        GraphModel.from_text("A B\n")
