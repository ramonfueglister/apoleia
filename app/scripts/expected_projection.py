#!/usr/bin/env python3
"""Independent scalar camera mapping; does not import Godot or copy observations.

Perspective since camera contract v5 (vertical FOV, KEEP_HEIGHT; the visible
ground width at the focus equals visible_width_model). Samples recorded before
v5, or with camera_projection "orthogonal", use the former orthographic mapping.

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
    right=x-tx
    up=(y-ty)*math.cos(a)-(z-tz)*math.sin(a)
    if sample.get('camera_projection','orthogonal')!='perspective':
        return [width/2+right*k,height/2-up*k]
    # Camera sits at focus+back*d; d is the focus distance whose ground width
    # equals visible_width_model, so k is the pixel scale at the focus plane.
    fov=math.radians(sample['camera_fov_degrees'])
    d=sample['visible_width_model']/(2.0*(width/height)*math.tan(fov*0.5))
    depth=d-((y-ty)*math.sin(a)+(z-tz)*math.cos(a))
    if depth<=1e-9:return [math.nan,math.nan]
    s=k*d/depth
    return [width/2+right*s,height/2-up*s]
