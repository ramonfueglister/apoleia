#!/bin/sh
# rhair.sh out idx,idx [zoom] : Godot render of persons.json people with the Roman hair test
cd /home/claude/apoleia
export APOLEIA_TEST_BARE=1 APOLEIA_REAL=/home/claude/work/mhreal APOLEIA_MH_DIR=/home/claude/work/mhreal APOLEIA_MH_MEN=${MEN:-roman01} APOLEIA_MH_WOMEN=${WOMEN:-bun01} APOLEIA_REAL_ANISO=1 APOLEIA_REAL_BLEND=1 APOLEIA_REAL_NMAP=1 APOLEIA_REAL_SCALP=/home/claude/work/mhreal/${MEN:-roman01}_scalp.txt
if [ "$3" = zoom ]; then S=mh_zoom.gd; R=1400x860; else S=mh_compare.gd; R=1760x440; fi
timeout 300 xvfb-run -a -s "-screen 0 1920x1080x24" /home/claude/work/gdbin/Godot_v4.7.2-stable_linux.x86_64 --rendering-driver vulkan --resolution $R --path app --script /home/claude/work/gdtest/$S -- ${PJ:-/home/claude/work/persons.json} $1 $2 2>&1 | grep -iE "panic|SCRIPT ERROR" | head -5
