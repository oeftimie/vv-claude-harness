# Ovidiu's Claude Code harness 
This is my harness system for Claude Code, a combination between Anthropic's guidelines of long running tasks and the implementation of the [Manus style persistent markdown planning](https://github.com/OthmanAdi/planning-with-files) 


Every AI coding agent has the same Achilles heel: memory. Not the technical kind (context windows are growing). The practical kind. Start a complex project with Claude Code or Cursor. Work for an hour. Hit a context limit or close the session. Come back the next day. The agent has no idea what happened. It's like onboarding a new contractor every morning who's never seen the codebase.

This isn't a model problem. It's an infrastructure .. "harness"... problem. And solving it requires thinking about agents less like chat interfaces and more like software systems that need state management.

## The shift problem
Anthropic's engineering team articulated this beautifully in their [research on effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): imagine a software project staffed by engineers working in shifts, where each new engineer arrives with no memory of what happened on the previous shift. That's exactly what happens with AI agents across context windows. Session ends. Context compacts or resets. New session starts fresh. The agent might have access to the files it created, but it has no memory of why it created them, what worked, what failed, or what comes next.

Two failure patterns emerge consistently:
* First, the agent tries to do too much in a single session; it "one-shots" the entire project, runs out of context mid-implementation, and leaves a half-built mess for the next session to puzzle over. 
* Second (and more insidious), after making some progress, the agent looks around, sees working code, and declares victory. The project is 30% complete but the agent thinks it's done.
Both failures stem from the same root cause: no persistent memory of intent, progress, or remaining work.

## Two solutions, one insight
Two independent approaches emerged to solve this problem, and they converged on the same fundamental insight.

Anthropic's research proposed a two-phase architecture: 
1. an initializer agent that runs in the first session and sets up scaffolding, followed by 
2. coding agents that make incremental progress in subsequent sessions. 

The key innovation was externalizing state into files that persist between sessions:
* a `features.json` file tracks what needs to be built (and what's done). 
* a `claude-progress.txt` file logs what each session accomplished. The coding agent reads these files at the start of every session, orients itself, picks up where the last session left off.

Almost in the same time, the Manus team (before their $2B acquisition by Meta) discovered the same principle through production experience. They distilled it into what the community now calls the "planning-with-files" pattern. Their insight: the context window is RAM; the filesystem is disk. Anything important gets written to disk.

Manus uses three files for every complex task: `task_plan.md` (phases and progress), `findings.md` (research and discoveries), and `progress.md` (session logs and test results). The agent re-reads the plan before major decisions. It writes findings immediately rather than holding them in context. It logs errors so it doesn't repeat them.

Same problem. Same solution. Different vocabulary.

## Why files, not memory systems?
You might wonder: why markdown files? Why not Jira, Github issues, vector databases, RAG pipelines, or proper memory systems?
Three reasons:
* *Simplicity* : files require no infrastructure and no assumptions.The agent writes. The agent reads. Done.
* *Transparency* : When an agent goes off the rails, you can open `task_plan.md` and see exactly what it thinks it's doing. Can;t really debug a vector database when an agent starts hallucinating. Files are inspectable, editable, and version-controlled.
* *Structure* : Anthropic specifically chose JSON for their features file because, [as they noted](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), "the model is less likely to inappropriately change or overwrite JSON files compared to Markdown files." Structured formats create implicit contracts. The agent knows that `passes: false` means work remains. It knows not to delete entries. The file format itself enforces discipline.

## The combined harness
Building on both approaches, I have build a combined harness for long-running projects using these four components:
1. *Initializer* . The initialization phase runs once, at project start. It doesn't write code. It creates scaffolding: a feature list expanded from your high-level prompt, a progress log initialized for tracking, a context file capturing decisions and constraints, and a build script that verifies the environment works. The initializer's job is to transform "build me an app" into a structured work breakdown that subsequent sessions can execute against.

2. *Session protocol* .  I need to mention here first, that the main Claude instance that I start for a project does not write code : it accts as an orchestrator for all the coding agents I mention below. The session protocol runs at the start of every subsequent session. A "subsequent session" is a session that Claude starts when it needs to work on a feature. The harness provides the standard structure in which all subagents start theuir work. This makes the execution of the subagents predicatable in terms of input and expected output. So when the session protocol is triggered, the coding agent reads the progress log ("what happened?"), checks the feature list ("what's left?"), runs the build script ("does it still work?"), and reads the context file ("what should I remember?"). Only then does it start coding with the specific prompt given by Claude.  At *the agent's session end*, it commits progress, updates the feature list, appends to the progress log, and ensures the build still passes - a clean handoff exactly as specified in the defined structure.

The single-feature rule that Claude prompts the subagent with, prevents one-shotting. Each session works on exactly one feature. Not two. Not "as many as I can.". This forces incremental progress. The agent can't exhaust context trying to build everything at once because the harness explicitly forbids it, thus using each subagent context and optimizing the context use of the orchestrator.

End-to-end verification prevents premature victory. The agent can't mark a feature complete just because it wrote the code. It has to actually test it. Not unit tests alone (they can pass while the feature is broken). Not manual inspection (the agent can convince itself anything works). Real end-to-end verification that proves the feature actually functions.

## The init.sh script
I initialy started my exploration with building iOS apps- now at the second iteration with this harness, I adapted it to be used for multiple programming languages. Every session starts by running `init.sh`, which installs dependencies, builds the project, and runs a smoke test. If `init.sh` fails, the agent fixes it before doing anything else.  

This seems minor but it's load-bearing. Without it, agents accumulate subtle environment drift across sessions. Dependencies get out of sync. Build configurations rot. The agent starts a session, tries to work, hits a mysterious failure, spends half its context debugging something that has nothing to do with the feature it's supposed to build.

For multi-language projects (iOS app with a Node backend, say), the script auto-detects or reads from a config file:

```json
{
  "stacks": [
    {"name": "ios", "path": "./", "scheme": "MyApp"},
    {"name": "node", "path": "./backend"}
  ]
}
```

Each stack gets its own initialization. If any fails, the session stops and fixes before proceeding.

## Why I think this combination works - 

The Anthropic approach and the Manus approach complement each other precisely because they solve different parts of the problem.
Anthropic's two-phase architecture solves the macro problem: how do you structure work across many sessions? You need an initializer that creates the structure. You need coding agents that follow the structure. You need artifacts that bridge sessions.
The Manus planning-with-files pattern solves the micro problem: how does an agent stay focused within a session? You externalize findings instead of stuffing context. You re-read the plan before decisions. You log errors to avoid repetition.

Putting them together: the initializer creates `features.json` (Anthropic pattern) and `task_plan.md` (Manus pattern). The coding agent reads `claude-progress.txt` (Anthropic pattern) and writes to `findings.md` (Manus pattern). The session protocol ensures clean handoffs (Anthropic pattern) while the 2-action rule ensures the agent doesn't lose important context mid-session (Manus pattern).

The filesystem becomes the connective tissue. Not because files are the optimal data structure for agent memory (they're not), but because they're the optimal trade-off between simplicity, transparency, and effectiveness. We can always build something more sophisticated later, but this works today, and during my break I alreayd pushed one MacOs app - [Lan Lens](https://apps.apple.com/us/app/lanlensapp/id6757317898?mt=12) and one iOS one [NOTAM App](https://apps.apple.com/us/app/notams-app/id6757545391) to the Apple AppStore.  

## What remains unsolved

This harness addresses the core challenge of multi-session continuity, but several questions remain open.
* Should you use one general-purpose agent or specialized agents (testing agent, documentation agent, cleanup agent)? Anthropic notes they haven't determined which approach works better. Specialization might improve quality but adds coordination overhead. I nitially started personifying my agents, and building them with specific Claude skills. However, I realized, that no matter how exhaustive my prompt was to create a specific agent or skill it could never match the exact problem I would try to solve. So i ended up using very few named agents, and basically rely on Claude to prompt an agent with exacly the capabilities it needed to work on a feature or solve an issue. 
  

* How do these patterns generalize beyond coding? Anthropic suggests the lessons likely apply to scientific research, financial modeling, and other long-running tasks. But the specifics (what's the equivalent of `features.json` for a research project?) remain to be worked out - I still need to research

* What's the right granularity for features? Too coarse and you're back to one-shotting. Too fine and you spend all your time on coordination overhead. The sweet spot probably varies by project and I'm looking at folks to explore and let me know

## Getting started
Everything you need is in this repo, including my [Claude.md](https://github.com/oeftimie/vv-claude-harness/blob/main/CLAUDE.md) 

### Some screenshots from my sessions
<img width="1248" height="1076" alt="Screenshot 2026-01-09 at 12 47 25" src="https://github.com/user-attachments/assets/25b4be66-c384-4225-92a6-cd4d2c8964a8" />
<img width="849" height="766" alt="Screenshot 2026-01-09 at 12 42 01" src="https://github.com/user-attachments/assets/031c3dfb-4a35-4b6b-bac9-200049c7ee28" />


### UI test automation with XCode & Claude Code
https://github.com/user-attachments/assets/9684d120-3cbf-438d-a01f-469387f507ff


---
