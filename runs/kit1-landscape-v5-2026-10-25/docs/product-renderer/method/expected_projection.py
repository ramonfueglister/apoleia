#!/usr/bin/env python3
"""Independent scalar orthographic mapping; does not import Godot or copy observations.

Given a raw runtime sample and source-space control point (converted through the
bound projection), returns expected top-left framebuffer pixels. The caller
supplies canonical terrain height (metres), never a measured screen coordinate.
"""
import math


def expected_pixel(lon, lat, height_m, sample, bounds, water_kind=0):
    radius=6371008.8
    scale=0.001
    mid_lon=19.0
    mid_lat=41.0
    x=math.radians(lon-mid_lon)*radius*math.cos(math.radians(41))*scale
    z=math.radians(mid_lat-lat)*radius*scale
    tx=math.radians(sample['center_lon']-mid_lon)*radius*math.cos(math.radians(41))*scale
    tz=math.radians(mid_lat-sample['center_lat'])*radius*scale
    y=(0.0 if water_kind==1 else height_m)*scale*sample['relief_weight']
    ty=sample['target_height_model']
    width,height=sample['viewport']
    k=width/sample['visible_width_model']
    a=math.radians(sample['elevation_degrees'])
    return [width/2+(x-tx)*k,height/2-((y-ty)*math.cos(a)-(z-tz)*math.sin(a))*k]
