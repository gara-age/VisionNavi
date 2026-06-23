# VisionNavi MVP Roadmap

## MVP Scope

The first usable milestone should prove the architecture, not full autonomy.

### Commands to Support

- Web search and read summary
- Open Notepad and type dictated text
- Switch Windows to dark mode

### Safety Boundaries

- `low`: auto-run allowed
- `medium`: confirm based on policy
- `high`: explicit approval required

### Milestones

1. `Foundation`
   - repository scaffold
   - shared contracts
   - FastAPI health endpoint
   - Flutter shell with command input surface
2. `Pipeline`
   - command normalizer
   - intent router
   - safety classifier
   - session event streaming
3. `Execution`
   - browser executor interface
   - desktop executor interface
   - stub observe/decide/act/verify/recover loop
4. `Demo Flows`
   - Naver search-and-read flow
   - Notepad writing flow
   - Windows dark mode flow
5. `Guardrails`
   - interrupt endpoint
   - confirmation policy
   - structured logs

## Definition of Done for MVP

- Text commands can enter the orchestrator from the frontend
- The orchestrator returns a canonical command and a routed task domain
- At least one browser flow and one desktop flow run through the same session pipeline
- The UI can display current phase, latest action, and final outcome
