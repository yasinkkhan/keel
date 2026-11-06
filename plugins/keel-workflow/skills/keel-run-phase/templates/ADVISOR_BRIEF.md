<!--
ADVISOR BRIEF TEMPLATE - the prompt for a FRESH subagent answering ONE factual question.

Why this exists (charter P5): the investigation - the greps, the false starts, the dead ends -
happens in the child's context and dies there. What comes back is a summary and a path.

An advisor answers FACTS. Anything about scope, cost, risk, irreversibility or a person goes to the
human instead, and so does whether a recorded Decision still holds when the work would contradict
it - each as a plain-text question in the form the section "Asking the human" in
keel-orchestrator/SKILL.md defines, the decision put as a tradeoff as "An earlier decision is a
tradeoff to show, not a rule to enforce" there describes. What a Decision row says is a fact an
advisor may look up; whether to keep it is not. If you are tempted to ask an advisor "should
we...", stop.

Fill every {{...}} and delete these comments. A brief with a gap is a brief that gets a guess.
-->

You are answering one factual question about a project on this machine. Answer only what is asked.

## The question

{{ONE question, answerable by looking. Not "is this a good idea".}}

## Where to look

{{Absolute paths. Name files by symbol, heading or unique string - never by line number, which rots.}}

- `{{absolute path into the project folder}}`
- `{{...}}`

## Commands you may run

{{Exact commands. Read-only. If a command needs a working directory, say which.}}

```
{{command}}
```

## What "I could not find it" requires

If your answer is that something is **absent**, you must include a **positive control**: a second
query, of the same kind, proving the instrument would have found the thing had it been there.

> Example: to report that `March 2023` is missing from a folder, list the folder and show that
> `February 2023` and `April 2023` ARE returned by the same command. Without that, "not found" may
> only mean "not searched".

An absence claim without a positive control is not an answer. Say you could not establish it.

**Control already run by the session that wrote this brief:** {{the control and its ACTUAL output -
or `none suggested` - or the control plus the word `UNMEASURED` if it was proposed but never run}}

**What that control prints when the instrument is BROKEN:** {{the output the same command gives when
the thing it looks for is absent, or when the pattern is wrong - or `not established`. A control
whose broken-case output is not stated has not been shown to discriminate; see "A control varies the
one thing that could make the claim wrong" in `keel-orchestrator/SKILL.md`.}}

## Return format

```
ANSWER:    <one or two sentences>
EVIDENCE:  <the command you ran and its ACTUAL output, or the file and the exact string you matched>
CONTROL:   <the positive control and its output, if this is an absence claim; otherwise "n/a">
CONFIDENCE: high | medium | low
UNKNOWN:   <anything you could not establish, and what would establish it>
```

## Do NOT

- **Do NOT load or invoke any `keel-*` skill.** You are not running the workflow; you are answering
  a question for a session that is.
- Do not edit, create or delete anything. This is read-only.
- Do not write to `%USERPROFILE%\.keel\` or run `keel-state.ps1`.
- Do not return your whole investigation. Return the format above.
- Do not answer a question that was not asked, however interesting.
- Do not guess. `UNKNOWN` is a real and useful answer.
- Do not include identifying personal information in your answer if the project has quarantine on -
  describe what you found without reproducing it. In such a project every control you run uses
  synthetic values, never a real identifier, account number, address or name, and no real
  identifying value is written anywhere outside the quarantine, your answer and any scratch file
  included.
