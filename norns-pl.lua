-- Norns Performance Mixer Script with MIDI Sync from Dirtywave M8

local bars = 1          -- Default number of bars to record
local tempo = 120       -- Default BPM, will be updated by MIDI
local crossfade = 0     -- Crossfade level
local recording = false -- Recording state

-- Setup MIDI
local midi_device
local function midi_event(data)
    local msg = midi.to_msg(data)
    -- Sync tempo and start/stop based on MIDI clock and transport messages
    if msg.type == "clock" then
        -- MIDI Clock messages are sent frequently, we could calculate tempo here
    elseif msg.type == "start" or msg.type == "continue" then
        -- Handle start or continue
        if not recording then
            clock.run(arm_recording) -- Use clock to synchronize
        end
    elseif msg.type == "stop" then
        -- Handle stop
        if recording then
            stop_recording()
        end
    elseif msg.type == "tempo" then
        -- MIDI Tempo (BPM) change detected
        tempo = msg.bpm
        update_loop_end()
        redraw()
    end
end

-- Initialize
function init()
    softcut_reset()
    midi_device = midi.connect(1) -- Connect to the first MIDI device
    midi_device.event = midi_event
    redraw()
end

-- Softcut reset and default setup
function softcut_reset()
    softcut.buffer_clear()
    for i = 1, 2 do
        softcut.enable(i, 1)
        softcut.buffer(i, 1)
        softcut.level(i, 1.0)
        softcut.loop(i, 1)
        softcut.loop_start(i, 1)
        softcut.loop_end(i, 1)
        softcut.position(i, 1)
        softcut.play(i, 1)
    end
    softcut.rec_level(1, 0)
    softcut.pre_level(1, 0.5) -- Allows for overdubbing
    softcut.level_input_cut(1, 1, 1.0)
    softcut.level_input_cut(2, 1, 1.0)
end

-- Arming recording with synchronization
function arm_recording()
    clock.sync(1) -- Sync to the next beat
    recording = true
    softcut.rec_level(1, 1)
    softcut.position(1, 1)
    update_loop_end()
    softcut.rec(1, 1)
    clock.run(stop_recording)
    redraw()
end

-- Automatically stop recording after the set duration
function stop_recording()
    local bars_duration = bars * 4 -- 4 beats per bar
    clock.sync(bars_duration)
    softcut.rec(1, 0)
    softcut.rec_level(1, 0)
    recording = false
    redraw()
end

-- Update loop end based on tempo and number of bars
function update_loop_end()
    local loop_duration = 60 / tempo * 4 * bars -- 4 beats per bar
    softcut.loop_end(1, 1 + loop_duration)
end

-- Screen redraw function
function redraw()
    screen.clear()
    -- Display the current tempo
    screen.move(10, 10)
    screen.text("Tempo: " .. tempo .. " BPM")
    -- Display the number of bars
    screen.move(120, 10)
    screen.text(bars .. " Bars")
    -- Display crossfade level
    screen.move(64, 30)
    screen.text("XF: " .. crossfade)
    -- Recording status
    screen.move(10, 60)
    screen.text(recording and "Rec" or "Idle")
    screen.update()
end

init()
