-- Norns Performance Mixer Script with MIDI Sync from Dirtywave M8 and Transport Icons
local bars = 1 -- Default number of bars to record
local tempo = 120 -- Default BPM, will be updated from MIDI clock
local crossfade = 0 -- Crossfade level
local recording = false -- Recording state
local is_playing = false -- Transport play state
local blink_phase = true -- Blink phase for play icon
local blinking_id -- ID for the blinking coroutine
local clock_times = {} -- Store times of MIDI clock messages for averaging
local num_clocks_to_average = 48 -- Number of MIDI clocks to average for BPM calculation
local util = require 'util'
local beat_count = 0 -- Global variable to keep track of the number of beats
local current_beat_in_bar = 1 -- Track the current beat within a bar for beat indicator visualization
local recording_beat_in_bar = 1 -- Track the current beat within a bar during recording
local arm_next_bar = false -- Flag to start recording at the next bar
local loop_duration = 60 / tempo * 4 * bars -- Calculate loop end based on current tempo and bars
local loop_phase = false
local loop_phase_duration = 0
local last_start_time = 0 -- Store the time of the last MIDI start message
local decimal_places = 1 -- Number of decimal places for the tempo
local arm_beat_count = math.huge -- Initialize to a large number
local key1_hold = false
-- Initialize the variables
local hp = {0, 0} -- Highpass filter cutoff frequency for each channel
local rq = {1/math.sqrt(2), 1/math.sqrt(2)} -- Q factor for each channel

-- Setup MIDI
local midi_device

local function midi_event(data)
    local msg = midi.to_msg(data)
    if msg.type == "clock" then
        table.insert(clock_times, util.time())
        if #clock_times % 24 == 0 then
            if is_playing then
                beat_count = beat_count + 1
                recording_beat_in_bar = (beat_count - 1) % 4 + 1
                if beat_count % (bars * 4) == 0 and beat_count > arm_beat_count then
                    print("Arming recording...")
                    arm_recording()
                    arm_beat_count = math.huge
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
            tempo = tonumber(string.format("%." .. decimal_places .. "f", (60 / average_duration_per_clock) / 24)) -- Round BPM to nearest integer
            redraw()
            clock_times = {} -- Reset clock times after calculating tempo
        end
    elseif msg.type == "start" then
        last_start_time = util.time() -- Store the time of the MIDI start message
        is_playing = true
        clock_times = {} -- Clear clock times at the start of transport
        for i = 1, 2 do
            softcut.play(i, 1) -- Start Softcut playing
        end
        if not blinking_id then
            blinking_id = clock.run(handle_blinking)
        end
        redraw()
    elseif msg.type == "stop" then
        is_playing = false
        recording = false
        beat_count = 0
        recording_beat_in_bar = 1
        current_beat_in_bar = 1
        for i = 1, 2 do
            softcut.play(i, 0) -- Stop Softcut playing
            softcut.position(i, 0) -- Set Softcut position to the start
        end
        if blinking_id then
            clock.cancel(blinking_id)
            blinking_id = nil
        end
        arm_next_bar = false
        redraw()
    end
end

function calculate_current_beat_in_bar()
    local time_elapsed = util.time() - last_start_time -- Time elapsed since the last MIDI start message
    local beat_duration = 60 / tempo -- Duration of one beat
    local beat = math.floor(time_elapsed / beat_duration) % 4 + 1 -- Current beat within the bar
    return beat
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
    params:add{
        type = "number",
        id = "bars",
        name = "Bars",
        min = 1,
        max = 8,
        default = 1,
        action = function(value)
            bars = value
            update_loop_end()
        end
    }
    params:add{
        type = "control",
        id = "crossfade",
        name = "Crossfade",
        controlspec = controlspec.new(0, 100, "lin", 1, 0, "%"),
        action = function(value)
            crossfade = value
            adjust_crossfade()
        end
    }
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
    -- encoder 1 changes post highpass filter cutoff frequency of softcut, but if K1 is pressed, it changes Q of filter instead
    -- if n == 1 then
    --     if key1_hold then
    --         for i = 1, 2 do
    --             rq[i] = util.clamp(rq[i] + delta / 100, 1/math.sqrt(2), 5)
    --             softcut.post_filter_rq(i, rq[i])
    --             print("Post highpass filter Q set to " .. rq[i] .. " for channel " .. i)
    --         end
    --     else
    --         for i = 1, 2 do
    --             hp[i] = util.clamp(hp[i] + delta * 10, 0, 20000)
    --             softcut.post_filter_hp(i, hp[i])
    --             print("Post highpass filter cutoff frequency set to " .. hp[i] .. " for channel " .. i)
    --         end
    --     end
    -- end
    if n == 2 then -- Encoder 2 changes the number of bars
        bars = util.clamp(bars + delta / 2, 1, 8)
        update_loop_end()
    end

    if n == 3 then -- Encoder 3 changes the crossfade level
        local new_crossfade = util.clamp(crossfade + delta * 2, 0, 100)
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
        softcut.loop_end(i, loop_duration) -- Make sure this is set correctly outside the loop
        softcut.position(i, 0)
        softcut.fade_time(i, 0.01)
        softcut.rec(i, 0)
        softcut.rec_level(i, 0)
        softcut.pre_level(i, 0)
        softcut.level_input_cut(i, i, 1.0)
        -- Set post highpass filter cutoff frequency and Q factor
        -- softcut.post_filter_hp(i, 20)
        -- softcut.post_filter_rq(i, 1/math.sqrt(2))        
    end
end

function update_loop_end()
    loop_duration = 60 / tempo * 4 * bars -- Calculate loop end based on current tempo and bars
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
        if blink_phase then
            current_beat_in_bar = (current_beat_in_bar % 4) + 1
        end
        redraw()
        clock.sleep(beat_duration * (blink_phase and 1 or 3))
    end
end

function key(n, z)
    if n == 1 then
        key1_hold = z == 1
    else
        key1_hold = false
    end
    if n == 2 and z == 1 then
        if recording then
            stop_recording()
        elseif is_playing and not recording then
            arm_beat_count = beat_count
        end
    elseif n == 3 and z == 1 then
        softcut.buffer_clear()
        recording = false
        arm_beat_count = math.huge
        redraw()
    end
end

function arm_recording()
    update_loop_end()
    recording = true
    beat_count = 0
    for i = 1, 2 do
        adjust_crossfade() -- Update Softcut output level
        softcut.position(i, 0) -- Set playhead position to the start of the buffer
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
