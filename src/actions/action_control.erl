-module(action_control).
-author('Maxim Sokhatsky').
-include_lib("n2o/include/wf.hrl").
-compile(export_all).

render_action(#control{ 
    actions=Actions, source=Source,
    anchor=Anchor, trigger=Trigger, target=Target, validation_group=ValidationGroup,
    type=Type, keycode=KeyCode, shift_key=ShiftKey, delay=Delay, delegate=Delegate,
    extra_param=ExtraParam}) ->

    Data = "[" ++ string:join([ "Bert.tuple(Bert.atom('"++atom_to_list(Src)++
                     "'), utf8.toByteArray($('#"++atom_to_list(Src)++"').val()))" || Src <- Source ],",") ++ "]",

    ValidationGroup1 = wf:coalesce([ValidationGroup, Trigger]),
    PostbackScript = wf_event:generate_postback_script(ok, Anchor, ValidationGroup1, Delegate, control_event, Data),
    WireAction = #wire { trigger=Trigger, target=Target, actions=Actions },

    [
        wf:f("$('#~s').bind('~s',function anonymous(event) { ", [ValidationGroup1,Type]), PostbackScript, "});"
    ].
