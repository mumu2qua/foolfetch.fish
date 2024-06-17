#!/usr/bin/env fish

function parse_flags
    argparse --name=fetch 'h/help' 'p/pad=' 'a/ascii=' 'o/opts=' 'n/no_colors' -- $argv
    or close

    if test -n "$_flag_h"
        print_help
    end

    if test -n "$_flag_a"
        set -l ascii_file "$_flag_a"
        # check for errors
        if not test -e "$ascii_file"
            echo file not found: "$ascii_file"
            close
        else if type -q file
        and not file "$ascii_file" | string match -q '*text*'
            echo must be a text file: "$ascii_file"
            close
        end
        set -g ascii (cat $ascii_file)
    else
        set -g ascii "  (\ /)" "  ( . .)" "  c(\")(\")"
    end

    if test -n "$_flag_n"
        set -g nocolors "1"
    end

    if test -n "$_flag_p"
        set -g text_padding "$_flag_p"
        if string match --quiet --regex '\D' -- "$text_padding"
            echo incorrect value: $text_padding
            close
        end
    else
        set -l max_length 0
        for line in $ascii
            set line_length (string length "$line")
            if test $line_length -gt $max_length
                set max_length $line_length
            end
        end
        set -g text_padding (math $max_length + 12)
    end

    # Options
    if test -n "$_flag_o"
        set opts (string replace ' ' '' "$_flag_o")
        set opts (string upper $opts)
        set -g opts (string split ',' $opts)
    else
        set -g opts "OS" "KERNEL" "CPU" "GPU" "PACKAGES" "UPTIME" "MEM" "SWAP"
    end

end

function print_help
    echo -e "Usage:
    -a [path] path to a text file with an ascii art
    -p [int] Manually set the text offset.
    -o [opt1,opt2,..] enable options in order; Example: os,kernel,cpu,gpu,packages,uptime,mem,swap
    -n don't print the color palette
    -h print help"
    exit
end

function close
    echo Unable to continue due to errors.
    # restore cursor
    printf "\e[?25h"
    exit 1
end

function max
    if test $argv[1] -gt $argv[2]
        echo $argv[1]
    else
        echo $argv[2]
    end
end

# move cursor with ansi codes
function move
    set -l direction $argv[1]
    set -l distance $argv[2]
    if test "$distance" -lt 1;
    or test -z "$distance"
        return
    end
    switch $direction
    case up
        printf "\e[%dA" $distance
    case left
        printf "\e[%dD" $distance
    case down
        printf "\e[%dB" $distance
    case right
        printf "\e[%dC" $distance
    end
end

# Like string pad -m, but using cursor movement instead of spaces
function strpad
    set -l strlen (string length $argv)
    set -l pad (math $text_padding - $strlen)
    if test "$pad" -gt 1
        move right $pad
    end
end

function printos
    if test -e '/etc/os-release'
        string match -er '^PRETTY_NAME=' </etc/os-release | string split -f 2 '"'
    else if type -q lsb_release
        lsb_release -ds | string trim -c '"'
    else
        echo unknown
    end
end

function printcpu
    # Will return multiple cores, read gets only the first one
    string match -er '^model name' </proc/cpuinfo | string split -f 2 ': ' | read cpu
    echo $cpu
end

function printgpu
    if type -q lspci
        set gpu (lspci | string match -r 'VGA*.+:*.+' | string split ': ' -f 2 | string replace -r '\(rev .+\)$' '')
        printf '%s ' $gpu #in case there's more than one
    else
        echo unknown
    end
end

function formatmem
    set num $argv[1]
    set format K
    if test $num -gt 1048576
        set num (math -s 2 $num/1048576)
        set format G
    else if test $num -gt 1024
        set num (math "round($num/1024)")
        set format M
    end
    printf '%s%s\n' $num $format
end

function printmem
    for i in (string match -r '^MemTotal:.+|^MemFree:.+|^Buffers:.+|^Cached:.+|^SReclaimable:.+|^Shmem:.+' </proc/meminfo)
        set (string match -r '\w+' $i) (string match -r '\d+' $i)
    end
    set Memuse (math "($MemTotal - $MemFree - $Buffers - $Cached - $SReclaimable + $Shmem)")
    set MemuseProc (math -s 1 "($Memuse/$MemTotal) x 100")
    printf '%s/%s, %s%% used\n' (formatmem $Memuse) (formatmem $MemTotal) $MemuseProc
end

function printswap
    for i in (string match -r '^SwapTotal:.+|^SwapFree:.+' </proc/meminfo)
        set (string match -r '\w+' $i) (string match -r '\d+' $i)
    end
    set Swapuse (math "($SwapTotal - $SwapFree)")
    set SwapuseProc (math -s 1 "($Swapuse/$SwapTotal) x 100")
    printf '%s/%s, %s%% used\n' (formatmem $Swapuse) (formatmem $SwapTotal) $SwapuseProc
end

function findinstalled
    for prog in $argv
        type -q $prog; and echo $prog
    end
end

function packagecount
    set -l found_packmans (findinstalled pacman dpkg rpm flatpak qlist /sbin/installpkg)
    if test -z "$found_packmans"
        echo unknown
        return
    end
    for packman in $found_packmans
        switch $packman
        case pacman
            set -a output "pacman $(pacman -Q | count)"
        case dpkg
            set -a output "dpkg $(dpkg -l | count)"
        case rpm
            set -a output "rpm $(rpm -qa | count)"
        case flatpak
            set -a output "flatpak $(flatpak list --all | count)"
        case qlist
            set -a output "portage $(qlist -ICv | count)"
        case /sbin/installpkg
            set -a output "installpkg $(count /var/log/packages/*)"
        case '*'
            set -a output "unknown"
        end
    end
    printf '%s, ' $output | string trim -c ', '
end

function fetch_info
    switch "$argv"
    case CPU
        printcpu
    case KERNEL
        uname -s -r
    case GPU
        printgpu
    case UPTIME
        uptime -p
    case OS
        printos
    case MEM
        printmem
    case PACKAGES
        packagecount
    case SWAP
        printswap
    case '*'
        echo UNKNOWN
    end
end

function print_info
    for opt in $opts
        set -l label "$opt "
        strpad "$label"
        set -l value (string shorten -m $maxoptsize (fetch_info $opt))
        printf "%s%s%s%s\n" (set_color blue) "$label" (set_color normal) "$value"
    end
end

function print_colors
    set -l colors black red green yellow blue magenta cyan white
    set -l text '   '
    set -l text_len (string length "$text")
    set -l line1
    set -l line2

    for color in $colors
         set -a line1 (set_color -b $color; echo -n "$text")
         set -a line2 (set_color -b br$color; echo -n "$text")
    end

    strpad "$text"; move down 1
    printf "%s" $line1
    move down 1; move left (math $text_len x 8)
    printf "%s" $line2
    printf "%s\n" (set_color normal)
end

function opts_linenums
    if test -n "$nocolors"
        count $opts
    else
        # need more space for the color palette
        math (count $opts) + 4
    end
end

# force terminal to scroll in case cursor is too low
function reserve_space
    set -l l $argv[1]
    printf '%*s' $l | string split ' '
    move up $l
end

function main
    parse_flags $argv

    # This will be used to determine offsets of things
    set -l opts_linenums (opts_linenums)
    set -l ascii_lines (count (printf '%s\n' $ascii))
    set max_lines (max $ascii_lines $opts_linenums)

    # Determine how much space we have
    set -g maxoptsize (math $COLUMNS - $text_padding)

    # Everything will break if the terminal is too small
    if test $maxoptsize -lt 1; or test $LINES -lt $max_lines
        echo "Terminal is too small"
        close
    end

    # Hide cursor because it will jump around a lot
    printf "\e[?25l"

    reserve_space $max_lines

    # Print the art
    printf '%s\n' $ascii; move up $ascii_lines
    # Print the info
    move down $max_lines; move up $opts_linenums
    print_info

    # Print colors if needed
    if not set -q nocolors
        print_colors
    end

    # Make cursor visible again
    printf "\e[?25h\n"

end

main $argv

# vim: ts=4 sts=4 sw=4 et:
