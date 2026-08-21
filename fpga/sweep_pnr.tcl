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
# NOTE: Gowin's add_file rejects a file already in the project, so build_files.tcl
# cannot be re-sourced in a loop within one gw_sh process. Run ONE trial per
# process instead:
#
#   for each row below:  gw_sh sweep_pnr.tcl <tag>
#
# If Gowin rejects an option in this version, note which and drop that row; the
# accepted values differ between releases.

# --- combinations to try -----------------------------------------------------
# tag                place route  notes
# Place/route effort was swept on 0cf00b7 and none closed; 2/2 was already the
# best available, and place effort 1 and 2 gave identical results. So these rows
# now vary the SYNTHESIS options instead, which that sweep never touched:
#
#   iob     pack registers next to pins into the IO blocks -- frees CLS and
#           shortens IO paths, no functional change
#   retime  let synthesis move registers across logic to balance path delays,
#           which is aimed squarely at an imbalanced critical path
#
# tag        place route  iob  retime
set trials {
    {base       2     2     0    0    "baseline, matches build.tcl"}
    {iob        2     2     1    0    "IO register packing"}
    {retime     2     2     0    1    "synthesis retiming"}
    {both       2     2     1    1    "both"}
}

# one trial per process: pass the tag as an argument
set want [lindex $argv 0]
if {$want eq ""} {
    puts "usage: gw_sh sweep_pnr.tcl <tag>"
    puts "tags:"
    foreach t $trials { puts "  [lindex $t 0]   [lindex $t 5]" }
    exit 1
}

foreach t $trials {
    lassign $t tag popt ropt iob retime note
    if {$tag ne $want} { continue }

    puts "=========================================================="
    puts "sweep: $tag  (place_option $popt, route_option $ropt) $note"
    puts "=========================================================="

    # start from a clean project each time
    source build_files.tcl

    set_option -use_sspi_as_gpio 1 -use_mspi_as_gpio 1 \
               -top_module top -verilog_std sysv2017 -include_path src
    set_option -place_option $popt
    set_option -route_option $ropt
    if {$iob}    { set_option -oreg_in_iob 1 -ireg_in_iob 1 }
    if {$retime} { set_option -retiming 1 }
    set_option -output_base_name "sweep_$tag"

    if {[catch {run syn} err]} { puts "  SYNTH FAILED: $err"; continue }
    if {[catch {run pnr} err]} { puts "  PNR FAILED:   $err"; continue }

    puts "  done: see impl/pnr/sweep_$tag.tr for the timing report"
}

puts ""
puts "Now compare clock_54m Fmax across impl/pnr/sweep_*.tr and keep the best."
puts "Anything at or above 54.000 MHz closes; report the margin either way."
