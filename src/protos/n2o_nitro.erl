-module(n2o_nitro).
-description('N2O Nitrogen Web Framework Protocol').
-include("n2o.hrl").
-export([info/3,render_actions/1]).

% Nitrogen pickle handler

info({text,<<"N2O,",Auth/binary>>}, Req, State) ->
    info(#init{token=Auth},Req,State);

info(#init{token=Auth}, Req, State) ->
    {'Token', Token} = n2o_session:authenticate([], Auth),
    Sid = case n2o:depickle(Token) of {{S,_},_} -> S; X -> X end,
    ?LOG_INFO("N2O SESSION: ~p~n",[Sid]),
    New = State#cx{session = Sid},
    put(context,New),
    {reply,{bert,case io(init, State) of
		      #io{data={stack,_}} = Io -> Io;
		      Io -> Io#io{data={'Token',Token}} end},
            Req,New};

info(#client{data=Message}, Req, State) ->
    nitro:actions([]),
    ?LOG_INFO("Client Message: ~p",[Message]),
    {reply,{bert,io(#client{data=Message},State)},Req,State};

info(#pickle{}=Event, Req, State) ->
    nitro:actions([]),
    {reply,{bert,html_events(Event,State)},Req,State};

info(#flush{data=Actions}, Req, State) ->
    nitro:actions(Actions),
    {reply,{bert,io(<<>>)},Req,State};

info(#direct{data=Message}, Req, State) ->
    nitro:actions([]),
    {reply,{bert,case io(Message, State) of
		      #io{data={stack,_}} = Io -> Io;
		      #io{data=Res} = Io -> Io#io{data={direct,Res}} end},
            Req,State};

info(Message,Req,State) -> {unknown,Message,Req,State}.

% double render: actions could generate actions

render_actions(Actions) ->
    nitro:actions([]),
    First  = nitro:render(Actions),
    Second = nitro:render(nitro:actions()),
    nitro:actions([]),
    nitro:to_binary([First,Second]).

% n2o events

html_events(#pickle{source=Source,pickled=Pickled,args=Linked}, State=#cx{session = Token}) ->
    Ev  = n2o:depickle(Pickled),
    L   = n2o_session:prolongate(),
    Res = case Ev of
          #ev{} when L =:= false -> render_ev(Ev,Source,Linked,State), <<>>;
          #ev{} -> render_ev(Ev,Source,Linked,State), n2o_session:authenticate([], Token);
          CustomEnvelop -> ?LOG_ERROR("EV expected: ~p~n",[CustomEnvelop]),
                           {error,"EV expected"} end,
    io(Res).

render_ev(#ev{name=F,msg=P,trigger=T},_Source,Linked,State=#cx{module=M}) ->
    case F of
         api_event -> M:F(P,Linked,State);
             event -> % io:format("Linked: ~p~n",[Linked]),
                      lists:map(fun ({K,V})-> erlang:put(K,nitro:to_binary([V]))
                                end,Linked),
                      M:F(P);
                 _ -> M:F(P,T,State) end.

% exception-safe io constructor

-ifdef(OTP_RELEASE).

io(Event, #cx{module=Module}) ->
    try X = Module:event(Event), #io{code=render_actions(nitro:actions()),data=X}
    catch E:R:Stack ->
        ?LOG_ERROR("Catch: ~p:~p~n~p", [E,R,Stack]),
        #io{data={stack,Stack}} end.

io(Data) ->
    try #io{code=render_actions(nitro:actions()),data=Data}
    catch E:R:Stack ->
        ?LOG_ERROR("Catch: ~p:~p~n~p", [E,R,Stack]),
        #io{data={stack,Stack}} end.

-else.

io(Event, #cx{module=Module}) ->
    try X = Module:event(Event), #io{code=render_actions(nitro:actions()),data=X}
    catch E:R ->
        Stack = erlang:get_stacktrace(),
        ?LOG_ERROR("Catch: ~p:~p~n~p", [E,R,Stack]),
        #io{data={stack,Stack}} end.

io(Data) ->
    try #io{code=render_actions(nitro:actions()),data=Data}
    catch E:R ->
        Stack = erlang:get_stacktrace(),
        ?LOG_ERROR("Catch: ~p:~p~n~p", [E,R,Stack]),
        #io{data={stack,Stack}} end.

-endif.

