local mp = require "mp"

-- Wallpaper configuration
local HOME = os.getenv("HOME") or "."
local WALLPAPER_DIR = HOME .. "/Pictures/Wallpapers"
local DEFAULT_WALLPAPER = WALLPAPER_DIR .. "/nino.png"

-- Persistent cache configuration
local CACHE_DIR = "/tmp/mpv-pause-cache"
local CACHE_VERSION = 5
local CACHE_TTL_MINUTES = 10080
local STALE_TEMP_TTL_MINUTES = 1440

-- Wallpaper cache resolution
local CACHE_WIDTH = 2560
local CACHE_HEIGHT = 1440

-- Animation configuration
local CIRCLE_FPS = 60
local FRAME_COUNT = 49
local CIRCLE_DURATION = (FRAME_COUNT - 1) / CIRCLE_FPS
local CIRCLE_FEATHER = 4
local RANDOM_MARGIN = 0.12

-- FFmpeg performance
local FFMPEG_FILTER_THREADS = 2
local FFMPEG_NICE_LEVEL = 10

-- Overlay configuration
local OVERLAY_ID = 10

-- Transition safety timeouts
local CACHE_WAIT_TIMEOUT = 30
local NAVIGATION_WATCHDOG_TIMEOUT = 3
local RELEASE_HOOK_TIMEOUT = 5

-- Derived constants
local MAX_STEP = FRAME_COUNT - 1
local FRAME_SIZE = CACHE_WIDTH * CACHE_HEIGHT * 4
local STRIDE = CACHE_WIDTH * 4
local EXPECTED_CACHE_SIZE = FRAME_SIZE * FRAME_COUNT

-- Generate a unique temporary-file suffix for this mpv process.
local token_path = os.tmpname()
local instance_id = token_path:match("([^/]+)$") or tostring(os.time())
os.remove(token_path)

-- Session wallpaper assignments.
-- Each playlist entry keeps the same wallpaper for this mpv session.
local session_wallpapers = {}
local used_wallpapers = {}
local first_video_selection = true

-- Cache state.
local cache_entries = {}
local pending_cache = nil
local cache_queue = {}
local queued_cache_keys = {}
local conversion_id = nil
local generation = 0

-- The default wallpaper has a dedicated reusable fallback cache.
local default_wallpaper_identity = nil
local default_cache_entry = nil
local pending_pause_cache = nil

-- Playback state.
local file_loaded = mp.get_property("path") ~= nil
    and mp.get_property("path") ~= ""

local desired_paused = mp.get_property_bool("pause") or false
local pause_wait_key = nil
local current_entry_key = nil
local loading_entry_key = nil

local current_wallpaper = nil
local active_cache = nil
local display_cache = nil

-- Overlay and animation state.
local overlay_visible = false
local current_step = 0
local transition_timer = nil
local transition_start_time = 0
local transition_start_step = 0
local transition_target_step = 0
local transition_duration = 0
local transition_mode = nil
local phase = "idle"

-- Playlist transition state.
local playlist_transition = false
local cover_complete = false
local new_video_ready = false
local pending_navigation_command = nil
local pending_playlist_hook = nil
local pending_navigation_delta = 0
local waiting_for_default_transition_cache = false

local playlist_transition_timeout = nil
local navigation_watchdog = nil
local release_hook_timer = nil
local release_next_start_hook = false

-- Forward declarations.
local start_transition
local finish_transition
local ensure_cache_for_identity
local assign_wallpaper_for_entry
local handle_pause
local continue_playlist_transition
local skip_playlist_transition
local arm_playlist_transition_timeout
local start_navigation_watchdog
local queue_cache_identity
local process_cache_queue
local navigate_playlist_by_delta

math.randomseed(
    os.time() + math.floor(os.clock() * 1000000)
)

-- Utility functions.
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local function smootherstep(value)
    local t = clamp(value, 0, 1)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function run_subprocess(args)
    local success, result = pcall(mp.command_native, {
        name = "subprocess",
        args = args,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    })

    if not success then
        return nil, tostring(result)
    end

    if not result or result.status ~= 0 then
        return nil, tostring(
            result and result.stderr or "Subprocess failed"
        )
    end

    return result
end

local function file_size(path)
    local file = io.open(path, "rb")

    if not file then
        return nil
    end

    local size = file:seek("end")
    file:close()

    return size
end

local function file_exists(path)
    return file_size(path) ~= nil
end

local function parse_null_paths(output)
    local paths = {}
    local cursor = 1

    while cursor <= #output do
        local delimiter = output:find("\0", cursor, true)

        if not delimiter then
            break
        end

        local path = output:sub(cursor, delimiter - 1)

        if path ~= "" then
            paths[#paths + 1] = path
        end

        cursor = delimiter + 1
    end

    return paths
end

local function ensure_cache_directory()
    local result, error_message = run_subprocess({
        "mkdir",
        "-p",
        "-m",
        "700",
        CACHE_DIR
    })

    if not result then
        mp.msg.error(
            "[pause-cache] ERROR: Cache directory: "
            .. tostring(error_message)
        )

        return false
    end

    return true
end

-- Update the cache modification time only when the cache is actually used.
local function mark_cache_used(entry)
    if not entry or not entry.path then
        return
    end

    if file_size(entry.path) ~= EXPECTED_CACHE_SIZE then
        return
    end

    local result, error_message = run_subprocess({
        "touch",
        "-m",
        "-c",
        "--",
        entry.path
    })

    if not result then
        mp.msg.warn(
            "[pause-cache] WARNING: Unable to update cache timestamp: "
            .. tostring(error_message)
        )
    end
end

-- Run once when this mpv session starts.
local function cleanup_expired_caches()
    if not ensure_cache_directory() then
        return
    end

    local invalid_count = 0
    local expired_count = 0
    local temporary_count = 0

    local all_result, all_error = run_subprocess({
        "find",
        CACHE_DIR,
        "-type",
        "f",
        "-name",
        "*.bgra",
        "-print0"
    })

    if not all_result then
        mp.msg.error(
            "[pause-cache] ERROR: Cache scan failed: "
            .. tostring(all_error)
        )

        return
    end

    -- Remove incomplete or invalid permanent cache files.
    for _, path in ipairs(
        parse_null_paths(all_result.stdout or "")
    ) do
        if file_size(path) ~= EXPECTED_CACHE_SIZE then
            if os.remove(path) then
                invalid_count = invalid_count + 1
            end
        end
    end

    -- Remove valid caches that have not been used for more than seven days.
    local expired_result, expired_error = run_subprocess({
        "find",
        CACHE_DIR,
        "-type",
        "f",
        "-name",
        "*.bgra",
        "-mmin",
        "+" .. tostring(CACHE_TTL_MINUTES),
        "-print0"
    })

    if not expired_result then
        mp.msg.error(
            "[pause-cache] ERROR: Expiration scan failed: "
            .. tostring(expired_error)
        )

        return
    end

    for _, path in ipairs(
        parse_null_paths(expired_result.stdout or "")
    ) do
        if file_size(path) == EXPECTED_CACHE_SIZE then
            if os.remove(path) then
                expired_count = expired_count + 1
            end
        end
    end

    -- Remove abandoned temporary files older than 24 hours.
    local temporary_result, temporary_error = run_subprocess({
        "find",
        CACHE_DIR,
        "-type",
        "f",
        "-name",
        "*.tmp",
        "-mmin",
        "+" .. tostring(STALE_TEMP_TTL_MINUTES),
        "-print0"
    })

    if temporary_result then
        for _, path in ipairs(
            parse_null_paths(temporary_result.stdout or "")
        ) do
            if os.remove(path) then
                temporary_count = temporary_count + 1
            end
        end
    else
        mp.msg.warn(
            "[pause-cache] WARNING: Temporary cleanup failed: "
            .. tostring(temporary_error)
        )
    end

    mp.msg.info(
        string.format(
            "[pause-cache] CLEANUP: expired=%d | invalid=%d | abandoned_temp=%d",
            expired_count,
            invalid_count,
            temporary_count
        )
    )
end

-- Find PNG wallpapers recursively.
local function scan_wallpapers()
    local result, error_message = run_subprocess({
        "find",
        WALLPAPER_DIR,
        "-type",
        "f",
        "-iname",
        "*.png",
        "-print0"
    })

    if not result then
        mp.msg.warn(
            "[pause-cache] WARNING: Wallpaper scan failed: "
            .. tostring(error_message)
        )

        return {}
    end

    return parse_null_paths(result.stdout or "")
end

-- Select a wallpaper for a playlist entry that has no session assignment.
local function select_new_wallpaper()
    if first_video_selection then
        first_video_selection = false

        if file_exists(DEFAULT_WALLPAPER) then
            mp.msg.info(
                "[pause-cache] WALLPAPER: using default wallpaper."
            )

            return DEFAULT_WALLPAPER
        end
    end

    local files = scan_wallpapers()

    if #files == 0 then
        if file_exists(DEFAULT_WALLPAPER) then
            return DEFAULT_WALLPAPER
        end

        mp.msg.error(
            "[pause-cache] ERROR: No PNG wallpaper found."
        )

        return nil
    end

    local candidates = {}

    for _, path in ipairs(files) do
        if not used_wallpapers[path] then
            candidates[#candidates + 1] = path
        end
    end

    if #candidates == 0 then
        candidates = files
    end

    return candidates[math.random(1, #candidates)]
end

-- Generate a stable cache key from the source wallpaper and cache settings.
local function hash_string(value)
    local hash_a = 5381
    local hash_b = 52711

    for index = 1, #value do
        local byte = value:byte(index)

        hash_a = (hash_a * 33 + byte) % 2147483647
        hash_b = (hash_b * 65599 + byte) % 2147483647
    end

    return string.format("%08x%08x", hash_a, hash_b)
end

local function get_file_signature(path)
    local result, error_message = run_subprocess({
        "stat",
        "-c",
        "%Y:%s:%i",
        "--",
        path
    })

    if not result then
        mp.msg.error(
            "[pause-cache] ERROR: Unable to inspect wallpaper: "
            .. tostring(error_message)
        )

        return nil
    end

    return (result.stdout or ""):match("^%s*(.-)%s*$")
end

local function build_cache_identity(wallpaper)
    local signature = get_file_signature(wallpaper)

    if not signature then
        return nil
    end

    local basename = wallpaper:match("([^/]+)$") or "wallpaper"
    basename = basename:gsub("%.[^%.]+$", "")
    basename = basename:gsub("[^%w%-_]", "_")
    basename = basename:sub(1, 48)

    if basename == "" then
        basename = "wallpaper"
    end

    local configuration = table.concat({
        tostring(CACHE_VERSION),
        tostring(CACHE_WIDTH),
        tostring(CACHE_HEIGHT),
        tostring(CIRCLE_FPS),
        tostring(FRAME_COUNT),
        tostring(CIRCLE_FEATHER),
        "smootherstep"
    }, ":")

    local fingerprint = table.concat({
        wallpaper,
        signature,
        configuration
    }, "\0")

    local hash = hash_string(fingerprint)

    local filename = string.format(
        "%s_%s_v%d.bgra",
        basename,
        hash,
        CACHE_VERSION
    )

    local cache_path = CACHE_DIR .. "/" .. filename

    return {
        key = filename,
        hash = hash,
        wallpaper = wallpaper,
        path = cache_path,
        tmp_path = cache_path .. "." .. instance_id .. ".tmp"
    }
end

-- Generate a deterministic circle origin for each wallpaper cache.
local function generate_circle_position(identity)
    local seed = tonumber(identity.hash:sub(1, 8), 16) or 1
    seed = (seed % 2147483646) + 1

    local function next_random()
        seed = (seed * 48271) % 2147483647
        return seed / 2147483647
    end

    local min_x = math.floor(CACHE_WIDTH * RANDOM_MARGIN)
    local max_x = math.floor(CACHE_WIDTH * (1 - RANDOM_MARGIN))
    local min_y = math.floor(CACHE_HEIGHT * RANDOM_MARGIN)
    local max_y = math.floor(CACHE_HEIGHT * (1 - RANDOM_MARGIN))

    local center_x = min_x + math.floor(
        next_random() * (max_x - min_x + 1)
    )

    local center_y = min_y + math.floor(
        next_random() * (max_y - min_y + 1)
    )

    local farthest_x = math.max(
        center_x,
        CACHE_WIDTH - center_x
    )

    local farthest_y = math.max(
        center_y,
        CACHE_HEIGHT - center_y
    )

    local max_radius = math.sqrt(
        farthest_x * farthest_x
        + farthest_y * farthest_y
    ) + CIRCLE_FEATHER

    return center_x, center_y, max_radius
end

local function create_cache_entry(identity)
    local center_x, center_y, max_radius =
        generate_circle_position(identity)

    return {
        key = identity.key,
        hash = identity.hash,
        wallpaper = identity.wallpaper,
        path = identity.path,
        tmp_path = identity.tmp_path,
        center_x = center_x,
        center_y = center_y,
        max_radius = max_radius,
        ready = true
    }
end

local function load_disk_cache(identity)
    if file_size(identity.path) ~= EXPECTED_CACHE_SIZE then
        return nil
    end

    return create_cache_entry(identity)
end

local function get_cached_entry(identity)
    if not identity then
        return nil
    end

    local entry = cache_entries[identity.key]

    if entry then
        if file_size(entry.path) == EXPECTED_CACHE_SIZE then
            return entry
        end

        cache_entries[identity.key] = nil
    end

    entry = load_disk_cache(identity)

    if entry then
        cache_entries[identity.key] = entry
    end

    if entry
        and default_wallpaper_identity
        and identity.key == default_wallpaper_identity.key then

        default_cache_entry = entry
    end

    return entry
end

-- Session assignment: returning to a playlist entry reuses its wallpaper.
local function get_wallpaper_for_entry(entry_key)
    local existing = session_wallpapers[entry_key]

    if existing then
        mp.msg.info(
            string.format(
                "[pause-cache] SESSION REUSE: entry=%s | wallpaper=%s",
                entry_key,
                existing.wallpaper
            )
        )

        return existing
    end

    local wallpaper = select_new_wallpaper()

    if not wallpaper then
        return nil
    end

    local identity = build_cache_identity(wallpaper)

    if not identity then
        return nil
    end

    session_wallpapers[entry_key] = identity
    used_wallpapers[wallpaper] = true

    mp.msg.info(
        string.format(
            "[pause-cache] SESSION ASSIGN: entry=%s | wallpaper=%s",
            entry_key,
            wallpaper
        )
    )

    return identity
end

-- Display geometry.
local function get_display_geometry()
    local width = mp.get_property_number("osd-width", 0)
    local height = mp.get_property_number("osd-height", 0)

    if width <= 0 or height <= 0 then
        return nil
    end

    local scale = math.max(
        width / CACHE_WIDTH,
        height / CACHE_HEIGHT
    )

    local display_width = CACHE_WIDTH * scale
    local display_height = CACHE_HEIGHT * scale

    local base_x = (width - display_width) / 2
    local base_y = (height - display_height) / 2

    return scale, base_x, base_y
end

local function apply_frame(step)
    if not display_cache or not display_cache.ready then
        return false
    end

    local scale, base_x, base_y = get_display_geometry()

    if not scale then
        return false
    end

    -- Keep the overlay geometry identical for every animation frame.
    -- Only the cache offset changes, so the wallpaper cannot shift while
    -- mpv rescales differently sized crop regions.
    local display_x = math.floor(base_x + 0.5)
    local display_y = math.floor(base_y + 0.5)

    local display_width = math.max(
        1,
        math.floor(CACHE_WIDTH * scale + 0.5)
    )

    local display_height = math.max(
        1,
        math.floor(CACHE_HEIGHT * scale + 0.5)
    )

    local offset = step * FRAME_SIZE

    mp.command_native({
        name = "overlay-add",
        id = OVERLAY_ID,
        x = display_x,
        y = display_y,
        file = display_cache.path,
        offset = offset,
        fmt = "bgra",
        w = CACHE_WIDTH,
        h = CACHE_HEIGHT,
        stride = STRIDE,
        dw = display_width,
        dh = display_height
    })

    current_step = step
    overlay_visible = true

    return true
end

local function clear_timer(timer)
    if timer then
        timer:kill()
    end
end

local function cancel_transition()
    clear_timer(transition_timer)
    transition_timer = nil
    transition_mode = nil
end

local function remove_overlay()
    cancel_transition()

    if overlay_visible then
        mp.command_native({
            name = "overlay-remove",
            id = OVERLAY_ID
        })
    end

    overlay_visible = false
    current_step = 0
    display_cache = nil
    phase = "idle"
end

-- Playlist transition watchdog: restore the current picture if no new
-- file starts after a navigation command, for example at the playlist end.
start_navigation_watchdog = function()
    clear_timer(navigation_watchdog)

    local previous_entry = current_entry_key

    navigation_watchdog = mp.add_timeout(
        NAVIGATION_WATCHDOG_TIMEOUT,
        function()
            navigation_watchdog = nil

            if not playlist_transition
                or not cover_complete
                or current_entry_key ~= previous_entry
                or loading_entry_key then
                return
            end

            mp.msg.warn(
                "[pause-cache] TRANSITION: no next file started; restoring current video."
            )

            pending_navigation_command = nil
            pending_playlist_hook = nil

            start_transition(
                0,
                "playlist_cancel_reveal",
                display_cache
            )
        end
    )
end

-- Continue loading only after the cover animation reaches full screen.
continue_playlist_transition = function()
    clear_timer(playlist_transition_timeout)
    playlist_transition_timeout = nil

    cover_complete = true
    phase = "waiting_next_video"

    if pending_navigation_command then
        pending_navigation_command = nil

        local navigation_delta = pending_navigation_delta
        pending_navigation_delta = 0

        mp.msg.info(
            "[pause-cache] TRANSITION: full cover reached; starting navigation."
        )

        if navigation_delta ~= 0 then
            local navigation_started =
                navigate_playlist_by_delta(navigation_delta, true)

            if not navigation_started then
                start_transition(
                    0,
                    "playlist_cancel_reveal",
                    display_cache
                )
            end
        else
            start_transition(
                0,
                "playlist_cancel_reveal",
                display_cache
            )
        end

        return
    end

    if pending_playlist_hook then
        local hook = pending_playlist_hook
        pending_playlist_hook = nil

        mp.msg.info(
            "[pause-cache] TRANSITION: full cover reached; continuing file loading."
        )

        start_navigation_watchdog()
        hook:cont()

        return
    end

    mp.msg.warn(
        "[pause-cache] TRANSITION: no pending navigation request."
    )
end

local function arm_playlist_transition_timeout()
    clear_timer(playlist_transition_timeout)

    playlist_transition_timeout = mp.add_timeout(
        CACHE_WAIT_TIMEOUT,
        function()
            playlist_transition_timeout = nil

            if not playlist_transition or cover_complete then
                return
            end

            if display_cache
                and display_cache.ready
                and apply_frame(MAX_STEP) then

                current_step = MAX_STEP

                mp.msg.warn(
                    "[pause-cache] TRANSITION: forcing full cover after timeout."
                )

                continue_playlist_transition()
            else
                skip_playlist_transition(
                    "wallpaper cache was not ready before timeout"
                )
            end
        end
    )
end

skip_playlist_transition = function(reason)
    clear_timer(playlist_transition_timeout)
    playlist_transition_timeout = nil

    clear_timer(navigation_watchdog)
    navigation_watchdog = nil

    cancel_transition()

    local command = pending_navigation_command
    local hook = pending_playlist_hook
    local navigation_delta = pending_navigation_delta

    pending_navigation_command = nil
    pending_playlist_hook = nil
    pending_navigation_delta = 0
    waiting_for_default_transition_cache = false

    playlist_transition = false
    cover_complete = false
    new_video_ready = false

    if overlay_visible then
        remove_overlay()
    end

    phase = "ready"

    mp.msg.warn(
        "[pause-cache] TRANSITION: skipped: " .. tostring(reason)
    )

    if command then
        if navigation_delta ~= 0 then
            navigate_playlist_by_delta(navigation_delta, false)
        end
    elseif hook then
        pending_navigation_delta = navigation_delta
        hook:cont()
    end
end

-- Activate a cache for the current video.
local function activate_cache(entry)
    if not current_wallpaper
        or current_wallpaper.key ~= entry.key then
        return
    end

    active_cache = entry

    mp.msg.info(
        string.format(
            "[pause-cache] CACHE: ready %s",
            entry.key
        )
    )

    -- A pending navigation waits for this video's cache before covering.
    if playlist_transition
        and not cover_complete
        and (
            pending_navigation_command
            or pending_playlist_hook
        ) then

        start_transition(
            MAX_STEP,
            "playlist_cover",
            entry
        )

        return
    end

    if file_loaded and desired_paused and not playlist_transition then
        -- If the default fallback is still animating in, finish that motion
        -- first. The newly ready video cache is applied once the screen is
        -- fully covered, avoiding a visible jump between circle origins.
        if display_cache
            and display_cache.key ~= entry.key
            and overlay_visible
            and transition_mode == "pause_in"
            and current_step < MAX_STEP then

            pending_pause_cache = entry

            mp.msg.info(
                "[pause-cache] PAUSE: next wallpaper cache ready; switching after fallback cover."
            )

            return
        end

        pending_pause_cache = nil

        start_transition(
            MAX_STEP,
            "pause_in",
            entry
        )
    else
        phase = "ready"
    end
end

-- Generate a persistent cache only when no valid cache exists.
local function start_cache_generation(identity)
    if pending_cache or conversion_id then
        return
    end

    generation = generation + 1

    local current_generation = generation
    local entry = create_cache_entry(identity)

    entry.ready = false
    entry.tmp_path = identity.tmp_path
    pending_cache = entry

    local t = "(N/" .. tostring(MAX_STEP) .. ")"

    local easing =
        "(6*" .. t .. "*" .. t .. "*" .. t .. "*" .. t .. "*" .. t ..
        "-15*" .. t .. "*" .. t .. "*" .. t .. "*" .. t ..
        "+10*" .. t .. "*" .. t .. "*" .. t .. ")"

    local radius_expression = string.format(
        "(1+(%.6f-1)*%s)",
        entry.max_radius,
        easing
    )

    local distance_expression = string.format(
        "sqrt((X-%d)*(X-%d)+(Y-%d)*(Y-%d))",
        entry.center_x,
        entry.center_x,
        entry.center_y,
        entry.center_y
    )

    local alpha_expression = string.format(
        "255*clip((%s-%s+%d)/%d\\,0\\,1)",
        radius_expression,
        distance_expression,
        CIRCLE_FEATHER,
        CIRCLE_FEATHER * 2
    )

    -- Keep source RGB intact and generate only the alpha mask.
    local filter = string.format(
        "[0:v]" ..
        "scale=%d:%d:force_original_aspect_ratio=increase:flags=lanczos," ..
        "crop=%d:%d:(in_w-%d)/2:(in_h-%d)/2," ..
        "format=rgb24,split=2[base][maskbase];" ..
        "[maskbase]" ..
        "format=gray," ..
        "geq=lum='%s'[alpha];" ..
        "[base][alpha]" ..
        "alphamerge," ..
        "format=gbrap," ..
        "premultiply=inplace=1," ..
        "format=bgra[out]",

        CACHE_WIDTH,
        CACHE_HEIGHT,
        CACHE_WIDTH,
        CACHE_HEIGHT,
        CACHE_WIDTH,
        CACHE_HEIGHT,
        alpha_expression
    )

    mp.msg.info(
        string.format(
            "[pause-cache] PRE: wallpaper=%s | cache=%s | origin=(%d, %d)",
            identity.wallpaper,
            identity.key,
            entry.center_x,
            entry.center_y
        )
    )

    local args = {
        "nice",
        "-n",
        tostring(FFMPEG_NICE_LEVEL),
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
        "-filter_complex_threads",
        tostring(FFMPEG_FILTER_THREADS),
        "-loop",
        "1",
        "-framerate",
        tostring(CIRCLE_FPS),
        "-i",
        identity.wallpaper,
        "-filter_complex",
        filter,
        "-map",
        "[out]",
        "-frames:v",
        tostring(FRAME_COUNT),
        "-pix_fmt",
        "bgra",
        "-f",
        "rawvideo",
        identity.tmp_path
    }

    local function on_conversion_complete(success, result, error_message)
        if pending_cache ~= entry
            or generation ~= current_generation then

            os.remove(entry.tmp_path)
            return
        end

        conversion_id = nil

        if not success or not result or result.status ~= 0 then
            mp.msg.error(
                "[pause-cache] ERROR: FFmpeg failed: "
                .. tostring(error_message or "Unknown error")
            )

            os.remove(entry.tmp_path)
            pending_cache = nil

            if playlist_transition
                and not cover_complete
                and (
                    pending_navigation_command
                    or pending_playlist_hook
                ) then

                skip_playlist_transition("FFmpeg cache generation failed")
            elseif current_wallpaper
                and current_wallpaper.key ~= entry.key then

                queue_cache_identity(current_wallpaper, false)
            end

            process_cache_queue()
            return
        end

        -- A cache is committed only after its exact expected size is verified.
        local actual_size = file_size(entry.tmp_path)

        if actual_size ~= EXPECTED_CACHE_SIZE then
            mp.msg.error(
                string.format(
                    "[pause-cache] ERROR: Invalid cache size (%s / %s).",
                    tostring(actual_size),
                    tostring(EXPECTED_CACHE_SIZE)
                )
            )

            os.remove(entry.tmp_path)
            pending_cache = nil

            if playlist_transition
                and not cover_complete
                and (
                    pending_navigation_command
                    or pending_playlist_hook
                ) then

                skip_playlist_transition("generated cache is incomplete")
            end

            process_cache_queue()
            return
        end

        -- Reuse an already completed cache if another mpv process created it.
        if file_size(identity.path) == EXPECTED_CACHE_SIZE then
            os.remove(entry.tmp_path)
        else
            local renamed, rename_error = os.rename(
                entry.tmp_path,
                identity.path
            )

            if not renamed then
                mp.msg.error(
                    "[pause-cache] ERROR: Unable to commit cache: "
                    .. tostring(rename_error)
                )

                os.remove(entry.tmp_path)
                pending_cache = nil

                if playlist_transition
                    and not cover_complete
                    and (
                        pending_navigation_command
                        or pending_playlist_hook
                    ) then

                    skip_playlist_transition("cache commit failed")
                end

                process_cache_queue()
                return
            end
        end

        entry.path = identity.path
        entry.tmp_path = nil
        entry.ready = true

        cache_entries[entry.key] = entry
        pending_cache = nil

        if default_wallpaper_identity
            and entry.key == default_wallpaper_identity.key then

            default_cache_entry = entry

            mp.msg.info(
                "[pause-cache] DEFAULT CACHE: ready."
            )

            -- A playlist transition waiting for the fallback can start
            -- immediately. Do not wait for the current video's cache.
            if playlist_transition
                and not cover_complete
                and waiting_for_default_transition_cache
                and (
                    pending_navigation_command
                    or pending_playlist_hook
                ) then

                waiting_for_default_transition_cache = false

                mp.msg.info(
                    "[pause-cache] TRANSITION: default cache ready; starting cover."
                )

                start_transition(
                    MAX_STEP,
                    "playlist_cover",
                    entry
                )
            end

            -- Use the default cache only when the current video's own cache
            -- is still unavailable. Never replace a ready video cache with
            -- the fallback just because the default conversion finished later.
            if file_loaded
                and desired_paused
                and current_wallpaper
                and current_wallpaper.key ~= entry.key
                and not playlist_transition then

                local video_cache = get_cached_entry(current_wallpaper)
                local video_cache_ready = video_cache ~= nil

                if video_cache_ready then
                    activate_cache(video_cache)
                else
                    mp.msg.info(
                        "[pause-cache] PAUSE: displaying default cache while waiting for the video wallpaper."
                    )

                    start_transition(
                        MAX_STEP,
                        "pause_in",
                        entry
                    )
                end
            end
        end

        mp.msg.info(
            string.format(
                "[pause-cache] READY: %s | %.1f MiB | %d frames",
                entry.key,
                EXPECTED_CACHE_SIZE / 1024 / 1024,
                FRAME_COUNT
            )
        )

        if current_wallpaper
            and current_wallpaper.key == entry.key
            and file_loaded then

            activate_cache(entry)
        elseif current_wallpaper
            and current_wallpaper.key ~= entry.key
            and not playlist_transition then

            queue_cache_identity(current_wallpaper, false)
        end

        process_cache_queue()
    end

    local success, request_id = pcall(
        mp.command_native_async,
        {
            name = "subprocess",
            args = args,
            playback_only = false
        },
        on_conversion_complete
    )

    if not success or not request_id then
        mp.msg.error(
            "[pause-cache] ERROR: Unable to start FFmpeg: "
            .. tostring(request_id)
        )

        os.remove(identity.tmp_path)
        pending_cache = nil

        if playlist_transition
            and not cover_complete
            and (
                pending_navigation_command
                or pending_playlist_hook
            ) then

            skip_playlist_transition("unable to start FFmpeg")
        end

        process_cache_queue()
        return
    end

    conversion_id = request_id
end

-- Queue cache requests so the default fallback can take priority when
-- playback is paused, without cancelling a valid FFmpeg generation.
queue_cache_identity = function(identity, priority)
    if not identity then
        return
    end

    if pending_cache and pending_cache.key == identity.key then
        return
    end

    local cached_entry = get_cached_entry(identity)

    if cached_entry then
        if default_wallpaper_identity
            and identity.key == default_wallpaper_identity.key then
            default_cache_entry = cached_entry
        end

        return
    end

    local existing_index = nil

    for index, queued_identity in ipairs(cache_queue) do
        if queued_identity.key == identity.key then
            existing_index = index
            break
        end
    end

    if existing_index then
        if priority and existing_index > 1 then
            table.remove(cache_queue, existing_index)
            table.insert(cache_queue, 1, identity)
        end

        return
    end

    if priority then
        table.insert(cache_queue, 1, identity)
    else
        cache_queue[#cache_queue + 1] = identity
    end

    queued_cache_keys[identity.key] = true
end

process_cache_queue = function()
    if pending_cache then
        return
    end

    while #cache_queue > 0 do
        local identity = table.remove(cache_queue, 1)
        queued_cache_keys[identity.key] = nil

        local cached_entry = get_cached_entry(identity)

        if cached_entry then
            if default_wallpaper_identity
                and identity.key == default_wallpaper_identity.key then
                default_cache_entry = cached_entry
            end

            if current_wallpaper
                and current_wallpaper.key == identity.key
                and file_loaded then
                activate_cache(cached_entry)
            elseif default_wallpaper_identity
                and identity.key == default_wallpaper_identity.key
                and file_loaded
                and desired_paused
                and current_wallpaper
                and not playlist_transition then

                local video_cache = get_cached_entry(current_wallpaper)

                if video_cache then
                    activate_cache(video_cache)
                else
                    start_transition(
                        MAX_STEP,
                        "pause_in",
                        cached_entry
                    )
                end
            end
        else
            mp.msg.info(
                string.format(
                    "[pause-cache] CACHE MISS: %s",
                    identity.key
                )
            )

            if not ensure_cache_directory() then
                if playlist_transition then
                    skip_playlist_transition("cache directory unavailable")
                end

                return
            end

            start_cache_generation(identity)
            return
        end
    end
end


-- Cancel only unfinished non-default work. Completed cache files are never
-- touched, and the default cache job is preserved if it is already running.
local function cancel_non_default_cache_work(reason)
    local default_key = default_wallpaper_identity
        and default_wallpaper_identity.key
        or nil

    if pending_cache and pending_cache.key ~= default_key then
        local cancelled_entry = pending_cache
        local cancelled_request = conversion_id

        generation = generation + 1
        pending_cache = nil
        conversion_id = nil

        if cancelled_request then
            pcall(mp.abort_async_command, cancelled_request)
        end

        if cancelled_entry.tmp_path then
            os.remove(cancelled_entry.tmp_path)
        end

        mp.msg.info(
            string.format(
                "[pause-cache] CACHE: cancelled unfinished wallpaper generation (%s): %s",
                tostring(reason),
                cancelled_entry.key
            )
        )
    end

    local retained_queue = {}
    local retained_keys = {}

    for _, identity in ipairs(cache_queue) do
        if identity.key == default_key then
            retained_queue[#retained_queue + 1] = identity
            retained_keys[identity.key] = true
        else
            mp.msg.info(
                "[pause-cache] CACHE: skipped queued wallpaper during playlist navigation: "
                .. identity.key
            )
        end
    end

    cache_queue = retained_queue
    queued_cache_keys = retained_keys
end

-- Use the dedicated default wallpaper as the transition fallback whenever
-- the current video's cache is not complete yet.
local function start_default_transition_fallback()
    if not default_wallpaper_identity then
        skip_playlist_transition("default wallpaper is unavailable")
        return
    end

    cancel_non_default_cache_work("playlist transition fallback")

    local fallback_entry = default_cache_entry
        or get_cached_entry(default_wallpaper_identity)

    if fallback_entry then
        default_cache_entry = fallback_entry
        waiting_for_default_transition_cache = false

        mp.msg.info(
            "[pause-cache] TRANSITION: using ready default cache."
        )

        start_transition(
            MAX_STEP,
            "playlist_cover",
            fallback_entry
        )

        return
    end

    waiting_for_default_transition_cache = true

    mp.msg.info(
        "[pause-cache] TRANSITION: waiting for default cache."
    )

    ensure_cache_for_identity(default_wallpaper_identity)
end

-- Resolve cache: memory, disk, then FFmpeg.
ensure_cache_for_identity = function(identity)
    if not identity then
        return
    end

    local entry = get_cached_entry(identity)

    if entry then
        if default_wallpaper_identity
            and identity.key == default_wallpaper_identity.key then
            default_cache_entry = entry
        end

        mp.msg.info(
            string.format(
                "[pause-cache] CACHE HIT: %s",
                identity.key
            )
        )

        activate_cache(entry)
        return
    end

    if pending_cache then
        if pending_cache.key == identity.key then
            return
        end

        local is_default_priority = desired_paused
            and default_wallpaper_identity
            and identity.key == default_wallpaper_identity.key

        queue_cache_identity(identity, is_default_priority)
        return
    end

    if #cache_queue > 0 then
        local is_default_priority = desired_paused
            and default_wallpaper_identity
            and identity.key == default_wallpaper_identity.key

        queue_cache_identity(identity, is_default_priority)
        process_cache_queue()
        return
    end

    mp.msg.info(
        string.format(
            "[pause-cache] CACHE MISS: %s",
            identity.key
        )
    )

    if not ensure_cache_directory() then
        if playlist_transition then
            skip_playlist_transition("cache directory unavailable")
        end

        return
    end

    start_cache_generation(identity)
end

-- Assign the wallpaper to a playlist entry and prepare its cache.
assign_wallpaper_for_entry = function(entry_key)
    if not file_loaded or not entry_key then
        return
    end

    local identity = get_wallpaper_for_entry(entry_key)

    if not identity then
        return
    end

    current_wallpaper = identity
    active_cache = nil

    mp.msg.info(
        string.format(
            "[pause-cache] WALLPAPER: entry=%s | %s",
            entry_key,
            identity.wallpaper
        )
    )

    ensure_cache_for_identity(identity)

    if desired_paused and not active_cache then
        handle_pause(true)
    end
end

-- Finish a transition mode.
finish_transition = function(mode)
    transition_mode = nil

    if mode == "pause_in" then
        phase = "paused"

        -- If the default cache was used as a temporary fallback, switch to
        -- the current video's cache after the fallback animation completes.
        if pending_pause_cache
            and desired_paused
            and file_loaded
            and not playlist_transition then

            local next_entry = pending_pause_cache
            pending_pause_cache = nil

            mp.msg.info(
                "[pause-cache] PAUSE: switching to the current video's cache."
            )

            start_transition(
                MAX_STEP,
                "pause_in",
                next_entry
            )

            return
        end

        mp.msg.info(
            "[pause-cache] PAUSE: wallpaper displayed."
        )

        return
    end

    if mode == "pause_out" then
        remove_overlay()
        phase = "ready"
        return
    end

    if mode == "playlist_cover" then
        current_step = MAX_STEP
        phase = "waiting_next_video"

        mp.msg.info(
            "[pause-cache] TRANSITION: full cover reached; holding frame."
        )

        -- Keep the overlay visible. Navigation starts only now.
        continue_playlist_transition()
        return
    end

    if mode == "playlist_reveal" then
        remove_overlay()

        clear_timer(navigation_watchdog)
        navigation_watchdog = nil

        clear_timer(playlist_transition_timeout)
        playlist_transition_timeout = nil

        playlist_transition = false
        cover_complete = false
        new_video_ready = false

        pending_navigation_command = nil
        pending_playlist_hook = nil
        pending_navigation_delta = 0
        waiting_for_default_transition_cache = false
        pending_pause_cache = nil

        current_wallpaper = nil
        active_cache = nil

        phase = "ready"

        mp.msg.info(
            "[pause-cache] TRANSITION: new video revealed."
        )

        -- The new video's wallpaper is selected only after its reveal.
        assign_wallpaper_for_entry(current_entry_key)
        return
    end

    if mode == "playlist_cancel_reveal" then
        remove_overlay()

        clear_timer(navigation_watchdog)
        navigation_watchdog = nil

        clear_timer(playlist_transition_timeout)
        playlist_transition_timeout = nil

        playlist_transition = false
        cover_complete = false
        new_video_ready = false

        pending_navigation_command = nil
        pending_playlist_hook = nil
        pending_navigation_delta = 0
        waiting_for_default_transition_cache = false

        phase = "ready"

        mp.msg.info(
            "[pause-cache] TRANSITION: cancelled; current video restored."
        )
        return
    end
end

-- Animation engine.
start_transition = function(target_step, mode, entry)
    cancel_transition()

    local previous_cache_key = display_cache and display_cache.key

    if entry then
        display_cache = entry
    end

    if not display_cache or not display_cache.ready then
        phase = "waiting_cache"
        return
    end

    if mode == "pause_in" and not desired_paused then
        return
    end

    if mode == "pause_out" and desired_paused then
        return
    end

    if (
        mode == "playlist_cover"
        or mode == "playlist_reveal"
        or mode == "playlist_cancel_reveal"
    ) and not playlist_transition then
        return
    end

    -- This cache is now being displayed by an animation.
    mark_cache_used(display_cache)

    -- When a fallback cache is replaced by the video's own cache, refresh
    -- the current frame using the new source while keeping overlay geometry
    -- fixed. This prevents stale wallpaper and avoids restarting the motion.
    if overlay_visible
        and entry
        and previous_cache_key ~= entry.key then

        if not apply_frame(current_step) then
            phase = "waiting_display"
            return
        end
    end

    if target_step > 0 and not overlay_visible then
        current_step = 0

        if not apply_frame(0) then
            phase = "waiting_display"
            return
        end
    end

    if target_step == 0 and not overlay_visible then
        finish_transition(mode)
        return
    end

    local distance = math.abs(target_step - current_step)

    if distance == 0 then
        finish_transition(mode)
        return
    end

    transition_mode = mode
    transition_start_step = current_step
    transition_target_step = target_step
    transition_start_time = mp.get_time()
    transition_duration = CIRCLE_DURATION * distance / MAX_STEP

    if mode == "playlist_cover" then
        phase = "playlist_cover"
    elseif mode == "playlist_reveal" then
        phase = "playlist_reveal"
    elseif mode == "playlist_cancel_reveal" then
        phase = "playlist_cancel_reveal"
    elseif target_step > current_step then
        phase = "circle_reveal"
    else
        phase = "circle_hide"
    end

    local function update()
        transition_timer = nil

        if transition_mode ~= mode then
            return
        end

        if mode == "pause_in" and not desired_paused then
            return
        end

        if mode == "pause_out" and desired_paused then
            return
        end

        if (
            mode == "playlist_cover"
            or mode == "playlist_reveal"
            or mode == "playlist_cancel_reveal"
        ) and not playlist_transition then
            return
        end

        local elapsed = mp.get_time() - transition_start_time

        local progress = clamp(
            elapsed / transition_duration,
            0,
            1
        )

        local interpolated =
            transition_start_step
            + (transition_target_step - transition_start_step)
            * progress

        local next_step = math.floor(interpolated + 0.5)

        if next_step ~= current_step then
            if not apply_frame(next_step) then
                phase = "waiting_display"
                return
            end
        end

        if progress >= 1 then
            current_step = target_step
            finish_transition(mode)
            return
        end

        local next_frame =
            (math.floor(elapsed * CIRCLE_FPS) + 1)
            / CIRCLE_FPS

        local delay = math.max(
            next_frame - elapsed,
            0.001
        )

        transition_timer = mp.add_timeout(delay, update)
    end

    transition_timer = mp.add_timeout(
        1 / CIRCLE_FPS,
        update
    )
end

-- Pause and resume handling.
handle_pause = function(paused)
    desired_paused = paused

    if not file_loaded or playlist_transition then
        return
    end

    if paused then
        if active_cache and active_cache.ready then
            pending_pause_cache = nil

            start_transition(
                MAX_STEP,
                "pause_in",
                active_cache
            )

            return
        end

        -- Use the dedicated default cache while this video's cache is
        -- still generating. The default cache is preloaded at session start.
        local fallback_cache = default_cache_entry

        if fallback_cache
            and file_size(fallback_cache.path) ~= EXPECTED_CACHE_SIZE then

            fallback_cache = nil
            default_cache_entry = nil
        end

        if not fallback_cache and default_wallpaper_identity then
            fallback_cache = get_cached_entry(default_wallpaper_identity)
            default_cache_entry = fallback_cache
        end

        if fallback_cache then
            mp.msg.info(
                "[pause-cache] PAUSE: video cache not ready; using default cache."
            )

            start_transition(
                MAX_STEP,
                "pause_in",
                fallback_cache
            )

            if current_wallpaper then
                ensure_cache_for_identity(current_wallpaper)
            end

            return
        end

        local wait_key = current_wallpaper
            and current_wallpaper.key
            or "unknown"

        if pause_wait_key ~= wait_key then
            mp.msg.info(
                "[pause-cache] PAUSE: video and default caches are not ready; waiting."
            )

            pause_wait_key = wait_key
        end

        if default_wallpaper_identity then
            local default_entry = get_cached_entry(default_wallpaper_identity)

            if default_entry then
                default_cache_entry = default_entry
            else
                queue_cache_identity(default_wallpaper_identity, true)
                process_cache_queue()
            end
        end

        if current_wallpaper then
            ensure_cache_for_identity(current_wallpaper)
        end
    else
        pause_wait_key = nil
        pending_pause_cache = nil

        -- Hide whichever pause cache is currently displayed, including the
        -- default fallback if the video's own cache has not finished yet.
        if display_cache and overlay_visible then
            start_transition(
                0,
                "pause_out",
                display_cache
            )
        else
            phase = active_cache and "ready" or "preparing"
        end
    end
end

-- Find the current playlist entry identifier.
local function find_current_entry_key()
    local playlist = mp.get_property_native("playlist")

    if type(playlist) == "table" then
        for _, item in ipairs(playlist) do
            if item.current and item.id ~= nil then
                return tostring(item.id)
            end
        end

        local position = mp.get_property_number("playlist-pos", -1)

        if position >= 0 then
            local item = playlist[math.floor(position) + 1]

            if item and item.id ~= nil then
                return tostring(item.id)
            end
        end
    end

    local path = mp.get_property("path")

    if path and path ~= "" then
        return "path:" .. path
    end

    return nil
end

-- Check playlist bounds before starting a transition. At the first or last
-- entry, mpv must not animate a transition for a navigation that cannot load
-- another playlist item. Playlist looping remains supported.
local function can_navigate_playlist(command)
    local playlist = mp.get_property_native("playlist")

    if type(playlist) ~= "table" or #playlist == 0 then
        return false
    end

    local position = mp.get_property_number("playlist-pos", -1)

    if position < 0 then
        for index, item in ipairs(playlist) do
            if item.current then
                position = index - 1
                break
            end
        end
    end

    if position < 0 or position >= #playlist then
        return false
    end

    local direction = command == "playlist-next" and 1 or -1
    local target_position = math.floor(position) + direction

    if target_position >= 0 and target_position < #playlist then
        return true
    end

    local loop_mode = mp.get_property("loop-playlist", "no")

    return loop_mode == "inf" or loop_mode == "force"
end


-- Apply a combined next/previous delta in one playlist position change.
-- This avoids loading and generating caches for intermediate videos.
navigate_playlist_by_delta = function(delta, use_watchdog)
    if delta == 0 then
        return false
    end

    local playlist = mp.get_property_native("playlist")

    if type(playlist) ~= "table" or #playlist == 0 then
        return false
    end

    local position = mp.get_property_number("playlist-pos", -1)

    if position < 0 then
        for index, item in ipairs(playlist) do
            if item.current then
                position = index - 1
                break
            end
        end
    end

    if position < 0 then
        return false
    end

    position = math.floor(position)

    local target_position = position + delta
    local loop_mode = mp.get_property("loop-playlist", "no")

    if loop_mode == "inf" or loop_mode == "force" then
        target_position = target_position % #playlist

        if target_position < 0 then
            target_position = target_position + #playlist
        end
    else
        target_position = clamp(target_position, 0, #playlist - 1)
    end

    if target_position == position then
        mp.msg.info(
            "[pause-cache] NAVIGATION: playlist boundary reached."
        )

        return false
    end

    if use_watchdog then
        start_navigation_watchdog()
    end

    if not playlist_transition then
        release_next_start_hook = true

        clear_timer(release_hook_timer)
        release_hook_timer = mp.add_timeout(
            RELEASE_HOOK_TIMEOUT,
            function()
                release_next_start_hook = false
                release_hook_timer = nil
            end
        )
    end

    mp.msg.info(
        string.format(
            "[pause-cache] NAVIGATION: playlist position %d -> %d.",
            position,
            target_position
        )
    )

    local success, result = pcall(
        mp.set_property_number,
        "playlist-pos",
        target_position
    )

    if not success or result == false then
        mp.commandv(
            "set",
            "playlist-pos",
            tostring(target_position)
        )
    end

    return true
end

-- Get the cache belonging to the currently playing video.
local function get_previous_video_cache()
    local identity = current_entry_key
        and session_wallpapers[current_entry_key]
        or current_wallpaper

    if identity then
        local entry = get_cached_entry(identity)

        if entry then
            return entry
        end
    end

    if active_cache and active_cache.ready then
        return active_cache
    end

    if display_cache and display_cache.ready then
        return display_cache
    end

    return nil
end

-- Begin navigation only after the current video's cover animation completes.
local function request_playlist_navigation(command)
    local direction = command == "playlist-next" and 1 or -1

    -- During an active cover/load/reveal cycle, accumulate navigation input.
    -- Intermediate videos can then be skipped without generating their caches.
    if playlist_transition then
        pending_navigation_delta = pending_navigation_delta + direction

        mp.msg.info(
            string.format(
                "[pause-cache] TRANSITION: queued navigation delta=%d.",
                pending_navigation_delta
            )
        )

        -- If the new video is already being revealed, cover it again with
        -- the same default transition cache before skipping onward.
        if cover_complete and transition_mode == "playlist_reveal" then
            cancel_transition()

            if display_cache and display_cache.ready then
                apply_frame(MAX_STEP)
                current_step = MAX_STEP
                new_video_ready = false

                local queued_delta = pending_navigation_delta
                pending_navigation_delta = 0

                if queued_delta ~= 0 then
                    local navigation_started =
                        navigate_playlist_by_delta(queued_delta, true)

                    if not navigation_started then
                        start_transition(
                            0,
                            "playlist_reveal",
                            display_cache
                        )
                    end
                end
            end
        end

        return
    end

    if not can_navigate_playlist(command) then
        mp.msg.info(
            "[pause-cache] NAVIGATION: no playlist entry available; transition skipped."
        )

        return
    end

    if not file_loaded
        or not current_entry_key
        or not current_wallpaper then

        mp.commandv(command)
        return
    end

    playlist_transition = true
    cover_complete = false
    new_video_ready = false
    pending_pause_cache = nil
    pending_navigation_command = command
    pending_navigation_delta = direction
    waiting_for_default_transition_cache = false

    local source_cache = get_previous_video_cache()

    if source_cache and source_cache.ready then
        active_cache = source_cache

        arm_playlist_transition_timeout()

        mp.msg.info(
            string.format(
                "[pause-cache] TRANSITION: covering current video with %s",
                source_cache.key
            )
        )

        start_transition(
            MAX_STEP,
            "playlist_cover",
            source_cache
        )
    else
        mp.msg.info(
            "[pause-cache] TRANSITION: current video cache is not ready; switching to default fallback."
        )

        start_default_transition_fallback()
    end
end

-- Fallback for file changes initiated outside this script.
-- This hook can hold the incoming file until the previous wallpaper covers it.
local function handle_before_start_file(hook)
    if release_next_start_hook then
        release_next_start_hook = false

        clear_timer(release_hook_timer)
        release_hook_timer = nil

        return
    end

    if playlist_transition then
        return
    end

    if not current_entry_key or not current_wallpaper then
        return
    end

    playlist_transition = true
    cover_complete = false
    new_video_ready = false
    pending_pause_cache = nil
    pending_playlist_hook = hook
    pending_navigation_delta = 0
    waiting_for_default_transition_cache = false

    hook:defer()

    local source_cache = get_previous_video_cache()

    if source_cache and source_cache.ready then
        active_cache = source_cache

        arm_playlist_transition_timeout()

        mp.msg.info(
            string.format(
                "[pause-cache] TRANSITION: external navigation, covering with %s",
                source_cache.key
            )
        )

        start_transition(
            MAX_STEP,
            "playlist_cover",
            source_cache
        )
    else
        mp.msg.info(
            "[pause-cache] TRANSITION: external navigation using default fallback."
        )

        start_default_transition_fallback()
    end
end

-- Track when mpv actually begins loading the next file.
local function handle_start_file(event)
    clear_timer(navigation_watchdog)
    navigation_watchdog = nil

    if event and event.playlist_entry_id ~= nil then
        loading_entry_key = tostring(event.playlist_entry_id)
    else
        loading_entry_key = find_current_entry_key()
    end

    mp.msg.info(
        string.format(
            "[pause-cache] TRANSITION: start-file entry=%s",
            tostring(loading_entry_key)
        )
    )
end

-- The new video is revealed only after file-loaded.
local function handle_file_loaded()
    clear_timer(navigation_watchdog)
    navigation_watchdog = nil

    local new_key = loading_entry_key
        or find_current_entry_key()

    loading_entry_key = nil

    if not new_key then
        mp.msg.error(
            "[pause-cache] ERROR: Unable to identify loaded playlist entry."
        )

        return
    end

    current_entry_key = new_key
    file_loaded = true
    desired_paused = mp.get_property_bool("pause") or false

    if playlist_transition and cover_complete then
        if pending_navigation_delta ~= 0 then
            local queued_delta = pending_navigation_delta
            pending_navigation_delta = 0
            new_video_ready = false

            mp.msg.info(
                string.format(
                    "[pause-cache] TRANSITION: skipping intermediate video | next delta=%d.",
                    queued_delta
                )
            )

            if navigate_playlist_by_delta(queued_delta, true) then
                return
            end
        end

        new_video_ready = true

        mp.msg.info(
            string.format(
                "[pause-cache] TRANSITION: final video ready | entry=%s",
                new_key
            )
        )

        start_transition(
            0,
            "playlist_reveal",
            display_cache
        )

        return
    end

    -- If a deferred external navigation had extra next/previous requests
    -- while the fallback cache was unavailable, apply them after this file loads.
    if pending_navigation_delta ~= 0 then
        local queued_delta = pending_navigation_delta
        pending_navigation_delta = 0

        if navigate_playlist_by_delta(queued_delta, false) then
            return
        end
    end

    -- Initial load or a file change that did not require a cover transition.
    assign_wallpaper_for_entry(new_key)
end

-- Handle an incoming file hook that cannot be continued because loading failed.
local function handle_end_file(event)
    file_loaded = false

    if playlist_transition and cover_complete then
        local reason = event and event.reason or "unknown"

        mp.msg.warn(
            "[pause-cache] TRANSITION: file ended before ready: "
            .. tostring(reason)
        )

        if reason == "error" or reason == "redirect" then
            start_transition(
                0,
                "playlist_cancel_reveal",
                display_cache
            )
        end
    end
end

-- Reset visible playback state but preserve session assignments and valid caches.
local function reset_playback_state()
    if overlay_visible then
        remove_overlay()
    end

    clear_timer(playlist_transition_timeout)
    playlist_transition_timeout = nil

    clear_timer(navigation_watchdog)
    navigation_watchdog = nil

    current_entry_key = nil
    loading_entry_key = nil
    current_wallpaper = nil
    active_cache = nil

    playlist_transition = false
    cover_complete = false
    new_video_ready = false

    pending_navigation_command = nil
    pending_playlist_hook = nil
    pending_navigation_delta = 0
    waiting_for_default_transition_cache = false
    pending_pause_cache = nil

    phase = "idle"

    -- Do not clear session_wallpapers or used_wallpapers here.
end

local function update_display_geometry()
    if overlay_visible then
        apply_frame(current_step)
    end
end

-- Startup cleanup is intentionally performed only once per mpv session.
ensure_cache_directory()
cleanup_expired_caches()

mp.msg.info(
    "[pause-cache] SESSION: persistent wallpaper cache enabled."
)

mp.msg.info(
    "[pause-cache] SESSION: one wallpaper assignment per playlist entry."
)

mp.msg.info(
    "[pause-cache] SESSION: cache cleanup completed at startup."
)

-- Preload the default wallpaper cache independently from playlist entries.
-- This cache is the pause fallback while a newly assigned wallpaper is
-- still being generated.
if file_exists(DEFAULT_WALLPAPER) then
    default_wallpaper_identity = build_cache_identity(DEFAULT_WALLPAPER)

    if default_wallpaper_identity then
        default_cache_entry = get_cached_entry(default_wallpaper_identity)

        if default_cache_entry then
            mp.msg.info(
                "[pause-cache] DEFAULT CACHE: disk cache found and ready."
            )
        else
            mp.msg.info(
                "[pause-cache] DEFAULT CACHE: missing; generating fallback cache."
            )
        end

        ensure_cache_for_identity(default_wallpaper_identity)
    else
        mp.msg.error(
            "[pause-cache] ERROR: Unable to create default wallpaper cache identity."
        )
    end
else
    mp.msg.warn(
        "[pause-cache] WARNING: Default wallpaper not found; pause fallback is unavailable."
    )
end

-- Support scripts loaded after a video has already started.
if file_loaded then
    current_entry_key = find_current_entry_key()

    if current_entry_key then
        assign_wallpaper_for_entry(current_entry_key)
    end
end

-- Intercept the default mpv next/previous keys so the cover starts
-- before mpv changes the current playlist entry.
mp.add_forced_key_binding(
    ">",
    "pause_cache_next",
    function()
        request_playlist_navigation("playlist-next")
    end
)

mp.add_forced_key_binding(
    "<",
    "pause_cache_previous",
    function()
        request_playlist_navigation("playlist-prev")
    end
)

-- Script messages for OSC buttons or other scripts.
mp.register_script_message(
    "pause-cache-next",
    function()
        request_playlist_navigation("playlist-next")
    end
)

mp.register_script_message(
    "pause-cache-previous",
    function()
        request_playlist_navigation("playlist-prev")
    end
)

-- Fallback hook for playlist changes initiated outside this script.
mp.add_hook(
    "on_before_start_file",
    50,
    handle_before_start_file
)

-- mpv events.
mp.register_event("start-file", handle_start_file)
mp.register_event("file-loaded", handle_file_loaded)
mp.register_event("end-file", handle_end_file)

mp.register_event("idle", function()
    if not file_loaded then
        reset_playback_state()
    end
end)

-- Pause observer.
mp.observe_property("pause", "bool", function(_, paused)
    if paused ~= nil then
        handle_pause(paused)
    end
end)

-- Window resize observers.
mp.observe_property("osd-width", "number", function()
    update_display_geometry()
end)

mp.observe_property("osd-height", "number", function()
    update_display_geometry()
end)

-- Shutdown.
mp.register_event("shutdown", function()
    clear_timer(transition_timer)
    clear_timer(playlist_transition_timeout)
    clear_timer(navigation_watchdog)
    clear_timer(release_hook_timer)

    transition_timer = nil
    playlist_transition_timeout = nil
    navigation_watchdog = nil
    release_hook_timer = nil

    if overlay_visible then
        mp.command_native({
            name = "overlay-remove",
            id = OVERLAY_ID
        })

        overlay_visible = false
    end

    -- Abort only unfinished generation. Completed cache files are retained.
    generation = generation + 1

    if conversion_id then
        mp.abort_async_command(conversion_id)
        conversion_id = nil
    end

    if pending_cache and pending_cache.tmp_path then
        os.remove(pending_cache.tmp_path)
    end

    pending_cache = nil

    mp.msg.info(
        "[pause-cache] SHUTDOWN: valid persistent caches retained."
    )
end)
