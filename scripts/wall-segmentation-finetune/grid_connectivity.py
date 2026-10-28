from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from math import isfinite
from typing import Sequence


@dataclass(frozen=True)
class ConnectivityGrid:
    columns: int
    rows: int
    blocked: tuple[bool, ...]
    labels: tuple[int, ...]
    component_sizes: tuple[int, ...]
    largest_label: int
    significant_labels: frozenset[int]

    @property
    def blocked_ratio(self) -> float:
        return sum(self.blocked) / len(self.blocked)

    @property
    def largest_free_ratio(self) -> float:
        total = sum(self.component_sizes)
        if total == 0 or self.largest_label < 0:
            return 0.0
        return self.component_sizes[self.largest_label] / total

    @property
    def disconnected_free_ratio(self) -> float:
        total = sum(self.component_sizes)
        if total == 0:
            return 0.0
        disconnected = sum(
            self.component_sizes[label]
            for label in self.significant_labels
            if label != self.largest_label
        )
        return disconnected / total


def sample_blocked_grid(
    probabilities: Sequence[float],
    source_width: int,
    source_height: int,
    threshold: float,
    cell_size: int = 2,
) -> tuple[int, int, tuple[bool, ...]]:
    if (
        source_width <= 0
        or source_height <= 0
        or len(probabilities) != source_width * source_height
        or cell_size <= 0
        or not isfinite(threshold)
        or not 0 <= threshold <= 1
    ):
        raise ValueError("invalid probability grid arguments")
    columns = source_width // cell_size
    rows = source_height // cell_size
    if columns <= 0 or rows <= 0:
        raise ValueError("source image is smaller than one grid cell")

    blocked: list[bool] = []
    offset = cell_size // 2
    for row in range(rows):
        source_y = min(source_height - 1, row * cell_size + offset)
        for column in range(columns):
            source_x = min(source_width - 1, column * cell_size + offset)
            value = float(probabilities[source_y * source_width + source_x])
            if not isfinite(value):
                raise ValueError("probability grid contains a non-finite value")
            blocked.append(value >= threshold)
    return columns, rows, tuple(blocked)


def analyze_connectivity(
    blocked: Sequence[bool],
    columns: int,
    rows: int,
    significant_minimum: int | None = None,
) -> ConnectivityGrid:
    if columns <= 0 or rows <= 0 or len(blocked) != columns * rows:
        raise ValueError("invalid blocked grid dimensions")
    minimum = (
        max(50, len(blocked) // 1_000)
        if significant_minimum is None
        else significant_minimum
    )
    if minimum <= 0:
        raise ValueError("significant minimum must be positive")

    labels = [-1] * len(blocked)
    component_sizes: list[int] = []
    for start in range(len(blocked)):
        if blocked[start] or labels[start] != -1:
            continue
        label = len(component_sizes)
        queue = deque([start])
        labels[start] = label
        size = 0
        while queue:
            index = queue.popleft()
            size += 1
            x = index % columns
            y = index // columns
            for neighbor_x, neighbor_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if not (0 <= neighbor_x < columns and 0 <= neighbor_y < rows):
                    continue
                neighbor = neighbor_y * columns + neighbor_x
                if blocked[neighbor] or labels[neighbor] != -1:
                    continue
                labels[neighbor] = label
                queue.append(neighbor)
        component_sizes.append(size)

    largest_label = (
        max(range(len(component_sizes)), key=component_sizes.__getitem__)
        if component_sizes
        else -1
    )
    significant_labels = frozenset(
        label for label, size in enumerate(component_sizes) if size >= minimum
    )
    return ConnectivityGrid(
        columns=columns,
        rows=rows,
        blocked=tuple(bool(value) for value in blocked),
        labels=tuple(labels),
        component_sizes=tuple(component_sizes),
        largest_label=largest_label,
        significant_labels=significant_labels,
    )


def grid_connectivity(
    probabilities: Sequence[float],
    source_width: int,
    source_height: int,
    threshold: float,
    cell_size: int = 2,
    significant_minimum: int | None = None,
) -> ConnectivityGrid:
    columns, rows, blocked = sample_blocked_grid(
        probabilities,
        source_width,
        source_height,
        threshold,
        cell_size,
    )
    return analyze_connectivity(
        blocked,
        columns,
        rows,
        significant_minimum,
    )
