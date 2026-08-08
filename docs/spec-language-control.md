# Spec — language as a per-take control

## The problem

Modes are **actions**: Dictation, Email, Rewrite, Assistant. Language is a
**property of the take**. Today language lives only inside mode configuration,
which conflates the two axes and has three consequences:

1. Changing language means opening the mode editor. Nobody does that mid-flow,
   so in practice people have one language.
2. It multiplies badly. Hindi × five actions is five more modes.
3. It produced the Hinglish mode, which exists partly to carry a language rather
   than because "Hinglish" is a distinct action.

## Where it plugs in

One function decides the language for every take, for every recorder style and
every model, local or cloud:

```swift
// ModeRuntimeConfiguration.transcriptionRuntimeConfiguration(from:)
let language = TranscriptionLanguageSupport.validLanguageOrFallback(
    mode.selectedLanguage,           // ← the only input today
    for: model,
    realtimeEnabled: mode.isRealtimeTranscriptionEnabled
)
```

A session override consulted here is the entire mechanism. Nothing else in the
pipeline needs to change.

```swift
let language = TranscriptionLanguageSupport.validLanguageOrFallback(
    LanguageSession.shared.override ?? mode.selectedLanguage,
    for: model,
    realtimeEnabled: mode.isRealtimeTranscriptionEnabled
)
```

## Behaviour

### Precedence

```
session override  →  mode's language  →  model's fallback (auto, then en)
```

The mode keeps its language as a **default**, not a lock. Setting a mode to
Hindi still means "this mode is usually Hindi"; the panel says "but not this
time" without editing anything.

### Stickiness — recommended: sticky until changed

People work in one language for a stretch, then switch. A per-take reset would
mean re-picking every single take, which is the friction this is meant to
remove. Sticky within a session, cleared on quit.

Rejected: persisting across launches. A language chosen once and silently still
active a week later is the same class of bug as the mode/model mismatch that
started this — state you cannot see governing what happens.

### Auto-detect

`auto` stays a first-class choice and remains the default. Worth stating a limit
honestly: for code-switched speech, auto frequently settles on English and then
transcribes the other half phonetically. Auto is right for "I speak one language
but it varies"; it is wrong for Hinglish, which is why that mode pins Hindi.

### When the model cannot do the language

The current behaviour is `validLanguageOrFallback`, which **silently** falls back
to auto or English. That silence is exactly what made "VoiceInk has no Hindi"
look true when the real answer was "Parakeet has no Hindi".

Proposed: unsupported languages still appear in the panel picker, disabled, with
the reason and the model that would work. Choosing a language your model cannot
do should never quietly transcribe in a different one.

## Which languages appear

Whisper exposes 99. A picker listing all of them in a floating panel is unusable,
and a hand-curated shortlist in Settings is a chore nobody completes.

Proposed: **learned recents.** The panel shows `Auto` plus the last 3–4 languages
actually used, most recent first, and a `More…` entry opening the full searchable
list. Ordering by use means the list is correct for the user by the second week
without anyone configuring anything.

## Placement

The ambient control strip already carries mode chips, clock, Enhanced/Raw and
Cancel. Adding a permanent language chip makes a long row longer.

Proposed: the language chip appears **only when it is not `auto`**, or when more
than one language has been used. A monolingual user never sees it; a bilingual
one always does. Same rule for mini and notch.

## What happens to the Hinglish mode

It stays, because romanizing Devanagari output *is* an action — the prompt is
doing real work that no language setting can do.

What changes is why it exists. Today it exists partly to carry `hi`. After this,
the language is incidental: it is the mode's default, overridable from the panel
like any other. The mode is "write my mixed speech as romanized Hinglish", which
is a genuine action and belongs in the list.

## Out of scope

- Per-app language rules. Modes already have app triggers; language could ride
  on those later, but it is a separate feature.
- Translation. Choosing a language selects what is *heard*, never what is
  written out in another tongue.
- App UI localisation, which is `AppLanguagePreference` and unrelated.

## Testable behaviour

The arithmetic-free parts still have edges worth pinning:

- Precedence: override beats mode, mode beats fallback.
- An override the model cannot honour never silently becomes a different
  language.
- Recents order by last use, cap at their limit, and never list `auto` twice.
- The override clears on quit and does not survive into the next launch.
