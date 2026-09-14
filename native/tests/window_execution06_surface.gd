# SPDX-License-Identifier: MIT
extends SceneTree
const Surface=preload("res://src/native_pal98_dialogue_surface.gd")
const FontOwner=preload("res://src/native_ui_font.gd")
var args
var old_result={}
var checks=[]
func check(ok:bool,name:String):checks.append({"name":name,"passed":ok})
func _initialize():args=OS.get_cmdline_user_args();call_deferred("_run")
func capture_async(s):old_result=await s.apply_request({"kind":"capture_background"},"GBK")
func _run():
 var s=Surface.new();root.add_child(s)
 var b=Image.create(320,200,false,Image.FORMAT_RGBA8);b.fill(Color(0.1,0.2,0.3,1))
 var palette=PackedColorArray();palette.resize(256);palette.fill(Color.WHITE)
 check(s.configure(FontOwner.create(),palette,b),"real surface configured")
 call_deferred("capture_async",s)
 await process_frame
 check(s._busy,"live request owns the busy flag")
 s.invalidate()
 check(not s._busy,"invalidate releases the old busy flag")
 var next=await s.apply_request({"kind":"capture_background"},"GBK")
 check(next.has("receipt") and not next.has("error"),"new generation can finish its own capture")
 check(old_result.get("error","").contains("stale"),"old generation is rejected without overwriting the new one")
 check(not s._busy,"busy is clear after current generation completion")
 var third=await s.apply_request({"kind":"capture_background"},"GBK")
 check(not third.has("error"),"next request proceeds without a permanent busy leak")
 var out={"suite":"surface_busy_independent","checks":checks,"passed":checks.filter(func(x):return x.passed).size(),"failed":checks.filter(func(x):return not x.passed).size()}
 var f=FileAccess.open(args[1],FileAccess.WRITE);f.store_string(JSON.stringify(out,"  "));f.close();quit(1 if out.failed else 0)
