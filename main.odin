package yaml

import "core:fmt"
import "core:strings"
import "core:testing"

Lexer :: struct {
    source:       string,
    cursor:       int,
    line:         int,
    col:          int,
    tokens:       ^[dynamic]Token_Instance,
    indent_stack: [dynamic]int, // Track nesting levels (e.g., [0, 4, 8])
}

Token :: enum {
	INDENT,
	DEDENT,
	KV_VAL,
	COLON,
}

Token_Instance :: struct {
	token_type: Token,
	token_val:  string,
}

// 1. Define our Object Model Nodes
Node_Data :: union {
    string,              // For simple values like "8080" or "/healthz"
    [dynamic]Yaml_Pair,  // For nested maps/keys
}

Yaml_Pair :: struct {
    key:   string,
    value: ^Yaml_Node,
}

Yaml_Node :: struct {
    data: Node_Data,
}

// 2. The Parser Execution State
Parser :: struct {
    tokens: [dynamic]Token_Instance,
    pos:    int,
}

parse_tokens :: proc(p: ^Parser) -> ^Yaml_Node {
    if p.pos >= len(p.tokens) do return nil

    node := new(Yaml_Node)
    tok := p.tokens[p.pos]

    if tok.token_type == .KV_VAL {
        // Look ahead to see if this is a key-value pair container or a flat value
        if p.pos + 1 < len(p.tokens) && p.tokens[p.pos + 1].token_type == .COLON {
            // It's a map! Let's initialize a dynamic array for its elements
            pairs: [dynamic]Yaml_Pair
            
            for p.pos < len(p.tokens) {
                if p.tokens[p.pos].token_type == .DEDENT {
                    p.pos += 1
                    break
                }
                
                if p.tokens[p.pos].token_type == .KV_VAL {
                    k_tok := p.tokens[p.pos]
                    p.pos += 2 // Skip the key and the colon directly
                    
                    // If a map nests down immediately via INDENT
                    if p.pos < len(p.tokens) && p.tokens[p.pos].token_type == .INDENT {
                        p.pos += 1 // Consume INDENT
                    }
                    
                    val_node := parse_tokens(p)
                    append(&pairs, Yaml_Pair{key = k_tok.token_val, value = val_node})
                } else {
                    p.pos += 1
                }
            }
            node.data = pairs
        } else {
            // Just a plain value leaf
            node.data = tok.token_val
            p.pos += 1
        }
    }
    return node
}

peek_char :: proc(l: ^Lexer) -> u8 {
    if l.cursor >= len(l.source) {
        return 0
    }
    return l.source[l.cursor]
}

advance_char :: proc(l: ^Lexer) {
    if l.cursor >= len(l.source) do return

    ch := l.source[l.cursor]
    l.cursor += 1

    if ch == '\n' {
        l.line += 1
        l.col = 1
    } else {
		l.col += 1
    }
}

add_token :: proc(tokens: ^[dynamic]Token_Instance, val: string, token_type: Token) {
	token := Token_Instance {
		token_type = token_type,
		token_val  = val,
	}
	append(tokens, token)
}

main :: proc() {
    tokens: [dynamic]Token_Instance
        source_str := `
server:
  port: 8080
  path: /healthz
app: my-app` // Note: Switched to 2 spaces for predictable web/terminal layout testing
    tokenize(source_str, &tokens)
}

tokenize :: proc(source_str: string, tokens: ^[dynamic]Token_Instance) {
    l: Lexer
    l.source = source_str
    l.line = 1
    l.col = 1
    l.tokens = tokens
    
    // Seed the indentation stack with 0 (base level)
    append(&l.indent_stack, 0)

    is_start_of_line := true

    for peek_char(&l) != 0 {
        
        // 1. If we are at the start of a line, count the leading indentation
        if is_start_of_line {
            current_indent := 0
            for {
                ch := peek_char(&l)
                if ch == ' ' {
                    current_indent += 1
                    advance_char(&l)
                } else if ch == '\t' {
                    current_indent += 4 // Normalize tabs to 4 spaces for this exercise
                    advance_char(&l)
                } else {
                    break
                }
            }
            
            // Compare current indentation against our stack hierarchy
            last_indent := l.indent_stack[len(l.indent_stack) - 1]
            if current_indent > last_indent {
                append(&l.indent_stack, current_indent)
                add_token(l.tokens, "", .INDENT)
            } else if current_indent < last_indent {
                // Pop tracking levels until we match
                for len(l.indent_stack) > 0 && l.indent_stack[len(l.indent_stack) - 1] > current_indent {
                    pop(&l.indent_stack)
                    add_token(l.tokens, "", .DEDENT)
                }
            }
            is_start_of_line = false
        }

        ch := peek_char(&l)
        if ch == 0 do break
        
        // Track when a newline resets our line state
        if ch == '\r' || ch == '\n' {
            advance_char(&l)
            is_start_of_line = true
            continue
        }

        // Skip normal inline spaces between keys and values
        if ch == ' ' || ch == '\t' {
            advance_char(&l)
            continue
        }

        // 2. Trap structural Colon
        if ch == ':' {
            add_token(l.tokens, ":", .COLON)
            advance_char(&l)
            continue
        }

        // 3. Read raw value streams
        kv_val_token := strings.builder_make()
        for {
            next_ch := peek_char(&l)
            if next_ch == 0 || next_ch == ':' || next_ch == ' ' || next_ch == '\t' || next_ch == '\n' || next_ch == '\r' {
                break
            }
            strings.write_byte(&kv_val_token, next_ch)
            advance_char(&l)
        }

        token_str := strings.to_string(kv_val_token)
        if len(token_str) > 0 {
            add_token(l.tokens, token_str, .KV_VAL)
        } else {
            advance_char(&l)
        }
    }
    
    // Clear out any remaining open indents at the end of the file
    for len(l.indent_stack) > 1 {
        pop(&l.indent_stack)
        add_token(l.tokens, "", .DEDENT)
    }
    
    fmt.println("--- Full Lexed Token Stream ---")
    for t in tokens {
        if t.token_type == .INDENT do fmt.println("[INDENT]")
        else if t.token_type == .DEDENT do fmt.println("[DEDENT]")
        else do fmt.printf("Type: %v | Val: '%s'\n", t.token_type, t.token_val)
    }
    fmt.println("\n--- Full Parsed Stream ---")
    p := Parser{tokens = tokens^, pos = 0}
    root := parse_tokens(&p)
    defer free(root)

    print_node(root)
}

print_node :: proc(node: ^Yaml_Node, indent_level := 0) {
    if node == nil do return

    // We format nested spaces manually based on depth
    spaces := strings.repeat("  ", indent_level)

    switch val in node.data {
    case string:
        fmt.printf(" %s\n", val)

    case [dynamic]Yaml_Pair:
        fmt.println() // Break line for block content
        for pair in val {
            fmt.printf("%s%s:", spaces, pair.key)
            print_node(pair.value, indent_level + 1)
        }
    }
}

@(test)
test_flat_key_value :: proc(t: ^testing.T) {
    src := "host: localhost"
    tokens: [dynamic]Token_Instance
    defer delete(tokens)

    tokenize(src, &tokens)

    testing.expect_value(t, len(tokens), 3)
    testing.expect_value(t, tokens[0].token_type, Token.KV_VAL)
    testing.expect_value(t, tokens[0].token_val, "host")
    testing.expect_value(t, tokens[1].token_type, Token.COLON)
}

@(test)
test_parser_tree_generation :: proc(t: ^testing.T) {
    src := "port: 8080"
    tokens: [dynamic]Token_Instance
    defer delete(tokens)

    tokenize(src, &tokens)

    p := Parser{tokens = tokens, pos = 0}
    root := parse_tokens(&p)
    defer free(root)

    // Validate our top-level pair array layout
    pairs := root.data.([dynamic]Yaml_Pair)
    testing.expect_value(t, len(pairs), 1)
    testing.expect_value(t, pairs[0].key, "port")
    
    val := pairs[0].value.data.(string)
    testing.expect_value(t, val, "8080")
}