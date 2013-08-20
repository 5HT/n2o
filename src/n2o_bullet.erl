-module(n2o_bullet).
-author('Maxim Sokhatsky').
-include_lib("n2o/include/wf.hrl").
-export([init/4]).
-export([stream/3]).
-export([info/3]).
-export([terminate/2]).

-define(PERIOD, 1000).

init(_Transport, Req, _Opts, _Active) ->
    put(actions,[]),
    Ctx = wf_context:init_context(Req),
    NewCtx = wf_core:fold(init,Ctx#context.handlers,Ctx),
    wf_context:context(NewCtx),
    put(page_module,NewCtx#context.module),
    Req1 = wf:header(<<"Access-Control-Allow-Origin">>, <<"*">>, NewCtx#context.req),
    {ok, Req1, NewCtx}.

stream(<<"ping">>, Req, State) ->
    io:format("ping received~n"),
    {reply, <<"pong">>, Req, State};
stream({text,Data}, Req, State) ->
%    error_logger:info_msg("Text Received ~p",[Data]),
    self() ! Data,
    {ok, Req,State};
stream({binary,Info}, Req, State) ->
%    error_logger:info_msg("Binary Received: ~p",[Info]),    
    Pro = binary_to_term(Info,[safe]),
    Pickled = proplists:get_value(pickle,Pro),
    Linked = proplists:get_value(linked,Pro),
    Depickled = wf_pickle:depickle(Pickled),
    case Depickled of
        #ev{module=Module,name=Function,payload=Parameter,trigger=Trigger} ->
            case Function of 
                 control_event   -> lists:map(fun({K,V})-> put(K,V) end,Linked),
                                    Module:Function(Trigger, Parameter);
                 api_event       -> Module:Function(Parameter,Linked,State);
                 event           -> lists:map(fun({K,V})-> put(K,V) end,Linked),
                                    Module:Function(Parameter);
                 UserCustomEvent -> Module:Function(Parameter,Trigger,State) end;
          _ -> error_logger:error_msg("N2O allows only #ev{} events") end,

    Actions = get(actions),
    wf_context:clear_actions(),
    Render = wf_core:render(Actions),

    GenActions = get(actions),
    RenderGenActions = wf_core:render(GenActions),
    wf_context:clear_actions(),

    {reply,[Render,RenderGenActions], Req, State};
stream(Data, Req, State) ->
    error_logger:info_msg("Data Received ~p",[Data]),    
    self() ! Data,
    {ok, Req,State}.

info(Pro, Req, State) ->
    Render =  case Pro of
                {flush,Actions} ->
                    error_logger:info_msg("Comet Actions: ~p",[Actions]),
                    wf_core:render(Actions);
                <<"N2O,",Rest/binary>> ->
                    Module = State#context.module, Module:event(init),
                    InitActions = get(actions),
                    wf_context:clear_actions(),
                    Pid = list_to_pid(binary_to_list(Rest)),
                    X = Pid ! {'N2O',self()},
                    R = receive Actions ->
                        RenderInit = wf_core:render(InitActions),
                        InitGenActions = get(actions),
                        RenderInitGenActions = wf_core:render(InitGenActions),
                        wf_context:clear_actions(),
                        RenderPage = wf_core:render(Actions),
                        [RenderInit, RenderPage, RenderInitGenActions]
                    after 100 ->
                            case get(actions) of
                                [] -> [];
                                Actions ->
                                    % if the page has any actions,
                                    % right now we have to redirect to force them to propagate again
                                    %
                                    % actions should be carried with the client in the future
                                    wf:redirect(""),
                                    wf_core:render(Actions)
                            end
                    end,
                    R;
                <<"PING">> -> [];
                Unknown ->
                  M = State#context.module,
                  M:event(Unknown),
                  Actions = get(actions),
                  wf_context:clear_actions(),
                  wf_core:render(Actions) end,
    GenActions = get(actions),
    wf_context:clear_actions(),
    RenderGenActions = wf_core:render(GenActions),
    wf_context:clear_actions(),
    {reply, [Render,RenderGenActions], Req, State}.

terminate(_Req, _State) ->
%    error_logger:info_msg("Bullet Terminated~n"),
    ok.
