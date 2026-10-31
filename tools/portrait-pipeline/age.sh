#!/bin/sh
# age.sh set.json out.png : real look, ages 20..82 (row 1 man, row 2 woman)
cd /home/claude/apoleia
R=/home/claude/apoleia/app/assets/portrait/real
export APOLEIA_TEST_BARE=1 APOLEIA_REAL=$R APOLEIA_MH_DIR=$R APOLEIA_MH_AUTO=1 APOLEIA_REAL_ANISO=1 APOLEIA_REAL_BLEND=1 APOLEIA_REAL_NMAP=1 APOLEIA_MH_BEARD=$R APOLEIA_MH_CLOTHES=$R
timeout 300 xvfb-run -a -s "-screen 0 2200x1100x24" /home/claude/work/gdbin/Godot_v4.7.2-stable_linux.x86_64 --rendering-driver vulkan --resolution 2120x870 --path app --script /home/claude/work/gdtest/beard_compare.gd -- $1 $2 0,1,2,3,4,5,6,7,8,9,10,11 2>&1 | grep -iE "panic|SCRIPT ERROR" | head -5
