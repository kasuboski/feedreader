-module(feedreader_xml_ffi).
-include_lib("xmerl/include/xmerl.hrl").
-export([parse/1, node_kind/1, node_tag/1, node_attrs/1, node_children/1, node_text/1]).

%% Parse an XML string using xmerl. Returns {ok, Root} | {error, Reason}
%% where Root is our simplified node structure:
%%   {element, Tag :: binary(), Attrs :: [{binary(), binary()}], Children :: [Node]}
%%   {text, Text :: binary()}

parse(XmlString) when is_binary(XmlString) ->
    parse(binary_to_list(XmlString));
parse(XmlString) ->
    try
        Opts = [{space, normalize}],
        case xmerl_scan:string(XmlString, Opts) of
            {Element, _Rest} ->
                {ok, walk(Element)};
            {error, _Reason} ->
                {error, scan_error}
        end
    catch
        Class:ReasonErr:Stack ->
            {error, {exception, Class, ReasonErr, Stack}}
    end.

walk(#xmlElement{name = Name, attributes = Attrs, content = Content}) ->
    Tag = atom_to_binary(Name, utf8),
    A = [ {attr_name(Ax), attr_value(Ax)} || Ax <- Attrs ],
    C = [ walk(X) || X <- Content ],
    {element, Tag, A, C};
walk(#xmlText{value = V}) ->
    {text, unicode:characters_to_binary(V)};
walk(#xmlComment{}) ->
    {text, <<>>};
walk(#xmlPI{}) ->
    {text, <<>>};
walk(#xmlDecl{}) ->
    {text, <<>>};
walk(Other) ->
    {text, <<>>}.

attr_name(#xmlAttribute{name = N}) ->
    atom_to_binary(N, utf8).

attr_value(#xmlAttribute{value = V}) ->
    unicode:characters_to_binary(V).

%% Field accessors for Gleam FFI
node_kind({element, _, _, _}) -> <<"element">>;
node_kind({text, _}) -> <<"text">>;
node_kind(_) -> <<"text">>.

node_tag({element, Tag, _, _}) -> Tag;
node_tag(_) -> <<>>.

node_attrs({element, _, Attrs, _}) -> Attrs;
node_attrs(_) -> [].

node_children({element, _, _, Children}) -> Children;
node_children(_) -> [].

node_text({text, Text}) -> Text;
node_text(_) -> <<>>.
