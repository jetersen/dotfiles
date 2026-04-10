function paru
    set -l stamp_file ~/.local/share/paru-llama-stamp
    set -l throttled_pkg llama.cpp-vulkan
    set -l interval_days 30

    # Check if this is a -Syu / upgrade run (not a plain install/query/etc.)
    set -l is_upgrade false
    for arg in $argv
        if string match -qr -- '-S' $arg; or string match -q -- '--sync' $arg
            set is_upgrade true
            break
        end
    end
    # bare `paru` with no args also means upgrade
    if test (count $argv) -eq 0
        set is_upgrade true
    end

    if $is_upgrade
        set -l now (date +%s)
        set -l last 0
        if test -f $stamp_file
            set last (cat $stamp_file)
        end
        set -l elapsed (math "$now - $last")
        set -l threshold (math "$interval_days * 86400")

        if test $elapsed -ge $threshold
            # Enough time has passed — update the package and record the timestamp
            command paru $argv
            set -l exit_code $status
            if test $exit_code -eq 0
                echo $now > $stamp_file
            end
            return $exit_code
        else
            set -l days_left (math -s0 "($threshold - $elapsed) / 86400")
            echo "[paru wrapper] Skipping $throttled_pkg update ($days_left day(s) until next allowed update)"
            command paru --ignore $throttled_pkg $argv
            return $status
        end
    else
        command paru $argv
    end
end
