//// XML parsing via xmerl Erlang FFI.
////
//// Provides a simple `XmlNode` tree (`Element` or `Text`) and helpers for
//// walking RSS/Atom/OPML documents. Uses Erlang's built-in xmerl scanner
//// (same engine as Elixir's SweetXml), which handles WordPress namespaces,
//// Unicode, and entity decoding correctly.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type XmlNode {
  Element(tag: String, attrs: List(#(String, String)), children: List(XmlNode))
  Text(content: String)
}

pub type ParseError {
  ParseError(String)
}

/// Parse an XML string into an XmlNode tree.
pub fn parse(source: String) -> Result(XmlNode, ParseError) {
  case do_parse(source) {
    Ok(node) -> Ok(to_gleam_node(node))
    Error(_) -> Error(ParseError("Failed to parse XML"))
  }
}

@external(erlang, "feedreader_xml_ffi", "parse")
fn do_parse(source: String) -> Result(XmlNodeRaw, Nil)

/// Convert FFI opaque node to typed XmlNode.
fn to_gleam_node(raw: XmlNodeRaw) -> XmlNode {
  case kind(raw) {
    "element" ->
      Element(
        tag: tag(raw),
        attrs: attrs(raw),
        children: list.map(children(raw), to_gleam_node),
      )
    _ -> Text(content: text(raw))
  }
}

// Opaque type wrapping the Erlang term
pub type XmlNodeRaw

@external(erlang, "feedreader_xml_ffi", "node_kind")
fn kind(node: XmlNodeRaw) -> String

@external(erlang, "feedreader_xml_ffi", "node_tag")
fn tag(node: XmlNodeRaw) -> String

@external(erlang, "feedreader_xml_ffi", "node_attrs")
fn attrs(node: XmlNodeRaw) -> List(#(String, String))

@external(erlang, "feedreader_xml_ffi", "node_children")
fn children(node: XmlNodeRaw) -> List(XmlNodeRaw)

@external(erlang, "feedreader_xml_ffi", "node_text")
fn text(node: XmlNodeRaw) -> String

// ═══════════════════════════════════════════════════════════════
// Tree helpers
// ═══════════════════════════════════════════════════════════════

/// Get all descendant elements with a given tag name (recursive).
pub fn elements_by_tag(node: XmlNode, tag_name: String) -> List(XmlNode) {
  case node {
    Element(_, _, children) -> {
      let direct = list.filter(children, fn(c) { is_tag(c, tag_name) })
      let nested =
        list.flat_map(children, fn(c) { elements_by_tag(c, tag_name) })
      list.append(direct, nested)
    }
    Text(_) -> []
  }
}

/// Get immediate child elements with a given tag name (non-recursive).
pub fn children_by_tag(node: XmlNode, tag_name: String) -> List(XmlNode) {
  case node {
    Element(_, _, children) ->
      list.filter(children, fn(c) { is_tag(c, tag_name) })
    Text(_) -> []
  }
}

/// Get the first immediate child element with a given tag.
pub fn child_by_tag(node: XmlNode, tag_name: String) -> Option(XmlNode) {
  case children_by_tag(node, tag_name) |> list.first {
    Ok(child) -> Some(child)
    Error(_) -> None
  }
}

/// Get the concatenated text content of a node's text children.
pub fn text_of(node: XmlNode) -> String {
  case node {
    Element(_, _, children) ->
      children
      |> list.filter(fn(c) {
        case c {
          Text(_) -> True
          Element(_, _, _) -> False
        }
      })
      |> list.map(fn(c) {
        case c {
          Text(content:) -> content
          _ -> ""
        }
      })
      |> string.join("")
    Text(content:) -> content
  }
}

/// Get the text content of the first child with a given tag.
/// Returns None if the child doesn't exist or has no text.
pub fn child_text(node: XmlNode, tag_name: String) -> Option(String) {
  case child_by_tag(node, tag_name) {
    Some(child) -> {
      let t = text_of(child) |> string.trim()
      case t {
        "" -> None
        other -> Some(other)
      }
    }
    None -> None
  }
}

/// Get an attribute value from an element node.
pub fn attr(node: XmlNode, name: String) -> Option(String) {
  case node {
    Element(_, attrs, _) ->
      case
        attrs
        |> list.find(fn(pair) {
          let #(k, _) = pair
          k == name
        })
      {
        Ok(pair) -> {
          let #(_, v) = pair
          Some(v)
        }
        Error(_) -> None
      }
    Text(_) -> None
  }
}

/// Check if a node is an element with a specific tag.
fn is_tag(node: XmlNode, tag_name: String) -> Bool {
  case node {
    Element(tag, _, _) -> tag == tag_name
    Text(_) -> False
  }
}
