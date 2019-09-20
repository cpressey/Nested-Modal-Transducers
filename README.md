Nested Modal Transducers
========================

*Final draft*

An experiment in reactive framework design that tries to answer the question:
What happens if you take [UML state machines][] and make them
purely functional by following [The Elm Architecture][]?

We call the resulting construction a _nested modal transducer assemblage_.

The term "transducer" is adopted from automata theory and is basically
unrelated to [transducers in Clojure][] or [SRFI-171][];
"nested" stresses embedding one transducer in another, as opposed to
feeding the output of one transducer into the input of another; and
"modal" stresses that each transducer is, like a state machine, in exactly
one of a finite number of control states at any given time.

Code samples in this document are given in a purely functional pseudocode.
Runnable code for these examples can be found in the accompanying source
files:

*   Haskell: [NestedModalTransducers.hs](NestedModalTransducers.hs)
*   Scheme: [nested-modal-transducers.scm](nested-modal-transducers.scm)

Note: this repository contains only a description of the theoretical
framework.  Applications of the framework, should they ever come to pass,
will be listed in the [Related resources](#related-resources) section below.

Enriched state machines
-----------------------

I was thinking about ways to model a certain class of reactive systems
[(Footnote 1)](#footnote-1)
and I concluded that the most appropriate model was a state machine
extended with the following four properties:

*   The machine must keep track of more state than just the
    finite "control state" that the machine is in.  This additional
    state is unbounded rather than finite, and it can affect how the
    machine transitions.
*   It must be possible to arrange machines in a hierarchy, where a
    single state of an outer machine can contain multiple states of an
    inner machine.
*   It must be possible to define arrays of machines which transition
    independently: a single outer state might contain, not just a single
    inner machine, but a *set* of inner machines.
*   While an inner machine is primarily responsible for its own operation,
    the machine it is contained in should be able to oversee and manage
    its operation as necessary.

I'm not a huge fan of UML, but [UML state machines][] (descending, as
they do, from [Statecharts][]) turn out to have exactly the first three properties,
which they call
["extended state"](https://en.wikipedia.org/wiki/UML_state_machine#Extended_states),
["hierarchically nested states"](https://en.wikipedia.org/wiki/UML_state_machine#Hierarchically_nested_states) and
["orthogonal regions"](https://en.wikipedia.org/wiki/UML_state_machine#Orthogonal_regions)
respectively.

UML provides some tools to address the fourth property, notably "entry and exit actions",
which have been compared to constructors and destructors in object-oriented
programming.  You could think of this as [RAII][] for states: sensible
entry and exit actions allow sensible transitions between inner states, even
when they are deeply nested in different parts of an outer state machine.

But the facilities provided by UML for this purpose do have limitations.
The root condition here is that UML state machines inhabit an imperative,
effectful paradigm: just about _anything_ can trigger arbitrary
"actions" which do not have limits to their scope.  So the transitioning
of an inner machine may cause side-effects, and there is nothing the containing
machine can do about this.

In addition, for my purposes, I wanted a theoretical framework that
would make reasoning about these reactive systems as tractable as possible.
[(Footnote 2)](#footnote-2)

So, suppose UML's actions were _not_ unrestricted effects, but instead were symbolic
values, intended to be passed around during evaluation, only to be translated into
effects at some later point.

This would allow both things: it would let these hierarchical assemblages of
state machines be expressed in a purely functional manner, and it would permit
management of inner machines by outer machines, in the following way:
the inner machine can no longer execute arbitrary actions itself —
it must return them to the outer machine, which gets a chance to veto or
modify them before they are actually executed.

So, the challenge here is to make something that, if not equivalent to UML state
machines in their entirety, addresses the above four properties at least as
satisfactorily as UML state machines do, and is purely functional.

Purely functional transducers
-----------------------------

In [Redux][], your application's logic resides in pure functions which have
the type

> _f_ : S × A → S

where S is the countable set of _states_ that your application can take on,
and A is the countable set of _actions_ it can respond to.
The actions are just inert symbolic descriptions of actions; they
don't contain any logic themselves.

Meanwhile, in [The Elm Architecture][] (or [redux-loop][]) you can
write pure functions of the type

> _f_ : S × A → S × C

where C is the countable set of _commands_ that your application can issue.
In the same vein as the actions, these commands are just inert symbolic
descriptions of effects.  Some interpreting step that comes after evaluating
the function must enact those effects.

The first type of function is called a [reducer][] because,
according to [the Redux docs](https://redux.js.org/basics/reducers#handling-actions),
"it's the type of function you would pass to
[Array.prototype.reduce(reducer, ?initialValue)](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/Reduce)."
So there is a whole [theory and practice of folds][] that can be drawn on when working with reducers.
Indeed, you can think of a reducer as a fold over a lazy list of events —
the events that are currently happening.

The reducer concept also corresponds extremely well to the _transition function_
of various formal automata.  The [semiautomaton][] is
the most general example, but it is also easy to see how one
could write a [finite automaton][] or a [push-down automaton][]
as a reducer (even though these automata are not often employed
in a "reactive" setting).

These are all automata that, like reducers, do not produce outputs or have
effects of any kind.  An automaton that *does* produce outputs is
called a [transducer][].  Specific kinds of transducers include
[Moore machines][] and [Mealy machines][].

The second type of function above (the one from Elm) maps well to the transition function
of a generalized transducer.  The main difference is that,
in automata theory, the outputs of a transducer are often thought of as directly effectful:
signals sent to other devices, for example.  But here, they are merely
symbolic descriptions of effects — values that something else will observe and
execute later on.

### Note on terminology

For brevity, we will call the transition functions of transducers,
also _transducers_, where there is no danger of ambiguity.  To avoid
the clash between "actions" in Redux and "actions" in UML state machines,
we will stick to the terminology used for transducers: things that
go into a transducer are called its _inputs_, and things that come out
of a transducer are called its _outputs_.  Our outputs will be values
which describe effects, but we'll avoid calling them "effects"
because they are not the effects themselves.  ("Command" might be okay,
because it's used in Elm and it evokes the [command pattern][], which
is relevant; but for consistency we'll avoid it too.)

Also, it will be useful (for reasons explained below) to think of
any given transducer as producing a _list_ of outputs.  Such a list may be empty.
The signature of our transducers can now be written as:

> _f_ : S × I → S × [O]

### Example

As a contrived example, suppose we have a light switch that
rings a bell as a side-effect when you turn it on.

    lightTransducer mode input =
        case (mode, input) of
            (On, TurnOff) ->
                (Off, [])
            (Off, TurnOn) ->
                (On, [RingBell])
            _ ->
                (mode, [])

As a way to test this, you might want to run it on a list of inputs,
to obtain a final state and a list of outputs.

    rehearse transducer state [] = (state, [])
    rehearse transducer state (input:inputs) =
        let
            (state', outputs) = transducer state input
            (state'', outputs') = rehearse transducer state' inputs
        in
            (state'', outputs ++ outputs')

You would then expect that, for example,

    rehearse (lightTransducer) Off [TurnOn, TurnOff, TurnOn, TurnOff] =
        (Off, [RingBell, RingBell])

In a practical setting though, you probably want this to be "reactive",
in that you want to consume inputs when they are received, and enact
effects when they are produced.  You would have some top-level driver
code for that, and it might look like:

    reactWith transducer state =
        let
            input = waitForInput
            (state', outputs) = transducer state input
            _ = enactEffects outputs
        in
            reactWith transducer state'

Combining purely functional transducers
---------------------------------------

Redux provides ways to combine reducers, and advocates that you
combine reducers hierarchically until your entire application
is, at its core, one big reducer.

Redux defines a standard way to combine multiple reducers into a single
reducer. This standard way is not the only way to compose reducers,
and in many contexts it is probably not the "best" way either, but it
establishes a pattern and a practice.

The analogous thing here is combining transducers.  But there is an
important difference from reducers: insofar as the order of effects
matters, the order of outputs matters too, so the order in which
transducers are combined matters. [(Footnote 3)](#footnote-3)
This is the reason why we defined our transducers as producing lists
of outputs: lists already capture this ordering property.
The empty list is also useful for indicating that a transducer did
not produce any output.

The transducer equivalent of Redux's `combineReducers` can be written:

    combineTransducers tA tB = tC where
        tC (stateA, stateB) input =
            let
                (stateA', outputsA) = tA stateA input
                (stateB', outputsB) = tB stateB input
                outputsC = outputsA ++ outputsB
            in
                ((stateA', stateB'), outputsC)

In Redux, the resulting combined state is a Javascript object, so the
order of the keys doesn't matter.  Here, since order does matter,
our combined state is an ordered pair of the constituent states.

Combining transducers, in this manner and in other manners, lets us
form purely functional assemblages of transducers.

Implementing enriched state machines with purely functional transducers
-----------------------------------------------------------------------

So now we try to capture the four properties in the first section
with the tools of the second section.

### Extended state

This part is easy; in the functional theory that we've brought over from
Redux, S is an arbitrary countable set, so we can stick whatever we want in
there.  [(Footnote 4)](#footnote-4)

Actually, the part we should be concerned about is the other way around:
we want these transducers to behave, at their core, like traditional
state machines.  We don't want to abandon the fundamental idea of the
machine being in one of a finite number of states at any given time;
it's useful.

So we say that S is divided into a finite number of partitions,
which correspond to the "control states" of the machine — the values the
so-called "state variable" is allowed to take on.

In practice, S would typically be some kind of record type, and the
"state variable" would be a field of that record, of "enum" type
(or some moral equivalent thereof).

This highlights a terminological problem that we should address before
it becomes serious.  As soon as you add "extended state" to a state
machine, the word "state" becomes ambiguous.  When you say "state", do you
mean the finite (and qualitative) "state variable", the unbounded (and quantitative)
"extended state", or the state of the entire machine, taken as a whole?

For the current work, we will call this finite set of partitions of S,
the _modes_ of the transducer.  At any given time, the transducer is in exactly
one of these modes, and we will call that the _current mode_ (or just the _mode_ if
the context is clear).   What UML calls the "extended state", we will call
the _data_ of the transducer; and the state of the whole thing
(mode and data together) we will call the _configuration_ of the transducer.
[(Footnote 5)](#footnote-5)

In this way we can, in fact, completely avoid using the word "state" if we like.
We might not go that far, because sometimes it is evokative, but we will go in
this direction.  One concrete step in this direction is that, instead of
"state machines", we will talk about "modal transducers".  Another concrete step
is that the (nominal) datatypes that our example transducers will work with
will no longer be "state"s, but rather "config"s.

Here we modify the previous example of the light, to make it record
the number of times it was turned on:

    countingLightTransducer config input =
        case (config.mode, input) of
            (On, TurnOff) ->
                ({mode:Off, data:config.data}, [])
            (Off, TurnOn) ->
                ({mode:On, data:config.data+1}, [RingBell])
            _ ->
                (config, [])

### Hierarchically nested states

We can implement UML's hierarchically nested states by embedding the transition
function of the inner transducer within the transition function of
the outer transducer, and at the same time embedding the
configuration of the inner transducer within the configuration of the outer transducer
(specifically, in its data).

In more explicit terms, call the inner transducer tI and the outer
transducer tO.  tI has a configuration cI made up of mode mI and data dI;
tO has configuration cO made up of mode mO and data dO.  Now we can say:
A description of cI is embedded in some manner in dO, and
we can think of this embedding as a pair of functions:

> _extractInner_ : cO → cI  
> _embedInner_ : cO × cI → cO′

These have the usual form of "get" and "put" operations on a data
structure in a purely functional language.  Embedding cI in cO results
in a new cO′, but extracting cI from cO leaves cO unchanged.

In practical terms, you can think of both cI and cO as some kind of
record types (comprising mI and dI, and mO and dO, respectively),
and one field of the dO record will be able to hold a cI record.

One important thing to remember is that tI is entirely contained within tO,
so it is the responsibility of tO to transition the
embedded tI as well.  That is, somewhere in the definition of the function tO
is an application of the function tI.

Typically tO will only transition tI when mO is a particular mode, however
there is no strict requirement for that restriction.  (Departing from it
corresponds to "overlapping states" in the [Statecharts][] formalism.)

To spell out how tO would typically manage the transition of tI:

*   tO provides an input for tI (perhaps the same input tO received)
*   tO decodes tI's configuration (cI) from its own data (dO)
*   tO enacts the transition of tI (i.e. inside the transition function tO,
    the transition function tI is applied to the input for tI and the
    extracted configuration cI)
*   tO encodes tI's new configuration cI′ back into its own data (resulting in a new
    data dO′ for itself, which is part of its new configuration, cO′)
*   tO transitions itself based on its own configuration "as usual" (but we
    note that the new cI′ is also available to it for making this transition)

In pseudocode,

    outerTransducer outerConfig input =
        case (outerConfig.mode, input) of
             ...
             (ContainingMode, _) ->
                 let
                     innerInput = obtainInnerInputFrom input outerConfig
                     innerConfig = extractInnerConfigFrom outerConfig
                     (innerConfig', innerOutputs) = innerTransducer innerConfig innerInput
                     outerConfig' = embedInnerConfigIn outerConfig innerConfig'
                     outerOutputs = obtainOuterOutputsFrom innerOutputs outerConfig'
                 in
                     (outerConfig', outerOutputs)
             ...

The simplest way to write `obtainInnerInputFrom` and
`obtainOuterOutputsFrom` would just be to take the same input
that the outer transducer receives, and have the outputs of
the outer transducer be exactly the outputs of the inner tranducer.
Neither of these need to be the case, though, and by choosing
more than trivial logic for these functions we will enable the
outer transducer to "manage" the inner one.
We'll cover this in more detail below.

As a more concrete example, here is a transducer that represents
a `countingLightTransducer` behind a door.  The `TurnOn` and `TurnOff`
inputs will be sent to the light only when the door is open.

    doorTransducer config input =
        case (config.mode, input) of
            (Closed, Open) ->
                ({mode:Opened, data:config.data}, [])
            (Opened, Close) ->
                ({mode:Closed, data:config.data}, [])
            (Opened, lightInput) ->
                let
                    lightConfig = config.data
                    (lightConfig', outputs) = countingLightTransducer lightConfig lightInput
                in
                    ({mode:config.mode, data:lightConfig'}, outputs)
            _ ->
                (config, [])

### Orthogonal regions

Orthogonal regions are straightforward.  If we have a fixed number of
independent (and possibly heterogenous) transducers
embedded within an outer transducer, we simply transition them
all in the manner described in the previous section, combining the results
as we see fit.  (This is straightforward enough that I fear that a code
sample might be more obscuring than enlightening; thus it is left as an
exercise for the reader.)

We can extend this idea to an embedded array of homogenous transducers by
having a list of transducers and basically doing a `map` over it.  Except,
we can't simply `map` because we need to accumulate a list of
combined outputs of the inner transducers; and if the order of outputs
matters, then the order in which we transition this embedded array will
also matter.  The simplest approach, then, will be to `fold`.

To this end, here is a higher-order function that, given a transducer
function, an input, and a list of configurations, applies the transition
function to each configuration and returns the new list of configurations
along with the list of outputs that were generated:

    transduceAll t input [] acc = acc
    transduceAll t input (config:configs) (accConfigs, accOutputs) =
        let
            (config', outputs) = t config input
            newAcc = ((config':accConfigs), accOutputs ++ outputs)
        in
            transduceAll t input configs newAcc

Since this is a fold, it can also be written using `fold`, but this too
is left as an exercise for the reader.

Using `transduceAll`, we can now give an example of a `barnTransducer` which
manages a list of `countingLightTransducers` behind a barn door.  The `TurnOn`
and `TurnOff` inputs will be sent to all of the lights (but only when the barn
door is open), and every light will maintain its own counter and will contribute
to the collective list of outputs as appropriate.

    barnTransducer config input =
        case (config.mode, input) of
            (Closed, Open) ->
                ({mode:Opened, data:config.data}, [])
            (Opened, Close) ->
                ({mode:Closed, data:config.data}, [])
            (Opened, lightInput) ->
                let
                    lightConfigs = config.data
                    (lightConfigs', lightOutputs) =
                      transduceAll (countingLightTransducer) lightInput lightConfigs ([], [])
                in
                    ({mode:config.mode, data:lightConfigs'}, lightOutputs)
            _ ->
                (config, [])

### Management of inner transducers by outer transducers

#### Entry and exit actions

In the absence of hierarchially nested state machines,
entry and exit actions are unproblematic.  If you know that
when you leave mode A you must do action X and when you
enter mode B you must do action Y, you can simply specify
those outputs during that transition.

    someTransducer config input =
        case (config.mode, input) of
            ...
            (ModeA, InputFoo) ->
                let
                    config' = {mode:ModeB, data:config.data}
                in
                    (config', [ActionX, ActionY])

But in the presence of a hierarchy of states, it becomes more
complicated.  Since A and B may be nested arbitrarily deeply,
we must issue, between the exit actions of A and the entry actions of B,
the exit and entry actions of all the containing
states that we exit or enter on the way from A to B, in the
sequence we would encounter them on that journey through
the "nested state tree".

Since such sequences can be determined by examining the
state machine's structure, it is possible to automate the
production of these sequences, at either code-generation
time (e.g. in CASE tools that translate state machines
to C/C++), or as the responsibility of a state machine
"interpreter" used at run-time.

But if we want to directly write (and compose) functions that
describe this behaviour, neither of those options is available to us.

I don't pretend to have an optimal solution for this.  I'm not too
fussed about that, because having the equivalent of exit and entry actions
wasn't one of the four requirements listed in the first section.  They
would be "nice to have" though, so I would like to show that retaining
them is not an insurmountable problem.

What we can do, is define a higher-order function _h_ which takes a
transducer _t_ and returns a transducer _t′_ that transitions in
the same way _t_ does, but, under some conditions, produces extra
outputs.  These extra outputs may occur before or after (or indeed,
around) the outputs produced by _t_.

If this is all that _h_ does, then we can also say that functions
like _h_ are well-behaved during composition: if _h1_ adds extra
outputs before _t_ and _h2_ adds extra outputs after _t_, their
composition adds extra outputs around _t_.

We can derive an _h_ function from the structure of a state
machine, ensuring that _h_ always produces extra outputs that
correspond correctly with the entry actions and exit actions defined
for each mode in each transducer.

It only remains for all transducers under consideration (even
those that are nested within other transducers) to be "wrapped"
with this higher-order function _h_.

Sketch:

    addEntryExitOutputs t config input =
        let
            (config', outputs) = t config input
            exitOutputs = case config.mode of
                SomeFromMode -> [SomeExitAction]
                _ -> []
            entryOutputs = case config'.mode of
                SomeToMode -> [SomeEntryAction]
                _ -> []
            outputs' = exitOutputs ++ outputs ++ entryOutputs
        in
            (config', outputs')

##### Potential pitfalls

I would like to stress that _all_ transducers in the hierarchy
need to be "wrapped" with this higher-order function, otherwise
there is the potential for some exit or entry action to be missed.

Are there other potential pitfalls from this method?

What if we end up wrapping a transducer in `addEntryExitOutputs`
multiple times?  I am not entirely convinced this would happen
under normal circumstances, but even so, I think one can make a good
argument that exit and entry actions should be idempotent in any case.
In our setting, that could be accomplished by de-duplicating the
produced list of outputs.

More generally, we have to think about "when" the actions represented
by any _existing_ outputs of a transducer are intended to take place,
relative to any entry and exit actions our wrappers are going to add to the
sequence.  Any existing output may, upon reflection, strongly resemble
an entry or exit action, and if so it should arguably be modelled as one
instead.

A more serious departure is that while the UML spec guarantees that
a state's exit and entry actions are executed when a transition happens
that involves that state, here we can only ever guarantee that a list of
exit and entry "action outputs" will be produced; the outer transducer
is not strictly required to pass them upward to the "output executor"
or otherwise act on them.  But I think one can make a good argument that,
although outer transducers _can_ "manage" these exit and entry outputs
like any other outputs, they generally _should not_ do so.  There are
probably measures which can be taken to reduce the chance of doing so
in error, but an investigation of these possibilities is beyond the
scope of this article.

#### Synthesizing inputs

Often the inputs that a state machine deals with are not "real"
inputs at all, but some system's interpretation of what's going
on in the world around it.  For example, in a GUI, "hover" and
"drag" are two different kinds of events, but they are caused by the
same physical action (moving the mouse).  The only difference is
the context in which the physical action occurs.

Synthesized inputs are desirable because they allow the machine to deal
with the world outside it at an appropriate level of abstraction.  While
I'm sure it's possible to make UML state machines that synthesize inputs
and respond to synthesized inputs, I'm also not aware of any UML features
that are provided for that particular purpose.

In our system of nested transducers, synthesizing inputs is
straightforward, as the outer transducer can provide whatever input it
likes to the inner transducers that it manages.

A partial example illustrating the synthesizing of a "drag" event in
a GUI will probably suffice.  (A full, runnable example can be
found in [TransducerAssemblages.hs](TransducerAssemblages.hs).)

    makeGuiInputSynthesizingTransducer t = t' where
        t' config input =
            case (config.mode, input.type) of
                (MouseDown, MouseMove) ->
                    t config (Drag input.x input.y)
                _ ->
                    t config input

#### Capturing outputs

The outer transducer can do whatever it likes with the outputs
produced by an inner transducer that it manages.

As an extreme example of an outer transducer "managing" the
outputs of its inner transducers, consider that a transducer
which produces an empty list of outputs is indistinguishable
from a reducer.

We can always wrap a transducer with an outer transducer that
passes its inputs through to the inner transducer unchanged,
but takes all of the inner transducer's outputs and does something
with them other than return them as its own outputs (it could ignore
them, store them in its data, etc.,) resulting in a reducer.

You can go the other way around as well.  We can write a
higer-order transducer that, given a reducer, produces outputs
based on the new state of the reducer, every time the reducer
changes state.  This would be, in some sense, the functional
equivalent of the `subscribe` method of a Redux store.

I suppose this suggests some kind of "duality" between
transducers and reducers, but I hesitate to characterize
it in any more detail than that.

#### Internal state

Whenever there are hierarchically nested states, the following
situation is possible: the system is in some state in an inner
machine, and an input causes it to transition to a different
state in the outer machine — one where the inner machine does
not even exist.  The question is, what happens to the state of
that inner machine when that happens?  Does it get retained?
Or does it get reset to its local start state the next time
we enter the outer state that contains it?  Or does something
else happen?

Statecharts contains some machinery to try to express this
situation, notably a concept of "history" of the inner state
machine, which is somewhat sophisticated.

Our system of functional transducers does not require any
specific machinery for this, because the configuration of the
inner transducer is always embedded in the data in the outer
transducer.  It is essentially retained by default, when
the outer transducer switches modes.  But the outer transducer
also has access to it and could choose to reset it during
such a transition if desired.  Indeed, a higher-order wrapper
such as those that implement entry and exit actions could be
used for this purpose, or to implement any more sophisticated
scheme for managing this inner configuration, such as "history".

### Conclusion

We have described a way to implement UML state machines
(or at least, the parts of them that I like) as purely
functional transducers. [(Footnote 6)](#footnote-6)

Neither of these ideas are very new, and I have a feeling that someone
must have done something like this at some point, but if so, I have not
been successful at locating it.

In the interests of brevity, there is much that has been omitted
from this article, and consequently, much that could be explored in
more detail.

Our emphasis has been on how to construct transducers
hierarchically; much existing work on transducers emphasizes
hooking the output of one transducer to the input of another
(examples include Edward Kmett's [Data.Machine][]),
but this style of composition figures not at all into the current work.

In a sense we have given a kind of design pattern for writing functions
with the type `S × I → S × [O]`.  We touched on `[S] × I → S × [O]`
(in `transduceAll`).  `S × [I] → S × [O]` should be straightforward —
but what algebraic properties does it have?  And what happens when
`I` = `O`?

The preponderance of destructuring `let`s in the code examples here suggests
there might be some monadic (or other higher-order) formulation that
captures what we're doing.  On the other hand, the problem
of constructing a state machine (or in our case, a modal transducer)
does not, so far as I've seen, readily lend itself to a combinator approach.

#### Related resources

There are none yet.  This section will be updated when there are.

A definite next step would be to use functional transducer assemblages as
the basis for constructing a non-trivial reactive program.

Another definite possibility would be the formulation of a framework
for constructing such assemblages, and an investigation into how it could
(and whether it should) be presented as a combinator library.

- - - -

##### Footnote 1

Video games, if you must know.

##### Footnote 2

That's right, I've been trying to formulate a rigorous theory of
video games.  Do you have a problem with that?

##### Footnote 3

In a reducer, the actions must be composable, i.e. they must form
a monoid.  In a transducer, both the inputs must be composable,
and the outputs must be composable.  Under reducer combination
(Redux's `combineReducers`), reducers form a group, but under
transducer combination, transducers form a monoid.

##### Footnote 4

Okay, not real numbers, obviously.  You're welcome to extend
this model to uncountable sets if you _really_ want of course,
it's just that I have no interest in that myself.

##### Footnote 5

"Configuration" is borrowed from modern automata theory, where it
is used when describing Turing machines and such.  (Older texts
sometimes refer to the "instantaneous description" of a machine.)
A runner-up for "data" would be "context", which is used by [XState][],
but then both "configuration" and "context" begin with "c", which is
poor abbreviatability.

Note also that the term "modal transducer" also refers to a kind of
electronic component, but generally I expect this will be disambiguated
by context.

##### Footnote 6

And I am finally in a position to present a fully formal treatment of
_Mr. Do_.

[Redux]: https://redux.js.org/
[redux-loop]: https://redux-loop.js.org/
[finite automaton]: https://en.wikipedia.org/wiki/Finite_automaton
[push-down automaton]: https://en.wikipedia.org/wiki/Push-down_automaton
[reducer]: https://redux.js.org/basics/reducers
[Redux.js]: https://redux.js.org/
[redux-loop]: https://redux-loop.js.org/
[semiautomaton]: https://en.wikipedia.org/wiki/Semiautomaton
[transducer]: https://en.wikipedia.org/wiki/Finite-state_transducer
[The Elm Architecture]: https://guide.elm-lang.org/architecture/
[UML state machines]: https://en.wikipedia.org/wiki/UML_state_machine
[Moore machines]: https://en.wikipedia.org/wiki/Moore_machine
[Mealy machines]: https://en.wikipedia.org/wiki/Mealy_machine
[command pattern]: https://en.wikipedia.org/wiki/Command_pattern
[RAII]: https://en.wikipedia.org/wiki/Resource_acquisition_is_initialization
[theory and practice of folds]: https://en.wikipedia.org/wiki/Fold_(higher-order_function)
[XState]: https://xstate.js.org/docs/
[transducers in Clojure]: https://clojure.org/reference/transducers
[SRFI-171]: https://srfi.schemers.org/srfi-171/srfi-171.html
[Data.Machine]: http://github.com/ekmett/machines/
[Statecharts]: http://www.inf.ed.ac.uk/teaching/courses/seoc/2005_2006/resources/statecharts.pdf
