# Place & route option sweep, to find a run that closes clock_54m.
#
#   gw_sh sweep_pnr.tcl
#
# Why a sweep rather than a re-run: Gowin's PnR is deterministic, so repeating
# the same options reproduces the same result exactly. Something has to change
# for the placer to land differently.
#
# The design sits at 88% CLS and clock_54m has closed at 58.9 MHz on one build
# and missed at 53.2 and 50.4 on others, with under 1% difference in logic. It
# is congestion-sensitive, so different effort settings are worth more here than
# they would be on a half-empty device.
#
# Each run writes its report under impl/sweep_<tag>/. Compare the clock_54m
# Fmax across them and keep the winner -- then set those options permanently in
# build.tcl and record which combination it was.
#
# If Gowin rejects an option in this version, note which and drop that row; the
# accepted values differ between releases.

# --- combinations to try -----------------------------------------------------
# tag                place route  notes
set trials {
    {base            2     2      "current settings, as a baseline"}
    {place1          1     2      "less place effort, different starting point"}
    {place0          0     2      "default place effort"}
    {route1          2     1      "less route effort"}
    {p1r1            1     1      ""}
    {p0r0            0     0      "fastest, sometimes lands better by luck"}
}

foreach t $trials {
    lassign $t tag popt ropt note

    puts "=========================================================="
    puts "sweep: $tag  (place_option $popt, route_option $ropt) $note"
    puts "=========================================================="

    # start from a clean project each time
    source build_files.tcl

    set_option -use_sspi_as_gpio 1 -use_mspi_as_gpio 1 \
               -top_module top -verilog_std sysv2017 -include_path src
    set_option -place_option $popt
    set_option -route_option $ropt
    set_option -output_base_name "sweep_$tag"

    if {[catch {run syn} err]} { puts "  SYNTH FAILED: $err"; continue }
    if {[catch {run pnr} err]} { puts "  PNR FAILED:   $err"; continue }

    puts "  done: see impl/pnr/sweep_$tag.tr for the timing report"
}

puts ""
puts "Now compare clock_54m Fmax across impl/pnr/sweep_*.tr and keep the best."
puts "Anything at or above 54.000 MHz closes; report the margin either way."
