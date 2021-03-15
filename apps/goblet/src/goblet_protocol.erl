-module(goblet_protocol).

-export([decode/2, account_new/1, account_login/1, player_new/2, lobby_info/2]).
-export([player_log/1]).

-include("goblet_opcode.hrl").
-include("goblet_pb.hrl").
-include("goblet_database.hrl").

-include_lib("kernel/include/logger.hrl").

-record(session, {email = none, authenticated = false, statem = login, match = false}).

%%============================================================================
%% Goblet Protocol.
%%
%% This module handles decoding serialized messages and routing them to the
%% correct place for further processing and/or replies.
%%
%%============================================================================

%%----------------------------------------------------------------------------
%% @doc Decode messages from clients and route them to an appropriate function
%% @end
%%----------------------------------------------------------------------------
-spec decode(binary(), any()) -> {ok, any()} | {[binary(), ...], any()}.
decode(<<?VERSION:16, _T/binary>>, State) ->
    logger:notice("Got a version request~n"),
    {ok, State};
decode(<<?ACCOUNT_NEW:16, T/binary>>, _State) -> 
    logger:notice("Got a new account request~n"),
    account_new(T);
decode(<<?ACCOUNT_LOGIN:16, T/binary>>, _State) ->
    logger:notice("Got an account login request~n"),
    account_login(T);
decode(<<?LOBBY_INFO:16, T/binary>>, State) ->
    logger:notice("Got a lobby info request~n"),
    lobby_info(T, State);
decode(<<?PLAYER_NEW:16, T/binary>>, State) ->
    logger:notice("Got a new player request~n"),
    % Need to inspect the state for acct info
    player_new(T, State);
decode(<<?MATCH_CREATE:16, T/binary>>, State) ->
    logger:notice("Got a new match request~n"),
    % Need to inspect the state for acct info
    match_create(T, State);
decode(<<OpCode:16, _T/binary>>, State) ->
    logger:notice("Got an unknown opcode: ~p", [OpCode]),
    {ok, State}.

%%----------------------------------------------------------------------------
%% @doc Encodes a log message to be sent back to the client
%% @end
%%----------------------------------------------------------------------------
-spec player_log(list()) -> [binary(), ...].
player_log(Message) ->
    OpCode = <<?PLAYER_LOG:16>>,
    Sanitized = sanitize_message(Message),
    Msg = goblet_pb:encode_msg(#'PlayerLog'{msg = Sanitized}),
    [OpCode, Msg].

%%----------------------------------------------------------------------------
%% @doc Registers a new account, storing it in the database
%% @end
%%----------------------------------------------------------------------------
-spec account_new(binary()) -> {[binary(), ...], any()}.
account_new(Message) ->
    Decode = goblet_pb:decode_msg(Message, 'AccountNewReq'),
    Email = Decode#'AccountNewReq'.email,
    Password = Decode#'AccountNewReq'.password,
    % TODO Validate length
    {Msg, NewState} =
        case goblet_db:create_account(binary:bin_to_list(Email), Password) of
            {error, Error} ->
                Reply = goblet_pb:encode_msg(#'AccountNewResp'{
                    status = 'ERROR',
                    error = atom_to_list(Error)
                }),
                {Reply, #session{authenticated = false, statem = lobby}};
            _ ->
                Reply = goblet_pb:encode_msg(#'AccountNewResp'{status = 'OK'}),
                {Reply, #session{email = Email, authenticated = true, statem = lobby}}
        end,
    OpCode = <<?ACCOUNT_NEW:16>>,
    {[OpCode, Msg], NewState}.

%%----------------------------------------------------------------------------
%% @doc Login the user and mutate the session state
%% @end
%%----------------------------------------------------------------------------
-spec account_login(binary()) -> {[binary(), ...], any()}.
account_login(Message) ->
    Decode = goblet_pb:decode_msg(Message, 'AccountNewReq'),
    Email = binary:bin_to_list(Decode#'AccountNewReq'.email),
    Password = Decode#'AccountNewReq'.password,
    {Msg, NewState} =
        case goblet_db:account_login(Email, Password) of
            true ->
                Record = goblet_db:account_by_email(Email),
                Players = Record#goblet_account.player_ids,
                Reply = goblet_pb:encode_msg(#'AccountLoginResp'{status = 'OK', players = Players}),
                {Reply, #session{email = Email, authenticated = true, statem = lobby}};
            false ->
                Reply = goblet_pb:encode_msg(#'AccountLoginResp'{
                    status = 'ERROR',
                    error = "invalid password"
                }),
                {Reply, false}
        end,
    OpCode = <<?ACCOUNT_LOGIN:16>>,
    {[OpCode, Msg], NewState}.

%%----------------------------------------------------------------------------
%% @doc Get the current lobby information
%% @end
%%----------------------------------------------------------------------------
-spec lobby_info(binary(), any()) -> {[binary(), ...], any()}.
lobby_info(_Message, State) ->
    Matches = goblet_lobby:get_matches(),
    M1 = [repack_match(X) || X <- Matches],
    Resp = #'ResponseObject'{status = 'OK'},
    Msg = goblet_pb:encode_msg(#'LobbyInfo'{resp = Resp, matches = M1}),
    OpCode = <<?LOBBY_INFO:16>>,
    {[OpCode, Msg], State}.


%%----------------------------------------------------------------------------
%% @doc Create a new match. Will only create matches for sessions where the
%%      player is authenticated and in the 'lobby' state
%% @end
%%----------------------------------------------------------------------------
match_create(Message, State) when State#session.authenticated =:= true, State#session.statem =:= lobby ->
    Match = goblet_pb:decode_message(Message, 'MatchCreateReq'),
    Mode = Match#'MatchCreateReq'.mode,
    MaxPlayers = Match#'MatchCreateReq'.players_max,
    Extra = case Match#'MatchCreateReq'.extra of
        undefined -> <<>>;
        Bytes -> Bytes
    end,
    goblet_lobby:create_match(Mode, MaxPlayers, Extra).
    

%%----------------------------------------------------------------------------
%% @doc Create a new player character
%% @end
%%----------------------------------------------------------------------------
-spec player_new(binary(), any()) -> {[binary(), ...], any()}.
% Let it crash when an unauthenticated user tries to make an account.
player_new(Message, State) when State#session.authenticated =:= true ->
    Decode = goblet_pb:decode_msg(Message, 'PlayerNewReq'),
    Name = binary:bin_to_list(Decode#'PlayerNewReq'.name),
    Title = binary:bin_to_list(Decode#'PlayerNewReq'.title),
    Appearance = Decode#'PlayerNewReq'.appearance,
    Role = binary:bin_to_list(Decode#'PlayerNewReq'.role),
    Account = State#session.email,
    Msg =
        case goblet_space_player:new(Name, Title, Appearance, Role, Account) of
            ok ->
                goblet_pb:encode_msg(#'PlayerNewResp'{status = 'OK'});
            {error, Error} ->
                goblet_pb:encode_msg(#'PlayerNewResp'{status = 'ERROR', error = Error})
        end,
    OpCode = <<?PLAYER_NEW:16>>,
    {[OpCode, Msg], State}.

%%============================================================================
%% Internal functions
%%============================================================================

sanitize_message(Message) ->
    %TODO: Check for message lengths, etc. Ensure that a client isn't DOSing
    %      other client(s)
    Message.

repack_match(Match) ->
    % This is pointless and stupid.
    #'Match'{
        id = Match#goblet_match.id,
        state = Match#goblet_match.state,
        players = Match#goblet_match.players,
        players_max = Match#goblet_match.players_max,
        start_time = Match#goblet_match.start_time,
        mode = Match#goblet_match.mode,
        extra = Match#goblet_match.extra
    }.
