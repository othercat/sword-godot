# SPDX-License-Identifier: MIT
extends SceneTree
const Member=preload("res://src/native_pal98_member_sync.gd")
class ProbeDouble:
	var accepted:bool=true
	var seen:Array=[]
	func probe(x:int,y:int)->Dictionary:
		seen.append([x,y]);return {"accepted":accepted}
var checks:Array=[]
func ck(value:bool,name:String,actual=null)->void:checks.append({"name":name,"passed":value,"actual":actual.duplicate(true) if actual is Array or actual is Dictionary else actual})
func state()->Dictionary:
	var words: Array=[]; words.resize(450); words.fill(0)
	return {"equipment":{"role_words":words},"globals":{"member_last":2,"follower_count":0,"viewport_x":864,"viewport_y":912,
	"direction_word":0,"walk_phase_word":1,"leader_frame_offset_word":1,"party_frame_offset_word":2},
	"party_records":[{"role_id":0,"x":160,"y":112,"current_frame":0},{"role_id":1,"x":144,"y":104,"current_frame":0},{"role_id":2,"x":144,"y":104,"current_frame":0}],
	"party_trail":[{"x":1024,"y":1024,"direction_word":0},{"x":1008,"y":1016,"direction_word":0},
	{"x":992,"y":1008,"direction_word":1},{"x":976,"y":1000,"direction_word":2},{"x":960,"y":992,"direction_word":3}]}
func _initialize()->void:
	var p=ProbeDouble.new();var m=Member.new();m.bind_probe(p)
	var s:Dictionary=state();var r:Dictionary=m.answer({"kind":"sync_party_formation_and_frames","state":s})
	ck(not r.has("error"),"control: known three-role member state answers")
	ck(r.party_records[1].x==160 and r.party_records[1].y==96,"member 1 forms from trail[1] before probe",r.party_records[1])
	ck(r.party_records[2].x==160 and r.party_records[2].y==112,"member 2 forms from trail[1] plus parity offset",r.party_records[2])
	ck(p.seen==[[1024,1008],[1024,1024]],"formation candidates are checked world sums",p.seen)
	ck(r.party_records[1].current_frame==5 and r.party_records[2].current_frame==5,
		"both ordinary members take frame direction from trail[2]",[r.party_records[1].current_frame,r.party_records[2].current_frame])
	p.accepted=false
	r=m.answer({"kind":"sync_party_formation_and_frames","state":s})
	ck(r.party_records[1].x==144 and r.party_records[1].y==104 and r.party_records[2].x==144 and r.party_records[2].y==104,
		"refused formation falls back to trail[1] without applying formation again",[r.party_records[1],r.party_records[2]])
	p.accepted=true;s=state();s.globals.viewport_x=1;s.party_trail[1].x=-32768;s.party_trail[2].x=-32768
	r=m.answer({"kind":"sync_party_formation_and_frames","state":s})
	ck(r.has("error"),"relative coordinate checked-I2 underflow refuses without wrapping",r.get("error",r.get("party_records",[])))
	s=state();s.globals.member_last=0;s.globals.follower_count=1
	r=m.answer({"kind":"sync_party_formation_and_frames","state":s})
	ck(not r.has("error") and r.party_records[1].current_frame==8,
		"follower uses three frames and does not read a role-table frame count",r.get("error",r.get("party_records",[])))

	for invalid in ["duplicate_role", "invalid_role", "invalid_word", "missing_words", "frame_overflow"]:
		s=state()
		match invalid:
			"duplicate_role": s.party_records[1].role_id=0
			"invalid_role": s.party_records[1].role_id=6
			"invalid_word": s.equipment.role_words[10]=true
			"missing_words": s.equipment.erase("role_words")
			"frame_overflow":
				s.equipment.role_words[64*6]=4;s.globals.direction_word=3;s.globals.walk_phase_word=32767
		var before:Dictionary=s.duplicate(true)
		r=m.answer({"kind":"sync_party_formation_and_frames","state":s})
		ck(r.has("error") and s==before,"invalid current input refuses atomically: "+invalid)
	var failed:int=checks.filter(func(row):return not row.passed).size()
	var f=FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed},"  "));f.close()
	print("MEMBERS ",checks.size()-failed,"/",checks.size());quit(1 if failed else 0)
