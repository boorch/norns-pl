-- Norns Performance Mixer Script

-- Setup
local bars = 1                 -- Default number of bars to record
local tempo = 120              -- Default BPM
local crossfade = 0            -- Crossfade level
local arm_count = 0            -- Count of Key2 presses for arming
local recording_start_beat = 0 -- Beat to start recording
local recording = false        -- Recording state

-- Initialize softcut
function init()
    softcut_reset()
    params:add { type = "number", id = "tempo", name = "Tempo", min = 20, max = 300, default = 120,
        action = function(value)
            tempo = value
            update_loop_end()
        end
    }
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

-- Key input handling
function key(n, z)
    if n == 2 and z == 1 then
        if not recording then
            arm_count = arm_count + 1
            if arm_count == 1 then
                clock.run(arm_recording)
            end
        end
    elseif n == 2 and n == 3 and z == 1 then
        if recording or crossfade > 0 then
            softcut.buffer_clear()
            crossfade = 0
            recording = false
            arm_count = 0
            redraw()
        end
    end
end

-- Arming recording with a delay
function arm_recording()
    clock.sync(4 - arm_count) -- Sync to the next 1 beat, considering pre-arming
    recording = true
    arm_count = 0
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

-- Encoder input handling
function enc(n, d)
    if n == 1 then
        -- Adjust tempo
        params:set("tempo", params:get("tempo") + d)
    elseif n == 2 then
        -- Adjust number of bars
        bars = util.clamp(bars + d, 1, 8)
        update_loop_end()
    elseif n == 3 then
        -- Adjust crossfade
        crossfade = util.clamp(crossfade + d, 0, 100)
        softcut.level(1, 1 - crossfade / 100)
        softcut.level(2, crossfade / 100)
    end
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

-- Call the init function to setup everything
init()
