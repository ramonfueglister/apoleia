extends RefCounted
## Main-thread residency bookkeeping only. No Nodes/resources are owned here.
## Wanted changes reset the victim snapshot; otherwise no repeated minimum scan.
const REVISION="forest-residency-budgeted-lru-r1"
const MAX_EVICTIONS=8
const MAX_INSPECTED=64
const START_BUDGET_USEC=1000
var _candidates:Array=[]
var _cursor=0
var stats={"plans":0,"selected":0,"skipped_wanted":0,"skipped_absent":0,"peak_candidates":0,"max_selected":0,"max_plan_usec":0,"resets":0}
func reset()->void:
    _candidates.clear();_cursor=0;stats.resets+=1
func select(resident:Dictionary,wanted:Dictionary,limit:int=768)->Array:
    var started=Time.get_ticks_usec();var result=[]
    if resident.size()<=limit:
        _candidates.clear();_cursor=0;return result
    if _cursor>=_candidates.size():
        _candidates.clear();_cursor=0
        for cell in resident:
            if not wanted.has(cell):_candidates.append(cell)
        _candidates.sort_custom(func(a,b):
            var ta=int(resident[a].last_used);var tb=int(resident[b].last_used)
            return ta<tb or (ta==tb and (a.y<b.y or (a.y==b.y and a.x<b.x))))
        stats.plans+=1;stats.peak_candidates=maxi(stats.peak_candidates,_candidates.size())
    var inspected=0
    while _cursor<_candidates.size() and result.size()<MAX_EVICTIONS and inspected<MAX_INSPECTED and resident.size()-result.size()>limit:
        # Budget covers planning too. A slow planning frame performs no deletion;
        # bounded work resumes next frame instead of hiding the overshoot.
        if Time.get_ticks_usec()-started>=START_BUDGET_USEC:break
        var cell=_candidates[_cursor];_cursor+=1;inspected+=1
        if not resident.has(cell):stats.skipped_absent+=1;continue
        if wanted.has(cell):stats.skipped_wanted+=1;continue
        result.append(cell)
    stats.selected+=result.size();stats.max_selected=maxi(stats.max_selected,result.size());stats.max_plan_usec=maxi(stats.max_plan_usec,Time.get_ticks_usec()-started)
    return result
