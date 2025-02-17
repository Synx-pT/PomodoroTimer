-- luacheck: globals obslua script_properties script_load script_save script_update start_timer stop_timer
local obs = obslua

----------------------------------------------------------
-- Configuration Defaults (locals)
----------------------------------------------------------
local source_name = "PomodoroTimer" -- Name of your text source in OBS
local alert_sound_source = "AlertSound" -- Existing alert sound source

-- Timer durations (in minutes)
local focus_duration_minutes = 50 -- Focus duration
local break_duration_minutes = 10 -- Break duration (consolidated break mode)

-- Customizable messages
local focus_message = "Focus Time!"
local break_message = "Break Time!"
local session_limit_message = "Session limit reached!" -- New customizable message

-- Maximum focus sessions before stopping the timer
local session_limit = 4

-- Fast mode: for testing purposes (each real second simulates 60 seconds)
local fast_mode = false
local time_multiplier = fast_mode and 60 or 1

----------------------------------------------------------
-- Sound Options
----------------------------------------------------------
local break_bgm_enabled = false -- Toggle for Break BGM
local break_bgm_source = "BreakBGM" -- OBS media source name for Break BGM

local session_limit_music_enabled = false -- Toggle for Session Limit Music
local session_limit_music_source = "SessionLimitMusic" -- OBS media source name for Session Limit Music

----------------------------------------------------------
-- Timer State Variables (locals)
----------------------------------------------------------
local timer_active = false
local time_left = focus_duration_minutes * 60
local session_count = 0
local mode = "focus" -- Modes: "focus", "break", "session_limit"

----------------------------------------------------------
-- Utility Functions (locals)
----------------------------------------------------------

-- Update the OBS text source with the given text.
local function set_timer_text(text)
	local source = obs.obs_get_source_by_name(source_name)
	if source then
		local settings = obs.obs_data_create()
		obs.obs_data_set_string(settings, "text", text)
		obs.obs_source_update(source, settings)
		obs.obs_data_release(settings)
		obs.obs_source_release(source)
	end
end

-- Play a media source. If 'loop' is true, set looping on.
local function play_media_source(source_name, loop)
	local source = obs.obs_get_source_by_name(source_name)
	if source then
		local settings = obs.obs_source_get_settings(source)
		obs.obs_data_set_bool(settings, "looping", loop)
		obs.obs_source_update(source, settings)
		obs.obs_data_release(settings)
		-- Restart the media so it plays from the beginning
		obs.obs_source_media_restart(source)
		obs.obs_source_release(source)
	end
end

-- Stop a media source by pausing it.
local function stop_media_source(source_name)
	local source = obs.obs_get_source_by_name(source_name)
	if source then
		obs.obs_source_media_pause(source)
		obs.obs_source_release(source)
	end
end

-- Update the timer display based on current mode and remaining time.
local function update_timer_display()
	local minutes = math.floor(time_left / 60)
	local seconds = time_left % 60
	local time_str = string.format("%02d:%02d", minutes, seconds)
	if mode == "focus" then
		set_timer_text(focus_message .. "\n" .. time_str .. "\nSession: " .. session_count .. " / " .. session_limit)
	elseif mode == "break" then
		set_timer_text(break_message .. "\n" .. time_str .. "\nSession: " .. session_count .. " / " .. session_limit)
	elseif mode == "session_limit" then
		set_timer_text(session_limit_message .. "\nSession: " .. session_count .. " / " .. session_limit)
	end
end

----------------------------------------------------------
-- Timer Logic Functions
----------------------------------------------------------
local function timer_tick()
	if not timer_active then
		return
	end

	if time_left > 0 then
		time_left = time_left - 1
		update_timer_display()
	else
		if mode == "focus" then
			session_count = session_count + 1
			if session_count >= session_limit then
				mode = "session_limit"
				update_timer_display()
				if session_limit_music_enabled then
					play_media_source(session_limit_music_source, false)
				end
				timer_active = false -- Stop timer when session limit is reached
			else
				mode = "break"
				time_left = break_duration_minutes * 60
				update_timer_display()
				if break_bgm_enabled then
					play_media_source(break_bgm_source, true)
				end
			end
		elseif mode == "break" then
			mode = "focus"
			time_left = focus_duration_minutes * 60
			update_timer_display()
			if break_bgm_enabled then
				stop_media_source(break_bgm_source)
			end
		end
	end
end

local timer_timer = nil

local function start_timer()
	if not timer_active then
		timer_active = true
		timer_timer = obs.timer_add(timer_tick, 1000 / time_multiplier)
	end
end

local function stop_timer()
	if timer_active then
		timer_active = false
		if timer_timer then
			obs.timer_remove(timer_tick)
			timer_timer = nil
		end
		if break_bgm_enabled then
			stop_media_source(break_bgm_source)
		end
	end
end

----------------------------------------------------------
-- OBS Script Functions
----------------------------------------------------------
function script_description()
	return "Pomodoro Timer with Break BGM and Session Limit Music\n\n"
		.. "This script alternates between focus and break periods. When the session limit is reached, a customizable message and music are displayed.\n"
		.. "Configure media sources and toggles below."
end

function script_properties()
	local props = obs.obs_properties_create()

	-- Basic configuration
	obs.obs_properties_add_text(props, "source_name", "Text Source", obs.OBS_TEXT_DEFAULT)
	obs.obs_properties_add_text(props, "alert_sound_source", "Alert Sound Source", obs.OBS_TEXT_DEFAULT)
	obs.obs_properties_add_int(props, "focus_duration_minutes", "Focus Duration (minutes)", 1, 180, 1)
	obs.obs_properties_add_int(props, "break_duration_minutes", "Break Duration (minutes)", 1, 60, 1)
	obs.obs_properties_add_int(props, "session_limit", "Session Limit", 1, 20, 1)

	-- Messages
	obs.obs_properties_add_text(props, "focus_message", "Focus Message", obs.OBS_TEXT_DEFAULT)
	obs.obs_properties_add_text(props, "break_message", "Break Message", obs.OBS_TEXT_DEFAULT)
	obs.obs_properties_add_text(props, "session_limit_message", "Session Limit Message", obs.OBS_TEXT_DEFAULT)

	obs.obs_properties_add_bool(props, "fast_mode", "Enable Fast Mode (Testing)")

	-- Break BGM configuration
	obs.obs_properties_add_bool(props, "break_bgm_enabled", "Enable Break BGM")
	obs.obs_properties_add_text(props, "break_bgm_source", "Break BGM Source", obs.OBS_TEXT_DEFAULT)

	-- Session Limit Music configuration
	obs.obs_properties_add_bool(props, "session_limit_music_enabled", "Enable Session Limit Music")
	obs.obs_properties_add_text(props, "session_limit_music_source", "Session Limit Music Source", obs.OBS_TEXT_DEFAULT)

	return props
end

function script_update(settings)
	source_name = obs.obs_data_get_string(settings, "source_name")
	alert_sound_source = obs.obs_data_get_string(settings, "alert_sound_source")
	focus_duration_minutes = obs.obs_data_get_int(settings, "focus_duration_minutes")
	break_duration_minutes = obs.obs_data_get_int(settings, "break_duration_minutes")
	session_limit = obs.obs_data_get_int(settings, "session_limit")

	focus_message = obs.obs_data_get_string(settings, "focus_message")
	break_message = obs.obs_data_get_string(settings, "break_message")
	session_limit_message = obs.obs_data_get_string(settings, "session_limit_message")

	fast_mode = obs.obs_data_get_bool(settings, "fast_mode")
	time_multiplier = fast_mode and 60 or 1

	break_bgm_enabled = obs.obs_data_get_bool(settings, "break_bgm_enabled")
	break_bgm_source = obs.obs_data_get_string(settings, "break_bgm_source")

	session_limit_music_enabled = obs.obs_data_get_bool(settings, "session_limit_music_enabled")
	session_limit_music_source = obs.obs_data_get_string(settings, "session_limit_music_source")
end

function script_load(settings)
	-- Additional initialization if needed
end

function script_unload()
	stop_timer()
end

-- Optional functions to bind to hotkeys for manual control:
function start_timer_button(pressed)
	if pressed then
		start_timer()
	end
end

function stop_timer_button(pressed)
	if pressed then
		stop_timer()
	end
end
