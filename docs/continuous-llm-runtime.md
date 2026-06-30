# Continuous LLM-Guided Runtime Execution

## Background

VisionNavi is not intended to stop at classic JSON step automation.

The earlier automation model relied on a prebuilt step sequence from an upstream planner or LLM. That approach was easy to debug, but it was brittle when the live screen no longer matched the original plan.

The next iteration, inspired by the existing `C:\Navi` project, moved toward `Runtime Binding`:

- the upstream layer provides `intent`, `task_type`, and `slots`
- the local engine generates the executable action flow
- the binder chooses the concrete UI target at runtime using the latest snapshot
- recovery can happen locally without rebuilding the whole task from scratch

This was a meaningful improvement, but it still has practical limits. Rule-based binding, heuristic scoring, and local recovery remain weaker than a model that can keep interpreting the situation while the task is in progress.

## Problem Statement

Even a good Runtime Binding engine can still fail in cases where:

- the visible UI structure is valid but semantically ambiguous
- the right next target depends on current intent, not only on local candidate scores
- the task reaches an unexpected branch or intermediate state
- recovery requires reinterpreting what the user likely meant
- completion cannot be judged from one selector or one URL alone

In short, Runtime Binding is runtime-aware, but it is not yet fully situation-aware.

## Product Direction

The target direction for VisionNavi is `Continuous LLM-guided Runtime Execution`.

That means:

- the LLM does not only interpret the initial user request
- the LLM continues to help during execution
- the engine keeps collecting state, candidates, and evidence
- the next action can be revised using the latest runtime context
- recovery can use both deterministic rules and LLM-guided re-interpretation
- completion is judged from both deterministic signals and model-assisted interpretation

This is not a return to one-shot planning. It is a move toward a continuous decision loop.

## Evolution Stages

### 1. JSON Step Automation

- external system builds a low-level step sequence
- executor follows the sequence
- runtime only resolves targets

Strengths:

- clear behavior
- easy debugging
- high reproducibility

Weaknesses:

- brittle against UI changes
- poor recovery
- too much UI procedure logic must be authored up front

### 2. Runtime Binding Automation

- external system provides `intent`, `task_type`, and `slots`
- engine generates mid-level actions internally
- binder selects actual targets from the current snapshot
- recovery uses local policy and heuristics

Strengths:

- more flexible than fixed step plans
- better adaptation to live UI state
- closer to BrowserUse and ComputerUse style execution

Weaknesses:

- binder quality depends on scoring rules
- semantic ambiguity is still hard
- recovery remains limited by handcrafted policies

### 3. Continuous LLM-Guided Runtime Execution

- upstream layer still normalizes the request
- runtime engine still controls browser and desktop execution
- LLM continues helping with target choice, ambiguity resolution, recovery, and completion checks

Strengths:

- handles evolving state better
- supports more open-ended tasks
- more robust when rules alone are insufficient

Risks:

- model instability can introduce wrong actions
- tracing must explain why the model chose a target
- safety boundaries must remain code-enforced

## Core Design Principle

The goal is not to let the LLM perform every click directly.

The goal is to let the LLM participate in runtime decision-making until the task is complete, while code-based executors continue to own:

- browser and desktop control
- session continuity
- safety policy
- deterministic verification
- retry mechanics
- structured traces

This is a hybrid architecture, not a pure model-driven one.

## Role Split

### LLM Responsibilities

- interpret the user goal
- interpret the current screen state
- choose the most plausible next target from candidates
- explain ambiguous cases
- propose recovery paths when the current path stalls
- assist with completion judgment

### Engine Responsibilities

- collect DOM, UIA, screenshot, and candidate snapshots
- maintain browser and desktop sessions
- execute clicks, typing, waits, navigation, and reads
- enforce safety boundaries and confirmation policy
- verify observable outcomes
- store structured traces for debugging and review

## Runtime Loop

The target loop is:

1. `Observe`
   - gather current browser or desktop state
   - collect candidate targets
   - optionally attach screenshots or compact summaries
2. `Interpret`
   - ask the model what the current state means relative to the user goal
3. `Choose`
   - decide the next action and the best target
4. `Act`
   - execute through deterministic code paths
5. `Verify`
   - check whether the intended effect actually happened
6. `Recover`
   - when verification fails, retry locally or ask the model to re-evaluate

This loop continues until either:

- the goal is achieved
- the engine reaches a safe stop condition
- the system escalates for user confirmation

## Why This Is Different from JSON Step Planning

The critical difference is where intelligence lives.

In JSON step automation:

- most procedure logic is decided before execution

In Runtime Binding:

- some target choice happens during execution

In Continuous LLM-guided execution:

- runtime decisions can keep changing as the screen changes
- model assistance is available throughout the execution lifecycle
- the system does not depend on a single up-front plan staying correct

## Practical Implications for VisionNavi

The current VisionNavi implementation should keep moving away from:

- long one-shot action plans
- success criteria based only on single selectors
- growing collections of app-specific hardcoded step templates

And move toward:

- shorter decision cycles
- richer runtime observations
- target candidate ranking exposed to the LLM
- explicit recovery reasoning
- stronger task-level verification

## Trace Requirements

If the LLM remains involved until completion, the trace must show more than executed steps.

The trace should explain:

- what the system believed the goal was
- what the current screen state looked like
- which candidates were considered
- why one target was chosen
- why recovery was triggered
- why the task was judged complete or incomplete

This is essential for debugging open-source LLM behavior, especially when it makes surprising choices.

## Implementation Priorities

1. Strengthen runtime trace payloads
   - include observations, candidates, chosen targets, and recovery reasons
2. Reduce dependence on long one-shot planner output
   - prefer iterative decision loops where possible
3. Expand LLM runtime inputs
   - compact screen summaries, candidate inventories, and selective screenshots
4. Strengthen task-level verification
   - verify real outcomes, not only local UI interactions
5. Add LLM-guided recovery paths
   - use model assistance when deterministic recovery stalls

## Non-Goals

The direction is not:

- replacing all executors with free-form model control
- removing deterministic logic
- eliminating guardrails in favor of model autonomy

The direction is:

- deterministic execution
- runtime state awareness
- continuous model-assisted decision-making

## Summary

VisionNavi should be understood as evolving through three stages:

- past: `prebuilt JSON step execution`
- intermediate: `Runtime Binding with engine-owned target selection`
- target: `Continuous LLM-guided Runtime Execution`

The strategic shift is from:

- "the model writes the procedure"

to:

- "the engine executes safely while the model keeps helping interpret the situation until the task is complete"

For concrete implementation steps in the current repository, see [continuous-llm-runtime-roadmap.md](/C:/Users/USER/Documents/VisionNavi/docs/continuous-llm-runtime-roadmap.md).
