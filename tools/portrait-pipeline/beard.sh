#!/bin/sh
# beard.sh out idx,idx [script res] : Godot render of beards.json with Blender hair and beards
cd /home/claude/apoleia
export APOLEIA_TEST_BARE=1 APOLEIA_REAL=/home/claude/work/mhreal APOLEIA_MH_DIR=/home/claude/work/mhreal APOLEIA_MH_AUTO=1 APOLEIA_REAL_ANISO=1 APOLEIA_REAL_BLEND=1 APOLEIA_REAL_NMAP=1
[ -z "$NOBEARD" ] && export APOLEIA_MH_BEARD=/home/claude/work/mhreal
[ -n "$CLOTHES" ] && export APOLEIA_MH_CLOTHES=/home/claude/work/mhreal
export APOLEIA_TEST_BEARDS=${TB:-900000=shaven,900001=stubble,900002=short,900003=full,900004=phil,900005=chin,900020=shaven,900021=stubble,900022=short,900023=full,900024=phil,900025=chin}
S=${3:-beard_compare.gd}; R=${4:-2120x870}
timeout 300 xvfb-run -a -s "-screen 0 2200x1100x24" /home/claude/work/gdbin/Godot_v4.7.2-stable_linux.x86_64 --rendering-driver vulkan --resolution $R --path app --script /home/claude/work/gdtest/$S -- ${PJ:-/home/claude/work/beards.json} $1 $2 2>&1 | grep -iE "panic|SCRIPT ERROR" | head -5
