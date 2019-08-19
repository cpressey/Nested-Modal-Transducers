module TransducerAssemblages where

--
-- Runnable example code to accompany the write-up in README.md.
--
-- All of this code is in the public domain.  Do what you like with it.
--

-- -- -- -- -- -- -- --

-- First, a simple function to express our illustrative tests:
-- Given a list of pairs, show those pairs that are not equal.
-- Anything other than an empty list returned indicates a mistake.

expect [] = []
expect ((a, b):rest) = if a == b then expect rest else ((a, b):expect rest)

-- -- -- -- -- -- -- --

data LightMode = On | Off deriving (Show, Ord, Eq)
data LightInput = TurnOn | TurnOff deriving (Show, Ord, Eq)
data LightOutput = RingBell | BuzzBuzzer deriving (Show, Ord, Eq)

--
-- Purely functional definition of a simple transducer.
--

lightTransducer :: LightMode -> LightInput -> (LightMode, [LightOutput])
lightTransducer mode input =
    case (mode, input) of
        (On, TurnOff) ->
            (Off, [])
        (Off, TurnOn) ->
            (On, [RingBell])
        _ ->
            (mode, [])

--
-- Purely functional test harness for transducers:
-- Determine what state and outputs it will produce, given a sequence of inputs.
-- You can think of it as having a type like:
--
--     rehearse :: Transducer -> State -> [Input] -> (State, [Output])
--

rehearse t state [] = (state, [])
rehearse t state (input:inputs) =
    let
        (state', outputs) = t state input
        (state'', outputs') = rehearse t state' inputs
    in
        (state'', outputs ++ outputs')

testRehearse = expect
  [
    (rehearse (lightTransducer) On [TurnOff],                     (Off, [])),
    (rehearse (lightTransducer) Off [TurnOff],                    (Off, [])),
    (rehearse (lightTransducer) Off [TurnOn, TurnOn, TurnOff],    (Off, [RingBell])),
    (rehearse (lightTransducer) On [TurnOn, TurnOn, TurnOff],     (Off, []))
  ]

--
-- Reactive driver for transducer:
-- Accept inputs from console, display outputs on console, interactively.
-- Test it manually with:
--
--     reactWith lightTransducer Off
--

reactWith transducer state = do
    putStrLn $ "State is now: " ++ (show state)
    input <- waitForInput
    let (state', outputs) = transducer state input
    enactEffects outputs
    reactWith transducer state'

waitForInput = do
    putStrLn "Enter '1' to TurnOn, '2' to TurnOff"
    line <- getLine
    case line of
        "1" -> return TurnOn
        "2" -> return TurnOff
        _ -> waitForInput

enactEffects [] = return ()
enactEffects (output:outputs) = do
    enactEffect output
    enactEffects outputs

enactEffect output =
    case output of
        RingBell -> putStrLn "Ding!"

--
-- Higher-order function to combine transducers a la Redux's combineReducers.
-- Note that order matters: effects from tA will happen before effects from tB.
--

combineTransducers tA tB = tC where
    tC (stateA, stateB) input =
        let
            (stateA', outputsA) = tA stateA input
            (stateB', outputsB) = tB stateB input
            outputsC = outputsA ++ outputsB
        in
            ((stateA', stateB'), outputsC)

twoLightTransducer = combineTransducers lightTransducer lightTransducer

testCombinedTransducer = expect
  [
    (rehearse twoLightTransducer (On, Off) [TurnOff],         ((Off,Off),[])),
    (rehearse twoLightTransducer (On, Off) [TurnOff, TurnOn], ((On,On),[RingBell,RingBell]))
  ]

--
-- Extended state
--
-- (This is where we start using the word "configs" instead of "states", but don't get confused:
-- the term "configuration" comes from modern automata theory and refers to the state of the
-- entire machine.  Configuration = mode ("finite state variable") + data ("extended state").)
--

data LightConfig = LightConfig LightMode Integer deriving (Show, Ord, Eq)

countingLightTransducer (LightConfig mode count) input =
    case (mode, input) of
        (On, TurnOff) ->
            (LightConfig Off count, [])
        (Off, TurnOn) ->
            (LightConfig On (count + 1), [RingBell])
        _ ->
            (LightConfig mode count, [])

testCountingLightTransducer = expect
  [
    (rehearseCountingLightTransducer [TurnOn],                       (LightConfig On 1,[RingBell])),
    (rehearseCountingLightTransducer [TurnOn,TurnOn],                (LightConfig On 1,[RingBell])),
    (rehearseCountingLightTransducer [TurnOn,TurnOn,TurnOff],        (LightConfig Off 1,[RingBell])),
    (rehearseCountingLightTransducer [TurnOn,TurnOn,TurnOff,TurnOn], (LightConfig On 2,[RingBell,RingBell]))
  ]
  where
    rehearseCountingLightTransducer = rehearse countingLightTransducer (LightConfig Off 0)

--
-- Nested state machine.  The light is now in a room, behind a door.
-- It can only be turned on or off when the door is open.
--

-- LightMode and LightInput have already been defined

data DoorMode = Opened | Closed deriving (Show, Ord, Eq)
data DoorInput = Open | Close | LightInput LightInput deriving (Show, Ord, Eq)
data DoorConfig = DoorConfig DoorMode LightConfig deriving (Show, Ord, Eq)
data DoorOutput = LightOutput LightOutput deriving (Show, Ord, Eq)

doorTransducer :: DoorConfig -> DoorInput -> (DoorConfig, [DoorOutput])
doorTransducer (DoorConfig mode lightConfig) input =
    case (mode, input) of
        (Closed, Open) ->
            ((DoorConfig Opened lightConfig), [])
        (Opened, Close) ->
            ((DoorConfig Closed lightConfig), [])
        (Opened, LightInput lightInput) ->
            let
                (lightConfig', lightOutputs) = countingLightTransducer lightConfig lightInput
                doorOutputs = map (\x -> LightOutput x) lightOutputs
            in
                ((DoorConfig mode lightConfig'), doorOutputs)
        _ ->
            (DoorConfig mode lightConfig, [])

testDoor = expect
  [
    (rehearse doorTransducer initialDoorConfig [Open],                             (DoorConfig Opened (LightConfig Off 0),[])),
    (rehearse doorTransducer initialDoorConfig [LightInput TurnOn],                (DoorConfig Closed (LightConfig Off 0),[])),
    (rehearse doorTransducer initialDoorConfig [Open, (LightInput TurnOn), Close], (DoorConfig Closed (LightConfig On 1),[LightOutput RingBell]))
  ]
  where
    initialDoorConfig = (DoorConfig Closed (LightConfig Off 0))

--
-- Array of orthogonal regions - a list of lights are behind a barn door.
--

transduceAll t input [] acc = acc
transduceAll t input (config:configs) (accConfigs, accOutputs) =
    let
        (config', outputs) = t config input
    in
        transduceAll t input configs ((config':accConfigs), accOutputs ++ outputs)

data BarnConfig = BarnConfig DoorMode [LightConfig] deriving (Show, Ord, Eq)

barnTransducer :: BarnConfig -> DoorInput -> (BarnConfig, [DoorOutput])
barnTransducer config@(BarnConfig mode lightConfigs) input =
    case (mode, input) of
        (Closed, Open) ->
            ((BarnConfig Opened lightConfigs), [])
        (Opened, Close) ->
            ((BarnConfig Closed lightConfigs), [])
        (Opened, LightInput lightInput) ->
            let
                (lightConfigs', lightOutputs) = transduceAll (countingLightTransducer) lightInput lightConfigs ([], [])
                doorOutputs = map (\x -> LightOutput x) lightOutputs
            in
                ((BarnConfig mode lightConfigs'), doorOutputs)
        _ ->
            (config, [])

testBarn = expect
  [
    (rehearse barnTransducer barnConfig1 [Open],                             (BarnConfig Opened [LightConfig Off 0,LightConfig On 0],[])),
    (rehearse barnTransducer barnConfig1 [LightInput TurnOn],                (BarnConfig Closed [LightConfig Off 0,LightConfig On 0],[])),
    (rehearse barnTransducer barnConfig1 [Open, (LightInput TurnOn), Close], (BarnConfig Closed [LightConfig On 0,LightConfig On 1],[LightOutput RingBell])),
    (rehearse barnTransducer barnConfig2 [Open, (LightInput TurnOn), Close], (BarnConfig Closed [LightConfig On 1,LightConfig On 1],[LightOutput RingBell,LightOutput RingBell]))
  ]
  where
    barnConfig1 = (BarnConfig Closed [(LightConfig Off 0), (LightConfig On 0)])
    barnConfig2 = (BarnConfig Closed [(LightConfig Off 0), (LightConfig Off 0)])

--
-- Entry and exit actions
--

-- In some ideal or latently-typed world, we'd have a single higher-order function
-- that we wrap all our transducers with.  But here we have types, and I don't feel
-- like mashing them together into typeclasses or whatever, so.  We have two
-- separate decorator functions here.  This is not a great example in any case,
-- but like the article says, we don't pretend to have a good solution, we only
-- want to show that it is possible.

addEntryExitOutputsLight t config@(LightConfig mode _) input =
    let
        (config2@(LightConfig mode2 data2), outputs) = t config input
        exitOutputs = case mode of
            Off -> [BuzzBuzzer]
            _ -> []
        outputs2 = exitOutputs ++ outputs
    in
        (config2, outputs2)

addEntryExitOutputsDoor t config@(DoorConfig mode _) input =
    let
        (config2@(DoorConfig mode2 data2), outputs) = t config input
        entryOutputs = case mode2 of
            Closed -> [LightOutput BuzzBuzzer]
            _ -> []
        outputs2 = outputs ++ entryOutputs
    in
        (config2, outputs2)

decoDoorTransducer :: DoorConfig -> DoorInput -> (DoorConfig, [DoorOutput])
decoDoorTransducer = addEntryExitOutputsDoor t where
    t (DoorConfig mode lightConfig) input =
        case (mode, input) of
            (Closed, Open) ->
                ((DoorConfig Opened lightConfig), [])
            (Opened, Close) ->
                ((DoorConfig Closed lightConfig), [])
            (Opened, LightInput lightInput) ->
                let
                    decoLightTransducer = addEntryExitOutputsLight countingLightTransducer
                    (lightConfig', lightOutputs) = decoLightTransducer lightConfig lightInput
                    doorOutputs = map (\x -> LightOutput x) lightOutputs
                in
                    ((DoorConfig mode lightConfig'), doorOutputs)
            _ ->
                (DoorConfig mode lightConfig, [])

testDecoDoorTransducer = expect
  [
    (rehearseIt [Open],                             (DoorConfig Opened (LightConfig Off 0),[])),
    (rehearseIt [LightInput TurnOn],                (DoorConfig Closed (LightConfig Off 0),[LightOutput BuzzBuzzer])),
    (rehearseIt [Open, (LightInput TurnOn), Close], (DoorConfig Closed (LightConfig On 1),
      [LightOutput BuzzBuzzer,LightOutput RingBell,LightOutput BuzzBuzzer]))
  ]
  where
    rehearseIt = rehearse decoDoorTransducer initialDoorConfig
    initialDoorConfig = (DoorConfig Closed (LightConfig Off 0))

--
-- Synthesized events
--

data GUIInput = MouseMove Int Int | MousePress | MouseRelease | Drag Int Int deriving (Show, Ord, Eq)
data GUIMode = MouseDown | MouseUp deriving (Show, Ord, Eq)
data GUIConfig = GUIConfig GUIMode Int Int deriving (Show, Ord, Eq)
data GUIOutput = ShowClick Int Int | ShowHand Int Int deriving (Show, Ord, Eq)

makeGuiInputSynthesizingTransducer t = t' where
    t' config@(GUIConfig mode x y) input =
        case (mode, input) of
            (MouseDown, MouseMove x' y') ->
                t config (Drag x' y')
            _ ->
                t config input

baseGuiTransducer (GUIConfig mode x y) input =
    case (mode, input) of
        (MouseDown, MouseRelease) ->
            (GUIConfig MouseUp x y, [])
        (MouseUp, MousePress) ->
            (GUIConfig MouseDown x y, [ShowClick x y])
        (_, MouseMove x' y') ->
            (GUIConfig mode x' y', [])
        (_, Drag x' y') ->
            (GUIConfig mode x' y', [ShowHand x' y'])
        _ ->
            (GUIConfig mode x y, [])

guiTransducer = makeGuiInputSynthesizingTransducer baseGuiTransducer

testGui = expect
  [
    (rehearseIt [MouseMove 10 10, MousePress, MouseRelease], (GUIConfig MouseUp 10 10, [ShowClick 10 10])),
    (rehearseIt [MousePress, MouseMove 10 10, MouseRelease], (GUIConfig MouseUp 10 10, [ShowClick 0 0, ShowHand 10 10]))
  ]
  where
    rehearseIt = rehearse guiTransducer (GUIConfig MouseUp 0 0)

-- -- -- -- -- -- -- --

testAll = (map show testRehearse) ++
          (map show testCombinedTransducer) ++
          (map show testCountingLightTransducer) ++
          (map show testDoor) ++
          (map show testBarn) ++
          (map show testDecoDoorTransducer) ++
          (map show testGui)
