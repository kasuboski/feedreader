-module(feedreader_tcp_ffi).
-export([start_close_server/0, stop_server/1]).

%% Starts a TCP listener that accepts connections and immediately
%% closes them, simulating a server that drops the connection.
%% Returns {ok, Port} which can be used to build a URL.
start_close_server() ->
    {ok, ListenSock} = gen_tcp:listen(0, [
        binary,
        {active, false},
        {reuseaddr, true}
    ]),
    {ok, Port} = inet:port(ListenSock),
    spawn(fun Loop() ->
        case gen_tcp:accept(ListenSock, 1000) of
            {ok, Sock} ->
                %% Read a bit then abruptly close — no HTTP response sent
                gen_tcp:close(Sock),
                Loop();
            {error, _} ->
                ok
        end
    end),
    {ok, {Port, ListenSock}}.

stop_server(ListenSock) ->
    gen_tcp:close(ListenSock).
