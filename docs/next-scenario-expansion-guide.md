# VisionNavi Next Scenario Expansion Guide

## Purpose

This document defines when VisionNavi should expand beyond the current external-first baseline scenarios.

Current primary scenarios:

- `external_browser_agent`: `search_and_read`
- `external_desktop_agent`: `open_notepad_and_type`

Deferred scenarios:

- `find_map_route`
- broader third-party desktop app tasks

## Expansion Principle

New scenarios should move to external runtimes only after the current primary scenarios are repeatable, diagnosable, and benchmarked.

VisionNavi should avoid expanding scenario coverage based only on one-off successful demos.

## Readiness Criteria

### 1. Browser expansion readiness

`find_map_route` should be considered for external browser migration only when:

- browser benchmark success rate is stable across repeated runs
- failure reasons are taxonomy-friendly and traceable
- off-target navigation is rare
- output grounding is acceptable on real commands, not only canned examples

Suggested minimum gate:

- `search_and_read` success rate >= 0.8 across at least 10 runs
- no persistent blocker category dominating failures

### 2. Desktop expansion readiness

Third-party desktop tasks should be considered only when:

- `open_notepad_and_type` passes save verification repeatedly
- timeout and partial-completion failures are clearly classified
- raw and normalized trace are exportable for every run

Suggested minimum gate:

- `open_notepad_and_type` success rate >= 0.8 across at least 10 runs
- exact or acceptable text verification rate is stable

## What To Expand Next

Recommended order:

1. strengthen `search_and_read`
2. strengthen `open_notepad_and_type`
3. evaluate `find_map_route`
4. evaluate one additional third-party desktop app scenario

## Decision Table

| Scenario | Current owner | Move condition | Recommended next action |
|---|---|---|---|
| `search_and_read` | external | baseline scenario | keep benchmarking and improve grounding |
| `open_notepad_and_type` | external | baseline scenario | keep benchmarking and improve verification |
| `find_map_route` | internal | browser benchmark reaches repeatable stability | run external PoC after baseline passes |
| third-party desktop app | not started | desktop benchmark reaches repeatable stability | choose one concrete app and define a narrow PoC |

## Operational Rule

If a scenario is not yet benchmarked, it should not become the next external-first priority by default.

Benchmark first, then expand.
