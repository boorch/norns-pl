-- Norns Performance Mixer Script with MIDI Sync from Dirtywave M8 and Transport Icons

local bars = 1                   -- Default number of bars to record
local tempo = 120                -- Default BPM, will be updated from MIDI clock
local crossfade = 0              -- Crossfade level
local recording = false          -- Recording state
local is_playing = false         -- Transport play state
local blink_phase = true         -- Blink phase for play icon
local blinking_id                -- ID for the blinking coroutine
local clock_times = {}           -- Store times of MIDI clock messages for averaging
local num_clocks_to_average = 48 -- Number of MIDI clocks to average for BPM calculation
local util = require 'util'
local beat_count = 0             -- Global variable to keep track of the number of beats
local current_beat_in_bar = 1    -- Track the current beat within a bar
local arm_next_bar = false -- Flag to start recording at the next bar
local loop_duration = 60 / tempo * 4 * bars  -- Calculate loop end based on current tempo and bars
local loop_phase = false
local loop_phase_duration = 0

-- Setup MIDI
local midi_device

local function midi_event(data)
    local msg = midi.to_msg(data)
    if msg.type == "clock" then
        table.insert(clock_times, util.time())
        if #clock_times % 24 == 0 then
            if is_playing then
                beat_count = beat_count + 1
                current_beat_in_bar = beat_count % 4 + 1-- Adjusted to start from 0
                if arm_next_bar and current_beat_in_bar == 1 then -- Adjusted to start recording on beat 0
                    print("Arming recording...") -- Add this line
                    arm_recording()
                    arm_next_bar = false
                end
                redraw()
                if recording and beat_count >= bars * 4 then
                    stop_recording()
                    beat_count = 0
                end
            end
        end
        if #clock_times >= num_clocks_to_average then
            local total_duration = clock_times[#clock_times] - clock_times[1]
            local average_duration_per_clock = total_duration / (#clock_times - 1)
            tempo = math.floor((60 / average_duration_per_clock) / 24 + 0.5) -- Round BPM to nearest integer
            redraw()
            clock_times = {} -- Reset clock times after calculating tempo
        end
    elseif msg.type == "start" then
        is_playing = true
        if not blinking_id then
            blinking_id = clock.run(handle_blinking)
        end
        redraw()
    elseif msg.type == "stop" then
        is_playing = false
        recording = false
        beat_count = 0
        current_beat_in_bar = 1
        if blinking_id then
            clock.cancel(blinking_id)
            blinking_id = nil
        end
        redraw()
    end
end

-- Initialize
function init()
    audio.level_adc_cut(1)
    softcut_reset()
    setup_params()
    update_loop_end()
    midi_device = midi.connect(1) -- Connect to the first MIDI device
    midi_device.event = midi_event
    redraw()

    softcut.phase_quant(1, 1 / 48000) -- Set phase quantization to one sample
    softcut.event_phase(softcut_phase_callback)
    softcut.poll_start_phase()
end


-- Setup user control parameters
function setup_params()
    params:add { type = "number", id = "bars", name = "Bars", min = 1, max = 8, default = 1,
        action = function(value)
            bars = value
            update_loop_end()
        end }
    params:add { type = "control", id = "crossfade", name = "Crossfade",
        controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"),
        action = function(value)
            crossfade = value
            adjust_crossfade()
        end }
end

function adjust_crossfade()
    local input_level = 1 - crossfade / 100
    local softcut_level = crossfade / 100
    audio.level_monitor(input_level)
    audio.level_cut(softcut_level)
    -- print("Monitor level: " .. input_level)
    -- print("Softcut level: " .. softcut_level)
end

function enc(n, delta)
    if n == 2 then -- Encoder 2 changes the number of bars
        bars = util.clamp(bars + delta, 1, 8)
        update_loop_end()
    elseif n == 3 then -- Encoder 3 changes the crossfade level
        local new_crossfade = util.clamp(crossfade + delta, 0, 100)
        if new_crossfade ~= crossfade then
            crossfade = new_crossfade
            adjust_crossfade()
        end
    end
    redraw() -- Update the display whenever an encoder is turned
end

function softcut_reset()
    softcut.buffer_clear()
    for i = 1, 2 do
        softcut.enable(i, 1)
        softcut.buffer(i, i)
        softcut.level(i, 1.0)
        softcut.pan(i, i == 1 and -1 or 1)
        softcut.rate(i, 1.0)
        softcut.loop(i, 1)
        softcut.loop_start(i, 0)
        softcut.loop_end(i, loop_duration)  -- Make sure this is set correctly outside the loop
        softcut.position(i, 0)
        softcut.fade_time(i, 0.01)
        softcut.rec(i, 0)
        softcut.rec_level(i, 0)
        softcut.pre_level(i, 0)
        softcut.level_input_cut(i, i, 1.0)
        softcut.post_filter_fc(i, 20000) -- Set filter cutoff frequency to 20kHz to disable lowpass filter
        softcut.pre_filter_fc(i, 20000)
    end
end


function update_loop_end()
    loop_duration = 60 / tempo * 4 * bars  -- Calculate loop end based on current tempo and bars
    for i = 1, 2 do
        softcut.loop_start(i, 0)
        softcut.loop_end(i, loop_duration)
    end
end


function redraw()
    screen.clear()
    screen.level(15)
    screen.move(10, 10)
    screen.text(tempo .. " BPM")
    screen.move(100, 10)
    screen.text(bars .. " Bars")
    screen.move(64, 30)
    screen.text("XF: " .. crossfade)
    for i = 1, 4 do
        screen.rect(60 + 8 * i, 50, 5, 5)
        if i == current_beat_in_bar then
            screen.fill()
        else
            screen.stroke()
        end
    end
    screen.move(10, 60)
    screen.text(recording and "Rec" or "Idle")
    screen.move(118, 60)
    screen.level(is_playing and (blink_phase and 15 or 5) or 15)
    screen.text(is_playing and ">" or "[]")
    if loop_phase then
        screen.move(60, 45) -- Position the "*" character above the first beat indicator
        screen.text("*")
    end
    screen.update()
end

function handle_blinking()
    local beat_duration = 60 / tempo / 4
    blink_phase = true
    redraw()
    clock.sleep(beat_duration)
    while is_playing do
        blink_phase = not blink_phase
        loop_phase_duration = loop_phase_duration + 1
        redraw()
        clock.sleep(beat_duration * (blink_phase and 1 or 3))
    end
end

function key(n, z)
    print("Key pressed: " .. n .. " with state: " .. z)
    print("Recording: " .. tostring(recording))
    print("Is playing: " .. tostring(is_playing))
    if n == 2 and z == 1 then
        if recording then
            stop_recording()
        elseif is_playing and not recording then
            arm_next_bar = true
        end
    elseif n == 3 and z == 1 then
        softcut.buffer_clear()
        recording = false
        redraw()
    end
end

function arm_recording()
    update_loop_end()
    recording = true
    beat_count = 0
    for i = 1, 2 do
        adjust_crossfade() -- Update Softcut output level
        softcut.position(i, 0)  -- Set playhead position to the start of the buffer
        softcut.rec_level(i, 0.5)
        softcut.rec(i, 1)
        -- log setting rec level and rec to 1 for each channel
        print("Recording level set to 1 for channel " .. i)
        print("Recording set to 1 for channel " .. i)    
    end
    -- print("Softcut parameters at start of recording:")
    -- softcut.poll(i)
end

function stop_recording()
    recording = false
    for i = 1, 2 do
        adjust_crossfade() -- Update Softcut output level
        softcut.rec(i, 0)
        softcut.rec_level(i, 0) -- Set rec_level back to 0
        softcut.play(i, 1)
    end
    -- print("Softcut parameters at end of recording:")
    -- softcut.poll(i)
end


function softcut_phase_callback(voice, phase)
    if voice == 1 then
        if phase < 0.01 then
            loop_phase = true
            loop_phase_duration = 0
        elseif loop_phase and loop_phase_duration >= 2 then
            loop_phase = false
        end
        redraw()
    end
end

init()
