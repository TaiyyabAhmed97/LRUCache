package main 

import "core:fmt"
import "core:mem"

Node :: struct {
	key: string,
	value: int,
	prev: ^Node,
	next: ^Node
}

LRUCache :: struct {
	capacity: int,
	internal_map: map[string]^Node,
	head: ^Node, // most recently used
	tail: ^Node // lru
}

create_lru_cache :: proc(capacity: int) -> LRUCache {
	return LRUCache {
		capacity=capacity,
		internal_map=make(map[string]^Node),
		head = nil,
		tail = nil
	}
}

lru_get :: proc(key: string, cache: ^LRUCache) -> (value: int, found: bool) {
	node, ok := cache.internal_map[key]
	if !ok {
		return 0, false
	}
	move_to_front(cache, node)
	return node.value, true
}

move_to_front :: proc(cache: ^LRUCache, node: ^Node) {
	 // empty list
    if cache.head == nil {
        cache.head = node
        cache.tail = node
        node.prev = nil
        node.next = nil
        return
    }

    // already head
    if cache.head == node {
        return
    }

    // detach node from current position
    if node.prev != nil {
        node.prev.next = node.next
    }
    if node.next != nil {
        node.next.prev = node.prev
    }
    if cache.tail == node {
        cache.tail = node.prev
    }

    // insert node at front
    node.prev = nil
    node.next = cache.head
    cache.head.prev = node
    cache.head = node
}

lru_put :: proc(cache: ^LRUCache, key: string, value: int) {
	node, ok := cache.internal_map[key]

	if ok {
		node.value = value
		move_to_front(cache, node)
		return
	}

	new_node := new(Node)
	new_node.key = key
	new_node.value = value

	cache.internal_map[key] = new_node

	//check if eviction needed
	if len(cache.internal_map) > cache.capacity {
		if cache.tail != nil {
			old_key := cache.tail.key
			delete_key(&cache.internal_map, old_key)

			//reset the 2nd last node's next pointer
			if cache.tail.prev != nil {
				cache.tail.prev.next = nil
			}
			cache.tail = cache.tail.prev
		}

	}

	move_to_front(cache, new_node)
}

lru_print :: proc(cache: ^LRUCache) {
	head := cache.head
	for head != nil {
		fmt.printf("%s : %d -> ", head.key, head.value)
		head = head.next
	}
	fmt.println("")
}

print_internal_map :: proc(internal_map: ^map[string]^Node) {
	for k, v in internal_map {
		fmt.printf("%s: %v\n", k, v)
	}
}

main :: proc() {
	cache := create_lru_cache(2)

	lru_put(&cache, "a", 1)
	lru_print(&cache)
	lru_put(&cache, "b", 0)
	lru_print(&cache)
	lru_put(&cache, "d", 9)
	lru_print(&cache)
	lru_put(&cache, "e", 7)
	lru_print(&cache)
	lru_put(&cache, "f", 5)

	
	node, found := lru_get("e", &cache)
	lru_print(&cache)
}