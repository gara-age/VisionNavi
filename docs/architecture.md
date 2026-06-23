# VisionNavi Architecture

## Intent

VisionNavi moves from a single planner pipeline to a stateful hybrid agent that observes the current browser or desktop UI before choosing the next action.

## Design Principles

- `vision-first`: screen state is the primary source of truth for planning
- `semantics-assisted`: DOM, UIA, roles, labels, and accessibility trees provide supporting context
- `deterministic-execution`: Playwright and UIA-style tools are preferred when available
- `fallback-aware`: vision click or coordinate automation fills gaps when structure is missing

## System Layers

### Frontend

- Flutter desktop shell
- Voice/text input
- Session timeline
- User confirmations and stop controls
- TTS feedback

### Local Orchestrator

- FastAPI application
- Session lifecycle management
- WebSocket event streaming
- Command normalization
- Intent routing and safety classification

### Agent Loop

- `Observe`: gather browser state, desktop state, screenshots, and semantics
- `Decide`: choose the next action based on the latest observation
- `Act`: route to browser or desktop executor
- `Verify`: check DOM, URL, screenshot, UI state, or file effects
- `Recover`: choose a fallback strategy when verification fails

### Execution Layers

- Browser: Playwright first, Stagehand-assisted exploration when needed
- Desktop: UIA/pywinauto first, vision-capable executor second, coordinate fallback last

## Shared Contract

The core handoff between intake and execution is the canonical command object in [contracts/canonical_command.schema.json](/C:/Users/USER/Documents/VisionNavi/contracts/canonical_command.schema.json).

## Initial Module Boundaries

```text
frontend/
orchestrator/app/
  agent/
  api/
  automation/
    browser/
    desktop/
  core/
  models/
  services/
contracts/
docs/
```

## Near-Term Build Order

1. Stabilize the canonical command and session event contracts
2. Implement intake pipeline: normalize, route, classify
3. Add a stub agent loop with deterministic browser and desktop actions
4. Wire frontend status panels to orchestrator WebSocket events
5. Add verification and interrupt handling before advanced fallbacks
